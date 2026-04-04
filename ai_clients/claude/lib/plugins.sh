#!/bin/bash
# Promotes installed plugins from project scope to user scope.
# Ensures plugins load globally across all projects.

promote_plugin_to_user_scope() {
    local plugin_key="$1"      # e.g. superpowers@claude-plugins-official
    local plugin_name="$2"     # e.g. superpowers
    local marketplace_id="$3"  # e.g. claude-plugins-official

    local installed_file="$CLAUDE_DIR/plugins/installed_plugins.json"

    if [ ! -f "$installed_file" ]; then
        print_status "warning" "installed_plugins.json not found — install plugins in Claude Code first:"
        print_status "info"    "  /plugin install superpowers"
        print_status "info"    "  /plugin install claude-hud"
        print_status "info"    "  /plugin install codex-plugin-cc"
        print_status "info"    "  /plugin install copilot-plugin-cc"
        print_status "info"    "  /plugin install typescript-lsp"
        print_status "info"    "  /plugin install html-lsp"
        print_status "info"    "  /plugin install css-lsp"
        print_status "info"    "  /plugin install mssql-lsp"
        print_status "info"    "  /plugin install postgres-lsp"
        print_status "info"    "  /plugin install sqlite-lsp"
        print_status "info"    "  /plugin install mysql-lsp"
        print_status "info"    "  /plugin install mariadb-lsp"
        print_status "info"    "  /plugin install mongodb-lsp"
        print_status "info"    "  /plugin install json-lsp"
        print_status "info"    "  /plugin install yaml-lsp"
        print_status "info"    "  /plugin install toml-lsp"
        print_status "info"    "  /plugin install security-guidance"
        print_status "info"    "  /plugin install code-review"
        print_status "info"    "  /plugin install code-simplifier"
        print_status "info"    "  /plugin install feature-dev"
        print_status "info"    "  /plugin install frontend-design"
        print_status "info"    "  /plugin install math-olympiad"
        print_status "info"    "  /plugin install learning-output-style"
        print_status "info"    "  /plugin install pr-review-toolkit"
        print_status "info"    "  /plugin install supabase-postgres-best-practices"
        return 0
    fi

    local user_count
    user_count=$(jq -r --arg key "$plugin_key" \
        '.plugins[$key] // [] | map(select(.scope == "user")) | length' \
        "$installed_file" 2>/dev/null || echo "0")

    if [ "$user_count" -gt 0 ]; then
        print_status "warning" "Already at user scope: $plugin_key"
        return 0
    fi

    local cache_dir="$CLAUDE_DIR/plugins/cache/$marketplace_id/$plugin_name"
    if [ ! -d "$cache_dir" ]; then
        print_status "warning" "Cache missing for $plugin_key — install it first in Claude Code"
        return 0
    fi

    local versioned_dir
    versioned_dir=$(ls -d "$cache_dir"/*/ 2>/dev/null | sort -V | tail -1)
    versioned_dir="${versioned_dir%/}"

    if [ -z "$versioned_dir" ]; then
        print_status "warning" "No cached version for $plugin_key"
        return 0
    fi

    local version
    version=$(basename "$versioned_dir")

    local git_sha
    git_sha=$(jq -r --arg key "$plugin_key" \
        '.plugins[$key] // [] | first | .gitCommitSha // ""' \
        "$installed_file")

    local entry
    entry=$(jq -n \
        --arg install_path "$versioned_dir" \
        --arg version "$version" \
        --arg sha "$git_sha" \
        --arg now "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" \
        '{
            scope: "user",
            installPath: $install_path,
            version: $version,
            installedAt: $now,
            lastUpdated: $now,
            gitCommitSha: $sha
        }')

    jq --arg key "$plugin_key" --argjson entry "$entry" \
        '.plugins[$key] = ((.plugins[$key] // []) + [$entry])' \
        "$installed_file" > "${installed_file}.tmp" \
        && mv "${installed_file}.tmp" "$installed_file"

    print_status "success" "Promoted to user scope: $plugin_key (v$version)"
}
