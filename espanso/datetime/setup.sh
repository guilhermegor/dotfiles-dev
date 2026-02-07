#!/usr/bin/env bash
# setup.sh - Configure PATH and create terminal wrappers for :date, :time, :now, :today

set -e

BIN_DIR="$HOME/bin"

echo "Setting up :date, :time, :now, :today terminal commands..."

# Create ~/bin if it doesn't exist
mkdir -p "$BIN_DIR"

# Create wrapper scripts
cat > "$BIN_DIR/:date" <<'WRAPPER'
#!/usr/bin/env bash
exec /usr/bin/date '+%Y-%m-%d'
WRAPPER

cat > "$BIN_DIR/:today" <<'WRAPPER'
#!/usr/bin/env bash
exec /usr/bin/date '+%Y-%m-%d'
WRAPPER

cat > "$BIN_DIR/:time" <<'WRAPPER'
#!/usr/bin/env bash
exec /usr/bin/date '+%H:%M:%S'
WRAPPER

cat > "$BIN_DIR/:now" <<'WRAPPER'
#!/usr/bin/env bash
exec /usr/bin/date '+%Y-%m-%d %H:%M:%S'
WRAPPER

chmod +x "$BIN_DIR/:date" "$BIN_DIR/:today" "$BIN_DIR/:time" "$BIN_DIR/:now"

echo "✅ Created wrappers at $BIN_DIR/:date, $BIN_DIR/:today, $BIN_DIR/:time, $BIN_DIR/:now"

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
echo "  :date"
echo "  :today"
echo "  :time"
echo "  :now"
echo ""
echo "For new terminal sessions, it will work automatically."
