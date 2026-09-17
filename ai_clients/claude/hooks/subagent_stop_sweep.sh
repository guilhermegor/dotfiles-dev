#!/bin/bash
# SubagentStop hook — board sweep + free dispatch surface (dotfiles-dev#167).
#
# The problem this closes: a rule that must fire EVERY cycle cannot live in a
# document. Measured in one blueprintx session — three corrections, two
# lessons written, zero behaviour change, because "did you sweep the board /
# dispatch more agents?" depended on someone remembering to ask. This hook
# makes the sweep fire deterministically every time a subagent finishes,
# instead of on request.
#
# Generalised from the blueprintx-specific reference sweep (measured there
# 2026-08-29, see its own header comments for the two defects it survived):
# the repo is resolved from the session cwd + `git remote`, never hardcoded,
# and nothing here re-derives the review-thread gate's verdict — it calls the
# shared implementation in lib/review_thread_gate.sh (the same one
# open_review_threads_nudge.sh uses), because a re-derived copy inherited
# that gate's own bug plus a new one of its own when blueprintx tried it.
#
# ⚠️ Two traps carried forward from the reference sweep, both measured:
#   1. NEVER judge git state through the rtk proxy. `rtk proxy git status
#      --porcelain` on a clean tree returns the literal string "ok", which
#      `wc -l` counts as 1 line — reporting a clean branch as dirty. Every
#      git call below uses $GIT (/usr/bin/git) directly.
#   2. NEVER re-derive the review-thread gate's verdict; CALL it, and match
#      the sentence that discriminates when classifying its output, never a
#      bare noun (a first draft matched the word "thread" and hit it inside
#      a sentence that meant the opposite).
#
# Query, not judgement (the reference sweep's own framing): every section
# below only prints states that need action, and the final line is always
# explicit — "dispatch these N: ..." or "dispatch: free surface empty" —
# because silence is indistinguishable from the check having been skipped.
#
# Emits its report as SubagentStop `additionalContext` JSON so the parent
# session sees it without anyone asking. Never blocks: this hook cannot spawn
# agents, so blocking the stop would accomplish nothing — it only informs.
set -uo pipefail

GIT=/usr/bin/git
command -v gh >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/review_thread_gate.sh
source "$HOOK_DIR/lib/review_thread_gate.sh"
# shellcheck source=lib/free_surface.sh
source "$HOOK_DIR/lib/free_surface.sh"

emit() {
	# $1 = plain-text report body. Wraps it as SubagentStop additionalContext.
	jq -n --arg ctx "$1" '{hookSpecificOutput: {hookEventName: "SubagentStop", additionalContext: $ctx}}'
}

resolve_cwd() {
	local payload="$1" cwd
	cwd=""
	if [ -n "$payload" ]; then
		cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"
	fi
	if [ -n "$cwd" ]; then
		printf '%s\n' "$cwd"
	else
		printf '%s\n' "${CLAUDE_PROJECT_DIR:-$PWD}"
	fi
}

default_branch() {
	# Reads the remote's HEAD symref directly — never depends on whether a
	# local `fetch` already ran. Getting this wrong once (measured while
	# testing this hook against a never-fetched clone) turned into a false
	# positive: an empty $db matched nothing in the exclusion check below,
	# so the repo's OWN default branch was flagged as "pushed without PR".
	local cwd="$1" db
	db="$($GIT -C "$cwd" ls-remote --symref origin HEAD 2>/dev/null | awk '/^ref:/{print $2}')"
	db="${db#refs/heads/}"
	if [ -n "$db" ]; then
		printf '%s\n' "$db"
		return
	fi
	# Network unreachable / no origin: fall back to a local guess.
	for db in main master; do
		if $GIT -C "$cwd" show-ref --verify --quiet "refs/heads/$db"; then
			printf '%s\n' "$db"
			return
		fi
	done
	printf '%s\n' ""
}

repo_slug() {
	local cwd="$1" url
	url="$($GIT -C "$cwd" remote get-url origin 2>/dev/null)" || return 1
	[ -n "$url" ] || return 1
	url="${url%.git}"
	case "$url" in
	*github.com[:/]*)
		printf '%s\n' "${url#*github.com}" | sed 's#^[:/]##'
		;;
	*)
		return 1
		;;
	esac
}

sweep_worktrees() {
	local cwd="$1"
	local wt b st un any=0 main_wt
	# Every linked worktree, not just `worktrees/agent-*`. The old filter matched the name the
	# harness happens to pick, so a worktree created by hand (or by a resumed agent, named
	# `worktrees/issue-356`) held two uncommitted files while this step printed "none" — the
	# exact silence the step exists to break (dotfiles-dev#162 is about residue, not naming).
	# The main checkout is still skipped: the operator's own dirty tree is not agent residue.
	main_wt="$($GIT -C "$cwd" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')"
	while read -r wt; do
		[ -n "$wt" ] || continue
		[ "$wt" = "$main_wt" ] && continue
		b="$($GIT -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)"
		st="$($GIT -C "$wt" status --porcelain 2>/dev/null | wc -l)"
		un="$($GIT -C "$wt" rev-list --count "origin/$b..$b" 2>/dev/null || echo no-remote)"
		if [ "$st" != "0" ]; then
			echo "    - $b: $st uncommitted"
			any=1
		fi
		if [ "$un" != "0" ] && [ "$un" != "no-remote" ]; then
			echo "    - $b: $un unpushed"
			any=1
		fi
	done < <($GIT -C "$cwd" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}')
	[ "$any" = "0" ] && echo "    none"
}

