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
