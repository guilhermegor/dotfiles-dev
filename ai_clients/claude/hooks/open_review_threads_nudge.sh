#!/bin/bash
# Stop hook: refuse to end the turn while the current branch's PR has review threads that are
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
# ⚠️ `stop_hook_active` MUST be honoured. Claude Code sets it when the stop was itself triggered
# by a hook; ignoring it means blocking the stop that this very hook caused, forever. The model
# gets one nudge per turn, not an inescapable loop.
#
# Fails OPEN on everything it cannot resolve (no gh, no jq, no network, no PR, detached HEAD) —
# a nudge that fires on its own blindness is noise, and noise gets the hook deleted.

set -u

command -v jq >/dev/null 2>&1 || exit 0
command -v gh >/dev/null 2>&1 || exit 0

ROSTER_FILE='.review-bots.yaml'

# GraphQL query + classification live in one shared place (dotfiles-dev#167):
# the SubagentStop board sweep (subagent_stop_sweep.sh) calls the identical
# gate for every open PR, and a second hand-copy is exactly the risk this
# file's own header warns about (re-deriving a gate's verdict instead of
# calling it).
# shellcheck source=lib/review_thread_gate.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/review_thread_gate.sh"

main() {
	local payload active number repo owner name

	payload="$(cat)"

	# Never block a stop that a hook already caused.
	active="$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null)"
	[[ "$active" == "true" ]] && exit 0

	git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

	number="$(gh pr view --json number,state -q 'select(.state=="OPEN") | .number' 2>/dev/null)"
	[[ "$number" =~ ^[0-9]+$ ]] || exit 0

	repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" || exit 0
	owner="${repo%%/*}"
	name="${repo##*/}"
	[[ -n "$owner" && -n "$name" ]] || exit 0

	# ⚠️ FAIL CLOSED on an unreadable answer — see gate_pr_thread_state's own retry/partial-body
	# handling. Measured 2026-08-17: a run of HTTP 503s swallowed a thread reply, and the thread
	# then sat resolved with no reasoning recorded.
	gate_pr_thread_state "$owner" "$name" "$number" "$ROSTER_FILE"

	case "$GATE_STATUS" in
	unreadable)
		{
			echo "PR #${number}: could NOT read the review threads (GitHub API unreachable after"
			echo "3 attempts) — so their state is UNKNOWN, not clean."
			echo
			echo "Do not report this PR as finished on the strength of a check that never ran."
			echo "Re-read the threads when the API answers again."
		} >&2
		exit 2
		;;
	running)
		# ⚠️ "Zero open threads" is only a VERDICT once the reviewers have finished. Measured on
		# blueprintx#186, threads read 0 and a CodeRabbit re-review opened SIX new ones thirty
		# seconds later — and the turn had already been reported as clean.
		{
			echo "PR #${number}: every review thread is answered and resolved RIGHT NOW, but"
			echo "checks are still running — so that reading is a snapshot, not a verdict."
			echo
			echo "  still running: ${GATE_DETAIL}"
			echo
			echo "A reviewer bot posts its findings when its own check finishes. Wait for the"
			echo "checks to go terminal and re-read the threads before reporting this PR as clean."
		} >&2
		exit 2
		;;
	clean)
		exit 0
		;;
	problems | *)
		{
			echo "PR #${number} still has unfinished review threads — do not stop here."
			echo
			printf '%s\n' "$GATE_DETAIL"
			echo
			echo "For each: verify the finding against the code (some are wrong — refute those with"
			echo "measurement), reply with what changed and why, then resolve the conversation."
			echo
			echo "Checked live. The CI check cannot be trusted for this: it is evaluated on push and"
			echo "on new comments, and NOTHING re-runs it when a thread is resolved."
		} >&2
		exit 2
		;;
	esac
}

main "$@"
