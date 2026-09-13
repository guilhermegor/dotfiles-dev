#!/bin/bash
# Copies the shared, agent-agnostic ai_clients/shared/AGENTS.md to a single
# client's live config location. Source of truth: ai_clients/shared/AGENTS.md
# — edit that file, never a deployed copy; every deployed copy is overwritten
# on the next `make ai_clients` run.
#
# Client-agnostic on purpose: every AI client that reads a global instructions
# file (Claude, Codex, Qwen, Copilot, Kimi, ...) calls this with its own
# destination path instead of hand-copying the source itself, so the file
# content can never drift between clients.
#
# Usage (sourced by a client's main.sh):
#   install_shared_agents_md "$SOME_CLIENT_DIR/AGENTS.md"

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "shared_agents_md.sh is meant to be sourced, not executed." >&2
    exit 1
fi

# install_shared_agents_md <destination-file>
install_shared_agents_md() {
    local dest="$1"
    if [[ -z "$dest" ]]; then
        print_status "error" "install_shared_agents_md: destination path required"
        return 1
    fi

    print_status "section" "INSTALLING SHARED AGENTS.MD"

    local src
    src="$(cd "$(dirname "${BASH_SOURCE[0]}")/../shared" && pwd)/AGENTS.md"

    if [[ ! -f "$src" ]]; then
        print_status "error" "Source not found: $src"
        return 1
    fi

    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"

    print_status "success" "Installed AGENTS.md → $dest"
}
