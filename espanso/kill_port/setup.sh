#!/bin/bash
# setup.sh - Setup script for kill_port Espanso package

echo "Setting up :killport and :kp terminal commands..."

# Make the shell script executable
SCRIPT_PATH="$HOME/.config/espanso/packages/kill_port/kill_port.sh"

if [ -f "$SCRIPT_PATH" ]; then
    chmod +x "$SCRIPT_PATH"
else
    echo "⚠ Warning: kill_port.sh not found at $SCRIPT_PATH"
fi

# Check if lsof is available
if ! command -v lsof &> /dev/null; then
    echo "⚠ Warning: lsof command not found. Installing..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y lsof
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y lsof
    elif command -v yum &> /dev/null; then
        sudo yum install -y lsof
    else
        echo "✗ Could not install lsof automatically. Please install it manually."
        exit 1
    fi
fi

# Create terminal wrappers in ~/bin
BIN_DIR="$HOME/bin"
mkdir -p "$BIN_DIR"

# Create :killport wrapper
cat > "$BIN_DIR/:killport" << 'EOF'
#!/bin/bash
if [ -z "$1" ]; then
  echo "Usage: :killport <port>"
  echo "Example: :killport 8080"
  exit 1
fi
bash ~/.config/espanso/packages/kill_port/kill_port.sh "$1"
EOF

# Create :kp wrapper (shorthand)
cat > "$BIN_DIR/:kp" << 'EOF'
#!/bin/bash
if [ -z "$1" ]; then
  echo "Usage: :kp <port>"
  echo "Example: :kp 8080"
  exit 1
fi
bash ~/.config/espanso/packages/kill_port/kill_port.sh "$1"
EOF

chmod +x "$BIN_DIR/:killport"
chmod +x "$BIN_DIR/:kp"

echo "✅ Created wrappers at $BIN_DIR/:killport and $BIN_DIR/:kp"

# Check if ~/bin is in PATH
if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
  echo "⚠️  $HOME/bin is not in PATH"
  echo "Adding to ~/.profile and ~/.bashrc..."
  
  for rcfile in "$HOME/.profile" "$HOME/.bashrc"; do
    if [ -f "$rcfile" ]; then
      if ! grep -q 'export PATH="$HOME/bin:$PATH"' "$rcfile"; then
        echo '' >> "$rcfile"
        echo '# Add ~/bin to PATH' >> "$rcfile"
        echo 'export PATH="$HOME/bin:$PATH"' >> "$rcfile"
        echo "✅ Added to $rcfile"
      fi
    fi
  done
else
  echo "ℹ️  $HOME/bin is already in PATH"
fi

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
echo "  :killport 8080"
echo "  :kp 3000"
echo ""
echo "For new terminal sessions, it will work automatically."
