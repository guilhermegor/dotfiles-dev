#!/usr/bin/env bats
#
# Unit tests for ai_clients/claude/hooks/lib/commit_command_matcher.sh
#
# Direct tests of command_has_git_commit(), the matcher shared by
# commit_title_length_guard.sh, commit_body_wrap.sh and commit_secret_guard.sh
# (dotfiles-dev#324). Per-hook end-to-end coverage lives in each hook's own
# .bats file; this file pins the matcher's own contract so all three hooks
# inherit it correctly.
#
# Run locally:  bats tests/            (install with: sudo apt-get install -y bats)

setup() {
    MATCHER="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/ai_clients/claude/hooks/lib/commit_command_matcher.sh"
}

# --- issue #324 table: the four invocation shapes -----------------------------------------------

@test "MATCH: bare git commit" {
    run bash -c "source '$MATCHER' && command_has_git_commit 'git commit -m x'"
    [ "$status" -eq 0 ]
}

@test "MATCH: rtk git commit" {
    run bash -c "source '$MATCHER' && command_has_git_commit 'rtk git commit -m x'"
    [ "$status" -eq 0 ]
}

@test "MATCH (was MISS pre-#324): rtk proxy git commit" {
    run bash -c "source '$MATCHER' && command_has_git_commit 'rtk proxy git commit -m x'"
    [ "$status" -eq 0 ]
}

@test "MATCH (was MISS pre-#324): git add -A && rtk proxy git commit" {
    run bash -c "source '$MATCHER' && command_has_git_commit 'git add -A && rtk proxy git commit -m x'"
    [ "$status" -eq 0 ]
}

# --- additional chain operators the fix must also cover --------------------------------------

@test "MATCH: chained after ; " {
    run bash -c "source '$MATCHER' && command_has_git_commit 'git add -A; git commit -m x'"
    [ "$status" -eq 0 ]
}

@test "MATCH: chained after ||" {
    run bash -c "source '$MATCHER' && command_has_git_commit 'git add -A || git commit -m x'"
    [ "$status" -eq 0 ]
}

@test "MATCH: chained after a single pipe" {
    run bash -c "source '$MATCHER' && command_has_git_commit 'echo x | xargs -I{} git commit -m {}'"
    [ "$status" -eq 1 ]  # 'xargs -I{} git commit' — segment starts with xargs, not git/rtk: correctly no match
}

# --- false positive: a mere mention must NOT match ---------------------------------------------

@test "NO MATCH: git commit merely mentioned inside an argument" {
    run bash -c "source '$MATCHER' && command_has_git_commit 'gh pr create --body \"run git commit first\"'"
    [ "$status" -eq 1 ]
}

@test "NO MATCH: unrelated command" {
    run bash -c "source '$MATCHER' && command_has_git_commit 'git status'"
    [ "$status" -eq 1 ]
}

@test "NO MATCH: git commit-graph (word-boundary: commit is a distinct token, not a prefix match)" {
    run bash -c "source '$MATCHER' && command_has_git_commit 'git commit-graph write'"
    [ "$status" -eq 1 ]
}

# --- source-only guard -----------------------------------------------------------------------

@test "refuses direct execution (must be sourced)" {
    run bash "$MATCHER"
    [ "$status" -eq 1 ]
    [[ "$output" == *"meant to be sourced"* ]]
}
