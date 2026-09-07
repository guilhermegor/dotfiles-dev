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
    local missing=() target_repo root

    payload="$(cat)"
    tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"
    [[ "$tool" == "Bash" ]] || exit 0

    command="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    [[ -n "$command" ]] || exit 0

    # Only guard an actual `gh pr create` / `gh pr edit` invocation (optionally `rtk`-prefixed):
    # anchor to a line start so a mere mention of "gh pr create" in e.g. a commit message body
    # does not trip the guard (which would then misread `git commit -F -` as a gh body flag).
    # This anchor is ALSO what keeps `gh issue create` untouched (dotfiles-dev#154 defect 1): an
    # issue has no PR-template obligation, and "pr" is a required literal here, so "gh issue
    # create" never reaches this point.
    # ponytail: line-anchored, not a full shell parse — a body line literally starting with
    # "gh pr create" plus a body flag could still match; tighten to a real parser only if it bites.
    printf '%s' "$command" \
        | grep -Eq '^[[:space:]]*(rtk[[:space:]]+)?gh[[:space:]]+pr[[:space:]]+(create|edit)([[:space:]]|$)' \
        || exit 0

    # Only when a body is actually being set (skip title-only edits, editor-mode create, --fill).
    printf '%s' "$command" \
        | grep -Eq -- '(--body([[:space:]]|=)|-b[[:space:]]|--body-file([[:space:]]|=)|-F[[:space:]])' \
        || exit 0

    # Resolve the TARGET repo's template, not the session cwd's (dotfiles-dev#154 defect 2). A
    # `--repo`/`-R owner/name` on the gh command itself always wins over cwd — the command can
    # target a different repo than the session is sitting in (`cd other-repo; gh pr create --repo
    # this-repo ...` is routine in a multi-repo session), and judging it against the wrong repo's
    # template is worse than not judging it at all (it fails in the *permitting* direction too).
    target_repo="$(extract_target_repo "$command")"
    if [[ -n "$target_repo" ]]; then
        root="$HOME/github/${target_repo##*/}"
        [[ -d "$root/.git" ]] || block_unresolved_repo "$target_repo" "$root"
        template="$(find_template "$root" 0)"   # no personal-template fallback for a foreign repo
    else
        root="$(git rev-parse --show-toplevel 2>/dev/null)"
        template="$(find_template "$root" 1)"
    fi
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
        block_unresolved_body_file "$command" "$root"
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

# $1: repo root to search (may be empty). $2: 1 to fall back to the canonical personal template
# when the root ships none, 0 to skip that fallback. The fallback is only correct for the
# session's OWN repo — imposing a personal template preference onto an unrelated --repo target
# would be a scope overreach the caller (main) must opt out of explicitly (dotfiles-dev#154).
find_template() {
    local root="$1" allow_personal_fallback="${2:-1}" candidate multi
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
    [[ "$allow_personal_fallback" -eq 1 ]] || return 0   # target repo has no template → pass
    # Canonical personal fallback when the repo ships no template.
    local fallback="$HOME/.claude/projects/-home-guilhermegor-github-dotfiles-dev/memory/feedback_pr_template.md"
    [[ -r "$fallback" ]] && { printf '%s' "$fallback"; return 0; }
    return 0
}

# Echo the OWNER/NAME value passed to --repo/-R, if present. gh also accepts a full URL for
# --repo; that form is not parsed here.
# ponytail: shorthand covers the issue's repro and the overwhelmingly common case — extend to a
# URL form only if that ever bites.
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

block_unresolved_repo() {
    # A verdict from a template we could not locate is "unknown", not "approved" — same principle
    # as block_unresolved_body_file below. This must never share text with the "Missing required
    # sections" block: "I couldn't check" and "I checked and it's wrong" are different states.
    local target="$1" tried="$2"
    {
        echo "BLOCKED: could not resolve the PR template for --repo $target."
        echo
        echo "This gh command targets a different repository than the session's cwd. Its local"
        echo "checkout was expected at $tried but was not found there, so this repo's"
        echo ".github/PULL_REQUEST_TEMPLATE.md could not be read."
        echo
        echo "This is NOT a verdict on the PR body — the template could not be located, so"
        echo "nothing was checked."
        echo
        echo "Clone the repo to $tried (or correct the --repo value), then re-run the SAME"
        echo "gh command."
    } >&2
    exit 2
}

# True if the command carries a --body-file/-F flag at all — regardless of whether its value
# resolves to a readable file. Lets the caller tell "no body-file given" (scan inline command)
# apart from "body-file given but unreadable" (fail loud). Mirrors the flag set in extract_body_file.
has_body_file_flag() {
    printf '%s' "$1" | grep -Eq -- '(--body-file[[:space:]=]|-F[[:space:]])'
}

block_unresolved_body_file() {
    # A PreToolUse hook sees the command BEFORE shell expansion, AND runs sandboxed to the
    # project directory — either fact alone can make an otherwise-fine --body-file unreadable
    # HERE while the file is perfectly readable everywhere else. A generic "check the path" then
    # sends the author chasing a typo or permission bug that does not exist (dotfiles-dev#109),
    # so name the actual cause: an unexpanded shell variable, a path outside the project
    # directory (this hook's filesystem view is sandboxed to the project — dotfiles-dev#109), or
    # the file genuinely not existing yet (dotfiles-dev#78, e.g. create-and-consume in one call).
    local cmd="$1" root="${2:-}" path
    path="$(extract_body_file_raw "$cmd")"

    {
        echo "BLOCKED: the --body-file could not be read, so the PR body was never verified."
        echo
        echo "A --body-file/-F was passed but does not resolve to a readable file. A template"
        echo "verdict derived from any other source (the command line, the --title) would be a"
        echo "guess, not a check — so this fails loud instead of rescanning silently."
        if [[ "$path" == *'$'* || "$path" == *'`'* ]]; then
            echo
            echo "The path contains an unexpanded shell variable or \$(…) — this hook sees the"
            echo "command before the shell expands it. Pass a literal path, or inline the body"
            echo "with --body \"\$(cat file.md)\" (the substituted text then reaches the hook)."
        elif [[ -n "$root" && "$path" == /* && "$path" != "$root"/* ]]; then
            echo
            echo "The path is outside the project directory ($root), which this hook cannot"
            echo "read — its filesystem view is sandboxed to the project. Move the file inside"
            echo "the repo (e.g. $root/.git/, which stays out of the worktree and any commit),"
            echo "then re-run the SAME gh command with the new path."
        else
            echo
            echo "If the file is created and consumed in the same command (e.g. \`cat >file &&"
            echo "gh pr create --body-file file\`), this hook still sees the pre-write state —"
            echo "write the file in a prior, separate step, then re-run this command. Otherwise"
            echo "check the path exists and is readable, then re-run the SAME gh command."
        fi
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

main "$@"