sweep_review_gate() {
	local owner="$1" name="$2" repo="$3" roster_file="$4" prs
	prs="$(gh api "repos/$repo/pulls?state=open" --jq '.[].number' 2>/dev/null)"
	if [ -z "$prs" ]; then
		echo "    no open PRs"
		return
	fi
	local n
	while read -r n; do
		[ -n "$n" ] || continue
		gate_pr_thread_state "$owner" "$name" "$n" "$roster_file"
		case "$GATE_STATUS" in
		clean) echo "    #$n clean" ;;
		problems) echo "    #$n NEEDS REPLY/RESOLVE: $(printf '%s' "$GATE_DETAIL" | tr '\n' ';')" ;;
		running) echo "    #$n reviewer checks running — snapshot, not a verdict" ;;
		unreadable) echo "    #$n unreadable: $GATE_DETAIL" ;;
		esac
	done <<<"$prs"
}

# A pushed `git stash` snapshot has a tip commit titled by `git stash` itself
# (`WIP on <branch>: ...`, `index on <branch>: ...`, or, for `-u`, `untracked
# files on <branch>: ...`) — never a title a person or an agent would write.
# Matching on that title is what tells a real branch missing a PR apart from
# a stash pushed under a branch name (dotfiles-dev#399).
is_stash_snapshot_title() {
	case "$1" in
	"WIP on "* | "index on "* | "untracked files on "*) return 0 ;;
	*) return 1 ;;
	esac
}

# Extra context for a stash snapshot so the loop can decide whether to ask
# about deleting it, without re-deriving the diff by hand: how far $db has
# moved since the snapshot's base, and the three-dot per-file +/- (a mostly-
# deleting file is a stale snapshot re-adding lines $db already removed).
stash_snapshot_diff_context() {
	local cwd="$1" db="$2" b="$3" base gained
	base="$($GIT -C "$cwd" merge-base "origin/$db" "origin/$b" 2>/dev/null)"
	if [ -z "$base" ]; then
		echo "      no merge-base with $db — can't date this snapshot"
		return
	fi
	gained="$($GIT -C "$cwd" rev-list --count "$base..origin/$db" 2>/dev/null || echo 0)"
	echo "      $db gained $gained commit(s) since this snapshot's base"
	echo "      per-file +/- (three-dot diff vs $db):"
	$GIT -C "$cwd" diff --numstat "origin/$db...origin/$b" 2>/dev/null |
		while read -r add del path; do
			[ -n "$path" ] || continue
			echo "        $path: +$add/-$del"
		done
}

# Whether any open OR merged PR already touches the same files this snapshot
# touches — if so, opening a PR for the snapshot would bring back old content
# that is either already in flight or already landed.
#
# ⚠️ An API failure must read UNKNOWN, never "no open or merged PR touches
# these files" — the two gh calls below are checked for their own exit
# status (not just their captured text), because an empty result on success
# and an empty result on failure are otherwise indistinguishable, and the
# silently-empty reading is the wrong one to act on (CodeRabbit, PR #403).
stash_snapshot_pr_overlap() {
	local cwd="$1" repo="$2" db="$3" b="$4" files pr_nums n pr_files f hits=""
	files="$($GIT -C "$cwd" diff --name-only "origin/$db...origin/$b" 2>/dev/null)"
	if [ -z "$files" ]; then
		echo "      touches no files vs $db"
		return
	fi
	if ! pr_nums="$(gh api "repos/$repo/pulls?state=all" --paginate \
		--jq '.[] | select(.merged_at != null or .state == "open") | .number' 2>/dev/null)"; then
		echo "      UNKNOWN — could not list open/merged PRs (gh API failure)"
		return
	fi
	while read -r n; do
		[ -n "$n" ] || continue
		if ! pr_files="$(gh api "repos/$repo/pulls/$n/files" --paginate --jq '.[].filename' 2>/dev/null)"; then
			echo "      UNKNOWN — could not list files for PR #$n (gh API failure)"
			return
		fi
		while read -r f; do
			[ -n "$f" ] || continue
			if printf '%s\n' "$files" | grep -qxF "$f"; then
				hits="$hits #$n"
				break
			fi
		done <<<"$pr_files"
	done <<<"$pr_nums"
	hits="${hits# }"
	if [ -n "$hits" ]; then
		echo "      same files touched by: $hits"
	else
		echo "      no open or merged PR touches these files"
	fi
}

