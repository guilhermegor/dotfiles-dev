#!/usr/bin/env bash
# shortcuts.sh - List espanso package descriptions and triggers

set -e

PACKAGES_DIR="$HOME/.config/espanso/packages"

if [ ! -d "$PACKAGES_DIR" ]; then
  echo "No espanso packages directory found at $PACKAGES_DIR" >&2
  exit 1
fi

for pkg in "$PACKAGES_DIR"/*; do
  [ -d "$pkg" ] || continue
  name=$(basename "$pkg")
  desc=$(grep "^description:" "$pkg/package.yml" 2>/dev/null | sed 's/description: *//')
  triggers=$(grep "trigger:" "$pkg/package.yml" 2>/dev/null | sed 's/.*trigger: *"\?\([^"]*\)"\?.*/\1/' | tr '\n' ', ' | sed 's/,$//')
  echo "[$name]"
  [ -n "$desc" ] && echo "  Description: $desc"
  [ -n "$triggers" ] && echo "  Triggers: $triggers" || echo "  Triggers: (none)"
  echo ""
done
