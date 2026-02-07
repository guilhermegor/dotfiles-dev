#!/usr/bin/env bash
# setup.sh - Configure PATH and create terminal wrapper for :sshgen

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/bin"
WRAPPER_NAME=":sshgen"

echo "Setting up :sshgen terminal command..."

# Create ~/bin if it doesn't exist
mkdir -p "$BIN_DIR"

# Create wrapper script
cat > "$BIN_DIR/$WRAPPER_NAME" <<'WRAPPER'
#!/usr/bin/env bash
exec "$HOME/.config/espanso/packages/ssh_generate/ssh_generate.sh" "$@"
WRAPPER

chmod +x "$BIN_DIR/$WRAPPER_NAME"
echo "✅ Created wrapper at $BIN_DIR/$WRAPPER_NAME"

# Add ~/bin to PATH in common shell rc files if not already there
for rc in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [ -f "$rc" ] || [ "$rc" = "$HOME/.profile" ]; then
    if ! grep -q "export PATH=.*\$HOME/bin" "$rc" 2>/dev/null; then
      echo 'export PATH="$HOME/bin:$PATH"' >> "$rc"
      echo "✅ Added \$HOME/bin to PATH in $rc"
    else
      echo "ℹ️  \$HOME/bin is already in PATH ($rc)"
    fi
  fi
done

# Export PATH to current shell
export PATH="$BIN_DIR:$PATH"

echo ""
echo "════════════════════════════════════════════"
echo "Setup complete!"
echo "════════════════════════════════════════════"
echo ""
echo "To activate in your current terminal session:"
echo "  source ~/.profile"
echo "  # or: source ~/.bashrc"
echo ""
echo "Then you can run:"
echo "  :sshgen"
echo ""
echo "For new terminal sessions, it will work automatically."
