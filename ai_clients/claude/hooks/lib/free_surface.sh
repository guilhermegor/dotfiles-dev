#!/bin/bash
# Shared free-surface gate (dotfiles-dev#340): ONE implementation of "which open issues are
# safe to dispatch right now", mirroring hooks/lib/review_thread_gate.sh — skill-invoked shared
# logic that is not itself a hook, generic across repos (owner/repo arguments, nothing
# hardcoded), sourced by both the SubagentStop sweep and s:dev-loop step 6 instead of either one
# re-deriving the computation by hand.
#
# Measured on blueprintx, 2026-09-04: a directory-level "concentration" summary reported 9 of 11
# candidate issues as colliding; the exact recount showed a directory holding 6 of 200 files was
# 97% free. An aggregate over a per-item constraint always overestimates it — same family as the
# rtk-proxy `(empty)` collapse. So every comparison here is exact-path, file by file, never a
# directory prefix.
#
# Contract:
#   gate_free_surface OWNER REPO
#     Sets three globals (never partial — a failure leaves all three empty AND returns 1):
#       FREE_STATUS           = ok | unknown
#       FREE_HELD_PATHS       = newline-separated exact paths held by an open PR, or by a
#                               pushed branch with no open PR yet (union, deduped, sorted)
#       FREE_CLAIMED_ISSUES   = newline-separated issue numbers already claimed via
#                               `closingIssuesReferences`, across `is:pr` WITHOUT `is:open` —
#                               open AND merged, so a merged PR that forgot its `Closes #N`
#                               is still visible (dropping `is:open` is the whole point)
#       FREE_UNCLAIMED_ISSUES = newline-separated open issue numbers not in FREE_CLAIMED_ISSUES
#     Returns 1 and sets FREE_STATUS=unknown on any API failure. ⚠️ Never returns 0 with an
#     empty FREE_HELD_PATHS on a failure — a guard that fails open here reads as "everything is
#     free" and dispatches colliding agents.
#
#   free_classify_files FILE...
#     Pure, no network — classifies a candidate file list against the FREE_HELD_PATHS already
#     set by a prior gate_free_surface call. Prints one of:
#       free                              — no candidate file is held
#       held:<colliding paths>            — every candidate file is held
#       would-need-a-held-file:<paths>    — some but not all candidate files are held (usually
#                                           one trivial line; dispatch it anyway per s:dev-loop)
#     Collapsing this third state into "held" is the specific failure this exists to avoid.
#
# Deliberately out of scope (judgment, not data — see the issue): deciding WHICH free issue to
# dispatch, writing the brief, and supplying the candidate file list an issue's solution would
# touch (that needs reading the issue). This gate only does the exact-path set math underneath
# those decisions.
set -u

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	echo "free_surface.sh is meant to be sourced, not executed." >&2
	exit 1
fi

# _free_held_paths OWNER REPO
# Exact paths from every open PR, unioned with exact paths on any pushed branch that has no
# open PR (the "running agent, no PR yet" case) — compared via the GitHub compare API so no
# local clone of OWNER/REPO is required.
# ponytail: branches/PR lists are not paginated past gh's defaults beyond what's requested below;
# add --paginate to the `branches` call too if a repo ever exceeds one page (it already has it).
_free_held_paths() {
	local owner="$1" repo="$2"
	local slug="$owner/$repo"
	local db prs_json pr_numbers pr_heads paths n f branches b diff

	db="$(gh api "repos/$slug" --jq '.default_branch' 2>/dev/null)" || return 1
	[ -n "$db" ] || return 1

	prs_json="$(gh pr list --repo "$slug" --state open --json number,headRefName --limit 200 2>/dev/null)" || return 1
	pr_numbers="$(printf '%s' "$prs_json" | jq -r '.[].number' 2>/dev/null)" || return 1
	pr_heads="$(printf '%s' "$prs_json" | jq -r '.[].headRefName' 2>/dev/null)" || return 1

	paths=""
	while read -r n; do
		[ -n "$n" ] || continue
		f="$(gh pr view "$n" --repo "$slug" --json files --jq '.files[].path' 2>/dev/null)" || return 1
		paths="$(printf '%s\n%s' "$paths" "$f")"
	done <<<"$pr_numbers"

	branches="$(gh api "repos/$slug/branches" --paginate --jq '.[].name' 2>/dev/null)" || return 1
	while read -r b; do
		[ -n "$b" ] || continue
		[ "$b" = "$db" ] && continue
		printf '%s\n' "$pr_heads" | grep -qxF "$b" && continue
		diff="$(gh api "repos/$slug/compare/$db...$b" --jq '.files[]?.filename' 2>/dev/null)" || continue
		[ -n "$diff" ] && paths="$(printf '%s\n%s' "$paths" "$diff")"
	done <<<"$branches"

	printf '%s\n' "$paths" | sed '/^$/d' | sort -u
}

