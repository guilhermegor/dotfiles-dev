#!/bin/bash
#
# distro_config/install_coding_lib/_common.sh
#
# Thin shim that re-exports the shared install utilities. The single source
# of truth lives in distro_config/install_lib/_common.sh — that file defines
# print_status, detect_distro, install_package, INSTALL_REGISTRY, and so on.
# Both install_programs.sh and install_coding.sh depend on the same set.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "_common.sh is meant to be sourced, not executed." >&2
    exit 1
fi

# Resolve the sibling install_lib directory deterministically.
_this_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_shared_common="$_this_dir/../install_lib/_common.sh"

if [ ! -f "$_shared_common" ]; then
    echo "Missing shared utilities at $_shared_common — install_coding cannot start." >&2
    exit 1
fi

# shellcheck source=../install_lib/_common.sh
source "$_shared_common"

unset _this_dir _shared_common
