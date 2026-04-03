#!/bin/bash
# Shared variables and print_status used by all claude setup modules.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

LOG_FILE="$HOME/claude_configuration_$(date +%Y%m%d_%H%M%S).log"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

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
