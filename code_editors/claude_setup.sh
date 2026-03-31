#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

LOG_FILE="$HOME/claude_configuration_$(date +%Y%m%d_%H%M%S).log"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

print_status() {
    local status="$1"
    local message="$2"
    case "$status" in
        "success") echo -e "${GREEN}[✓]${NC} ${message}" ;;
        "error")   echo -e "${RED}[✗]${NC} ${message}" >&2 ;;
        "warning") echo -e "${YELLOW}[!]${NC} ${message}" ;;
        "info")    echo -e "${BLUE}[i]${NC} ${message}" ;;
        "config")  echo -e "${CYAN}[→]${NC} ${message}" ;;
        "section")
            echo -e "\n${MAGENTA}========================================${NC}"
            echo -e "${MAGENTA} $message${NC}"
            echo -e "${MAGENTA}========================================${NC}\n"
            ;;
        *) echo -e "[ ] ${message}" ;;
    esac
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$status] $message" >> "$LOG_FILE"
}

# ============================================================================
# PREREQUISITE CHECK
# ============================================================================

check_prerequisites() {
    print_status "section" "CHECKING PREREQUISITES"

    if ! command -v jq &>/dev/null; then
        print_status "error" "jq is required but not installed"
        print_status "info" "Install: sudo apt install jq"
        exit 1
    fi
    print_status "success" "jq found"

    if ! command -v claude &>/dev/null; then
        print_status "error" "claude CLI not found in PATH"
        exit 1
    fi
    print_status "success" "claude CLI found"
}

# ============================================================================
# SETTINGS CONFIGURATION
# ============================================================================

configure_settings() {
    print_status "section" "CONFIGURING CLAUDE SETTINGS"

    local settings_file="$CLAUDE_DIR/settings.json"
    mkdir -p "$CLAUDE_DIR"

    if [ -f "$settings_file" ]; then
        cp "$settings_file" "${settings_file}.backup_$(date +%Y%m%d_%H%M%S)"
        print_status "success" "Backed up existing settings.json"
    fi

    local current='{}'
    if [ -f "$settings_file" ] && jq empty "$settings_file" 2>/dev/null; then
        current=$(cat "$settings_file")
    else
        echo '{}' > "$settings_file"
        print_status "info" "Created new settings.json"
    fi

    # Base settings to always apply
    local base_settings
    base_settings=$(cat <<'EOF'
{
    "voiceEnabled": true,
    "enabledPlugins": {
        "superpowers@claude-plugins-official": true
    },
    "extraKnownMarketplaces": {
        "claude-hud": {
            "source": {
                "source": "github",
                "repo": "jarrodwatts/claude-hud"
            }
        }
    }
}
EOF
)

    # Merge: base_settings take priority over current (preserves any extra user keys)
    echo "$current" | jq --argjson base "$base_settings" '. * $base' > "${settings_file}.tmp"

    # Add portable statusLine only if claude-hud cache is present
    # Uses Python to avoid bash quoting corruption of the '"'"' awk trick when passed via jq --arg
    local hud_cache="$CLAUDE_DIR/plugins/cache/claude-hud/claude-hud"
    if [ -d "$hud_cache" ] && ls -d "$hud_cache"/*/ &>/dev/null 2>&1; then
        python3 - "${settings_file}.tmp" "$settings_file" << 'PYEOF'
import json, sys

src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    settings = json.load(f)

# Single-quoted bash -c command with proper '"'"' quoting for the awk program.
# Built as a Python string to avoid shell quoting corruption.
sq = "'"  # single quote character
cmd = (
    "bash -c " + sq +
    "plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null"
    " | awk -F/ " + sq + '"' + sq + '"' + sq + "{ print $(NF-1) \"\\t\" $(0) }" + sq + '"' + sq + '"' + sq +
    " | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1 | cut -f2-);"
    "node_bin=$(command -v node 2>/dev/null"
    " || ls ~/.nvm/versions/node/*/bin/node 2>/dev/null | sort -V | tail -1"
    " || echo node);"
    " exec \"$node_bin\" \"${plugin_dir}dist/index.js\"" + sq
)

settings['statusLine'] = {'type': 'command', 'command': cmd}

with open(dst, 'w') as f:
    json.dump(settings, f, indent=2)
PYEOF
        print_status "success" "statusLine configured (portable node resolution)"
    else
        mv "${settings_file}.tmp" "$settings_file"
        print_status "warning" "claude-hud cache not found — statusLine skipped (install claude-hud first)"
    fi

    rm -f "${settings_file}.tmp"
    print_status "config" "Settings written to: $settings_file"
}

