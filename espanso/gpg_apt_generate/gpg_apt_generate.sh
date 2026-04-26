#!/usr/bin/env bash
set -euo pipefail

PROMPT_CMD=""
if command -v zenity >/dev/null 2>&1; then
  PROMPT_CMD=zenity
elif command -v yad >/dev/null 2>&1; then
  PROMPT_CMD=yad
fi

prompt_input() {
  local title="$1" text="$2" default="$3"
  if [ "$PROMPT_CMD" = zenity ]; then
    zenity --entry --title="$title" --text="$text" --entry-text="$default" 2>/dev/null || echo "$default"
  elif [ "$PROMPT_CMD" = yad ]; then
    yad --entry --title="$title" --text="$text" --entry-text="$default" 2>/dev/null || echo "$default"
  else
    read -r -p "$text [$default]: " input
    echo "${input:-$default}"
  fi
}

prompt_password() {
  local title="$1" text="$2"
  if [ "$PROMPT_CMD" = zenity ]; then
    zenity --password --title="$title" --text="$text" 2>/dev/null || echo ""
  elif [ "$PROMPT_CMD" = yad ]; then
    yad --entry --title="$title" --text="$text" --entry-password 2>/dev/null || echo ""
  else
    read -r -s -p "$text (leave blank for none): " p
    echo
    echo "$p"
  fi
}

prompt_confirm() {
  local title="$1" text="$2"
  if [ "$PROMPT_CMD" = zenity ]; then
    zenity --question --title="$title" --text="$text" 2>/dev/null && echo yes || echo no
  elif [ "$PROMPT_CMD" = yad ]; then
    yad --title="$title" --text="$text" --button=gtk-yes:0 --button=gtk-no:1 2>/dev/null && echo yes || echo no
  else
    read -r -p "$text (y/N): " ans
    case "$ans" in [Yy]*) echo yes ;; *) echo no ;; esac
  fi
}

show_output() {
  local title="$1" body="$2"
  if [ "$PROMPT_CMD" = zenity ]; then
    echo "$body" | zenity --text-info --title="$title" --width=700 --height=500 --font="Monospace 10" 2>/dev/null || true
  elif [ "$PROMPT_CMD" = yad ]; then
    echo "$body" | yad --text-info --title="$title" --width=700 --height=500 2>/dev/null || true
  else
    echo ""
    echo "══════════════════════════════════════════════════"
    echo "$title"
    echo "══════════════════════════════════════════════════"
    echo "$body"
    echo "══════════════════════════════════════════════════"
  fi
}

# --- Collect inputs ---
name=$(prompt_input "GPG Key Generator" "Key name / label (e.g. MyProject Release):" "BlueprintX Release")
email=$(prompt_input "GPG Key Generator" "Email address:" "guirodrigues.gor@gmail.com")
uid="${name} <${email}>"

use_passphrase=$(prompt_confirm "GPG Key Generator" "Protect the key with a passphrase?\n(No = passphrase-free, suitable for CI)")

passphrase=""
if [ "$use_passphrase" = yes ]; then
  passphrase=$(prompt_password "GPG Key Generator" "Enter passphrase:")
fi

# --- Generate key ---
if [ -z "$passphrase" ]; then
  gpg --batch --quiet --gen-key <<EOF
Key-Type: EDDSA
Key-Curve: Ed25519
Key-Usage: sign
Name-Real: ${name}
Name-Email: ${email}
Expire-Date: 0
%no-protection
%commit
EOF
else
  gpg --batch --quiet --gen-key <<EOF
Key-Type: EDDSA
Key-Curve: Ed25519
Key-Usage: sign
Name-Real: ${name}
Name-Email: ${email}
Expire-Date: 0
Passphrase: ${passphrase}
%commit
EOF
fi

# --- Retrieve key ID ---
key_id=$(gpg --list-secret-keys --keyid-format LONG "${email}" \
  | awk '/^sec/{split($2,a,"/"); print a[2]; exit}')

# --- Export armored private key ---
if [ -z "$passphrase" ]; then
  private_key=$(gpg --export-secret-keys --armor "${key_id}")
else
  # gpg --export-secret-keys needs the passphrase piped via loopback pinentry
  private_key=$(echo "$passphrase" \
    | gpg --batch --pinentry-mode loopback --passphrase-fd 0 \
          --export-secret-keys --armor "${key_id}")
fi

# --- Build passphrase line for output ---
if [ -z "$passphrase" ]; then
  passphrase_display="(empty — key was generated without a passphrase)"
  passphrase_gh_arg='--body ""'
else
  passphrase_display="${passphrase}"
  passphrase_gh_arg="--body \"${passphrase}\""
fi

# --- Build output block ---
output=$(cat <<BLOCK
Copy the values below into your secrets store:

APT_GPG_KEY_ID
──────────────────────────────────────────────────
${key_id}

APT_GPG_PRIVATE_KEY
──────────────────────────────────────────────────
${private_key}

APT_GPG_PASSPHRASE
──────────────────────────────────────────────────
${passphrase_display}

GitHub CLI commands
──────────────────────────────────────────────────
gh secret set APT_GPG_KEY_ID --body "${key_id}" --repo <owner>/<repo>
gpg --export-secret-keys --armor ${key_id} | gh secret set APT_GPG_PRIVATE_KEY --repo <owner>/<repo>
gh secret set APT_GPG_PASSPHRASE ${passphrase_gh_arg} --repo <owner>/<repo>
BLOCK
)

show_output "GPG APT Secrets — ${uid}" "$output"
