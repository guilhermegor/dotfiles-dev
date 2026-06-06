#!/bin/bash
# Installs user-scoped MCP servers for Claude Code.
# Reads API keys from the project root .env file.

install_mcp_servers() {
    print_status "section" "INSTALLING MCP SERVERS"

    local project_root
    project_root="$(cd "$SCRIPT_DIR/../.." && pwd)"
    local env_file="$project_root/.env"

    if [ ! -f "$env_file" ]; then
        print_status "error" "No .env file found at: $env_file — skipping MCP server setup"
        return 1
    fi

    _install_context7 "$env_file"
    _install_tavily "$env_file"
    _install_playwright_mcp
    _install_notesnook
}

_install_tavily() {
    local env_file="$1"

    local tavily_key
    tavily_key=$(grep -E '^TAVILY_API_KEY=' "$env_file" | head -1 | cut -d'=' -f2-)

    if [ -z "$tavily_key" ]; then
        print_status "warning" "TAVILY_API_KEY not found in .env — skipping tavily"
        return 0
    fi

    if claude mcp list 2>/dev/null | grep -q '^tavily'; then
        print_status "info" "tavily MCP already registered — skipping"
        return 0
    fi

    claude mcp add --scope user \
        --transport http \
        tavily \
        "https://mcp.tavily.com/mcp/?tavilyApiKey=${tavily_key}"

    print_status "success" "tavily MCP registered (HTTP transport, user scope)"
}

_install_playwright_mcp() {
    if claude mcp list 2>/dev/null | grep -q '^playwright'; then
        print_status "info" "playwright MCP already registered — skipping"
        return 0
    fi

    claude mcp add --scope user \
        playwright \
        npx @playwright/mcp@latest

    print_status "success" "playwright MCP registered (stdio transport, user scope)"
}

_install_notesnook() {
    # Notesnook is a local HTTP/SSE daemon (port 3457), not a hosted URL or an
    # npx package — so we clone + build the upstream repo and let its own
    # installer own the build/systemd/wizard steps, then register the SSE
    # endpoint with Claude. Runtime prerequisite: the Notesnook desktop app.
    local repo_url="https://github.com/johnfire/openclaw-notesnook-mcp.git"
    local install_dir="$HOME/.local/share/notesnook-mcp"
    local sse_url="http://localhost:3457/sse"

    if claude mcp list 2>/dev/null | grep -q '^notesnook'; then
        print_status "info" "notesnook MCP already registered — skipping"
        return 0
    fi

    if ! command -v git &>/dev/null; then
        print_status "warning" "git not found — skipping notesnook"
        return 0
    fi

    local node_major
    node_major=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
    if [ -z "$node_major" ] || [ "$node_major" -lt 22 ]; then
        print_status "warning" "Node.js >= 22 required — skipping notesnook"
        return 0
    fi

    if [ ! -d "$install_dir" ]; then
        print_status "info" "Cloning notesnook MCP to $install_dir..."
        if ! git clone --depth=1 --quiet "$repo_url" "$install_dir"; then
            print_status "error" "git clone failed — skipping notesnook"
            return 1
        fi
    fi

    print_status "info" "Running upstream notesnook installer (interactive)"
    print_status "info" "It prompts for a sync folder and enables a systemd user service"
    print_status "info" "Runtime prerequisite: the Notesnook desktop app"
    if ! (cd "$install_dir" && ./install.sh); then
        print_status "error" "notesnook installer failed — skipping registration"
        return 1
    fi

    claude mcp add --scope user \
        --transport sse \
        notesnook \
        "$sse_url"

    print_status "success" "notesnook MCP registered (SSE transport, user scope)"
}

_install_context7() {
    local env_file="$1"

    local context7_key
    context7_key=$(grep -E '^CONTEXT7_API_KEY=' "$env_file" | head -1 | cut -d'=' -f2-)

    if [ -z "$context7_key" ]; then
        print_status "warning" "CONTEXT7_API_KEY not found in .env — skipping context7"
        return 0
    fi

    if claude mcp list 2>/dev/null | grep -q '^context7'; then
        print_status "info" "context7 MCP already registered — skipping"
        return 0
    fi

    claude mcp add --scope user \
        --transport http \
        context7 \
        https://mcp.context7.com/mcp \
        --header "CONTEXT7_API_KEY: $context7_key"

    print_status "success" "context7 MCP registered (HTTP transport, user scope)"
}
