#!/usr/bin/env bats
#
# Unit tests for ai_clients/claude/hooks/lesson_capture_checkpoint.sh
#
# Strategy (same as protected_branch_guard.bats): the hook is a pure
# stdin->stdout JSON filter. `payload <cmd>` builds the PostToolUse payload;
# `run_hook <cmd>` pipes it through the hook so $output is its stdout.
#
# Regression pin for dotfiles-dev#98: the mirror audit (`check_mirrors` in
# session_capture_audit.sh) joins purely by the literal substring
# `<filename>.md` inside the mirror doc — it never reads heading/Tier/Lesson/
# Why prose. That gap recurred 4/4 sessions because "write the lesson in the
# mirror" was followed as full prose, and the `- **Source:** \`<file>.md\``
# field — the part that doesn't look like content — got dropped. The
# checkpoint reminder must therefore quote that exact required field at the
# PR/issue completion boundary, not just describe it.
#
# Run locally:  bats tests/            (install with: sudo apt-get install -y bats)

setup() {
    HOOK="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/ai_clients/claude/hooks/lesson_capture_checkpoint.sh"
}

payload() {
    jq -nc --arg cmd "$1" '{tool_name: "Bash", tool_input: {command: $cmd}}'
}

run_hook() {
    payload "$1" | "$HOOK"
}

@test "gh pr create reminder quotes the mandatory Source: field verbatim" {
    run run_hook "gh pr create --title x --body y"
    [ "$status" -eq 0 ]
    ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
    [[ "$ctx" == *'- **Source:** `<filename>.md`'* ]]
}

@test "rtk gh issue create also fires and quotes the field" {
    run run_hook "rtk gh issue create --title x"
    [ "$status" -eq 0 ]
    ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
    [[ "$ctx" == *'- **Source:** `<filename>.md`'* ]]
}

@test "unrelated command does not fire the checkpoint" {
    run run_hook "git status"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
