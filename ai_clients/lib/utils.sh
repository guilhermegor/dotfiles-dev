#!/bin/bash
#
# ai_clients/lib/utils.sh
#
# Shared utilities for ai_clients setup modules. Inherits print_status, color
# vars, command_exists, check_internet from repo-root lib/common.sh.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "utils.sh is meant to be sourced, not executed." >&2
    exit 1
fi

# Set the ai_clients-specific log file name before sourcing common, so
# print_status writes to the right place.
LOG_FILE="${LOG_FILE:-$HOME/ai_clients_setup_$(date +%Y%m%d_%H%M%S).log}"

_utils_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$_utils_dir/../../lib/common.sh"
unset _utils_dir
