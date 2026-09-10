#!/bin/bash
# Shared matcher: "does this Bash command invoke `git commit`?" — extracted from
# commit_title_length_guard.sh, commit_body_wrap.sh and commit_secret_guard.sh (dotfiles-dev#324)
# so the three guards share ONE detection regex instead of drifting apart the way the same shape
# already has three times in this repo (#272, #293, #315).
#
# Two gaps fixed here that the old inline `grep -Eq '^...'` per hook missed:
#   1. `rtk proxy git commit` — the raw escape hatch documented in RTK.md ("execute raw command
#      without filtering"). Only `rtk git commit` and bare `git commit` were recognised before.
#   2. A commit chained after `&&` / `;` / `|` / `||` — the old `^` anchor only looked at the
#      START of the whole command string, so `git add -A && git commit ...` escaped detection
#      even with no `rtk` involved at all.
#
# The per-segment anchor is kept (dotfiles-dev#324 is explicit that losing it turns the guard
# into a false-positive machine): each segment is still anchored at ITS OWN start, so a mere
# *mention* of "git commit" inside another argument (e.g. --body "run git commit first") does
# not match — it never begins a segment.
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

# Bare `git commit`, `rtk git commit`, or `rtk proxy git commit`, anchored to the start of
# whatever segment it appears in.
_COMMIT_SEGMENT_RE='^[[:space:]]*(rtk[[:space:]]+(proxy[[:space:]]+)?)?git[[:space:]]+commit([[:space:]]|$)'

# command_has_git_commit COMMAND
# Return 0 if any segment of COMMAND (split on &&, ||, ; and |) is a git-commit invocation
# (bare / rtk-prefixed / rtk-proxy-prefixed); return 1 otherwise.
command_has_git_commit() {
    local command="$1" segment

    while IFS= read -r segment; do
        [[ "$segment" =~ $_COMMIT_SEGMENT_RE ]] && return 0
    done <<< "$(printf '%s' "$command" | sed -E 's/(&&|\|\||;|\|)/\n/g')"

    return 1
}
