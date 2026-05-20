#!/bin/bash
#
# lib/common.sh
#
# Shared utilities for all dotfiles-dev scripts. Sourced from project scripts to
# avoid the ~20 redefinitions of print_status, color vars, and command_exists
# that used to live in every entry point.
#
# Sourcing contract:
#   - Idempotent (guarded with _DOTFILES_COMMON_LOADED so re-sourcing is a no-op).
#   - Optional: scripts may set LOG_FILE before sourcing; print_status will tee
#     timestamped output there. If LOG_FILE is unset, console output only.
#   - Refuses direct execution.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "lib/common.sh is meant to be sourced, not executed." >&2
    exit 1
fi

# Re-sourcing guard
if [ -n "${_DOTFILES_COMMON_LOADED:-}" ]; then
    return 0
fi
_DOTFILES_COMMON_LOADED=1

# ============================================================================
# COLOR VARIABLES
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ============================================================================
# print_status — standard status-keyword API
# ============================================================================
#
# Usage:
#   print_status <level> <message>
#
# Levels: success | error | warning | info | config | debug | section
# Unknown levels fall through to a neutral "[ ] message" prefix.
# Errors go to stderr; everything else to stdout.
# If $LOG_FILE is set, every call appends a timestamped line to it.

print_status() {
    local status="$1"
    local message="$2"

    case "$status" in
        success)
            echo -e "${GREEN}[✓]${NC} ${message}"
            ;;
        error)
            echo -e "${RED}[✗]${NC} ${message}" >&2
            ;;
        warning)
            echo -e "${YELLOW}[!]${NC} ${message}"
            ;;
        info)
            echo -e "${BLUE}[i]${NC} ${message}"
            ;;
        config)
            echo -e "${CYAN}[→]${NC} ${message}"
            ;;
        debug)
            echo -e "${MAGENTA}[»]${NC} ${message}"
            ;;
        section)
            echo -e "\n${MAGENTA}========================================${NC}"
            echo -e "${MAGENTA} $message${NC}"
            echo -e "${MAGENTA}========================================${NC}\n"
            ;;
        *)
            echo -e "[ ] ${message}"
            ;;
    esac

    if [ -n "${LOG_FILE:-}" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$status] $message" >> "$LOG_FILE"
    fi
}

# ============================================================================
# Basic helpers
# ============================================================================

command_exists() {
    command -v "$1" &> /dev/null
}

check_internet() {
    print_status "info" "Checking internet connectivity..."
    if ping -c 1 google.com &> /dev/null; then
        print_status "success" "Internet connection verified"
        return 0
    fi
    print_status "error" "No internet connection detected"
    return 1
}

# ============================================================================
# run_or_echo — opt-in dry-run wrapper
# ============================================================================
#
# Usage:
#   run_or_echo <command> [args...]
#
# If DRY_RUN=1 in the environment, prints the command instead of executing it.
# Otherwise runs it. Use for state-mutating commands you want to preview:
#
#   run_or_echo sudo apt-get install -y "$pkg"
#   run_or_echo cp "$src" "$dst"
#
# Note: this is *opt-in*. Scripts must call run_or_echo explicitly to honor
# DRY_RUN — there is no magic interception. Most existing scripts run their
# package-manager commands directly; retrofitting them is intentionally out
# of scope here.

run_or_echo() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "[dry-run] $*"
        return 0
    fi
    "$@"
}
