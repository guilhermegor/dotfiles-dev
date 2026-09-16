#!/bin/bash
# Stop hook: refuse to end the turn while ANY open PR in this repo has review threads that are
# not finished — no reply, or replied and still open.
#
# This is the LOOP half, and it is a different job from `pr_merge_threads_guard.sh`.
#
# That guard blocks a bad merge. It is necessary and it is not sufficient, because blocking the
# exit does not drive the work: a reviewer posts findings minutes after a push, the agent has
# already moved on to another task, and nothing brings it back. The threads then sit open until
# a HUMAN notices and asks — which is precisely the dependency being removed. Measured across
# blueprintx PRs #180 and #182: three separate rounds of review findings, each one surfaced by
# the user asking, never by the loop noticing.
#
# A Stop hook is the right shape because "am I done?" is exactly the question whose answer the
# open threads change. Exit 2 feeds stderr back to the model and makes it continue, so the loop
# closes without anyone remembering anything.
#
# ⚠️ Repo-wide, not branch-scoped (dotfiles-dev#397). The original version resolved the PR
# STRICTLY via `gh pr view` on the current branch, and that lookup fails open exactly where the
# orchestrator session lives: on a detached HEAD (every `worktree add --detach` used to inspect
# a PR) or on a branch that carries no PR of its own — which made this hook a structural no-op
# in the one session that runs `/dev-loop`. Measured: #317 carried an unanswered Major CodeRabbit
# finding through an entire round, surfaced only because `subagent_stop_sweep.sh` was run by
# hand — the exact human-asks path this hook exists to remove. Fix: keep the branch-PR lookup as
# the fast, cheap common case (a contributor session on a feature branch still pays for exactly
# one gate call, same as before #397); fall back to a repo-wide scan only when that lookup comes
# up empty (no PR for this branch/HEAD).
#
# ⚠️ Bound the cost of the fallback scan — it is up to one gate call per open PR (~23 measured on
# this repo), far heavier than the single-PR fast path:
#   - CAP: at most $OPEN_THREADS_NUDGE_MAX_PRS PRs (default 50) are ever queried in one scan.
#   - SHORT-CIRCUIT: the scan stops at the first non-clean PR it finds — the nudge only needs ONE
#     reason to block, never an exhaustive report (that report is `subagent_stop_sweep.sh`'s job,
#     reused here via the same gate, not re-derived).
#   - CACHE: the scan's verdict is cached per session under
#     `$CLAUDE_CONFIG_DIR/open-threads-nudge/`, for $OPEN_THREADS_NUDGE_CACHE_TTL seconds
#     (default 300), so a long session's many Stops don't re-run a full scan on every turn.
#
# ⚠️ `stop_hook_active` MUST be honoured. Claude Code sets it when the stop was itself triggered
# by a hook; ignoring it means blocking the stop that this very hook caused, forever. The model
# gets one nudge per turn, not an inescapable loop.
#
# Fails OPEN on everything it cannot resolve (no gh, no jq, no network, no PR anywhere in the
# repo) — a nudge that fires on its own blindness is noise, and noise gets the hook deleted.

set -u

command -v jq >/dev/null 2>&1 || exit 0
command -v gh >/dev/null 2>&1 || exit 0

ROSTER_FILE='.review-bots.yaml'
: "${OPEN_THREADS_NUDGE_MAX_PRS:=50}"
: "${OPEN_THREADS_NUDGE_CACHE_TTL:=300}"

# GraphQL query + classification live in one shared place (dotfiles-dev#167):
# the SubagentStop board sweep (subagent_stop_sweep.sh) calls the identical
# gate for every open PR, and a second hand-copy is exactly the risk this
# file's own header warns about (re-deriving a gate's verdict instead of
# calling it).
# shellcheck source=lib/review_thread_gate.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/review_thread_gate.sh"

# _emit_verdict NUMBER PREFIX
# Prints the human-facing message for the current $GATE_STATUS/$GATE_DETAIL (set by a prior
# gate_pr_thread_state call) and returns the exit code the hook should use. A non-empty PREFIX
# marks a repo-wide finding, so the message never reads as if it came from the branch's own PR.
_emit_verdict() {
	local number="$1" prefix="$2"

	case "$GATE_STATUS" in
	unreadable)
		{
			echo "${prefix}PR #${number}: could NOT read the review threads (GitHub API unreachable"
			echo "after 3 attempts) — so their state is UNKNOWN, not clean."
			echo
			echo "Do not report this PR as finished on the strength of a check that never ran."
			echo "Re-read the threads when the API answers again."
		} >&2
		return 2
		;;
	running)
		# ⚠️ "Zero open threads" is only a VERDICT once the reviewers have finished. Measured on
		# blueprintx#186, threads read 0 and a CodeRabbit re-review opened SIX new ones thirty
		# seconds later — and the turn had already been reported as clean.
		{
			echo "${prefix}PR #${number}: every review thread is answered and resolved RIGHT NOW, but"
			echo "checks are still running — so that reading is a snapshot, not a verdict."
			echo
			echo "  still running: ${GATE_DETAIL}"
			echo
			echo "A reviewer bot posts its findings when its own check finishes. Wait for the"
			echo "checks to go terminal and re-read the threads before reporting this PR as clean."
		} >&2
		return 2
		;;
	clean)
		return 0
		;;
	problems | *)
		{
			echo "${prefix}PR #${number} still has unfinished review threads — do not stop here."
			echo
			printf '%s\n' "$GATE_DETAIL"
			echo
			echo "For each: verify the finding against the code (some are wrong — refute those with"
			echo "measurement), reply with what changed and why, then resolve the conversation."
			echo
			echo "Checked live. The CI check cannot be trusted for this: it is evaluated on push and"
			echo "on new comments, and NOTHING re-runs it when a thread is resolved."
		} >&2
		return 2
		;;
	esac
}

