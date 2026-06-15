#!/bin/bash

# Backup a mounted external SSD to a cloud folder on this PC.
#
# GUI flow (zenity — works from GNOME keyboard shortcut):
#   1. Pick the source drive from drives mounted under /media/$USER/
#   2. Enter / confirm the cloud destination path (remembered between runs)
#   3. Show a pulsing progress dialog while the drive is zipped
#   4. Notify on success or failure
#
# The backup is written as a single compressed .zip archived directly from the
# source drive — no uncompressed mirror is ever staged, so the cloud folder
# holds one compact file per run instead of a full duplicate of the drive.
#
# Destination structure:
#   <cloud_path>/<source_drive_name>/<yyyymmdd_hhmmss>.zip
#
# Last-used destination is saved to ~/.config/backup-external-ssd.conf

CONF_FILE="$HOME/.config/backup-external-ssd.conf"
CURRENT_USER=$(id -un)
MEDIA_BASE="/media/$CURRENT_USER"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# zip compression level (0=store … 9=max). 6 is zip's default: a balanced
# trade-off between archive size and CPU time. Lossless at every level.
ZIP_LEVEL=6

# ── Config helpers ────────────────────────────────────────────────────────────

load_last_dest() {
    [ -f "$CONF_FILE" ] || return
    grep '^LAST_DEST=' "$CONF_FILE" | cut -d= -f2-
}

save_last_dest() {
    mkdir -p "$(dirname "$CONF_FILE")"
    echo "LAST_DEST=$1" > "$CONF_FILE"
}

# ── Drive discovery ───────────────────────────────────────────────────────────

find_mounted_drives() {
    for drive_path in "$MEDIA_BASE"/*/; do
        [ -d "$drive_path" ] || continue
        basename "$drive_path"
    done
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    # 0. Require zip — the archive step depends on it
    if ! command -v zip >/dev/null 2>&1; then
        zenity --error --title="Backup" \
            --text="<b>zip</b> is not installed.\n\nInstall it with <tt>sudo apt install zip</tt> and try again."
        exit 1
    fi

    # 1. Collect mounted drives
    local -a drives
    mapfile -t drives < <(find_mounted_drives)

    if [ ${#drives[@]} -eq 0 ]; then
        zenity --error --title="Backup" \
            --text="No drives found under <tt>$MEDIA_BASE</tt>.\n\nMount your external SSD first."
        exit 1
    fi

    # 2. Pick source drive
    local source_name
    if [ ${#drives[@]} -eq 1 ]; then
        source_name="${drives[0]}"
        zenity --question --title="Backup" \
            --text="Back up <b>$source_name</b> to the cloud?\n\nPress OK to continue." \
            --ok-label="OK" --cancel-label="Cancel" || exit 0
    else
        source_name=$(
            zenity --list \
                --title="Backup — select source drive" \
                --text="Choose the drive to back up:" \
                --column="Drive" \
                "${drives[@]}"
        ) || exit 0
    fi

    local src="$MEDIA_BASE/$source_name"

    # 3. Ask for destination cloud path (pre-filled with last-used value)
    local last_dest
    last_dest=$(load_last_dest)

    local dest_base
    dest_base=$(
        zenity --entry \
            --title="Backup — destination" \
            --text="Enter the cloud folder path on this PC\n(files will be saved under <b>$source_name/&lt;timestamp&gt;/</b>):" \
            --entry-text="${last_dest:-$HOME/}"
    ) || exit 0

    if [ -z "$dest_base" ]; then
        zenity --error --title="Backup" --text="No destination path provided."
        exit 1
    fi

    save_last_dest "$dest_base"

    local dest_dir="${dest_base%/}/${source_name}"
    local dest="${dest_dir}/${TIMESTAMP}.zip"

    if ! mkdir -p "$dest_dir"; then
        zenity --error --title="Backup" \
            --text="Cannot create destination:\n<tt>$dest_dir</tt>\n\nCheck the path and permissions."
        exit 1
    fi

    # 4. Zip the drive into a single archive with a pulsing progress dialog.
    #    Zipping is run from inside $src so archive paths are relative to the
    #    drive root; -r recurses, -y stores symlinks as links rather than
    #    following them, -q stays quiet, and lost+found is excluded.
    notify-send --urgency=low "Backup started" \
        "$source_name → $dest_base" 2>/dev/null || true

    ( cd "$src" || exit 1; zip -r -y -q -"$ZIP_LEVEL" "$dest" . -x 'lost+found/*' ) &
    local zip_pid=$!

    zenity --progress --pulsate --no-cancel --auto-close \
        --title="Backing up $source_name" \
        --text="Compressing <b>$source_name</b> to:\n<tt>$dest</tt>" 2>/dev/null &
    local zenity_pid=$!

    wait "$zip_pid"
    local exit_code=$?

    kill "$zenity_pid" 2>/dev/null || true
    wait "$zenity_pid" 2>/dev/null || true

    # 5. Report result
    if [ "$exit_code" -eq 0 ]; then
        notify-send --urgency=normal "Backup complete" \
            "$source_name → $dest" 2>/dev/null || true
        zenity --info --title="Backup complete" \
            --text="<b>$source_name</b> backed up successfully.\n\n<tt>$dest</tt>"
    else
        notify-send --urgency=critical "Backup failed" \
            "zip exited with code $exit_code" 2>/dev/null || true
        zenity --error --title="Backup failed" \
            --text="zip exited with error <b>$exit_code</b>.\n\nCheck available space and permissions."
        exit 1
    fi
}

main
