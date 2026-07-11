#!/bin/bash
# PreToolUse (Bash matcher) hook: block a `git commit` / `git push` while HEAD is on a protected
# branch (master or main), forcing a feature-branch-first workflow.
#
# Why this exists: every user repo protects master/main — direct commits/pushes must go through
# pull -> branch -> PR. A memory note or CLAUDE.md rule ("branch first") is only advisory: nothing
# runs it before the commit. This hook is harness-run, so it turns "oops, committed on master" into
# an instant pre-commit block with a one-line remedy.
#
# Hook I/O contract (same as commit_title_length_guard.sh): silent on stdout, speaks only through
# exit code + stderr — so there is intentionally no lib/common.sh / print_status here. It fails OPEN:
# not a git repo, a detached HEAD, or any state the guard cannot resolve to a protected branch name
# exits 0 and lets the command proceed. Better to miss than to false-block a valid command.

set -u

# jq parses the hook payload; without it we cannot inspect the command, so fail open.
command -v jq >/dev/null 2>&1 || exit 0

# ponytail: two literal names cover every user repo today (memory: main/master protected
# everywhere). Make this a .git-config / env list only if a repo ever protects a differently-named
# default branch.
PROTECTED_BRANCHES='^(master|main)$'

main() {
    local payload tool command branch verb

    payload="$(cat)"
    tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"
    [[ "$tool" == "Bash" ]] || exit 0

    command="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    [[ -n "$command" ]] || exit 0

    # Only guard an actual `git commit` / `git push` (optionally rtk-prefixed), anchored to a line
    # start so a mere mention inside another argument does not trip the guard.
    if printf '%s' "$command" \
        | grep -Eq '^[[:space:]]*(rtk[[:space:]]+)?git[[:space:]]+commit([[:space:]]|$)'; then
        verb="commit"
    elif printf '%s' "$command" \
        | grep -Eq '^[[:space:]]*(rtk[[:space:]]+)?git[[:space:]]+push([[:space:]]|$)'; then
        verb="push"
    else
        exit 0
    fi

    # symbolic-ref resolves the current branch name even on an unborn branch (before the first
    # commit); it fails on a detached HEAD, which we treat as "unknown" -> fail open.
    branch="$(git symbolic-ref --short HEAD 2>/dev/null)" || exit 0
    [[ -n "$branch" ]] || exit 0

    printf '%s' "$branch" | grep -Eq "$PROTECTED_BRANCHES" || exit 0   # feature branch -> allow

    {
        echo "BLOCKED: refusing to git ${verb} on protected branch '${branch}'."
        echo
        echo "This repo protects '${branch}' — a direct ${verb} must go through a feature branch + PR."
        echo "Create one first, then re-run the SAME command:"
        echo
        echo "  git pull --ff-only && git checkout -b <type>/<short-desc>"
        echo
        echo "(A commit already staged/made on '${branch}' carries onto the new branch losslessly.)"
    } >&2
    exit 2
}

main "$@"
