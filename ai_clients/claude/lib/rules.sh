#!/bin/bash
# Installs user-level rule files into ~/.claude/rules/.
# Each file uses path-scoped frontmatter so it only loads for matching file types.
#
# Source files live in ai_clients/claude/rules/<lang>.md and are copied verbatim,
# matching the same pattern used for commands, agents, and skills.
#
# To add a new language:
#   1. Create ai_clients/claude/rules/<lang>.md with path-scoped frontmatter.
#   2. Write an install_<lang>_rules() function below that calls copy_rule_file.
#   3. Add a call to it inside install_rules().

RULES_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../rules" && pwd)"

copy_rule_file() {
    local src="$RULES_SRC_DIR/$1"
    local dest="$2/$1"

    if [[ ! -f "$src" ]]; then
        print_status "error" "Rule source not found: $src"
        return 1
    fi

    cp "$src" "$dest"
    print_status "success" "Installed $1 → $dest"
}

# ── Python ────────────────────────────────────────────────────────────────────

install_python_rules() {
    local rules_dir="$1"
    copy_rule_file "python.md" "$rules_dir"
}

# ── Dispatcher ────────────────────────────────────────────────────────────────

install_rules() {
    print_status "section" "INSTALLING CLAUDE RULES"

    local rules_dir="$CLAUDE_DIR/rules"
    mkdir -p "$rules_dir"

    install_python_rules "$rules_dir"
    # install_typescript_rules "$rules_dir"  # future
    # install_go_rules "$rules_dir"          # future
}
