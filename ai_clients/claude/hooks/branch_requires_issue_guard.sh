#!/bin/bash
# PreToolUse (Bash matcher) hook: block `git checkout -b` / `git switch -c` when the new branch
# does not trace back to a tracked issue, and point the author at /issue.
#
# Why this exists: the house rule is "an issue (and a kanban card) exists BEFORE any
# implementation" — it is what keeps the backlog the plan of record, the PR's `Closes #N` link
# honest, and the board moving on its own. Today that rule is enforced only by remembering to run
# /issue first, and the moment a branch is cut without one, the card, the `Closes #N` and the
# release notes all silently lose the trace. Prose is advisory; a PreToolUse guard is binding.
#
# Branch creation is the right interception point: it is the first observable tool call of any
# implementation. Its sibling — protected_branch_guard.sh — catches the other end of the same
# mistake (work committed straight onto main, where no branch was ever cut). Deliberately NOT a
# Write/Edit guard: gating file edits would fire on scratchpads, notes and read-modify
# exploration, which is user-hostile.
#
# Hook I/O contract (same as the other guards): silent on stdout, speaks through exit code +
# stderr, no lib/common.sh. It fails OPEN — not a git repo, no GitHub remote, no gh CLI, or any
# answer the tracker cannot give confidently exits 0 and lets the branch be created.

set -u

command -v jq >/dev/null 2>&1 || exit 0

# Prefixing the command with this makes the guard stand aside, for a genuine throwaway branch:
#   ALLOW_UNTRACKED_BRANCH=1 git checkout -b scratch/poke-at-it
ESCAPE_HATCH='ALLOW_UNTRACKED_BRANCH=1'

main() {
    local payload tool command branch issue

    payload="$(cat)"
    tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"
    [[ "$tool" == "Bash" ]] || exit 0

    command="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    [[ -n "$command" ]] || exit 0

    [[ "$command" == *"$ESCAPE_HATCH"* ]] && exit 0

    branch="$(extract_new_branch "$command")" || exit 0   # not a branch-creating command
    [[ -n "$branch" ]] || exit 0

    has_github_remote || exit 0      # no tracker to check against → nothing to enforce

    issue="$(issue_ref_in "$branch")"
    if [[ -n "$issue" ]] && issue_exists "$issue"; then
        exit 0
    fi

    block "$branch" "$issue"
}

extract_new_branch() {
    # Emit the branch name from `git checkout -b|-B <name>` / `git switch -c|-C <name>`, or return 1
    # when the command creates no branch. ponytail: a regex over the raw string, not a shell parse —
    # a name built from shell expansion is rejected below and fails open, which is the safe miss.
    local s=" $1" re
    re='[[:space:]](rtk[[:space:]]+)?git[[:space:]]+(checkout|switch)[[:space:]]+(.*[[:space:]]+)?(-b|-B|-c|-C)[[:space:]]+("[^"]*"|'\''[^'\'']*'\''|[^[:space:]]+)'
    [[ "$s" =~ $re ]] || return 1

    local val="${BASH_REMATCH[5]}"
    val="${val#[\"\']}"
    val="${val%[\"\']}"

    case "$val" in
        *'$'* | *'`'*) return 1 ;;   # dynamic name — cannot resolve statically
    esac

    printf '%s' "$val"
}

has_github_remote() {
    local url
    url="$(git remote get-url origin 2>/dev/null)" || return 1
    [[ "$url" == *github.com* ]]
}

issue_ref_in() {
    # Emit the issue number carried by the branch name, if any. Covers the shapes /issue produces
    # and the ones people type by hand: feat/short-desc-42, 42-short-desc, fix/42-short-desc.
    local branch="$1"
    [[ "$branch" =~ (^|[^0-9])([0-9]+)([^0-9]|$) ]] || return 0
    printf '%s' "${BASH_REMATCH[2]}"
}

issue_exists() {
    # True only when the tracker confirms the issue. Any other failure (offline, unauthenticated,
    # rate-limited) is "unknown", not "absent" — and unknown must not block a valid branch.
    local number="$1" err
    command -v gh >/dev/null 2>&1 || return 0

    err="$(gh issue view "$number" --json number 2>&1 >/dev/null)" && return 0

    printf '%s' "$err" | grep -qiE 'could not resolve|not found|no issue' && return 1
    return 0   # gh failed for some other reason → cannot verify → let it through
}

block() {
    local branch="$1" issue="$2"
    {
        echo "BLOCKED: branch '${branch}' does not trace back to a tracked issue."
        echo
        if [[ -n "$issue" ]]; then
            echo "The name carries #${issue}, but no such issue exists in this repo."
        else
            echo "The name carries no issue number."
        fi
        echo
        echo "Every implementation starts from an issue on the board — that is what keeps the"
        echo "backlog the plan of record, the PR's 'Closes #N' honest, and the kanban card moving."
        echo
        echo "Run /issue: it opens the issue, adds it to the kanban, and hands back the branch"
        echo "name to use here. For a genuine throwaway branch, re-run with:"
        echo
        echo "  ${ESCAPE_HATCH} <your command>"
    } >&2
    exit 2
}

main "$@"
