#!/bin/bash
# PreToolUse (Bash matcher) hook: block a `git commit` whose inline title line exceeds the repo's
# gitlint title-max-length (read from .gitlint, default 72) BEFORE the pre-commit gate runs.
#
# Why this exists: gitlint's T1 rule fails at the commit-msg stage, which runs AFTER the whole
# pre-commit gate (tests + coverage). On a slow gate (~15 min in some repos) a too-long title
# silently wastes an entire run before the failure surfaces. A memory note ("keep titles <= 72")
# cannot enforce this — nothing runs it before the gate. This hook is harness-run, so it turns a
# post-gate failure into an instant pre-gate block.
#
# Hook I/O contract (same as pr_template_guard.sh): silent on stdout, speaks only through exit code
# + stderr — so there is intentionally no lib/common.sh / print_status here. It fails OPEN
# everywhere: any message the guard cannot cleanly parse out of the raw command string (a heredoc,
# -F/--file, more than one -m, a combined short cluster like -am, or a title built from shell
# expansion) exits 0 and lets the commit proceed. Per the hook-command-string-scraping-fragile
# lesson, better to miss some long titles than to false-block a valid commit.

set -u

# jq parses the hook payload; without it we cannot inspect the command, so fail open.
command -v jq >/dev/null 2>&1 || exit 0

DEFAULT_TITLE_MAX_LENGTH=72

main() {
    local payload tool command title max_len

    payload="$(cat)"
    tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"
    [[ "$tool" == "Bash" ]] || exit 0

    command="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    [[ -n "$command" ]] || exit 0

    # Only guard an actual `git commit` (optionally rtk-prefixed), anchored to a line start so a
    # mere mention of "git commit" inside another argument does not trip the guard.
    printf '%s' "$command" \
        | grep -Eq '^[[:space:]]*(rtk[[:space:]]+)?git[[:space:]]+commit([[:space:]]|$)' \
        || exit 0

    # Fail open on message sources we cannot cleanly read the title out of a raw command string:
    #   * a heredoc-fed message (`<<`), whose body is not in the command string at all;
    #   * a file-fed message (`-F` / `--file`), whose title lives in a file we are not reading here.
    printf '%s' "$command" | grep -q '<<' && exit 0
    printf '%s' "$command" | grep -Eq -- '(-F[[:space:]]|--file([[:space:]]|=))' && exit 0

    title="$(extract_single_title "$command")" || exit 0   # unparseable / multi / dynamic → allow
    max_len="$(read_title_max_length)"

    (( ${#title} > max_len )) || exit 0   # within limit → allow

    {
        echo "BLOCKED: commit title is ${#title} characters; the limit is ${max_len} (gitlint T1 / title-max-length)."
        echo
        echo "  Title: ${title}"
        echo
        echo "gitlint's T1 fails at the commit-msg stage, which runs AFTER the full pre-commit gate"
        echo "(tests + coverage) — this title would waste that entire run before the error surfaces."
        echo "Shorten the title to <= ${max_len} characters and re-run the SAME commit."
    } >&2
    exit 2
}

extract_single_title() {
    # Emit the sole inline commit title (first line only), or return 1 if the message cannot be
    # cleanly parsed. Handles `-m "x"`, `-m 'x'`, `-mx`, `--message x`, `--message=x`. Leading space
    # is prepended so every flag is space-preceded, which stops `-m` from matching inside
    # `--message`. ponytail: this is a regex over the raw string, not a shell parse — a combined
    # short cluster (`-am`) finds no match and fails open (safe miss); upgrade to real argv parsing
    # only if that ever bites.
    local s=" $1" re raw matched val
    local titles=()
    re='[[:space:]](-m|--message)[[:space:]=]*("[^"]*"|'\''[^'\'']*'\''|[^[:space:]]+)'
    while [[ "$s" =~ $re ]]; do
        raw="${BASH_REMATCH[2]}"
        matched="${BASH_REMATCH[0]}"
        s="${s#*"$matched"}"          # advance past this candidate, keep looking
        val="${raw#[\"\']}"           # strip a leading quote, if any
        val="${val%[\"\']}"           # strip a trailing quote, if any
        titles+=("$val")
    done

    # Exactly one inline message is required: zero means editor-mode/--amend/--fill (nothing to
    # check), and more than one is a multi-paragraph commit whose title extraction is ambiguous.
    [[ ${#titles[@]} -eq 1 ]] || return 1

    # A title built from shell expansion cannot be measured statically — fail open rather than
    # count the literal `$(...)` / `$VAR` text.
    case "${titles[0]}" in
        *'$'* | *'`'*) return 1 ;;
    esac

    printf '%s' "${titles[0]%%$'\n'*}"   # first line only
}

read_title_max_length() {
    # Echo the repo's gitlint title-max-length, or the default when absent/unparseable. The option
    # name `line-length` is shared with [body-max-line-length], so it MUST be read only inside the
    # [title-max-length] section.
    local root gitlint val
    root="$(git rev-parse --show-toplevel 2>/dev/null)"
    gitlint="$root/.gitlint"
    if [[ -n "$root" && -r "$gitlint" ]]; then
        val="$(awk '
            /^\[/ { in_section = ($0 ~ /^\[title-max-length\]/) }
            in_section && /^[[:space:]]*line-length[[:space:]]*=/ {
                sub(/^[^=]*=[[:space:]]*/, ""); gsub(/[[:space:]]/, ""); print; exit
            }' "$gitlint" 2>/dev/null)"
        [[ "$val" =~ ^[0-9]+$ ]] && { printf '%s' "$val"; return 0; }
    fi
    printf '%s' "$DEFAULT_TITLE_MAX_LENGTH"
}

main "$@"
