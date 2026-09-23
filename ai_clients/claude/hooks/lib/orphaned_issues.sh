#!/bin/bash
# Shared orphaned-issues gate (dotfiles-dev#418): ONE implementation of "which open issues
# already shipped in a merged PR that forgot to declare it", mirroring free_surface.sh and
# roadmap_unblock.sh — skill-invoked shared logic that is not itself a hook, generic across
# repos (owner/repo arguments, nothing hardcoded), sourced by s:dev-loop step 2 (SWEEP) instead
# of re-deriving the computation by hand.
#
# The direction is the mirror image of free_surface.sh's `_free_claimed_issues`: that helper
# asks "given an issue about to be dispatched, does some PR already claim it?" (used to decide
# NOT to dispatch). This gate asks the other direction, proactively, over every open issue: "is
# there a merged PR whose title/branch/body already mentions this issue, without declaring it
# via closingIssuesReferences?" — the fully-decidable half of dotfiles-dev#418's scope (a
# textual PR-mention with a missing link). The complementary signal named in #418 (the issue's
# declared file surface existing on the default branch, with no PR mention at all) is already
# s:intake-shipped's job (shipped_check.sh) once a specific issue is in hand; re-deriving that
# content-probe here for every open issue on every round would duplicate it, so this gate stays
# scoped to the PR-mention signal and s:dev-loop calls both.
#
# Measured (dotfiles-dev#418): blueprintx#381's own PR (#467) had "381" in its branch name
# (`refactor/migrations-folder-alembic-parity-373-381`) and in its title, and still only closed
# 373 -- the orphan survived a human reading the title. blueprintx#355 shipped via PR #509 with
# closingIssuesReferences = []. Never trust the branch-name `-<issue>` suffix heuristic alone
# (dotfiles-dev's own step 6 already rejects it): a mention can sit anywhere in title/body too,
# so this gate scans all three fields.
#
# Contract:
#   gate_orphaned_issues OWNER REPO
#     Sets two globals (never partial -- a failure leaves both empty AND returns 1):
#       ORPHAN_STATUS = ok | unknown
#       ORPHAN_REPORT = newline-separated candidate lines, one per open issue with a merged PR
#                       mentioning it without closing it -- "#N may already be shipped by PR #M
#                       (mentions #N, closingIssuesReferences=<list|none>) -- verify on <default
#                       branch>". Empty when no candidate is found (still ORPHAN_STATUS=ok).
#     Returns 1 and sets ORPHAN_STATUS=unknown on any gh/jq read failure. ⚠️ Never returns 0 with
#     a stale/partial ORPHAN_REPORT on a failure -- a report is a *candidate*, never a verdict
#     (see #418's own scope: report, never auto-close), so a caller that treats a failure as "no
#     candidates" would silently stop re-offering issues that already merged.
set -u

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	echo "orphaned_issues.sh is meant to be sourced, not executed." >&2
	exit 1
fi

# _orphan_merged_pr_mentions SLUG
# Prints "issue_number<TAB>pr_number<TAB>closing_list" one line per (mentioned issue, PR) pair
# where a MERGED pull request's title, body, or branch name mentions the issue number while its
# own closingIssuesReferences omits it. `is:merged` (not `is:open`) on purpose -- same reasoning
# as free_surface.sh's `_free_claimed_issues`: a merged PR that forgot the link is invisible
# under `is:open`.
_orphan_merged_pr_mentions() {
	local slug="$1" cursor="" has_next="true" query result page after node
	while [ "$has_next" = "true" ]; do
		after=""
		[ -n "$cursor" ] && after=",after:\"$cursor\""
		query="{search(query:\"repo:$slug is:pr is:merged\",type:ISSUE,first:50$after){pageInfo{hasNextPage endCursor} nodes{... on PullRequest{number title body headRefName closingIssuesReferences(first:20){nodes{number}}}}}}"
		result="$(gh api graphql -f query="$query" 2>/dev/null)" || return 1
		printf '%s' "$result" | jq -e '.errors' >/dev/null 2>&1 && return 1
		page="$(printf '%s' "$result" | jq -c '.data.search.nodes[]?' 2>/dev/null)" || return 1
		while IFS= read -r node; do
			[ -n "$node" ] || continue
			printf '%s' "$node" | jq -r '
				(.number) as $pr
				| ((.title // "") + " " + (.body // "")) as $text
				| ([$text | scan("#[0-9]+")] | map(ltrimstr("#"))) as $hash_mentions
				| ((.headRefName // "") | [splits("[^0-9]+")] | map(select(length > 0))) as $branch_mentions
				| ([.closingIssuesReferences.nodes[]?.number | tostring]) as $closed
				| (($hash_mentions + $branch_mentions) | unique) as $mentioned
				| $mentioned[] as $m
				| select(($closed | index($m)) == null)
				| "\($m)\t\($pr)\t\($closed | join(","))"
			' 2>/dev/null || return 1
		done <<<"$page"
		has_next="$(printf '%s' "$result" | jq -r '.data.search.pageInfo.hasNextPage // "false"' 2>/dev/null)"
		cursor="$(printf '%s' "$result" | jq -r '.data.search.pageInfo.endCursor // empty' 2>/dev/null)"
	done
}

gate_orphaned_issues() {
	local owner="$1" repo="$2"
	local slug="$owner/$repo"
	ORPHAN_STATUS="unknown"
	ORPHAN_REPORT=""

	local db
	db="$(gh api "repos/$slug" --jq '.default_branch' 2>/dev/null)" || return 1
	[ -n "$db" ] || return 1

	local open_issues
	open_issues="$(gh issue list --repo "$slug" --state open --limit 500 --json number --jq '.[].number' 2>/dev/null)" || return 1

	local mentions
	mentions="$(_orphan_merged_pr_mentions "$slug")" || return 1

	local issue pr closed report=""
	while IFS=$'\t' read -r issue pr closed; do
		[ -n "$issue" ] || continue
		printf '%s\n' "$open_issues" | grep -qxF "$issue" || continue
		report="$(printf '%s\n%s' "$report" \
			"#$issue may already be shipped by PR #$pr (mentions #$issue, closingIssuesReferences=${closed:-none}) -- verify on $db")"
	done <<<"$mentions"

	# shellcheck disable=SC2034 # read by callers after this returns, not within this file
	ORPHAN_REPORT="$(printf '%s\n' "$report" | sed '/^$/d' | sort -u)"
	# shellcheck disable=SC2034 # read by callers after this returns, not within this file
	ORPHAN_STATUS="ok"
	return 0
}
