#!/usr/bin/env bash
# setup.sh - Post-install setup for gh_protect_branch Espanso package.

set -e

SCRIPT_PATH="$HOME/.config/espanso/packages/gh_protect_branch/gh_protect_branch.sh"

if [ -f "$SCRIPT_PATH" ]; then
    chmod +x "$SCRIPT_PATH"
    echo "Made executable: $SCRIPT_PATH"
else
    echo "Warning: gh_protect_branch.sh not found at $SCRIPT_PATH"
fi
