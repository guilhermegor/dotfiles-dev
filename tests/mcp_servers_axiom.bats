#!/usr/bin/env bats
#
# Unit tests for _install_axiom() in ai_clients/claude/lib/mcp_servers.sh.
#
# Strategy: stub print_status and claude BEFORE sourcing, so no real `claude`
# CLI or network call ever runs. `claude` is a function that logs every
# invocation to $CLAUDE_LOG and answers `mcp list` from $CLAUDE_MCP_LIST.

setup() {
    print_status() { echo "[$1] $2"; }

    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_TMP="$(mktemp -d)"
    CLAUDE_LOG="$TEST_TMP/claude.log"
    CLAUDE_MCP_LIST=""
    : > "$CLAUDE_LOG"

    claude() {
        echo "claude $*" >> "$CLAUDE_LOG"
        if [ "$1" = "mcp" ] && [ "$2" = "list" ]; then
            printf '%s' "$CLAUDE_MCP_LIST"
        fi
    }
    export -f claude

    source "$REPO_ROOT/ai_clients/claude/lib/mcp_servers.sh"
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "_install_axiom registers axiom over HTTP with no .env value" {
    run _install_axiom
    [ "$status" -eq 0 ]
    [[ "$output" == *"axiom MCP registered (HTTP transport, user scope)"* ]]
    grep -q -- "--transport http axiom https://mcp.axiom.co/mcp" "$CLAUDE_LOG"
}

@test "_install_axiom is idempotent — skips when already registered" {
    CLAUDE_MCP_LIST="axiom  https://mcp.axiom.co/mcp  HTTP"

    run _install_axiom
    [ "$status" -eq 0 ]
    [[ "$output" == *"axiom MCP already registered — skipping"* ]]
    run grep -q -- "mcp add" "$CLAUDE_LOG"
    [ "$status" -ne 0 ]
}
