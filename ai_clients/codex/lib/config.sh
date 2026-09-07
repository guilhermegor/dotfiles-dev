#!/bin/bash
# Installs the OpenAI Codex CLI config.toml.
# Source file: ai_clients/codex/config/config.toml

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "config.sh is meant to be sourced, not executed." >&2
    exit 1
fi

install_config() {
    print_status "section" "INSTALLING CODEX CONFIG.TOML"

    local src
    src="$(cd "$(dirname "${BASH_SOURCE[0]}")/../config" && pwd)/config.toml"

    if [[ ! -f "$src" ]]; then
        print_status "error" "Source not found: $src"
        return 1
    fi

    mkdir -p "$CODEX_DIR"
    cp "$src" "$CODEX_DIR/config.toml"

    print_status "success" "Installed config.toml → $CODEX_DIR/config.toml"
}
