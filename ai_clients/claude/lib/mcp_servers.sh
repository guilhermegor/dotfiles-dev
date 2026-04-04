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