# ============================================================================
# MARKETPLACE REGISTRATION
# ============================================================================

register_marketplace() {
    local marketplace_id="$1"
    local github_repo="$2"

    local marketplaces_file="$CLAUDE_DIR/plugins/known_marketplaces.json"
    mkdir -p "$CLAUDE_DIR/plugins"

    [ -f "$marketplaces_file" ] || echo '{}' > "$marketplaces_file"

    if jq -e --arg id "$marketplace_id" '.[$id]' "$marketplaces_file" &>/dev/null; then
        print_status "warning" "Marketplace already registered: $marketplace_id"
        return 0
    fi

    local entry
    entry=$(jq -n \
        --arg repo "$github_repo" \
        --arg location "$CLAUDE_DIR/plugins/marketplaces/$marketplace_id" \
        --arg updated "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" \
        '{
            source: {source: "github", repo: $repo},
            installLocation: $location,
            lastUpdated: $updated
        }')

    jq --arg id "$marketplace_id" --argjson entry "$entry" \
        '. + {($id): $entry}' \
        "$marketplaces_file" > "${marketplaces_file}.tmp" \
        && mv "${marketplaces_file}.tmp" "$marketplaces_file"

    print_status "success" "Registered marketplace: $marketplace_id → $github_repo"
}

# ============================================================================
# PLUGIN USER-SCOPE PROMOTION
# ============================================================================

# Ensures a plugin has a user-scope entry in installed_plugins.json.
# If only a project-scope entry exists (from a previous install in another repo),
# this promotes it to user scope so it loads globally across all projects.
promote_plugin_to_user_scope() {
    local plugin_key="$1"    # e.g. superpowers@claude-plugins-official
    local plugin_name="$2"   # e.g. superpowers
    local marketplace_id="$3" # e.g. claude-plugins-official

    local installed_file="$CLAUDE_DIR/plugins/installed_plugins.json"

    if [ ! -f "$installed_file" ]; then
        print_status "warning" "installed_plugins.json not found — install plugins in Claude Code first:"
        print_status "info"    "  /plugin install superpowers"
        print_status "info"    "  /plugin install claude-hud"
        return 1
    fi

    # Already at user scope?
    local user_count
    user_count=$(jq -r --arg key "$plugin_key" \
        '.plugins[$key] // [] | map(select(.scope == "user")) | length' \
        "$installed_file" 2>/dev/null || echo "0")

    if [ "$user_count" -gt 0 ]; then
        print_status "warning" "Already at user scope: $plugin_key"
        return 0
    fi

    # Locate latest cached version
    local cache_dir="$CLAUDE_DIR/plugins/cache/$marketplace_id/$plugin_name"
    if [ ! -d "$cache_dir" ]; then
        print_status "warning" "Cache missing for $plugin_key — install it first in Claude Code"
        return 1
    fi

    local versioned_dir
    versioned_dir=$(ls -d "$cache_dir"/*/ 2>/dev/null | sort -V | tail -1)
    versioned_dir="${versioned_dir%/}"  # strip trailing slash

    if [ -z "$versioned_dir" ]; then
        print_status "warning" "No cached version for $plugin_key"
        return 1
    fi

    local version
    version=$(basename "$versioned_dir")

    # Reuse gitCommitSha from any existing entry
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

# ============================================================================
# MAIN
# ============================================================================

main() {
    print_status "section" "CLAUDE CODE CONFIGURATION SCRIPT"
    print_status "info" "Log: $LOG_FILE"
    print_status "info" "Claude dir: $CLAUDE_DIR"

    check_prerequisites
    configure_settings

    print_status "section" "REGISTERING MARKETPLACES"
    register_marketplace "claude-plugins-official" "anthropics/claude-plugins-official"
    register_marketplace "claude-hud"              "jarrodwatts/claude-hud"

    print_status "section" "PROMOTING PLUGINS TO USER SCOPE"
    promote_plugin_to_user_scope "superpowers@claude-plugins-official" "superpowers" "claude-plugins-official"
    promote_plugin_to_user_scope "claude-hud@claude-hud"               "claude-hud"  "claude-hud"

    print_status "section" "DONE"
    print_status "success" "Global Claude Code configuration applied to: $CLAUDE_DIR"
    print_status "info"    "Restart Claude Code for all changes to take effect"
}

main "$@"
