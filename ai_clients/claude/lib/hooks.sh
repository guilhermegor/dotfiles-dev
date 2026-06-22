#!/bin/bash
# Installs user-level hook scripts into ~/.claude/hooks/.
#
# Source files live in ai_clients/claude/hooks/<name>.sh and are copied verbatim,
# matching the same pattern used for rules, commands, agents, and skills. The
# scripts are referenced from settings.json (e.g. the SessionStart hook).
#
# To add a new hook:
#   1. Create ai_clients/claude/hooks/<name>.sh.
#   2. Add a copy_hook_file "<name>.sh" call inside install_hooks().
#   3. Reference it from settings.json's "hooks" block.

HOOKS_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)"

copy_hook_file() {
    local src="$HOOKS_SRC_DIR/$1"
    local dest="$2/$1"

    if [[ ! -f "$src" ]]; then
        print_status "error" "Hook source not found: $src"
        return 1
    fi

    cp "$src" "$dest"
    chmod +x "$dest"
    print_status "success" "Installed $1 → $dest"
}

install_hooks() {
    print_status "section" "INSTALLING CLAUDE HOOKS"

    local hooks_dir="$CLAUDE_DIR/hooks"
    mkdir -p "$hooks_dir"

    copy_hook_file "session_start_context.sh" "$hooks_dir"
}
