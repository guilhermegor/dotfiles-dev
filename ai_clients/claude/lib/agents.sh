#!/bin/bash
# Installs custom subagent definitions into ~/.claude/agents/.
# Subagents are orchestrators that coordinate multiple skills,
# with persistent memory, model selection, and color in the task list.

install_agents() {
    print_status "section" "INSTALLING PIPELINE AGENTS"

    local agents_src="$SCRIPT_DIR/agents"
    local agents_dst="$CLAUDE_DIR/agents"

    if [[ ! -d "$agents_src" ]]; then
        print_status "warning" "No agents source directory found at $agents_src — skipping"
        return 0
    fi

    mkdir -p "$agents_dst"

    local installed=0

    for agent_file in "$agents_src"/*.md; do
        [[ -e "$agent_file" ]] || continue  # glob matched nothing

        local filename
        filename="$(basename "$agent_file")"
        local dst="$agents_dst/$filename"

        cp "$agent_file" "$dst"
        print_status "success" "Installed agent: $filename → $dst"
        (( ++installed ))
    done

    if (( installed == 0 )); then
        print_status "info" "No agent files found in $agents_src"
    else
        print_status "info" "Installed $installed agent(s) to $agents_dst"
    fi
}
