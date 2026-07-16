#!/usr/bin/env bats
#
# Unit tests for ai_clients/claude/hooks/branch_requires_issue_guard.sh
#
# Strategy:
#   - Pure stdin->exit-code filter: feed a PreToolUse JSON payload, assert 0 (allow) / 2 (block).
#   - The guard extracts a new-branch name from the command, then asks the tracker. To keep the
#     BLOCK path deterministic and offline, tests that need a tracker export
#     CLAUDE_ISSUE_TRACKER=github (the env override): a branch with NO issue number then hits
#     `block_no_ref` BEFORE any `gh` call. Tests where no branch is extracted exit 0 before the
#     tracker is ever consulted, so they need no setup.
#
# These tests pin the same-class false-positive from issue #54: the branch-name regex used to run
# greedily over the WHOLE command string, so an unrelated `-c` in a chained/piped command
# (`grep -c 'labels:'`) and a `git switch -c` mentioned inside a heredoc body were mistaken for a
# real branch creation.
#
# Run locally:  bats tests/            (install with: sudo apt-get install -y bats)

setup() {
    GUARD="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/ai_clients/claude/hooks/branch_requires_issue_guard.sh"
    TEST_TMP="$(mktemp -d)"
    cd "$TEST_TMP"
}

teardown() {
    rm -rf "$TEST_TMP"
}

payload() {
    jq -nc --arg cmd "$1" '{tool_name: "Bash", tool_input: {command: $cmd}}'
}

run_guard() {
    payload "$1" | "$GUARD"
}

# --- Defect (same class as #54): the regex must not cross command boundaries -------------------

@test "allows git switch chained with an unrelated grep -c 'labels:'" {
    export CLAUDE_ISSUE_TRACKER=github
    run run_guard "git switch main && grep -c 'labels:' foo"
    [ "$status" -eq 0 ]
}

@test "allows a git switch -c mentioned inside a heredoc body" {
    export CLAUDE_ISSUE_TRACKER=github
    cmd="$(cat <<'CMD'
gh issue create --title x --body "$(cat <<'EOF'
   git switch -c feat/example-branch
EOF
)"
CMD
)"
    run run_guard "$cmd"
    [ "$status" -eq 0 ]
}

# --- regression: real branch creations are still caught ----------------------------------------

@test "blocks a real git checkout -b with no issue ref" {
    export CLAUDE_ISSUE_TRACKER=github
    run run_guard "git checkout -b scratch/poke-at-it"
    [ "$status" -eq 2 ]
}

@test "blocks a real git switch -c with no issue ref" {
    export CLAUDE_ISSUE_TRACKER=github
    run run_guard "git switch -c wip"
    [ "$status" -eq 2 ]
}

@test "still extracts a real creation that FOLLOWS another command" {
    export CLAUDE_ISSUE_TRACKER=github
    run run_guard "git checkout main && git checkout -b feat/no-number"
    [ "$status" -eq 2 ]
}

@test "still catches a real creation with an intervening flag" {
    export CLAUDE_ISSUE_TRACKER=github
    run run_guard "git checkout -q -b feat/no-number"
    [ "$status" -eq 2 ]
}

# --- regression: non-creations and the escape hatch --------------------------------------------

@test "ignores git status" {
    run run_guard "git status"
    [ "$status" -eq 0 ]
}

@test "ignores git -c config on a commit (not a checkout/switch)" {
    export CLAUDE_ISSUE_TRACKER=github
    run run_guard "git -c user.name=x commit -m y"
    [ "$status" -eq 0 ]
}

@test "honors the escape hatch" {
    export CLAUDE_ISSUE_TRACKER=github
    run run_guard "ALLOW_UNTRACKED_BRANCH=1 git checkout -b scratch/anything"
    [ "$status" -eq 0 ]
}

@test "ignores non-Bash tools" {
    run bash -c "jq -nc '{tool_name: \"Read\", tool_input: {command: \"git checkout -b feat/x\"}}' | '$GUARD'"
    [ "$status" -eq 0 ]
}
