#!/bin/bash
# PreToolUse (Bash matcher) hook: enforce the repo PR template on `gh pr create` / `gh pr edit`.
#
# Why this exists: the "a PR body must follow .github/PULL_REQUEST_TEMPLATE.md" rule recurred 7+
# times from memory/lessons alone — advisory context cannot enforce. This hook is harness-run, so
# it cannot be skipped. It BLOCKS (exit 2) a gh-pr call whose --body is missing template sections,
# feeding the template back so the body is recomposed; a compliant body passes untouched.
#
# Hook I/O contract (deliberately NOT the usual script convention): this file must stay silent on
# stdout and speak only through exit code + stderr — so there is intentionally no lib/common.sh /
# print_status here. It also fails OPEN everywhere: any uncertainty exits 0, so it can never wedge
# unrelated Bash calls.

set -u

# Fail open if jq (used to parse the hook payload) is unavailable.
command -v jq >/dev/null 2>&1 || exit 0

main() {
    local payload tool command template bodyfile body_source header line
    local missing=()

    payload="$(cat)"
    tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"
    [[ "$tool" == "Bash" ]] || exit 0

    command="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    [[ -n "$command" ]] || exit 0

    # Only guard an actual `gh pr create` / `gh pr edit` invocation (optionally `rtk`-prefixed):
    # anchor to a line start so a mere mention of "gh pr create" in e.g. a commit message body
    # does not trip the guard (which would then misread `git commit -F -` as a gh body flag).
    # ponytail: line-anchored, not a full shell parse — a body line literally starting with
    # "gh pr create" plus a body flag could still match; tighten to a real parser only if it bites.
    printf '%s' "$command" \
        | grep -Eq '^[[:space:]]*(rtk[[:space:]]+)?gh[[:space:]]+pr[[:space:]]+(create|edit)([[:space:]]|$)' \
        || exit 0

    # Only when a body is actually being set (skip title-only edits, editor-mode create, --fill).
    printf '%s' "$command" \
        | grep -Eq -- '(--body([[:space:]]|=)|-b[[:space:]]|--body-file([[:space:]]|=)|-F[[:space:]])' \
        || exit 0

    template="$(find_template)"
    [[ -n "$template" && -r "$template" ]] || exit 0   # no template anywhere → nothing to enforce

    # Inspect the --body-file contents if given, else the inline command string (an inline --body
    # embeds the section headers directly in the command text).
    #
    # A --body-file/-F flag that we cannot resolve to a readable file is NOT the same as "no
    # body-file" (dotfiles-dev#78): falling back to scanning the command string then produces a
    # verdict from the wrong source — it can false-PASS when the header texts happen to appear in
    # e.g. --title, or block with a misleading "missing sections". A verdict from unresolved input
    # is "unknown", not "approved": fail loud instead.
    bodyfile="$(extract_body_file "$command")"
    if [[ -n "$bodyfile" && -r "$bodyfile" ]]; then
        body_source="$(cat "$bodyfile")"
    elif has_body_file_flag "$command"; then
        block_unresolved_body_file "$command"
    else
        body_source="$command"
    fi

    # Every `## Heading` in the template must appear (by its text) in the body.
    while IFS= read -r line; do
        header="$(printf '%s' "$line" | sed -E 's/^#+[[:space:]]*//; s/[[:space:]]+$//')"
        [[ -n "$header" ]] || continue
        printf '%s' "$body_source" | grep -qiF -- "$header" || missing+=("$header")
    done < <(grep -E '^##[[:space:]]' "$template" 2>/dev/null)

    [[ ${#missing[@]} -eq 0 ]] && exit 0   # compliant → allow

    {
        echo "BLOCKED: this PR body does not follow the repository's PR template."
        echo "Template: $template"
        echo
        echo "Missing required sections:"
        for header in "${missing[@]}"; do
            echo "  - $header"
        done
        echo
        echo "Re-run the SAME gh command with a --body that fills EVERY section below:"
        echo "-----8<----- PULL_REQUEST_TEMPLATE -----8<-----"
        cat "$template"
        echo "-----8<----------------------------------8<-----"
    } >&2
    exit 2
}

find_template() {
    local root candidate multi
    root="$(git rev-parse --show-toplevel 2>/dev/null)"
    if [[ -n "$root" ]]; then
        for candidate in \
            "$root/.github/PULL_REQUEST_TEMPLATE.md" \
            "$root/.github/pull_request_template.md" \
            "$root/docs/PULL_REQUEST_TEMPLATE.md" \
            "$root/PULL_REQUEST_TEMPLATE.md"; do
            [[ -r "$candidate" ]] && { printf '%s' "$candidate"; return 0; }
        done
        multi="$(find "$root/.github/PULL_REQUEST_TEMPLATE" -maxdepth 1 -iname '*.md' 2>/dev/null \
            | sort | head -n1)"
        [[ -n "$multi" && -r "$multi" ]] && { printf '%s' "$multi"; return 0; }
    fi
    # Canonical personal fallback when the repo ships no template.
    local fallback="$HOME/.claude/projects/-home-guilhermegor-github-dotfiles-dev/memory/feedback_pr_template.md"
    [[ -r "$fallback" ]] && { printf '%s' "$fallback"; return 0; }
    return 0
}

# True if the command carries a --body-file/-F flag at all — regardless of whether its value
# resolves to a readable file. Lets the caller tell "no body-file given" (scan inline command)
# apart from "body-file given but unreadable" (fail loud). Mirrors the flag set in extract_body_file.
has_body_file_flag() {
    printf '%s' "$1" | grep -Eq -- '(--body-file[[:space:]=]|-F[[:space:]])'
}

block_unresolved_body_file() {
    # A PreToolUse hook sees the command BEFORE shell expansion, so `--body-file "$SP/body.md"`
    # arrives as the literal string `$SP/body.md` — unreadable. That unexpanded-variable case is
    # the common real trigger (dotfiles-dev#78), so name it in the diagnostic.
    {
        echo "BLOCKED: the --body-file could not be read, so the PR body was never verified."
        echo
        echo "A --body-file/-F was passed but does not resolve to a readable file. A template"
        echo "verdict derived from any other source (the command line, the --title) would be a"
        echo "guess, not a check — so this fails loud instead of rescanning silently."
        if printf '%s' "$1" | grep -Eq -- '(--body-file[[:space:]=]|-F[[:space:]])[^[:space:]]*[$`]'; then
            echo
            echo "The path contains an unexpanded shell variable or \$(…) — this hook sees the"
            echo "command before the shell expands it. Pass a literal path, or inline the body"
            echo "with --body \"\$(cat file.md)\" (the substituted text then reaches the hook)."
        fi
        echo
        echo "Check the path exists and is readable, then re-run the SAME gh command."
    } >&2
    exit 2
}

extract_body_file() {
    # Echo the path passed to --body-file/-F, if present. Scraping the flag out
    # of a raw shell command string has two fragilities, both handled here:
    #   * the value may be bare, "double-quoted", or 'single-quoted' (a quoted
    #     path may even contain spaces) — capture the quoted token whole, then
    #     strip the surrounding quotes;
    #   * the literal "--body-file"/"-F " may ALSO appear inside another
    #     argument (e.g. a --title that mentions it), so taking the first match
    #     grabs the wrong token. Disambiguate with the one invariant a real
    #     body-file value always satisfies: it names a readable file on disk.
    # Walk every candidate left-to-right and return the first readable one; if
    # none is readable the caller falls back to scanning the inline command.
    # ponytail: readability is the disambiguator, not a shell parse — a title
    # that names a path which happens to exist could still fool it; acceptable
    # ceiling, upgrade to real argv parsing only if that ever bites.
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

main "$@"
