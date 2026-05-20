#!/bin/bash
#
# distro_config/install_coding.sh
#
# Coding-side installer: languages, editors, databases, containers, VCS, AI CLIs.
# Counterpart to install_programs.sh (general desktop apps).
#
# Architecture:
#   - distro_config/install_coding_lib/_common.sh        Shim that sources the
#     shared utilities from ../install_lib/_common.sh (single source of truth).
#   - distro_config/install_coding_lib/<category>.sh     One file per category,
#     each ending in an INSTALL_REGISTRY+=( ... ) block.
#   - distro_config/install_coding_lib/bootstrappers.sh  Foundational installers
#     (core_dependencies, homebrew, asdf, pyenv) — splice-prepended below.
#
# Failure policy: failures during 'Full Installation' are collected and reported
# at the end (see run_install in _common.sh). The orchestrator does NOT use
# `set -e` — each install function runs in a subshell where set -e applies
# locally, so failures stop the function but not the whole run.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOG_FILE="$HOME/coding_installation_$(date +%Y%m%d_%H%M%S).log"

# ----------------------------------------------------------------------------
# 1. Source utilities (via the install_coding_lib shim → install_lib/_common.sh)
# ----------------------------------------------------------------------------

if [ ! -f "$SCRIPT_DIR/install_coding_lib/_common.sh" ]; then
    echo "Missing $SCRIPT_DIR/install_coding_lib/_common.sh — orchestrator cannot start." >&2
    exit 1
fi
# shellcheck source=install_coding_lib/_common.sh
source "$SCRIPT_DIR/install_coding_lib/_common.sh"

# ----------------------------------------------------------------------------
# 2. Source category lib files
# ----------------------------------------------------------------------------

shopt -s nullglob
for lib in "$SCRIPT_DIR/install_coding_lib/"[!_]*.sh; do
    # shellcheck source=/dev/null
    if ! source "$lib"; then
        print_status "error" "Failed to source $lib — orchestrator aborting."
        exit 1
    fi
done
shopt -u nullglob

# ----------------------------------------------------------------------------
# 3. Splice bootstrappers into INSTALL_REGISTRY (prepended)
# ----------------------------------------------------------------------------
# Bootstrappers are foundational — other installs depend on them. They are
# defined in bootstrappers.sh but not auto-registered there; we prepend them
# here so they always run first in 'Full Installation' mode.

INSTALL_REGISTRY=(
    "install_core_dependencies:Core Dependencies::"
    "install_homebrew:Homebrew Package Manager::"
    "install_asdf:asdf Version Manager::"
    "install_pyenv:Python (pyenv)::"
    "${INSTALL_REGISTRY[@]}"
)

# ----------------------------------------------------------------------------
# 4. Validate the registry before any install runs
# ----------------------------------------------------------------------------

validate_registry

# ----------------------------------------------------------------------------
# 5. Menu + dispatch
# ----------------------------------------------------------------------------

show_menu() {
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}              ${MAGENTA}Coding Environment Installation${NC}                  ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}\n"

    echo -e "${GREEN}Detected System:${NC} $DISTRO"
    echo -e "${GREEN}Package Manager:${NC} $PACKAGE_MANAGER"
    echo -e "${GREEN}Registry entries:${NC} ${#INSTALL_REGISTRY[@]}"
    echo
    echo -e "${YELLOW}Select installation mode:${NC}"
    echo -e "  ${GREEN}1)${NC} Full Installation (all registry entries, failures collected)"
    echo -e "  ${GREEN}2)${NC} Custom Installation (pick entries)"
    echo -e "  ${GREEN}3)${NC} Exit"
    echo -e "\n${CYAN}Choice:${NC} "
}

run_full_installation() {
    print_status "section" "FULL CODING INSTALLATION MODE"

    local entry fn label
    for entry in "${INSTALL_REGISTRY[@]}"; do
        IFS=':' read -r fn label _ _ <<< "$entry"
        run_install "$fn" "$label"
    done

    print_status "section" "CODING INSTALLATION COMPLETE"
    report_failures
    print_status "info" "Log file: $LOG_FILE"

    if command_exists brew || command_exists asdf || command_exists ollama; then
        print_status "info" "Tools installed. Reload your shell:"
        print_status "config" "source ~/.bashrc"
    fi
}

