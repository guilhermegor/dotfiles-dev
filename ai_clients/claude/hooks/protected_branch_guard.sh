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

# Drop heredoc bodies from a command string. `grep`'s `^` anchors to ANY line start, and a heredoc
# injects lines that are line-starts but not commands — so a `git push` written inside an issue/PR
# body (`gh issue create --body "$(cat <<EOF ... EOF)"`) used to trip the verb match. The opener
# line and everything outside the heredoc is kept; only the body + terminator are removed.
strip_heredoc_bodies() {
    local line delim="" trimmed in_body=0
    # `|| [[ -n "$line" ]]` so a final line with no trailing newline is not dropped.
    while IFS= read -r line || [[ -n "$line" ]]; do
        if (( in_body )); then
            trimmed="${line#"${line%%[!$'\t']*}"}"      # ltrim tabs (a `<<-` terminator may indent)
            [[ "$trimmed" == "$delim" ]] && in_body=0    # terminator -> body ends; drop this line too
            continue
        fi
        if [[ "$line" =~ \<\<-?[[:space:]]*[\"\'\\]?([[:alnum:]_]+) ]]; then
            delim="${BASH_REMATCH[1]}"
            in_body=1
        fi
        printf '%s\n' "$line"
    done
}

# Return 0 iff a `git push` ONLY deletes non-protected ref(s) — safe even on a protected branch,
# because it writes nothing there (it is the normal post-merge cleanup, always run from main).
# Decide on the TARGET refspec, never on "we happen to be on a protected branch".
push_is_safe_deletion() {
    local cmd="$1" tok ref is_del=0
    local -a toks
    read -ra toks <<< "$cmd"                            # split on IFS without globbing
    for tok in "${toks[@]}"; do
        case "$tok" in
            --delete|-d) is_del=1 ;;
            :?*|+:?*)    is_del=1 ;;                     # empty-source refspec (`:dst`) == delete dst
        esac
    done
    (( is_del )) || return 1                            # a normal push (writes a ref) -> block
    for tok in "${toks[@]}"; do
        ref="${tok#+}"; ref="${ref#:}"; ref="${ref%:}"; ref="${ref#refs/heads/}"
        [[ "$ref" =~ ^(master|main)$ ]] && return 1     # a target IS protected -> block
    done
    return 0                                            # deletes only non-protected refs -> allow
}

main() {
    local payload tool command branch verb

    payload="$(cat)"
    tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"
    [[ "$tool" == "Bash" ]] || exit 0

    command="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    [[ -n "$command" ]] || exit 0

    # A `git push`/`git commit` inside a heredoc body is prose, not a command — strip bodies first.
    command="$(printf '%s\n' "$command" | strip_heredoc_bodies)"

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

    # ponytail: refspec-aware exception (issue #54). Deleting a NON-protected ref never writes the
    # protected branch. Upgrade path: parse src:dst destinations too if pushing OTHER branches from
    # a protected branch ever needs allowing (today those stay blocked — a rare, safe false-block).
    if [[ "$verb" == "push" ]] && push_is_safe_deletion "$command"; then
        exit 0
    fi

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
