#!/usr/bin/env bash
# setup.sh - Setup script for gitpull_safe Espanso package

set -e

echo "Setting up gitpull-safe and :gitpull terminal commands..."

SCRIPT_PATH="$HOME/.config/espanso/packages/gitpull_safe/gitpull_safe.sh"
if [ -f "$SCRIPT_PATH" ]; then
  chmod +x "$SCRIPT_PATH"
  echo "Created executable script: $SCRIPT_PATH"
else
  echo "Warning: gitpull_safe.sh not found at $SCRIPT_PATH"
fi

BIN_DIR="$HOME/bin"
mkdir -p "$BIN_DIR"

cat > "$BIN_DIR/gitpull-safe" << 'EOF'
#!/usr/bin/env bash
exec bash ~/.config/espanso/packages/gitpull_safe/gitpull_safe.sh "$@"
EOF

cat > "$BIN_DIR/:gitpull" << 'EOF'
#!/usr/bin/env bash
exec bash ~/.config/espanso/packages/gitpull_safe/gitpull_safe.sh "$@"
EOF

chmod +x "$BIN_DIR/gitpull-safe"
chmod +x "$BIN_DIR/:gitpull"
echo "Created wrappers at $BIN_DIR/gitpull-safe and $BIN_DIR/:gitpull"

# Add ~/bin to PATH in common shell rc files if not already there
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
echo "  gitpull-safe"
echo "  gitpull-safe feature/my-new-branch"
echo "  :gitpull"
echo "  :gitpull feature/my-new-branch"
echo ""
echo "Use in Espanso:"
echo "  :gitpull"
echo "  :gitpullb"
