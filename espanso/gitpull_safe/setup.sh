#!/usr/bin/env bash
# setup.sh - Setup script for gitpull_safe Espanso package

set -e

echo "Setting up gitpull-safe terminal commands..."

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

cat > "$BIN_DIR/:git_sync_main" << 'EOF'
#!/usr/bin/env bash
exec bash ~/.config/espanso/packages/gitpull_safe/gitpull_safe.sh "$@"
EOF

cat > "$BIN_DIR/:git_sync_main_create_branch" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$HOME/.config/espanso/packages/gitpull_safe/gitpull_safe.sh"

read -r -p "Create and switch to a new branch after sync? [Y/n]: " proceed

case "${proceed:-y}" in
  y|Y|yes|YES)
    echo "Branch naming convention: <purpose>/<branch-task>"
    echo "Purposes: feature|feat, bugfix|fix, hotfix, release, docs, refactor, chore"
    echo "Examples: feat/user-authentication, fix/login-validation-issue, docs/update-api-reference"
    read -r -p "Branch name: " branch_name

    if [ -z "$branch_name" ]; then
      echo "Branch name is required when proceeding. Convention: <purpose>/<branch-task> (e.g., feat/user-authentication)"
      exit 1
    fi

    exec bash "$SCRIPT_PATH" "$branch_name"
    ;;
  n|N|no|NO)
    exec bash "$SCRIPT_PATH"
    ;;
  *)
    echo "Invalid answer: $proceed"
    echo "Use y/yes or n/no."
    exit 1
    ;;
esac
EOF

cat > "$BIN_DIR/:git_reset_current_branch_to_main" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$HOME/.config/espanso/packages/gitpull_safe/gitpull_safe.sh"

echo "This will reset the current branch to match main."
echo "The branch will not be deleted locally or remotely, but local commits ahead of main on this branch will be discarded."
read -r -p "Continue? [y/N]: " proceed

case "${proceed:-n}" in
  y|Y|yes|YES)
    exec bash "$SCRIPT_PATH" --reset-current-branch-to-main
    ;;
  *)
    echo "Reset cancelled."
    exit 0
    ;;
esac
EOF

chmod +x "$BIN_DIR/gitpull-safe"
chmod +x "$BIN_DIR/:git_sync_main"
chmod +x "$BIN_DIR/:git_sync_main_create_branch"
chmod +x "$BIN_DIR/:git_reset_current_branch_to_main"
rm -f "$BIN_DIR/:gitpull" "$BIN_DIR/:gitpullb"
echo "Created wrappers at $BIN_DIR/gitpull-safe, $BIN_DIR/:git_sync_main, $BIN_DIR/:git_sync_main_create_branch, and $BIN_DIR/:git_reset_current_branch_to_main"

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
echo "  gitpull-safe --reset-current-branch-to-main"
echo "  :git_sync_main"
echo "  :git_sync_main feature/my-new-branch"
echo "  :git_sync_main_create_branch"
echo "  :git_reset_current_branch_to_main"
echo ""
echo "Use in Espanso:"
echo "  :git_sync_main"
echo "  :git_sync_main_create_branch"
echo "  :git_reset_current_branch_to_main"