# _scan_cache_path SESSION_ID OWNER NAME
# Prints the cache file path, or fails (empty stdout, non-zero return) when there is no session
# id to key it by, or the cache directory cannot be created — either way the caller treats that
# as "no cache available" and scans fresh instead of erroring.
_scan_cache_path() {
	local session_id="$1" owner="$2" name="$3" dir
	[ -n "$session_id" ] || return 1
	dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/open-threads-nudge"
	mkdir -p "$dir" 2>/dev/null || return 1
	printf '%s/%s-%s_%s\n' "$dir" "$session_id" "$owner" "$name"
}

# _repo_wide_scan OWNER NAME SESSION_ID
# Sets GATE_STATUS/GATE_DETAIL/REPORT_NUMBER to the FIRST non-clean open PR found (REPORT_NUMBER
# stays empty and GATE_STATUS=clean when every scanned PR is clean, or there are none), reusing
# a same-session cache when it is still fresh. Returns 1 only when the PR list itself could not
# be read — the caller's fail-open case.
_repo_wide_scan() {
	local owner="$1" name="$2" session_id="$3" cache now ts age cached prs n

	cache="$(_scan_cache_path "$session_id" "$owner" "$name" 2>/dev/null)" || cache=""
	if [ -n "$cache" ] && [ -r "$cache" ]; then
		now="$(date +%s)"
		cached="$(cat "$cache" 2>/dev/null)"
		ts="$(printf '%s' "$cached" | jq -r '.ts // 0' 2>/dev/null)"
		[[ "$ts" =~ ^[0-9]+$ ]] || ts=0
		age=$((now - ts))
		if [ "$age" -ge 0 ] && [ "$age" -lt "$OPEN_THREADS_NUDGE_CACHE_TTL" ]; then
			REPORT_NUMBER="$(printf '%s' "$cached" | jq -r '.number // empty' 2>/dev/null)"
			GATE_STATUS="$(printf '%s' "$cached" | jq -r '.status // "clean"' 2>/dev/null)"
			GATE_DETAIL="$(printf '%s' "$cached" | jq -r '.detail // empty' 2>/dev/null)"
			return 0
		fi
	fi

	prs="$(gh pr list --repo "$owner/$name" --state open --json number \
		--limit "$OPEN_THREADS_NUDGE_MAX_PRS" --jq '.[].number' 2>/dev/null)" || return 1

	REPORT_NUMBER=""
	GATE_STATUS="clean"
	GATE_DETAIL=""
	while read -r n; do
		[ -n "$n" ] || continue
		gate_pr_thread_state "$owner" "$name" "$n" "$ROSTER_FILE"
		if [ "$GATE_STATUS" != "clean" ]; then
			REPORT_NUMBER="$n"
			break
		fi
	done <<<"$prs"

	if [ -n "$cache" ]; then
		jq -nc --arg n "$REPORT_NUMBER" --arg s "$GATE_STATUS" --arg d "$GATE_DETAIL" \
			--argjson ts "$(date +%s)" \
			'{ts: $ts, number: (if ($n | length) > 0 then $n else null end), status: $s, detail: $d}' \
			>"$cache" 2>/dev/null || true
	fi
	return 0
}

main() {
	local payload active number repo owner name session_id

	payload="$(cat)"

	# Never block a stop that a hook already caused.
	active="$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null)"
	[[ "$active" == "true" ]] && exit 0

	git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

	# Fast path: the current branch's own open PR. Unchanged from before #397 — a contributor
	# session on a feature branch still pays for exactly one gate call.
	number="$(gh pr view --json number,state -q 'select(.state=="OPEN") | .number' 2>/dev/null)"
	if [[ "$number" =~ ^[0-9]+$ ]]; then
		repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" || exit 0
		owner="${repo%%/*}"
		name="${repo##*/}"
		[[ -n "$owner" && -n "$name" ]] || exit 0

		# ⚠️ FAIL CLOSED on an unreadable answer — see gate_pr_thread_state's own retry/partial-body
		# handling. Measured 2026-08-17: a run of HTTP 503s swallowed a thread reply, and the thread
		# then sat resolved with no reasoning recorded.
		gate_pr_thread_state "$owner" "$name" "$number" "$ROSTER_FILE"
		_emit_verdict "$number" ""
		exit $?
	fi

	# No PR for this branch/HEAD (detached, or a branch with none) — the exact session shape
	# #397 reports as silent. Fall back to a repo-wide scan instead of exiting clean here.
	repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" || exit 0
	owner="${repo%%/*}"
	name="${repo##*/}"
	[[ -n "$owner" && -n "$name" ]] || exit 0
	session_id="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)"

	_repo_wide_scan "$owner" "$name" "$session_id" || exit 0
	[ -n "$REPORT_NUMBER" ] || exit 0

	_emit_verdict "$REPORT_NUMBER" "[repo-wide scan, no PR for this branch/HEAD] "
	exit $?
}

main "$@"
