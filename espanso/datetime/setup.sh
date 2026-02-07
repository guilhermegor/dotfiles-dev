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

# Add ~/bin to PATH in ~/.profile if not already there
if ! grep -q "export PATH=.*\$HOME/bin" "$HOME/.profile" 2>/dev/null; then
  echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.profile"
  echo "✅ Added \$HOME/bin to PATH in ~/.profile"
else
  echo "ℹ️  \$HOME/bin is already in PATH (~/.profile)"
fi

# Export PATH to current shell
export PATH="$BIN_DIR:$PATH"

echo ""
echo "════════════════════════════════════════════"
echo "Setup complete!"
echo "════════════════════════════════════════════"
echo ""
echo "To activate in your current terminal session:"
echo "  source ~/.profile"
echo ""
echo "Then you can run:"
echo "  :date"
echo "  :today"
echo "  :time"
echo "  :now"
echo ""
echo "For new terminal sessions, it will work automatically."