sweep_orphan_branches() {
	local cwd="$1" repo="$2" owner="$3" db="$4" b p any=0 title
	while read -r b; do
		[ -n "$b" ] || continue
		case "$b" in "$db" | gh-pages) continue ;; esac
		p="$(gh api "repos/$repo/pulls?head=$owner:$b&state=all" --jq '.[0].number // empty' 2>/dev/null)"
		if [ -z "$p" ]; then
			title="$($GIT -C "$cwd" log -1 --format=%s "origin/$b" 2>/dev/null)"
			if is_stash_snapshot_title "$title"; then
				echo "    - $b: STASH SNAPSHOT (\"$title\"), not a branch missing a PR"
				stash_snapshot_diff_context "$cwd" "$db" "$b"
				stash_snapshot_pr_overlap "$cwd" "$repo" "$db" "$b"
			else
				echo "    - $b"
			fi
			any=1
		fi
	done < <($GIT -C "$cwd" ls-remote --heads origin 2>/dev/null | sed 's#.*refs/heads/##')
	[ "$any" = "0" ] && echo "    none"
}

sweep_no_automerge() {
	local repo="$1" n any=0
	while read -r n; do
		[ -n "$n" ] || continue
		echo "    - #$n"
		any=1
	done < <(gh api "repos/$repo/pulls?state=open" --jq '.[] | select(.auto_merge == null) | .number' 2>/dev/null)
	[ "$any" = "0" ] && echo "    none"
}

sweep_behind_base() {
	local cwd="$1" repo="$2" db="$3" n headref behind any=0
	while read -r n; do
		[ -n "$n" ] || continue
		headref="$(gh api "repos/$repo/pulls/$n" --jq .head.ref 2>/dev/null)"
		[ -n "$headref" ] || continue
		behind="$($GIT -C "$cwd" rev-list --count "origin/$headref..origin/$db" 2>/dev/null || echo 0)"
		if [ -n "$behind" ] && [ "$behind" != "0" ]; then
			echo "    - #$n: $behind commit(s) behind $db"
			any=1
		fi
	done < <(gh api "repos/$repo/pulls?state=open" --jq '.[].number' 2>/dev/null)
	[ "$any" = "0" ] && echo "    none"
}

# Free dispatch surface: calls the shared gate_free_surface (lib/free_surface.sh) instead of
# re-deriving it — the branch-name `-<issue>` heuristic this used to run is disqualified by
# measurement (it missed a PR open four days closing the same issue an agent was dispatched
# for; dotfiles-dev#340). Prints "#N #M ..." (space-separated), "UNKNOWN" on an API failure
# (never an empty string — empty is indistinguishable from "nothing left to dispatch"), or
# nothing when every open issue is already claimed.
free_dispatch_surface() {
	local repo="$1" owner="${1%%/*}" name="${1##*/}"
	if ! gate_free_surface "$owner" "$name"; then
		echo "UNKNOWN"
		return 1
	fi
	local n free_list=()
	while read -r n; do
		[ -n "$n" ] || continue
		free_list+=("#$n")
	done <<<"$FREE_UNCLAIMED_ISSUES"
	[ "${#free_list[@]}" -gt 0 ] && printf '%s\n' "${free_list[*]}"
}

main() {
	local payload cwd repo owner name db roster_file report
	if [ ! -t 0 ]; then payload="$(cat)"; else payload=""; fi
	cwd="$(resolve_cwd "$payload")"

	$GIT -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

	if ! repo="$(repo_slug "$cwd")"; then
		emit "sweep: no GitHub origin at $cwd — nothing to sweep.
dispatch: free surface empty"
		exit 0
	fi
	owner="${repo%%/*}"
	name="${repo##*/}"
	roster_file="$cwd/.review-bots.yaml"
	db="$(default_branch "$cwd")"
	$GIT -C "$cwd" fetch origin --quiet 2>/dev/null || true

	report="$(
		echo "── sweep $(date -u '+%H:%M UTC') — $repo ──"
		echo "[1] worktree residue"
		sweep_worktrees "$cwd"
		echo "[2] review-thread gate (called, not re-derived)"
		sweep_review_gate "$owner" "$name" "$repo" "$roster_file"
		echo "[3] branch pushed without PR"
		sweep_orphan_branches "$cwd" "$repo" "$owner" "$db"
		echo "[4] PR without auto-merge armed"
		sweep_no_automerge "$repo"
		echo "[5] PR behind base ($db)"
		sweep_behind_base "$cwd" "$repo" "$db"
		echo "[6] free dispatch surface"
		free="$(free_dispatch_surface "$repo")"
		if [ "$free" = "UNKNOWN" ]; then
			echo "dispatch: UNKNOWN — free surface unreadable (gh API failure), not empty"
		elif [ -n "$free" ]; then
			# shellcheck disable=SC2086 # word-splitting is intentional: count the tokens
			set -- $free
			echo "dispatch these $#: $free"
		else
			echo "dispatch: free surface empty"
		fi
	)"

	emit "$report"
	exit 0
}

main "$@"
