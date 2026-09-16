#!/usr/bin/env bats
#
# Unit tests for ai_clients/claude/hooks/lib/free_surface.sh — free_classify_files only, which is
# pure set math over FREE_HELD_PATHS (dotfiles-dev#340). The network half is exercised through
# free_dispatch_surface in subagent_stop_sweep.bats.

setup() {
    source "$BATS_TEST_DIRNAME/../ai_clients/claude/hooks/lib/free_surface.sh"
    FREE_HELD_PATHS='a/held.sh
b/other.sh'
}

@test "no candidate file held is free" {
    run free_classify_files a/free.sh
    [[ "$output" == "free" ]]
}

@test "every candidate file held is held" {
    run free_classify_files a/held.sh b/other.sh
    [[ "$output" == "held:a/held.sh b/other.sh" ]]
}

@test "some candidate files held is would-need-a-held-file, not held" {
    run free_classify_files a/held.sh a/free.sh
    [[ "$output" == "would-need-a-held-file:a/held.sh" ]]
}

@test "a shared directory prefix is not a collision — exact path only" {
    run free_classify_files a/held.sh.bak a/
    [[ "$output" == "free" ]]
}

# One non-PR branch whose compare call fails with $COMPARE_ERR.
gh() {
    case "$*" in
        "api repos/o/r --jq .default_branch") echo master ;;
        "pr list"*) echo '[]' ;;
        "api repos/o/r/branches"*) printf 'master\nside\n' ;;
        "api repos/o/r/compare/"*) echo "gh: $COMPARE_ERR" >&2; return 1 ;;
        *) return 1 ;;
    esac
}

@test "an orphan branch (no common ancestor) is skipped, not a read failure" {
    COMPARE_ERR='No common ancestor between master and side. (HTTP 404)'
    run _free_held_paths o r
    [ "$status" -eq 0 ]
}

@test "any other compare failure fails the held-path read closed" {
    COMPARE_ERR='API rate limit exceeded (HTTP 403)'
    run _free_held_paths o r
    [ "$status" -eq 1 ]
}
