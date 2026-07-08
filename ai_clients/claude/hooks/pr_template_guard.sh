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
    bodyfile="$(extract_body_file "$command")"
    if [[ -n "$bodyfile" && -r "$bodyfile" ]]; then
        body_source="$(cat "$bodyfile")"
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

extract_body_file() {
    # Echo the path passed to --body-file/-F, if present. The value may be
    # bare, "double-quoted", or 'single-quoted' (and a quoted path may contain
    # spaces) — capture the quoted token whole, then strip the surrounding
    # quotes, so a quoted path is not silently dropped (which would make the
    # guard fall back to the inline command and wrongly report every section
    # missing).
    local re val
    re='(--body-file[[:space:]=]+|-F[[:space:]]+)("[^"]+"|'\''[^'\'']+'\''|[^[:space:]]+)'
    [[ "$1" =~ $re ]] || return 0
    val="${BASH_REMATCH[2]}"
    val="${val#[\"\']}"   # strip a leading quote, if any
    val="${val%[\"\']}"   # strip a trailing quote, if any
    printf '%s' "$val"
}

main "$@"
