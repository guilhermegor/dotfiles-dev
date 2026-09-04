#!/usr/bin/env bats
#
# Unit tests for ai_clients/claude/hooks/commit_title_length_guard.sh
#
# Strategy (same as protected_branch_guard.bats):
#   - The hook is a pure stdin->exit-code filter: it reads a PreToolUse JSON payload on stdin and
#     exits 0 (allow) or 2 (block). Every test is "feed a payload, assert the exit code".
#   - `read_title_max_length()` resolves the limit from the repo's `.gitlint`, so each test runs
#     inside a throwaway repo (no `.gitlint` present → the 72-char default applies).
#   - `payload <cmd>` builds the harness JSON; `run_guard <cmd>` pipes it through the guard so the
#     pipe's exit status IS the guard's.
#
# These tests pin issue #140: the guard fails open on the heredoc form agents actually use
# (`-F- <<'MSG' ... MSG`) because a heredoc `<<` was blanket fail-open, and gitlint's T1 catches
# the too-long title instead — after the whole pre-commit gate has already run.
#
# Run locally:  bats tests/            (install with: sudo apt-get install -y bats)

setup() {
    GUARD="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/ai_clients/claude/hooks/commit_title_length_guard.sh"
    TEST_TMP="$(mktemp -d)"
    cd "$TEST_TMP"
    git init -q -b main .
    git config user.email t@t && git config user.name t
    git commit -q --allow-empty -m init
}

teardown() {
    rm -rf "$TEST_TMP"
}

payload() {
    jq -nc --arg cmd "$1" '{tool_name: "Bash", tool_input: {command: $cmd}}'
}

# Pipe the payload through the guard; the pipe's status is the guard's exit code.
run_guard() {
    payload "$1" | "$GUARD"
}

# --- issue #140: the heredoc-fed -F- form, unparsed before the fix -----------------------------

@test "BLOCKS a 75-char title via -F- fed by a quoted heredoc (would fail open pre-#140)" {
    cmd="$(cat <<'CMD'
rtk git commit -F- <<'MSG'
docs(backlog): every zero-review notice fails, including the successful one

body text
MSG
CMD
)"
    run run_guard "$cmd"
    [ "$status" -eq 2 ]
    [[ "$output" == *"75 characters"* ]]
}

@test "PASSES a 71-char title via -F- fed by a quoted heredoc" {
    cmd="$(cat <<'CMD'
rtk git commit -F- <<'MSG'
docs(backlog): every zero-review notice fails, incl the successful one

body text
MSG
CMD
)"
    run run_guard "$cmd"
    [ "$status" -eq 0 ]
}

@test "BLOCKS via -F- fed by an unquoted heredoc delimiter" {
    cmd="$(cat <<'CMD'
git commit -F- <<MSG
docs(backlog): every zero-review notice fails, including the successful one
MSG
CMD
)"
    run run_guard "$cmd"
    [ "$status" -eq 2 ]
}

@test "BLOCKS via --file=- fed by a heredoc" {
    cmd="$(cat <<'CMD'
git commit --file=- <<'MSG'
docs(backlog): every zero-review notice fails, including the successful one
MSG
CMD
)"
    run run_guard "$cmd"
    [ "$status" -eq 2 ]
}

@test "PASSES a short title via -F- fed by a heredoc" {
    cmd="$(cat <<'CMD'
git commit -F- <<'MSG'
fix: short title
MSG
CMD
)"
    run run_guard "$cmd"
    [ "$status" -eq 0 ]
}

# --- fail-open controls preserved ---------------------------------------------------------------

@test "still fails open on -F path/to/file (title genuinely not in the payload)" {
    run run_guard "git commit -F /tmp/msg.txt"
    [ "$status" -eq 0 ]
}

@test "still fails open on --file path/to/file (title genuinely not in the payload)" {
    run run_guard "git commit --file /tmp/msg.txt"
    [ "$status" -eq 0 ]
}

@test "still fails open on a heredoc that does not feed -F-" {
    cmd="$(cat <<'CMD'
cat <<'EOF' > notes.md
some notes about a very long line that would exceed the title length limit easily
EOF
CMD
)"
    run run_guard "$cmd"
    [ "$status" -eq 0 ]
}

@test "fails open when -F- heredoc coexists with an -m (ambiguous source)" {
    cmd="$(cat <<'CMD'
git commit -m wip -F- <<'MSG'
docs(backlog): every zero-review notice fails, including the successful one
MSG
CMD
)"
    run run_guard "$cmd"
    [ "$status" -eq 0 ]
}

@test "fails open when more than one heredoc is present" {
    cmd="$(cat <<'CMD'
git commit -F- <<'MSG'
docs(backlog): every zero-review notice fails, including the successful one
MSG
cat <<'EOF' > notes.md
extra
EOF
CMD
)"
    run run_guard "$cmd"
    [ "$status" -eq 0 ]
}

@test "fails open on a heredoc title containing \$(...) shell expansion" {
    cmd="$(cat <<'CMD'
git commit -F- <<'MSG'
docs: $(date) some title text that is not measured statically here at all
MSG
CMD
)"
    run run_guard "$cmd"
    [ "$status" -eq 0 ]
}

# --- the existing -m tests still pass unchanged --------------------------------------------------

@test "BLOCKS a too-long -m title" {
    run run_guard 'git commit -m "docs(backlog): every zero-review notice fails, including the successful one"'
    [ "$status" -eq 2 ]
}

@test "PASSES a short -m title" {
    run run_guard "git commit -m wip"
    [ "$status" -eq 0 ]
}

@test "fails open on an -m title containing \$(...) shell expansion" {
    run run_guard 'git commit -m "$(printf x)"'
    [ "$status" -eq 0 ]
}

@test "fails open on more than one -m (multi-paragraph, ambiguous title)" {
    run run_guard 'git commit -m title -m body'
    [ "$status" -eq 0 ]
}

@test "allows editor-mode commit with no inline message" {
    run run_guard "git commit --amend --no-edit"
    [ "$status" -eq 0 ]
}

@test "ignores non-Bash tools" {
    run bash -c "jq -nc '{tool_name: \"Read\", tool_input: {command: \"git commit -m wip\"}}' | '$GUARD'"
    [ "$status" -eq 0 ]
}
