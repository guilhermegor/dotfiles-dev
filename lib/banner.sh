#!/bin/bash
#
# lib/banner.sh — DOTFILES-DEV ASCII banner.
#
# Same visual style as BlueprintX (bin/blueprintx.sh): hand-coded ANSI Shadow
# letterforms in CYAN, with a one-line tagline in MAGENTA underneath. Uses
# `echo -e` for colour escapes to match print_status' pattern in lib/common.sh.
#
# Dual-mode:
#   - sourced  → defines show_banner(); call it where you want the banner.
#   - executed → prints the banner once and exits (handy for preview).

_BANNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Pull in CYAN/MAGENTA/NC if the caller has not already sourced common.sh.
if [[ -z "${CYAN:-}" || -z "${MAGENTA:-}" || -z "${NC:-}" ]]; then
    # shellcheck source=common.sh
    source "$_BANNER_DIR/common.sh"
fi

show_banner() {
    echo
    echo -e "${CYAN}██████╗  ██████╗ ████████╗███████╗██╗██╗     ███████╗███████╗      ██████╗ ███████╗██╗   ██╗${NC}"
    echo -e "${CYAN}██╔══██╗██╔═══██╗╚══██╔══╝██╔════╝██║██║     ██╔════╝██╔════╝      ██╔══██╗██╔════╝██║   ██║${NC}"
    echo -e "${CYAN}██║  ██║██║   ██║   ██║   █████╗  ██║██║     █████╗  ███████╗█████╗██║  ██║█████╗  ██║   ██║${NC}"
    echo -e "${CYAN}██║  ██║██║   ██║   ██║   ██╔══╝  ██║██║     ██╔══╝  ╚════██║╚════╝██║  ██║██╔══╝  ╚██╗ ██╔╝${NC}"
    echo -e "${CYAN}██████╔╝╚██████╔╝   ██║   ██║     ██║███████╗███████╗███████║      ██████╔╝███████╗ ╚████╔╝ ${NC}"
    echo -e "${CYAN}╚═════╝  ╚═════╝    ╚═╝   ╚═╝     ╚═╝╚══════╝╚══════╝╚══════╝      ╚═════╝ ╚══════╝  ╚═══╝  ${NC}"
    echo
    echo -e "${MAGENTA}  The make-driven Linux dotfiles toolkit.${NC}"
    echo
}

# When invoked directly (e.g. `bash lib/banner.sh`), print the banner once.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    show_banner
fi
