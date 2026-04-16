#!/bin/bash
# Installs the user-level ~/.claude/CLAUDE.md with global programming preferences.
# Source file: ai_clients/claude/config/CLAUDE.md

install_claude_md() {
    print_status "section" "INSTALLING GLOBAL CLAUDE.MD"

    local src
    src="$(cd "$(dirname "${BASH_SOURCE[0]}")/../config" && pwd)/CLAUDE.md"

    if [[ ! -f "$src" ]]; then
        print_status "error" "Source not found: $src"
        return 1
    fi

    mkdir -p "$CLAUDE_DIR"
    cp "$src" "$CLAUDE_DIR/CLAUDE.md"

    print_status "success" "Installed CLAUDE.md → $CLAUDE_DIR/CLAUDE.md"
}
