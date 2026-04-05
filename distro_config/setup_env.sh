#!/usr/bin/env bash
# distro_config/setup_env.sh
# Prompts the user to create a .env file from .env.example during `make init`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_EXAMPLE="${REPO_ROOT}/.env.example"
ENV_FILE="${REPO_ROOT}/.env"

# Nothing to do if .env already exists
if [[ -f "${ENV_FILE}" ]]; then
    echo "  ✅ .env already exists — skipping."
    exit 0
fi

if [[ ! -f "${ENV_EXAMPLE}" ]]; then
    echo "  ⚠️  No .env.example found — skipping env setup."
    exit 0
fi

echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│  .env file not found                                        │"
echo "│                                                             │"
echo "│  Some tools (Context7, Tavily) require API keys stored      │"
echo "│  in a .env file. Without it:                                │"
echo "│    • Context7 MCP server won't authenticate                 │"
echo "│    • Tavily search/research tools will be unavailable       │"
echo "│    • Any script sourcing .env will silently skip those keys │"
echo "└─────────────────────────────────────────────────────────────┘"
echo ""
read -r -p "  Create .env from .env.example now? [Y/n] " answer

case "${answer}" in
    [nN]*)
        echo ""
        echo "  Skipped. You can create it later by running:"
        echo "    cp .env.example .env"
        echo "  and filling in your API keys."
        echo ""
        ;;
    *)
        cp "${ENV_EXAMPLE}" "${ENV_FILE}"
        echo ""
        echo "  ✅ .env created. Open it and replace placeholder values:"
        echo "    \$EDITOR ${ENV_FILE}"
        echo ""
        ;;
esac