run_custom_installation() {
    print_status "section" "CUSTOM CODING INSTALLATION MODE"

    echo -e "\n${YELLOW}Select components to install (space-separated numbers, or 'all'):${NC}"
    local i entry _fn label
    for i in "${!INSTALL_REGISTRY[@]}"; do
        IFS=':' read -r _fn label _ _ <<< "${INSTALL_REGISTRY[$i]}"
        echo -e "  ${GREEN}$((i+1)))${NC} $label"
    done
    echo -e "\n${CYAN}Selection:${NC} "
    read -r selection

    if [[ "$selection" == "all" ]]; then
        run_full_installation
        return
    fi

    local num
    for num in $selection; do
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#INSTALL_REGISTRY[@]}" ]; then
            IFS=':' read -r fn label _ _ <<< "${INSTALL_REGISTRY[$((num-1))]}"
            run_install "$fn" "$label"
        fi
    done

    print_status "section" "CUSTOM CODING INSTALLATION COMPLETE"
    report_failures
    print_status "info" "Log file: $LOG_FILE"
}

main() {
    if [ "$EUID" -eq 0 ]; then
        print_status "error" "This script should NOT be run with sudo!"
        print_status "info" "Please run as: bash $0"
        exit 1
    fi

    detect_distro

    # Best-effort: source asdf for the current session so toolchain installs work.
    if [ -f "$HOME/.asdf/asdf.sh" ]; then
        source "$HOME/.asdf/asdf.sh"
    elif [ -f "/opt/homebrew/opt/asdf/libexec/asdf.sh" ]; then
        source "/opt/homebrew/opt/asdf/libexec/asdf.sh"
    elif [ -f "/usr/local/opt/asdf/libexec/asdf.sh" ]; then
        source "/usr/local/opt/asdf/libexec/asdf.sh"
    fi

    if ! check_internet; then
        print_status "error" "Internet connection required for installation"
        exit 1
    fi

    mkdir -p "$DOWNLOADS_DIR"

    while true; do
        show_menu
        read -r choice
        case $choice in
            1) run_full_installation; break ;;
            2) run_custom_installation; break ;;
            3) print_status "info" "Installation cancelled"; exit 0 ;;
            *) print_status "error" "Invalid option. Please select 1, 2, or 3." ;;
        esac
    done

    echo ""
    print_status "info" "Current tool versions:"
    source "$HOME/.asdf/asdf.sh" 2>/dev/null || true

    if command_exists node; then
        print_status "config" "  Node.js: $(node --version 2>/dev/null || echo 'Not available')"
    fi
    if command_exists npm; then
        print_status "config" "  npm: $(npm --version 2>/dev/null || echo 'Not available')"
    fi
    if command_exists npx; then
        print_status "config" "  npx: $(npx --version 2>/dev/null || echo 'Not available')"
    fi
    if command_exists tsc; then
        print_status "config" "  TypeScript: $(tsc --version 2>/dev/null | sed 's/Version //' || echo 'Not available')"
    fi
    if command_exists nest; then
        print_status "config" "  NestJS CLI: $(nest --version 2>/dev/null || echo 'Not available')"
    fi
    if command_exists rustc; then
        print_status "config" "  Rust: $(rustc --version 2>/dev/null || echo 'Not available')"
    fi
    if command_exists cargo; then
        print_status "config" "  Cargo: $(cargo --version 2>/dev/null || echo 'Not available')"
    fi
    if command_exists copilot; then
        print_status "config" "  GitHub Copilot CLI: $(timeout 5 copilot --version 2>/dev/null | head -n1 || echo 'Not available')"
    fi
    if command_exists claude; then
        print_status "config" "  Claude Code: $(timeout 5 claude --version 2>/dev/null | head -n1 || echo 'Not available')"
    fi
    if command_exists qwen; then
        print_status "config" "  Qwen Code: $(timeout 5 qwen --version 2>/dev/null | head -n1 || echo 'Not available')"
    fi

    echo ""
    print_status "info" "Global versions set in ~/.tool-versions:"
    if [ -f "$HOME/.tool-versions" ]; then
        while read -r line; do
            print_status "config" "  $line"
        done < "$HOME/.tool-versions"
    else
        print_status "config" "  No global versions file found"
    fi

    print_status "warning" "\nImportant: You may need to reload your shell for changes to take effect:"
    print_status "config" "source ~/.bashrc  # or source ~/.zshrc"
    echo ""
}

main "$@"
