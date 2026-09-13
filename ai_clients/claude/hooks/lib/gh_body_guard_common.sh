#!/bin/bash
# Shared primitives for gh body-editing guards (pr_template_guard.sh, issue_template_guard.sh):
# resolving a --repo/-R target and extracting a --body-file/-F value from a raw command string.
#
# Extracted so both guards share ONE implementation of body extraction and repo-target resolution
# instead of each carrying its own copy that drifts the way commit_command_matcher.sh's header
# already documents for the three commit guards (dotfiles-dev#324).
#
# Deliberately NOT extracted: the BLOCKED/message-formatting functions. Their wording differs
# meaningfully between "PR body" and "issue body" and each caller's existing tests are pinned to
# its own exact text — a shared parameterized formatter would risk both for a few lines of prose.

set -u

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "gh_body_guard_common.sh is meant to be sourced, not executed." >&2
    exit 1
fi

# Echo the OWNER/NAME value passed to --repo/-R, if present. gh also accepts a full URL for
# --repo; that form is not parsed here.
# ponytail: shorthand covers the overwhelmingly common case — extend to a URL form only if that
# ever bites.
extract_target_repo() {
    local s="$1" re val
    re='(--repo[[:space:]=]+|-R[[:space:]]+)("[^"]+"|'\''[^'\'']+'\''|[^[:space:]]+)'
    [[ "$s" =~ $re ]] || return 0
    val="${BASH_REMATCH[2]}"
    val="${val#[\"\']}"   # strip a leading quote, if any
    val="${val%[\"\']}"   # strip a trailing quote, if any
    [[ "$val" == */* ]] || return 0   # not owner/name shorthand → nothing to resolve from it
    printf '%s' "$val"
}

# True if the command carries a --body-file/-F flag at all — regardless of whether its value
# resolves to a readable file. Lets a caller tell "no body-file given" (scan inline command) apart
# from "body-file given but unreadable" (fail loud). Mirrors the flag set in extract_body_file.
has_body_file_flag() {
    printf '%s' "$1" | grep -Eq -- '(--body-file[[:space:]=]|-F[[:space:]])'
}

# Echo the path passed to --body-file/-F, if present. Scraping the flag out of a raw shell command
# string has two fragilities, both handled here:
#   * the value may be bare, "double-quoted", or 'single-quoted' (a quoted path may even contain
#     spaces) — capture the quoted token whole, then strip the surrounding quotes;
#   * the literal "--body-file"/"-F " may ALSO appear inside another argument (e.g. a --title that
#     mentions it), so taking the first match grabs the wrong token. Disambiguate with the one
#     invariant a real body-file value always satisfies: it names a readable file on disk.
# Walk every candidate left-to-right and return the first readable one; if none is readable the
# caller falls back to scanning the inline command.
# ponytail: readability is the disambiguator, not a shell parse — a title that names a path which
# happens to exist could still fool it; acceptable ceiling, upgrade to real argv parsing only if
# that ever bites.
extract_body_file() {
    local s="$1" re val matched
    re='(--body-file[[:space:]=]+|-F[[:space:]]+)("[^"]+"|'\''[^'\'']+'\''|[^[:space:]]+)'
    while [[ "$s" =~ $re ]]; do
        val="${BASH_REMATCH[2]}"
        matched="${BASH_REMATCH[0]}"
        val="${val#[\"\']}"   # strip a leading quote, if any
        val="${val%[\"\']}"   # strip a trailing quote, if any
        [[ -r "$val" ]] && { printf '%s' "$val"; return 0; }
        s="${s#*"$matched"}"  # advance past this candidate, keep looking
    done
    return 0
}

# Echo the FIRST --body-file/-F candidate value, unfiltered by readability. Used only for
# diagnostics once every candidate in extract_body_file has already failed the readable check —
# it needs the literal, as-written path to tell "unexpanded shell var" from "outside the project
# dir" apart, which a readability-filtered result (always empty at that point) cannot do.
extract_body_file_raw() {
    local s="$1" re val
    re='(--body-file[[:space:]=]+|-F[[:space:]]+)("[^"]+"|'\''[^'\'']+'\''|[^[:space:]]+)'
    [[ "$s" =~ $re ]] || return 0
    val="${BASH_REMATCH[2]}"
    val="${val#[\"\']}"   # strip a leading quote, if any
    val="${val%[\"\']}"   # strip a trailing quote, if any
    printf '%s' "$val"
}
