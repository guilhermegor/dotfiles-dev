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
	local wt b st un any=0
	while read -r wt; do
		[ -n "$wt" ] || continue
		case "$wt" in *worktrees/agent-*) ;; *) continue ;; esac
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

sweep_orphan_branches() {
	local cwd="$1" repo="$2" owner="$3" db="$4" b p any=0
	while read -r b; do
		[ -n "$b" ] || continue
		case "$b" in "$db" | gh-pages) continue ;; esac
		p="$(gh api "repos/$repo/pulls?head=$owner:$b&state=all" --jq '.[0].number // empty' 2>/dev/null)"
		if [ -z "$p" ]; then
			echo "    - $b"
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

# Free dispatch surface: open issues not already claimed by an open branch
# (house convention: branch name ends in -<issue-number>) or an open PR body
# (Closes/Fixes/Resolves #N). Prints "#N #M ..." (one line, space-separated)
# or nothing when every open issue is already claimed.
free_dispatch_surface() {
	local cwd="$1" repo="$2"
	local issues branches prbodies n claimed free_list=()
	issues="$(gh issue list --repo "$repo" --state open --limit 200 --json number --jq '.[].number' 2>/dev/null)"
	[ -n "$issues" ] || return 0
	branches="$($GIT -C "$cwd" ls-remote --heads origin 2>/dev/null | sed 's#.*refs/heads/##')"
	prbodies="$(gh api "repos/$repo/pulls?state=open" --jq '.[].body' 2>/dev/null)"
	while read -r n; do
		[ -n "$n" ] || continue
		claimed=0
		if printf '%s\n' "$branches" | grep -qE "(^|-)${n}(\$|-)"; then claimed=1; fi
		if [ "$claimed" = 0 ] && printf '%s' "$prbodies" | grep -qiE "(closes|fixes|resolves)[^0-9]*#${n}([^0-9]|\$)"; then claimed=1; fi
		[ "$claimed" = 0 ] && free_list+=("#$n")
	done <<<"$issues"
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
		free="$(free_dispatch_surface "$cwd" "$repo")"
		if [ -n "$free" ]; then
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
