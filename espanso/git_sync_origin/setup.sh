#!/usr/bin/env bash
# setup.sh - Setup script for git_sync_origin espanso package

set -e

echo "Setting up git-sync-origin terminal commands..."

SCRIPT_PATH="$HOME/.config/espanso/packages/git_sync_origin/git_sync_origin.sh"
if [ -f "$SCRIPT_PATH" ]; then
  chmod +x "$SCRIPT_PATH"
  echo "Made executable: $SCRIPT_PATH"
else
  echo "Warning: git_sync_origin.sh not found at $SCRIPT_PATH"
fi

BIN_DIR="$HOME/bin"
mkdir -p "$BIN_DIR"

cat > "$BIN_DIR/git-sync-origin" << 'EOF'
#!/usr/bin/env bash
exec bash ~/.config/espanso/packages/git_sync_origin/git_sync_origin.sh "$@"
EOF

cat > "$BIN_DIR/:git_sync_origin" << 'EOF'
#!/usr/bin/env bash
exec bash ~/.config/espanso/packages/git_sync_origin/git_sync_origin.sh "$@"
EOF

chmod +x "$BIN_DIR/git-sync-origin"
chmod +x "$BIN_DIR/:git_sync_origin"

echo "Created wrappers at $BIN_DIR/git-sync-origin and $BIN_DIR/:git_sync_origin"

for rc in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [ -f "$rc" ] || [ "$rc" = "$HOME/.profile" ]; then
    if ! grep -q "export PATH=.*\\$HOME/bin" "$rc" 2>/dev/null; then
      echo 'export PATH="$HOME/bin:$PATH"' >> "$rc"
      echo "Added \$HOME/bin to PATH in $rc"
    fi
  fi
done

export PATH="$HOME/bin:$PATH"

echo ""
echo "========================================"
echo "Setup complete"
echo "========================================"
echo ""
echo "Use in terminal:"
echo "  git-sync-origin"
echo "  :git_sync_origin"
echo ""
echo "Use in Espanso:"
echo "  :git_sync_origin"
