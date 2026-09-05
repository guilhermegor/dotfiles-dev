#!/usr/bin/env bats
#
# Unit tests for ai_clients/claude/hooks/pr_self_assign.sh
#
# Strategy (same shape as kanban_lifecycle.bats): the hook is a PostToolUse stdin->stdout filter
# that reads a JSON payload and, on `gh pr create` (bare or rtk-proxied), shells out to `gh pr view`
# then `gh pr edit --add-assignee @me`. Every `gh` call is replaced by a fake `gh` script placed
# first on PATH so tests never touch the network. The fake logs every invocation to gh.log so a
# test can assert an `--add-assignee @me` edit did (or did not) happen, and with what args.
#
# Run locally:  bats tests/            (install with: sudo apt-get install -y bats)

setup() {
    HOOK="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/ai_clients/claude/hooks/pr_self_assign.sh"
    TEST_TMP="$(mktemp -d)"
    FAKE_BIN="$TEST_TMP/bin"
    mkdir -p "$FAKE_BIN"
    PATH="$FAKE_BIN:$PATH"
    GH_LOG="$TEST_TMP/gh.log"
}

teardown() {
    rm -rf "$TEST_TMP"
}

payload() {
    jq -nc --arg cmd "$1" '{tool_name: "Bash", tool_input: {command: $cmd}}'
}

# Pipe the payload through the hook; the pipe's status/stdout are the hook's.
run_hook() {
    payload "$1" | "$HOOK"
}

# Fake `gh` covering `pr view` (resolves the just-opened PR) and `pr edit` (the assignment).
# Every invocation is appended to $GH_LOG for assertions on exact args (e.g. --repo passthrough).
write_fake_gh() {
    local pr_view_status="${1:-0}" pr_edit_status="${2:-0}"
    cat > "$FAKE_BIN/gh" <<EOF
#!/bin/bash
echo "\$*" >> "$GH_LOG"
case "\$1 \$2" in
    "pr view")
        [[ "$pr_view_status" -eq 0 ]] || exit "$pr_view_status"
        echo '{"number": 42}'
        ;;
    "pr edit")
        exit "$pr_edit_status"
        ;;
    *)
        exit 1
        ;;
esac
EOF
    chmod +x "$FAKE_BIN/gh"
}

# --- simple form -----------------------------------------------------------------------------

@test "assigns @me on a plain gh pr create" {
    write_fake_gh
    run run_hook "gh pr create --title x --body y"
    [ "$status" -eq 0 ]
    [[ -f "$GH_LOG" ]]
    grep -q '^pr view' "$GH_LOG"
    grep -q '^pr edit.*--add-assignee @me' "$GH_LOG"
}

# --- rtk-proxied form --------------------------------------------------------------------------

@test "assigns @me on the rtk-proxied form" {
    write_fake_gh
    run run_hook "rtk gh pr create --title x --body y"
    [ "$status" -eq 0 ]
    grep -q '^pr edit.*--add-assignee @me' "$GH_LOG"
}

# --- form with --repo: must resolve/assign in THAT repo, not cwd's origin ----------------------

@test "honours an explicit --repo and passes it through to view and edit" {
    write_fake_gh
    run run_hook "gh pr create --repo guilhermegor/blueprintx --title x --body y"
    [ "$status" -eq 0 ]
    grep -q -- '--repo guilhermegor/blueprintx' <(grep '^pr view' "$GH_LOG")
    grep -q -- '--repo guilhermegor/blueprintx' <(grep '^pr edit' "$GH_LOG")
}

# --- fail-open: cannot assign (no network / no auth / no PR) never blocks -----------------------

@test "fails open and silently when gh pr view cannot resolve a PR" {
    write_fake_gh 1 0
    run run_hook "gh pr create --title x --body y"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    # never reached the edit step
    ! grep -q '^pr edit' "$GH_LOG"
}

@test "fails open and silently when gh pr edit itself fails" {
    write_fake_gh 0 1
    run run_hook "gh pr create --title x --body y"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- not our verb: anything other than gh pr create is a no-op ---------------------------------

@test "does nothing for an unrelated Bash command" {
    write_fake_gh
    run run_hook "git status"
    [ "$status" -eq 0 ]
    [ ! -f "$GH_LOG" ]
}

# --- no gh on PATH at all: fails open before ever trying -----------------------------------------

@test "fails open when gh is not installed" {
    rm -f "$FAKE_BIN/gh"
    run run_hook "gh pr create --title x --body y"
    [ "$status" -eq 0 ]
}
