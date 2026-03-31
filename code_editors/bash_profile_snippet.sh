#!/usr/bin/env bash
# Adds a .bash_profile that loads .bashrc for interactive shells

set -e

BASH_PROFILE="$HOME/.bash_profile"

if [ ! -f "$BASH_PROFILE" ]; then
  cat > "$BASH_PROFILE" <<'EOF'
# Load bashrc for interactive shells
if [ -f ~/.bashrc ]; then
  source ~/.bashrc
fi
EOF
  echo "✅ Created $BASH_PROFILE to load ~/.bashrc"
else
  if ! grep -q "source ~/.bashrc" "$BASH_PROFILE"; then
    cat >> "$BASH_PROFILE" <<'EOF'

# Load bashrc for interactive shells
if [ -f ~/.bashrc ]; then
  source ~/.bashrc
fi
EOF
    echo "✅ Appended ~/.bashrc loader to $BASH_PROFILE"
  else
    echo "ℹ️  $BASH_PROFILE already loads ~/.bashrc"
  fi
fi
