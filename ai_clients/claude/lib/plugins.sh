#!/bin/bash
# Promotes installed plugins from project scope to user scope.
# Ensures plugins load globally across all projects.

# Installs a plugin from a standalone GitHub repo (marketplace = single repo),
# then promotes it to user scope. Safe to re-run: skips clone when cache exists.
bootstrap_plugin() {
    local plugin_key="$1"      # e.g. context-mode@context-mode
    local plugin_name="$2"     # e.g. context-mode
    local marketplace_id="$3"  # e.g. context-mode
    local github_repo="$4"     # e.g. mksglu/context-mode

    local cache_dir="$CLAUDE_DIR/plugins/cache/$marketplace_id/$plugin_name"
    local installed_file="$CLAUDE_DIR/plugins/installed_plugins.json"

    if ls -d "$cache_dir"/*/ 2>/dev/null | grep -q .; then
        promote_plugin_to_user_scope "$plugin_key" "$plugin_name" "$marketplace_id"
        return 0
    fi

    print_status "info" "Bootstrapping $plugin_key from github.com/$github_repo ..."

    local tmp_dir
    tmp_dir=$(mktemp -d)

    if ! git clone --depth=1 --quiet \
            "https://github.com/$github_repo.git" "$tmp_dir" 2>/dev/null; then
        print_status "error" "Clone failed for github.com/$github_repo — skipping $plugin_key"
        rm -rf "$tmp_dir"
        return 1
    fi

    local version git_sha
    git_sha=$(git -C "$tmp_dir" rev-parse HEAD 2>/dev/null || true)
    version=$(jq -r '.version // empty' "$tmp_dir/package.json" 2>/dev/null || true)
    if [ -z "$version" ]; then
        version=$(git -C "$tmp_dir" describe --tags --abbrev=0 2>/dev/null || echo "1.0.0")
    fi

    mkdir -p "$cache_dir/$version"
    cp -r "$tmp_dir/." "$cache_dir/$version/"
    rm -rf "$tmp_dir"

    [ -f "$installed_file" ] || echo '{"plugins":{}}' > "$installed_file"

    local now entry
    now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
    entry=$(jq -n \
        --arg path "$cache_dir/$version" \
        --arg ver  "$version" \
        --arg sha  "$git_sha" \
        --arg now  "$now" \
        '{scope:"user",installPath:$path,version:$ver,installedAt:$now,lastUpdated:$now,gitCommitSha:$sha}')

    jq --arg key "$plugin_key" --argjson entry "$entry" \
        '.plugins[$key] = ((.plugins[$key] // []) + [$entry])' \
        "$installed_file" > "${installed_file}.tmp" \
        && mv "${installed_file}.tmp" "$installed_file"

    print_status "success" "Installed: $plugin_key (v$version)"
}

demote_plugin_from_user_scope() {
    local plugin_key="$1"
    local installed_file="$CLAUDE_DIR/plugins/installed_plugins.json"

    if [ ! -f "$installed_file" ]; then
        return 0
    fi

    local user_count
    user_count=$(jq -r --arg key "$plugin_key" \
        '.plugins[$key] // [] | map(select(.scope == "user")) | length' \
        "$installed_file" 2>/dev/null || echo "0")

    if [ "$user_count" -eq 0 ]; then
        return 0
    fi

    jq --arg key "$plugin_key" \
        'if (.plugins[$key] | map(select(.scope != "user")) | length) == 0
         then del(.plugins[$key])
         else .plugins[$key] = (.plugins[$key] | map(select(.scope != "user")))
         end' \
        "$installed_file" > "${installed_file}.tmp" \
        && mv "${installed_file}.tmp" "$installed_file"

    print_status "success" "Removed from user scope: $plugin_key"
}

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
        print_status "info"    "  /plugin install learning-output-style"
        print_status "info"    "  /plugin install pr-review-toolkit"
        print_status "info"    "  /plugin install supabase-postgres-best-practices"
        print_status "info"    "  /plugin install senior-prompt-engineer"
        print_status "info"    "  /plugin install clean-code"
        print_status "info"    "  /plugin install claude-mem"
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
