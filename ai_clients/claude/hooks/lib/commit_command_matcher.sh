#!/bin/bash
# Shared matcher: "does this Bash command invoke `git commit`?" — extracted from
# commit_title_length_guard.sh, commit_body_wrap.sh and commit_secret_guard.sh (dotfiles-dev#324)
# so the three guards share ONE detection rule instead of drifting apart the way the same shape
# already has three times in this repo (#272, #293, #315).
#
# The old per-hook rule was a single anchored regex:
#
#     ^[[:space:]]*(rtk[[:space:]]+)?git[[:space:]]+commit([[:space:]]|$)
#
# It recognised exactly two shapes, and MISSED four that this repo uses every day. Each miss
# meant all three guards silently no-opped — the failure #324 was filed for:
#
#   1. `rtk proxy git commit` — the raw escape hatch documented in RTK.md ("execute raw command
#      without filtering").
#   2. A commit chained after `&&` / `;` / `|` / `||`. The `^` anchor only looked at the START of
#      the whole command string, so the everyday `git add -A && git commit ...` walked past.
#   3. An absolute path: `/usr/bin/git commit`. The global CLAUDE.md and the `dev-loop` skill both
#      mandate `/usr/bin/git` in the places where the rtk proxy must be bypassed, so this is not a
#      hypothetical spelling — it is the house style for exactly the commands most worth guarding.
#   4. Git's global flags between the binary and the subcommand: `git -C <path> commit`. Also
#      house style, since `cd <dir> &&` is discouraged (global CLAUDE.md, "Avoid `cd &&`").
#
# 3 and 4 compose into `/usr/bin/git -C "$dir" commit -F msg`, which is how commits are actually
# written here — measured on this very repo while landing #324.
#
# Parsing tokens rather than matching one regex is what makes 3 and 4 expressible at all; the
# regex would have needed a fifth and sixth alternation branch each time a new spelling appeared,
# which is the drift this file exists to stop.
#
# The per-segment anchor is preserved (dotfiles-dev#324 is explicit that losing it turns the guard
# into a false-positive machine): the binary must be the FIRST token of its segment, so a mere
# *mention* of "git commit" inside another argument (e.g. --body "run git commit first") never
# matches — it never begins a segment. Token-walking also makes `git commit-graph` a clean miss,
# where the regex needed an explicit trailing-boundary group to exclude it.
#
# ponytail: the split on &&/||/;/| is a regex over the raw string, not a real shell parse — same
# class of heuristic every guard in this repo already uses (see commit_secret_guard.sh's header).
# A chain operator that happens to appear literally inside a quoted argument can still confuse it;
# upgrade to real argv/AST parsing only if that ever produces a real false positive or miss.

set -u

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "commit_command_matcher.sh is meant to be sourced, not executed." >&2
    exit 1
fi

# Git global flags that take their value as a SEPARATE token, so the value must be skipped too
# before the subcommand can be read (`git -C /path commit` → skip `-C` *and* `/path`). The
# `--flag=value` spellings carry their value in one token and need no entry here.
_GIT_VALUE_FLAGS=' -C -c --git-dir --work-tree --namespace --exec-path --super-prefix '

# _segment_invokes_commit SEGMENT
# Return 0 if SEGMENT is a `git commit` invocation anchored at its own start: an optional
# `rtk` / `rtk proxy` prefix, the git binary (bare or an absolute path), any run of global
# flags, then the literal subcommand `commit`.
_segment_invokes_commit() {
    local segment="$1"
    local -a words=()
    read -ra words <<< "$segment"

    local i=0
    # `rtk` / `rtk proxy` prefix (RTK.md's proxy and its raw escape hatch).
    if [[ "${words[i]:-}" && "${words[i]##*/}" == "rtk" ]]; then
        i=$((i + 1))
        [[ "${words[i]:-}" == "proxy" ]] && i=$((i + 1))
    fi

    # The binary itself: `git` or any path ending in `/git`.
    [[ "${words[i]:-}" && "${words[i]##*/}" == "git" ]] || return 1
    i=$((i + 1))

    # Global flags sit between the binary and the subcommand.
    while [[ "${words[i]:-}" == -* ]]; do
        [[ "$_GIT_VALUE_FLAGS" == *" ${words[i]} "* ]] && i=$((i + 1))
        i=$((i + 1))
    done

    [[ "${words[i]:-}" == "commit" ]]
}

# command_has_git_commit COMMAND
# Return 0 if any segment of COMMAND (split on &&, ||, ; and |) is a git-commit invocation;
# return 1 otherwise.
command_has_git_commit() {
    local command="$1" segment

    while IFS= read -r segment; do
        _segment_invokes_commit "$segment" && return 0
    done <<< "$(printf '%s' "$command" | sed -E 's/(&&|\|\||;|\|)/\n/g')"

    return 1
}
