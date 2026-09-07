#!/usr/bin/env bash
# distro_config/setup_env.sh
# Shell environment setup, run by `make run` (see Makefile's `setup_env` target):
#   1. Prompts to create the project .env from .env.example (Context7/Tavily/DeepSeek keys).
#   2. Bootstraps ~/.bashrc to source ~/.claude/.env — the per-machine secrets file
#      (e.g. CODERABBIT_TRIGGER_PAT) that must never land in this public repo.
#      See the "Machine Secrets" section in README.md for the full key reference.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

ENV_EXAMPLE="${REPO_ROOT}/.env.example"
ENV_FILE="${REPO_ROOT}/.env"
BASHRC="${HOME}/.bashrc"
CLAUDE_ENV_MARKER="# Claude Code per-machine secrets — see README.md 'Machine Secrets'"

prompt_create_project_env() {
    if [[ -f "${ENV_FILE}" ]]; then
        print_status "success" ".env already exists — skipping."
        return 0
    fi

    if [[ ! -f "${ENV_EXAMPLE}" ]]; then
        print_status "warning" "No .env.example found — skipping env setup."
        return 0
    fi

    local answer

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
            print_status "info" "Skipped. Create it later with: cp .env.example .env"
            ;;
        *)
            cp "${ENV_EXAMPLE}" "${ENV_FILE}"
            print_status "success" ".env created. Open it and replace placeholder values: \$EDITOR ${ENV_FILE}"
            ;;
    esac
}

# Makes ~/.claude/.env (git-ignored, lives outside every repo's working tree)
# reproducible on a fresh machine: any KEY=value line in it becomes an exported
# shell variable in every new shell, without the value ever touching this repo.
bootstrap_claude_env_sourcing() {
    if grep -qF "${CLAUDE_ENV_MARKER}" "${BASHRC}" 2>/dev/null; then
        print_status "success" "\$HOME/.claude/.env bootstrap already present in \$HOME/.bashrc — skipping."
        return 0
    fi

    {
        printf '\n%s\n' "${CLAUDE_ENV_MARKER}"
        printf 'if [ -f ~/.claude/.env ]; then\n'
        printf '    set -a\n'
        printf '    # shellcheck disable=SC1091\n'
        printf '    source ~/.claude/.env\n'
        printf '    set +a\n'
        printf 'fi\n'
    } >> "${BASHRC}"

    print_status "success" "Added \$HOME/.claude/.env bootstrap to \$HOME/.bashrc."
    print_status "info" "Run 'source ~/.bashrc' (or open a new shell) to pick up its keys now."
}

main() {
    prompt_create_project_env
    bootstrap_claude_env_sourcing
}

main "$@"
