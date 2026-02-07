#!/usr/bin/env bash
set -euo pipefail

# ssh_generate.sh
# Interactive SSH key generator designed to be called from Espanso (uses GUI prompts when available).

PROMPT_CMD=""
if command -v zenity >/dev/null 2>&1; then
  PROMPT_CMD=zenity
elif command -v yad >/dev/null 2>&1; then
  PROMPT_CMD=yad
fi

prompt_input() {
  local prompt="$1"
  local default="$2"
  if [ -n "$PROMPT_CMD" ]; then
    if [ "$PROMPT_CMD" = "zenity" ]; then
      zenity --entry --title="SSH Keygen" --text="$prompt" --entry-text="$default" 2>/dev/null || echo "$default"
    else
      yad --entry --title="SSH Keygen" --text="$prompt" --entry-text="$default" 2>/dev/null || echo "$default"
    fi
  else
    read -r -p "$prompt [$default]: " input
    input=${input:-$default}
    echo "$input"
  fi
}

prompt_password() {
  local prompt="$1"
  local default="$2"
  if [ -n "$PROMPT_CMD" ]; then
    if [ "$PROMPT_CMD" = "zenity" ]; then
      zenity --password --title="SSH Keygen" --text="$prompt" 2>/dev/null || echo "$default"
    else
      yad --entry --title="SSH Keygen" --text="$prompt" --entry-password 2>/dev/null || echo "$default"
    fi
  else
    read -s -p "$prompt [$default]: " p
    echo
    p=${p:-$default}
    echo "$p"
  fi
}

prompt_confirm() {
  local prompt="$1"
  local default="$2"
  if [ -n "$PROMPT_CMD" ]; then
    if [ "$PROMPT_CMD" = "zenity" ]; then
      if zenity --question --title="SSH Keygen" --text="$prompt" 2>/dev/null; then
        echo "yes"
      else
        echo "no"
      fi
    else
      if yad --title="SSH Keygen" --button=gtk-yes:0 --button=gtk-no:1 --text="$prompt" 2>/dev/null; then
        echo "yes"
      else
        echo "no"
      fi
    fi
  else
    read -r -p "$prompt [$default] (y/N): " ans
    ans=${ans:-$default}
    case "$ans" in
      [Yy]* ) echo "yes" ;;
      * ) echo "no" ;;
    esac
  fi
}

# CLI args support: email passphrase path type
email=""
passphrase=""
path=""
type="ed25519"

if [ "$#" -ge 1 ]; then email="$1"; fi
if [ "$#" -ge 2 ]; then passphrase="$2"; fi
if [ "$#" -ge 3 ]; then path="$3"; fi
if [ "$#" -ge 4 ]; then type="$4"; fi

# Ask for missing values
confirm=$(prompt_confirm "Create a new SSH key?" "y")
if [ "$confirm" != "yes" ]; then
  echo "Aborted by user. No key created." >&2
  exit 0
fi
if [ -z "$email" ]; then
  email=$(prompt_input "Enter email for SSH key comment (leave blank for none):" "")
fi
if [ -z "$type" ]; then
  type=$(prompt_input "Key type (ed25519, rsa):" "ed25519")
fi
if [ -z "$path" ]; then
  # default to ~/.ssh/id_<type>
  path_default="$HOME/.ssh/id_${type}"
  path=$(prompt_input "Path for private key file:" "$path_default")
fi
if [ -z "$passphrase" ]; then
  passphrase=$(prompt_password "Enter passphrase (leave blank for no passphrase):" "")
fi

# Ensure directory exists
mkdir -p "$(dirname "$path")"

# If file exists, ask to overwrite
if [ -f "$path" ] || [ -f "${path}.pub" ]; then
  overwrite="no"
  if [ -n "$PROMPT_CMD" ]; then
    if [ "$PROMPT_CMD" = "zenity" ]; then
      if zenity --question --title="SSH Keygen" --text="File $path (or ${path}.pub) exists. Overwrite?" 2>/dev/null; then
        overwrite="yes"
      fi
    else
      if yad --title="SSH Keygen" --button=gtk-yes:0 --button=gtk-no:1 --text="File $path (or ${path}.pub) exists. Overwrite?" 2>/dev/null; then
        overwrite="yes"
      fi
    fi
  else
    read -r -p "File $path exists. Overwrite? (y/N): " yn
    case "$yn" in
      [Yy]*) overwrite="yes" ;;
      *) overwrite="no" ;;
    esac
  fi
  if [ "$overwrite" != "yes" ]; then
    echo "Aborting: user chose not to overwrite existing key files." >&2
    exit 1
  fi
fi

# Run ssh-keygen
if [ -z "$passphrase" ]; then
  ssh-keygen -t "$type" -C "$email" -f "$path" -N "" || true
else
  ssh-keygen -t "$type" -C "$email" -f "$path" -N "$passphrase" || true
fi

pub="${path}.pub"
if [ -f "$pub" ]; then
  pubkey=$(cat "$pub")
  echo "$pubkey"
  # Try to copy to clipboard
  if command -v wl-copy >/dev/null 2>&1; then
    echo "$pubkey" | wl-copy
    copied=true
  elif command -v xclip >/dev/null 2>&1; then
    echo "$pubkey" | xclip -selection clipboard
    copied=true
  elif command -v xsel >/dev/null 2>&1; then
    echo "$pubkey" | xsel --clipboard --input
    copied=true
  else
    copied=false
  fi

  # Notify user
  if [ -n "$PROMPT_CMD" ]; then
    if [ "$copied" = true ]; then
      if [ "$PROMPT_CMD" = "zenity" ]; then
        zenity --info --title="SSH Keygen" --text="Public key generated and copied to clipboard.\n$pub" 2>/dev/null || true
      else
        yad --info --title="SSH Keygen" --text="Public key generated and copied to clipboard.\n$pub" 2>/dev/null || true
      fi
    else
      if [ "$PROMPT_CMD" = "zenity" ]; then
        zenity --info --title="SSH Keygen" --text="Public key generated at $pub (clipboard not available)." 2>/dev/null || true
      else
        yad --info --title="SSH Keygen" --text="Public key generated at $pub (clipboard not available)." 2>/dev/null || true
      fi
    fi
  else
    if [ "$copied" = true ]; then
      echo "Public key copied to clipboard. Location: $pub"
    else
      echo "Public key saved to: $pub (clipboard not available)"
    fi
  fi
  exit 0
else
  echo "ERROR: public key not found after generation" >&2
  exit 2
fi
