#!/bin/bash
# Installs personal skill files into ~/.claude/skills/.
# Skills are markdown files loaded by Claude's Skill tool mid-task,
# distinct from slash commands which are user-invoked.

install_skills() {
    print_status "section" "INSTALLING USER SKILLS"

    local skills_src="$SCRIPT_DIR/skills"
    local skills_dst="$CLAUDE_DIR/skills"

    if [[ ! -d "$skills_src" ]]; then
        print_status "warning" "No skills source directory found at $skills_src — skipping"
        return 0
    fi

    mkdir -p "$skills_dst"

    local installed=0
    local skipped=0

    for skill_file in "$skills_src"/*.md; do
        [[ -e "$skill_file" ]] || continue  # glob matched nothing

        local filename
        filename="$(basename "$skill_file")"
        local dst="$skills_dst/$filename"

        cp "$skill_file" "$dst"
        print_status "success" "Installed skill: $filename → $dst"
        (( installed++ ))
    done

    if (( installed == 0 )); then
        print_status "info" "No skill files found in $skills_src"
    else
        print_status "info" "Installed $installed skill(s) to $skills_dst"
    fi
}
