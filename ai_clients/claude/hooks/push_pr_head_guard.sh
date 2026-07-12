#!/bin/bash
# PostToolUse (Bash matcher) hook: after a `git push`, verify the branch's pull request actually
# took the commits — and shout if it did not.
#
# Why this exists: `git push` reporting OK, and `git rev-parse origin/<branch>` showing the new
# SHA, do NOT mean the commits are in the PR. If the PR was merged while you were still pushing,
# the merge took only the commits present AT MERGE TIME; everything pushed afterwards lives on the
# branch and nowhere else, so main silently loses them. That happened for real (filings-cvm PR #49:
# two of three commits lost, recovered only by cherry-picking onto a fresh branch and opening PR
# #50). The tell was a `gh pr view headRefOid` that stayed on the old commit — and it was
# rationalised as "API lag" and ignored.
#
# So this guard encodes the two rules that were missing:
#   1. A stale headRefOid is never dismissed as lag. It is treated as the truth.
#   2. A push to a branch whose PR is already MERGED is an emergency, not a warning.
#
# Hook I/O contract: silent on stdout, speaks through exit code + stderr (PostToolUse exit 2 feeds
# stderr back to the model — the tool has already run, so this is a loud notice, not a block). It
# fails OPEN: no gh, no PR, no network, or any unresolvable state exits 0.

set -u

command -v jq >/dev/null 2>&1 || exit 0
command -v gh >/dev/null 2>&1 || exit 0

# One retry is enough to tell a genuinely slow API from a head that is never going to move: a real
# push shows up within a second or two, a merged/orphaned one never does.
SETTLE_SECONDS=3

main() {
    local payload tool command branch local_head pr number state pr_head

    payload="$(cat)"
    tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"
    [[ "$tool" == "Bash" ]] || exit 0

    command="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    [[ -n "$command" ]] || exit 0

    printf '%s' "$command" \
        | grep -Eq '^[[:space:]]*(rtk[[:space:]]+)?git[[:space:]]+push([[:space:]]|$)' \
        || exit 0

    branch="$(git symbolic-ref --short HEAD 2>/dev/null)" || exit 0
    local_head="$(git rev-parse HEAD 2>/dev/null)" || exit 0

    pr="$(find_pr "$branch")" || exit 0
    [[ -n "$pr" ]] || exit 0          # no PR for this branch → nothing to cross-check

    number="$(printf '%s' "$pr" | jq -r '.number')"
    state="$(printf '%s' "$pr" | jq -r '.state')"
    pr_head="$(printf '%s' "$pr" | jq -r '.headRefOid')"

    [[ "$state" == "MERGED" ]] && warn_merged "$number" "$local_head"
    [[ "$state" == "OPEN" ]] || exit 0    # CLOSED / DRAFT-less states → not our problem

    [[ "$pr_head" == "$local_head" ]] && exit 0   # the PR took the push → all good

    # Give the API one genuine chance to catch up, then believe what it says.
    sleep "$SETTLE_SECONDS"
    pr="$(find_pr "$branch")" || exit 0
    state="$(printf '%s' "$pr" | jq -r '.state')"
    pr_head="$(printf '%s' "$pr" | jq -r '.headRefOid')"

    [[ "$state" == "MERGED" ]] && warn_merged "$number" "$local_head"
    [[ "$pr_head" == "$local_head" ]] && exit 0

    warn_stale "$number" "$local_head" "$pr_head"
}

find_pr() {
    # Emit the branch's PR as one JSON object (open one first, else the most recent of any state),
    # or nothing when the branch has no PR.
    local branch="$1" json
    json="$(gh pr list --head "$branch" --state open \
        --json number,state,headRefOid --limit 1 2>/dev/null)" || return 1
    [[ "$json" == "[]" || -z "$json" ]] && {
        json="$(gh pr list --head "$branch" --state all \
            --json number,state,headRefOid --limit 1 2>/dev/null)" || return 1
    }
    [[ "$json" == "[]" || -z "$json" ]] && return 0

    printf '%s' "$json" | jq -c '.[0]' 2>/dev/null
}

warn_merged() {
    local number="$1" local_head="$2"
    {
        echo "STOP: PR #${number} for this branch is already MERGED — the commits you just pushed"
        echo "are NOT in it, and are NOT in the default branch."
        echo
        echo "The merge took only the commits that existed at merge time. Your push succeeded and"
        echo "origin/<branch> now shows ${local_head:0:12}, but that work is orphaned: it is on the"
        echo "branch and nowhere else."
        echo
        echo "Recover before doing anything else:"
        echo "  1. git log --oneline <merge-base>..HEAD   — list the commits that missed the merge"
        echo "  2. branch fresh off the updated default branch, cherry-pick them across"
        echo "  3. open a second PR for the remainder"
        echo
        echo "And do not keep stacking commits onto an open PR someone may merge at any moment —"
        echo "either finish before opening it, or expect to re-open for the rest."
    } >&2
    exit 2
}

warn_stale() {
    local number="$1" local_head="$2" pr_head="$3"
    {
        echo "WARNING: PR #${number} still shows head ${pr_head:0:12}, but local HEAD is ${local_head:0:12}."
        echo
        echo "The push reported success and the PR did not move. Do NOT dismiss this as API lag —"
        echo "that is exactly the rationalisation that lost two commits in filings-cvm PR #49."
        echo "Treat the stale head as the truth and find out why:"
        echo
        echo "  gh pr view ${number} --json state,headRefOid,mergedAt"
        echo "  git rev-parse HEAD origin/\$(git symbolic-ref --short HEAD)"
        echo
        echo "If the PR turns out to be merged or its branch deleted, your commits are orphaned —"
        echo "cherry-pick them onto a fresh branch and open a second PR."
    } >&2
    exit 2
}

main "$@"
