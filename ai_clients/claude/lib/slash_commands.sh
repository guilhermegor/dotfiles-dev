#!/bin/bash
# Installs slash commands from ai_clients/claude/commands/*.md into ~/.claude/commands/.

install_slash_commands() {
    print_status "section" "INSTALLING CUSTOM SLASH COMMANDS"

    local commands_dir="$CLAUDE_DIR/commands"
    mkdir -p "$commands_dir"

    local src_dir
    src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../commands" && pwd)"

    local count=0
    for md_file in "$src_dir"/*.md; do
        [ -f "$md_file" ] || continue
        local name
        name="$(basename "$md_file")"
        cp "$md_file" "$commands_dir/$name"
        print_status "success" "Installed /${name%.md} → $commands_dir/$name"
        (( ++count ))
    done

    if [ "$count" -eq 0 ]; then
        print_status "warning" "No command files found in $src_dir"
    fi
}
