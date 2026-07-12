#!/bin/bash
# PreToolUse (Bash matcher) hook: reflow the BODY of a file-fed `git commit` message to <= 72
# characters per line, in place, BEFORE the commit runs — so gitlint's B1 (body-max-line-length)
# passes on the first attempt.
#
# Why this exists: "wrap the body at 72" is a convention, and a convention is probabilistic — it
# holds only while the author remembers it. gitlint is the deterministic catcher, but it fires at
# the commit-msg stage, i.e. after the whole pre-commit gate, costing a full retry per miss. A
# hook that merely *validates* would just duplicate gitlint; only a hook that *fixes* removes the
# retry. This one rewrites the message file the commit is about to read.
#
# Complements commit_title_length_guard.sh: the title is BLOCKED (shortening it is an editorial
# decision only the author can make), the body is AUTO-WRAPPED (reflowing prose is mechanical).
#
# Hook I/O contract (same as the other guards): no status output, no lib/common.sh. It fails OPEN
# everywhere — an unparseable command, a missing or unwritable message file, or an unreadable
# payload all exit 0 and let the commit proceed untouched.

set -u

# jq parses the hook payload; without it we cannot inspect the command, so fail open.
command -v jq >/dev/null 2>&1 || exit 0

# 72, not the repo's gitlint setting: 72 is safe under both the git convention (72) and gitlint's
# default (80), so the hook never has to read each repo's .gitlint to pick a target.
BODY_MAX_LENGTH=72

main() {
    local payload tool command msg_file reflowed

    payload="$(cat)"
    tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"
    [[ "$tool" == "Bash" ]] || exit 0

    command="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    [[ -n "$command" ]] || exit 0

    # Only act on an actual `git commit` (optionally rtk-prefixed), anchored to a line start so a
    # mere mention of "git commit" inside another argument does not trip the hook.
    printf '%s' "$command" \
        | grep -Eq '^[[:space:]]*(rtk[[:space:]]+)?git[[:space:]]+commit([[:space:]]|$)' \
        || exit 0

    msg_file="$(extract_message_file "$command")" || exit 0
    [[ -f "$msg_file" && -w "$msg_file" ]] || exit 0

    reflowed="$(reflow_body "$msg_file")" || exit 0
    [[ "$reflowed" == "$(cat "$msg_file")" ]] && exit 0   # already within the limit → no-op

    printf '%s\n' "$reflowed" > "$msg_file" || exit 0
    announce "$msg_file"
}

extract_message_file() {
    # Emit the sole `-F` / `--file` path, or return 1 when there is not exactly one. ponytail: this
    # only handles the file-fed form, which is what /commit-code emits (`git commit -F
    # /tmp/commit_msg.txt`). An inline `-m "<body>"` would have to be rewritten through the hook's
    # `updatedInput`, i.e. re-quoting a shell command from a regex match — not worth the blast
    # radius; gitlint still catches those. Add it only if inline bodies start showing up.
    local s=" $1" re raw matched val
    local files=()
    re='[[:space:]](-F|--file)[[:space:]=]*("[^"]*"|'\''[^'\'']*'\''|[^[:space:]]+)'
    while [[ "$s" =~ $re ]]; do
        raw="${BASH_REMATCH[2]}"
        matched="${BASH_REMATCH[0]}"
        s="${s#*"$matched"}"          # advance past this candidate, keep looking
        val="${raw#[\"\']}"
        val="${val%[\"\']}"
        files+=("$val")
    done

    [[ ${#files[@]} -eq 1 ]] || return 1

    # A path built from shell expansion cannot be resolved statically — fail open rather than
    # rewrite the wrong file.
    case "${files[0]}" in
        *'$'* | *'`'* | '-') return 1 ;;
    esac

    printf '%s' "${files[0]}"
}

reflow_body() {
    # Emit the message with every over-long body line split at word boundaries. Never joins lines,
    # so it can only shorten a line, never restructure a paragraph — and it is idempotent.
    #
    # Left untouched: the subject (line 1), fenced and indented code, trailer lines
    # (Co-Authored-By:, Signed-off-by:, …), and any single token longer than the limit (a URL or a
    # long path is left over-length rather than corrupted by a break).
    awk -v max="$BODY_MAX_LENGTH" '
        function wrap(line,   lead, rest, marker, cont, prefix, words, n, i, cur, cand) {
            match(line, /^[[:space:]]*/)
            lead = substr(line, 1, RLENGTH)
            rest = substr(line, RLENGTH + 1)

            # A bullet / numbered marker is kept on the first line; continuation lines are indented
            # to sit under its text, so the list structure survives the wrap.
            marker = ""
            if (match(rest, /^([-*+]|[0-9]+[.)])[[:space:]]+/)) {
                marker = substr(rest, 1, RLENGTH)
                rest = substr(rest, RLENGTH + 1)
            }
            cont = lead
            for (i = 0; i < length(marker); i++) cont = cont " "

            prefix = lead marker
            n = split(rest, words, /[ \t]+/)
            cur = ""
            for (i = 1; i <= n; i++) {
                if (words[i] == "") continue
                cand = (cur == "" ? prefix words[i] : cur " " words[i])
                if (cur != "" && length(cand) > max) {
                    print cur
                    cur = cont words[i]     # an over-long lone token stays whole on its own line
                } else {
                    cur = cand
                }
            }
            if (cur != "") print cur
        }

        NR == 1                         { print; next }   # subject: the author owns its length
        /^[[:space:]]*(```|~~~)/        { fence = !fence; print; next }
        fence                           { print; next }
        length($0) <= max               { print; next }
        /^(\t|[[:space:]]{4,})/         { print; next }   # indented code block
        /^[A-Za-z][A-Za-z-]*:[[:space:]]/ { print; next } # trailer line
                                        { wrap($0) }
    ' "$1"
}

announce() {
    # Tell the model the file it is about to commit no longer matches what it wrote. stdout JSON is
    # only read on exit 0, which is exactly the path we are on.
    jq -n --arg file "$1" --argjson max "$BODY_MAX_LENGTH" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            additionalContext: ("commit_body_wrap: reflowed the commit body in \($file) to <= \($max) chars per line (gitlint B1). The committed message differs slightly from the one you composed; the subject is unchanged.")
        }
    }' 2>/dev/null || true
}

main "$@"
