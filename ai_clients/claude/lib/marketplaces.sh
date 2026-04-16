#!/bin/bash
# Registers external plugin marketplaces in known_marketplaces.json.

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
