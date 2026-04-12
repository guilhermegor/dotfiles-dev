#!/bin/bash

# Backup external SSDs to the BKP cloud-sync drive.
#
# Destination structure:
#   <bkp_drive>/<source_drive_name>/<yyyymmdd_hhmmss>/
#
# BKP drive selection: first drive under /media/$USER/ whose name starts with
# "BKP" or contains "backup" (case-insensitive), matching the convention used
# in ai_clients/claude/commands/backup-env.md.
#
# Designed to run from a GNOME keybinding (Super+B): uses notify-send for
# feedback instead of a terminal. Run directly for verbose rsync output.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CURRENT_USER=$(id -un)
MEDIA_BASE="/media/$CURRENT_USER"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

print_status() {
    local status="$1"
    local message="$2"
    case "$status" in
        success) echo -e "${GREEN}[✓]${NC} ${message}" ;;
        error)   echo -e "${RED}[✗]${NC} ${message}" >&2 ;;
        warning) echo -e "${YELLOW}[!]${NC} ${message}" ;;
        info)    echo -e "${BLUE}[i]${NC} ${message}" ;;
        *)       echo -e "[ ] ${message}" ;;
    esac
}

notify_user() {
    local urgency="$1"
    local summary="$2"
    local body="${3:-}"
    notify-send --urgency="$urgency" "SSD Backup" "${summary}${body:+ — $body}" 2>/dev/null || true
}

find_bkp_drive() {
    if [ ! -d "$MEDIA_BASE" ]; then
        echo ""
        return
    fi

    for drive_path in "$MEDIA_BASE"/*/; do
        [ -d "$drive_path" ] || continue
        local name
        name=$(basename "$drive_path")
        if echo "$name" | grep -iqE '(^BKP|backup)'; then
            echo "$drive_path"
            return
        fi
    done

    echo ""
}

find_source_drives() {
    if [ ! -d "$MEDIA_BASE" ]; then
        return
    fi

    for drive_path in "$MEDIA_BASE"/*/; do
        [ -d "$drive_path" ] || continue
        local name
        name=$(basename "$drive_path")
        if ! echo "$name" | grep -iqE '(^BKP|backup)'; then
            echo "$drive_path"
        fi
    done
}

main() {
    print_status "info" "External SSD backup — $TIMESTAMP"
    notify_user "low" "Backup started" "$TIMESTAMP"

    local bkp_drive
    bkp_drive=$(find_bkp_drive)

    if [ -z "$bkp_drive" ]; then
        local msg="No BKP drive found under $MEDIA_BASE. Mount a drive named BKP* first."
        print_status "error" "$msg"
        notify_user "critical" "Backup failed" "$msg"
        exit 1
    fi

    print_status "info" "Destination: $bkp_drive"

    local -a sources
    mapfile -t sources < <(find_source_drives)

    if [ ${#sources[@]} -eq 0 ]; then
        local msg="No source drives found under $MEDIA_BASE."
        print_status "warning" "$msg"
        notify_user "normal" "Nothing to back up" "$msg"
        exit 0
    fi

    local backed_up=0
    local failed=0

    for src in "${sources[@]}"; do
        local drive_name
        drive_name=$(basename "$src")
        local dest="${bkp_drive}${drive_name}/${TIMESTAMP}"

        print_status "info" "Backing up '$drive_name' → $dest"

        if mkdir -p "$dest" && rsync -a --info=progress2 "$src" "$dest/"; then
            print_status "success" "Done: $drive_name"
            backed_up=$((backed_up + 1))
        else
            print_status "error" "Failed: $drive_name"
            failed=$((failed + 1))
        fi
    done

    if [ "$failed" -eq 0 ]; then
        local msg="$backed_up drive(s) → $(basename "$bkp_drive")/$TIMESTAMP"
        print_status "success" "Backup complete — $msg"
        notify_user "normal" "Backup complete" "$msg"
    else
        local msg="$backed_up succeeded, $failed failed"
        print_status "warning" "$msg"
        notify_user "critical" "Backup completed with errors" "$msg"
        exit 1
    fi
}

main
