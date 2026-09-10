#!/usr/bin/env bats
#
# Unit tests for ai_clients/claude/hooks/commit_secret_guard.sh
#
# Focus: the shared matcher integration (dotfiles-dev#324) — does the hook actually scan the
# staged diff for all four `git commit` invocation shapes, and does it correctly leave a mere
# mention of "git commit" alone? A staged secret makes the signal unambiguous: BLOCKED (exit 2)
# means the matcher let the hook past its early exit and it found the secret; ALLOWED (exit 0)
# with the secret still staged means the matcher's early exit fired (a MISS).
#
# Run locally:  bats tests/            (install with: sudo apt-get install -y bats)

setup() {
    GUARD="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/ai_clients/claude/hooks/commit_secret_guard.sh"
    TEST_TMP="$(mktemp -d)"
    cd "$TEST_TMP"
    git init -q -b main .
    git config user.email t@t && git config user.name t
    git commit -q --allow-empty -m init

    printf 'aws_key = "AKIAABCDEFGHIJKLMNOP"\n' > secret.txt
    git add secret.txt
}

teardown() {
    cd /
    rm -rf "$TEST_TMP"
}

payload() {
    jq -nc --arg cmd "$1" '{tool_name: "Bash", tool_input: {command: $cmd}}'
}

run_guard() {
    payload "$1" | "$GUARD"
}

# --- issue #324 table: all four invocation shapes -----------------------------------------------

@test "#324 row 1/4: BLOCKS bare git commit over a staged secret" {
    run run_guard 'git commit -m wip'
    [ "$status" -eq 2 ]
}

@test "#324 row 2/4: BLOCKS rtk git commit over a staged secret" {
    run run_guard 'rtk git commit -m wip'
    [ "$status" -eq 2 ]
}

@test "#324 row 3/4: BLOCKS rtk proxy git commit over a staged secret (was a MISS pre-#324)" {
    run run_guard 'rtk proxy git commit -m wip'
    [ "$status" -eq 2 ]
}

@test "#324 row 4/4: BLOCKS git add -A && rtk proxy git commit over a staged secret (was a MISS pre-#324)" {
    run run_guard 'git add -A && rtk proxy git commit -m wip'
    [ "$status" -eq 2 ]
}

@test "#324 false positive: a mere mention of 'git commit' in an argument does not trip the guard" {
    run run_guard 'gh pr create --body "run git commit first"'
    [ "$status" -eq 0 ]
}
