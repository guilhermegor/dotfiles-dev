#!/usr/bin/env bash
# ssh_list.sh - List available SSH public keys, let user pick one, and copy it to clipboard.
set -euo pipefail

SSH_DIR="$HOME/.ssh"

# ── collect public keys ──────────────────────────────────────────────────────
mapfile -t pub_files < <(find "$SSH_DIR" -maxdepth 1 -name "*.pub" 2>/dev/null | sort)

if [ "${#pub_files[@]}" -eq 0 ]; then
  if command -v zenity >/dev/null 2>&1; then
    zenity --error --title="SSH List" --text="No SSH public keys found in $SSH_DIR." 2>/dev/null || true
  elif command -v yad >/dev/null 2>&1; then
    yad --error --title="SSH List" --text="No SSH public keys found in $SSH_DIR." 2>/dev/null || true
  else
    echo "No SSH public keys found in $SSH_DIR." >&2
  fi
  exit 1
fi

# Build display names (basename without .pub) and a parallel array of full paths
declare -a key_names
for f in "${pub_files[@]}"; do
  key_names+=("$(basename "$f" .pub)")
done

# ── GUI selection (zenity / yad) ──────────────────────────────────────────────
select_gui_zenity() {
  local list_args=()
  for name in "${key_names[@]}"; do
    list_args+=("$name")
  done
  zenity --list \
    --title="SSH List" \
    --text="Select a public key to copy:" \
    --column="Key name" \
    "${list_args[@]}" 2>/dev/null
}

select_gui_yad() {
  local list_args=()
  for name in "${key_names[@]}"; do
    list_args+=("$name")
  done
  yad --list \
    --title="SSH List" \
    --text="Select a public key to copy:" \
    --column="Key name" \
    "${list_args[@]}" 2>/dev/null | cut -d'|' -f1
}

# ── terminal selection (fzf / select) ─────────────────────────────────────────
select_terminal_fzf() {
  printf '%s\n' "${key_names[@]}" | fzf --prompt="Select SSH key: " --height=~40%
}

select_terminal_builtin() {
  echo "Available SSH public keys:" >&2
  PS3="Select key number: "
  select name in "${key_names[@]}"; do
    if [ -n "$name" ]; then
      echo "$name"
      break
    fi
    echo "Invalid selection, try again." >&2
  done
}

# ── pick selection method ─────────────────────────────────────────────────────
chosen_name=""

if command -v zenity >/dev/null 2>&1; then
  chosen_name=$(select_gui_zenity) || true
elif command -v yad >/dev/null 2>&1; then
  chosen_name=$(select_gui_yad) || true
elif command -v fzf >/dev/null 2>&1; then
  chosen_name=$(select_terminal_fzf) || true
else
  chosen_name=$(select_terminal_builtin) || true
fi

if [ -z "$chosen_name" ]; then
  echo "No key selected. Aborted." >&2
  exit 0
fi

# ── resolve chosen name to file path ─────────────────────────────────────────
chosen_file=""
for f in "${pub_files[@]}"; do
  if [ "$(basename "$f" .pub)" = "$chosen_name" ]; then
    chosen_file="$f"
    break
  fi
done

if [ -z "$chosen_file" ] || [ ! -f "$chosen_file" ]; then
  echo "Could not find key file for '$chosen_name'." >&2
  exit 1
fi

pubkey=$(cat "$chosen_file")

# ── copy to clipboard ─────────────────────────────────────────────────────────
copied=false
if command -v wl-copy >/dev/null 2>&1 && printf '%s' "$pubkey" | wl-copy 2>/dev/null; then
  copied=true
elif command -v xclip >/dev/null 2>&1 && printf '%s' "$pubkey" | xclip -selection clipboard 2>/dev/null; then
  copied=true
elif command -v xsel >/dev/null 2>&1 && printf '%s' "$pubkey" | xsel --clipboard --input 2>/dev/null; then
  copied=true
fi

# ── notify user ───────────────────────────────────────────────────────────────
if $copied; then
  msg="Public key '$chosen_name' copied to clipboard."
else
  msg="Public key '$chosen_name' could not be copied (no clipboard tool found).\n\n$pubkey"
fi

if command -v zenity >/dev/null 2>&1; then
  zenity --info --title="SSH List" --text="$msg" 2>/dev/null || true
elif command -v yad >/dev/null 2>&1; then
  yad --info --title="SSH List" --text="$msg" 2>/dev/null || true
else
  echo "$msg"
fi
