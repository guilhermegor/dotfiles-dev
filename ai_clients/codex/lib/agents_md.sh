#!/bin/bash
# Installs the global OpenAI Codex CLI AGENTS.md.
# Source file: ai_clients/codex/config/AGENTS.md

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "agents_md.sh is meant to be sourced, not executed." >&2
    exit 1
fi

install_agents_md() {
    print_status "section" "INSTALLING GLOBAL AGENTS.MD"

    local src
    src="$(cd "$(dirname "${BASH_SOURCE[0]}")/../config" && pwd)/AGENTS.md"

    if [[ ! -f "$src" ]]; then
        print_status "error" "Source not found: $src"
        return 1
    fi

    mkdir -p "$CODEX_DIR"
    cp "$src" "$CODEX_DIR/AGENTS.md"

    print_status "success" "Installed AGENTS.md → $CODEX_DIR/AGENTS.md"
}