# _free_claimed_issues SLUG
# Issue numbers already claimed by ANY PR (open or merged) via closingIssuesReferences.
# ⚠️ `is:pr` WITHOUT `is:open` on purpose — a merged PR that forgot `Closes #N` is invisible
# under `is:open`. Disqualifies the branch-name `-<issue>` heuristic entirely (it missed a PR
# open four days closing the same issue an agent was dispatched for).
_free_claimed_issues() {
	local slug="$1" cursor="" has_next="true" claimed="" after query result page
	while [ "$has_next" = "true" ]; do
		after=""
		[ -n "$cursor" ] && after=",after:\"$cursor\""
		query="{search(query:\"repo:$slug is:pr\",type:ISSUE,first:100$after){pageInfo{hasNextPage endCursor} nodes{... on PullRequest{closingIssuesReferences(first:10){nodes{number}}}}}}"
		result="$(gh api graphql -f query="$query" 2>/dev/null)" || return 1
		printf '%s' "$result" | jq -e '.errors' >/dev/null 2>&1 && return 1
		page="$(printf '%s' "$result" | jq -r '.data.search.nodes[]?.closingIssuesReferences.nodes[]?.number' 2>/dev/null)"
		[ -n "$page" ] && claimed="$(printf '%s\n%s' "$claimed" "$page")"
		has_next="$(printf '%s' "$result" | jq -r '.data.search.pageInfo.hasNextPage // "false"' 2>/dev/null)"
		cursor="$(printf '%s' "$result" | jq -r '.data.search.pageInfo.endCursor // empty' 2>/dev/null)"
	done
	printf '%s\n' "$claimed" | sed '/^$/d' | sort -un
}

gate_free_surface() {
	local owner="$1" repo="$2"
	local slug="$owner/$repo"
	FREE_STATUS="unknown"
	FREE_HELD_PATHS=""
	FREE_CLAIMED_ISSUES=""
	FREE_UNCLAIMED_ISSUES=""

	local held claimed issues
	held="$(_free_held_paths "$owner" "$repo")" || return 1
	claimed="$(_free_claimed_issues "$slug")" || return 1
	issues="$(gh issue list --repo "$slug" --state open --limit 500 --json number --jq '.[].number' 2>/dev/null)" || return 1

	local n unclaimed=""
	while read -r n; do
		[ -n "$n" ] || continue
		printf '%s\n' "$claimed" | grep -qxF "$n" && continue
		unclaimed="$(printf '%s\n%s' "$unclaimed" "$n")"
	done <<<"$issues"

	FREE_HELD_PATHS="$held"
	# shellcheck disable=SC2034 # read by callers after this returns, not within this file
	FREE_CLAIMED_ISSUES="$claimed"
	# shellcheck disable=SC2034 # read by callers after this returns, not within this file
	FREE_UNCLAIMED_ISSUES="$(printf '%s\n' "$unclaimed" | sed '/^$/d' | sort -un)"
	# shellcheck disable=SC2034 # read by callers after this returns, not within this file
	FREE_STATUS="ok"
	return 0
}

# free_classify_files FILE...
# Requires FREE_HELD_PATHS from a prior gate_free_surface call. Exact-path membership only —
# never a prefix/substring test, which is the whole defect this gate exists to avoid.
free_classify_files() {
	local total=0 held_count=0 f collided=""
	for f in "$@"; do
		total=$((total + 1))
		if printf '%s\n' "$FREE_HELD_PATHS" | grep -qxF "$f"; then
			held_count=$((held_count + 1))
			collided="$collided $f"
		fi
	done
	collided="${collided# }"
	if [ "$held_count" -eq 0 ]; then
		echo "free"
	elif [ "$held_count" -eq "$total" ]; then
		echo "held:$collided"
	else
		echo "would-need-a-held-file:$collided"
	fi
}
