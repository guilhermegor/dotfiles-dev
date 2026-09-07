#!/bin/bash
# Installs the shared, agent-agnostic AGENTS.md that ~/.claude/CLAUDE.md
# imports via `@AGENTS.md`.
# Source file: ai_clients/shared/AGENTS.md

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "shared_agents_md.sh is meant to be sourced, not executed." >&2
    exit 1
fi

install_shared_agents_md() {
    print_status "section" "INSTALLING SHARED AGENTS.MD"

    local src
    src="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../shared" && pwd)/AGENTS.md"

    if [[ ! -f "$src" ]]; then
        print_status "error" "Source not found: $src"
        return 1
    fi

    mkdir -p "$CLAUDE_DIR"
    cp "$src" "$CLAUDE_DIR/AGENTS.md"

    print_status "success" "Installed AGENTS.md → $CLAUDE_DIR/AGENTS.md"
}
