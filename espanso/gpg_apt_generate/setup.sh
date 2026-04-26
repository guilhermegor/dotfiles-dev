#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/bin"
WRAPPER_NAME=":gpgaptgen"

echo "Setting up :gpgaptgen terminal command..."

mkdir -p "$BIN_DIR"

cat > "$BIN_DIR/$WRAPPER_NAME" <<'WRAPPER'
#!/usr/bin/env bash
exec "$HOME/.config/espanso/packages/gpg_apt_generate/gpg_apt_generate.sh" "$@"
WRAPPER

chmod +x "$BIN_DIR/$WRAPPER_NAME"
echo "Created wrapper at $BIN_DIR/$WRAPPER_NAME"

for rc in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [ -f "$rc" ] || [ "$rc" = "$HOME/.profile" ]; then
    if ! grep -q "export PATH=.*\$HOME/bin" "$rc" 2>/dev/null; then
      echo 'export PATH="$HOME/bin:$PATH"' >> "$rc"
      echo "Added \$HOME/bin to PATH in $rc"
    fi
  fi
done

export PATH="$BIN_DIR:$PATH"

echo ""
echo "Setup complete! Type :gpgaptgen in any text field or run it from a terminal."
