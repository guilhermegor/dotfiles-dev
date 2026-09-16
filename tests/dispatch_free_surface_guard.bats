#!/usr/bin/env bats
#
# Unit tests for ai_clients/claude/hooks/dispatch_free_surface_guard.sh (dotfiles-dev#396)
#
# Strategy (same as subagent_stop_sweep.bats): `gh` is stubbed on PATH with a real executable
# script written per-test, so gate_free_surface (lib/free_surface.sh) and the hook's own
# `gh repo view` never hit the network. `git` is the real `/usr/bin/git` against a throwaway
# local repo. The hook is invoked as an external process (it is a Stop hook script, not sourced),
# so the stub has to be a real file on PATH, not a shell function.
#
# `transcript_*` helpers build throwaway JSONL transcripts. Invoking s:dev-loop is a literal
# '"skill":"dev-loop"' substring — the same shape the Skill tool's own tool_use input serialises
# to (see any real transcript under ~/.claude/projects/*/*.jsonl). An unresolved Agent dispatch is
# a `tool_use` of name "Agent" with no later `tool_result` carrying the same `tool_use_id`.
#
# Run locally:  bats tests/            (install with: sudo apt-get install -y bats)

setup() {
    HOOK="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/ai_clients/claude/hooks/dispatch_free_surface_guard.sh"
    TEST_TMP="$(mktemp -d)"
    cd "$TEST_TMP" || return 1
    git init -q -b main .
    git config user.email t@t && git config user.name t
    git commit -q --allow-empty -m init

    BIN="$TEST_TMP/bin"
    mkdir -p "$BIN"
    PATH="$BIN:$PATH"
    export PATH
}

teardown() {
    rm -rf "$TEST_TMP"
}

# stub_gh ISSUES [FAIL_DEFAULT_BRANCH]
# ISSUES = newline-separated open issue numbers. No open PRs and no graphql claims, so every
# listed issue comes back unclaimed. FAIL_DEFAULT_BRANCH=1 makes the very first gate call fail,
# exercising the UNKNOWN path (gate_free_surface returns 1).
stub_gh() {
    local issues="$1" fail="${2:-0}"
    cat >"$BIN/gh" <<STUB
#!/bin/bash
case "\$*" in
"repo view --json nameWithOwner -q .nameWithOwner") echo "acme/widgets" ;;
"api repos/acme/widgets --jq .default_branch")
    [ "$fail" = 1 ] && exit 1
    echo main
    ;;
"pr list --repo acme/widgets"*) echo '[]' ;;
"api repos/acme/widgets/branches"*) echo main ;;
"api graphql"*) echo '{"data":{"search":{"pageInfo":{"hasNextPage":false},"nodes":[]}}}' ;;
"issue list --repo acme/widgets"*) printf '%s\n' '$issues' ;;
*) exit 1 ;;
esac
STUB
    chmod +x "$BIN/gh"
}

payload() {
    # $1 = transcript path, $2 = stop_hook_active ("true"/"false", default false)
    jq -nc --arg t "$1" --arg cwd "$TEST_TMP" --arg active "${2:-false}" \
        '{cwd: $cwd, transcript_path: $t, stop_hook_active: ($active == "true")}'
}

run_guard() {
    payload "$1" "${2:-false}" | "$HOOK"
}

transcript_no_dev_loop() {
    local f="$TEST_TMP/transcript.jsonl"
    echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"x1","name":"Bash","input":{"command":"ls"}}]}}' >"$f"
    printf '%s\n' "$f"
}

transcript_dev_loop_agent_running() {
    local f="$TEST_TMP/transcript.jsonl"
    {
        echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"skill1","name":"Skill","input":{"skill":"dev-loop"}}]}}'
        echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"agent1","name":"Agent","input":{}}]}}'
    } >"$f"
    printf '%s\n' "$f"
}

transcript_dev_loop_agent_resolved() {
    local f="$TEST_TMP/transcript.jsonl"
    {
        echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"skill1","name":"Skill","input":{"skill":"dev-loop"}}]}}'
        echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"agent1","name":"Agent","input":{}}]}}'
        echo '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"agent1","content":"done"}]}}'
    } >"$f"
    printf '%s\n' "$f"
}

# --- fail-open prerequisites ---------------------------------------------------------------

@test "exits 0 when stop_hook_active is true (one nudge per turn)" {
    stub_gh '42'
    t="$(transcript_dev_loop_agent_resolved)"
    run run_guard "$t" "true"
    [ "$status" -eq 0 ]
}

@test "fails open outside a git repo" {
    cd "$(mktemp -d)"
    t="$TEST_TMP/does-not-matter.jsonl"
    echo '{"type":"assistant"}' >"$t"
    run run_guard "$t"
    [ "$status" -eq 0 ]
}

@test "exits 0 when this session never invoked s:dev-loop" {
    stub_gh '42'
    t="$(transcript_no_dev_loop)"
    run run_guard "$t"
    [ "$status" -eq 0 ]
}

@test "exits 0 when a subagent of this session is still unresolved" {
    stub_gh '42'
    t="$(transcript_dev_loop_agent_running)"
    run run_guard "$t"
    [ "$status" -eq 0 ]
}

# --- the guard's actual job: block when free surface has unclaimed work --------------------

@test "blocks (exit 2) when free issues exist and no subagent is running" {
    stub_gh '42'
    t="$(transcript_dev_loop_agent_resolved)"
    run run_guard "$t"
    [ "$status" -eq 2 ]
    [[ "$output" == *"#42"* ]]
    [[ "$output" == *"do not stop here without dispatching"* ]]
}

@test "exits 0 when the gate is readable and nothing is unclaimed" {
    stub_gh ''
    t="$(transcript_dev_loop_agent_resolved)"
    run run_guard "$t"
    [ "$status" -eq 0 ]
}

@test "blocks (exit 2) and says UNREADABLE, never silently allows, on a gate failure" {
    stub_gh '42' 1
    t="$(transcript_dev_loop_agent_resolved)"
    run run_guard "$t"
    [ "$status" -eq 2 ]
    [[ "$output" == *"UNREADABLE"* ]]
    [[ "$output" != *"do not stop here without dispatching"* ]]
}
