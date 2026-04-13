#!/bin/bash
# Restores ~/.claude/ from a backup snapshot. Always creates a safety backup first.
# Reads CLAUDE_BACKUP_DIR from ~/.claude/.env.

read_backup_dir() {
    grep '^CLAUDE_BACKUP_DIR=' "$HOME/.claude/.env" 2>/dev/null | cut -d= -f2-
}

main() {
    local backup_dir
    backup_dir=$(read_backup_dir)

    if [[ -z "$backup_dir" ]]; then
        zenity --error --title="Restore Memory" \
            --text="<b>CLAUDE_BACKUP_DIR</b> is not set.\n\nAdd it to <tt>~/.claude/.env</tt>."
        exit 1
    fi

    if [[ ! -d "$backup_dir" ]]; then
        zenity --error --title="Restore Memory" \
            --text="Backup directory not accessible:\n<tt>$backup_dir</tt>\n\nCheck that the drive is mounted."
        exit 1
    fi

    local -a snapshots
    mapfile -t snapshots < <(
        find "$backup_dir" -maxdepth 1 -mindepth 1 -type d \
            ! -name 'pre-restore_*' \
            | grep -E '/[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{6}$' \
            | sort -r | head -10
    )

    if [[ ${#snapshots[@]} -eq 0 ]]; then
        zenity --info --title="Restore Memory" \
            --text="No snapshots found in:\n<tt>$backup_dir</tt>\n\nRun Export Memory (Super+Shift+M) first."
        exit 0
    fi

    local -a list_args=()
    for snapshot_path in "${snapshots[@]}"; do
        local snapshot_name
        snapshot_name=$(basename "$snapshot_path")
        local proj_count
        proj_count=$(find "$snapshot_path/projects" -maxdepth 1 -mindepth 1 \
            -type d 2>/dev/null | wc -l)
        local mem_count
        mem_count=$(find "$snapshot_path/projects" -name "*.md" 2>/dev/null | wc -l)
        local size
        size=$(du -sh "$snapshot_path" 2>/dev/null | cut -f1)
        list_args+=("$snapshot_name" "$proj_count projects" "$mem_count memory files" "$size")
    done

    local selected_name
    selected_name=$(
        zenity --list \
            --title="Restore Memory — select snapshot" \
            --text="Select a snapshot to restore (newest first):" \
            --column="Snapshot" \
            --column="Projects" \
            --column="Memory files" \
            --column="Size" \
            "${list_args[@]}"
    ) || exit 0

    local selected_snapshot="$backup_dir/$selected_name"

    zenity --question \
        --title="Restore Memory — confirm" \
        --text="Restore snapshot <b>$selected_name</b>?\n\nYour current <tt>~/.claude/</tt> will be saved as a safety backup first." \
        --ok-label="Restore" --cancel-label="Cancel" || exit 0

    local pre_restore="$backup_dir/pre-restore_$(date +%Y-%m-%d_%H%M%S)"

    zenity --progress --pulsate --no-cancel \
        --title="Restore Memory" \
        --text="Creating safety backup of <tt>~/.claude/</tt>..." 2>/dev/null &
    local zenity_pid=$!

    if ! rsync -a "$HOME/.claude/" "$pre_restore/"; then
        kill "$zenity_pid" 2>/dev/null || true
        zenity --error --title="Restore Memory" \
            --text="Failed to create safety backup at:\n<tt>$pre_restore</tt>\n\nAborting."
        exit 1
    fi

    kill "$zenity_pid" 2>/dev/null || true
    wait "$zenity_pid" 2>/dev/null || true

    zenity --progress --pulsate --no-cancel \
        --title="Restore Memory" \
        --text="Restoring snapshot <b>$selected_name</b>..." 2>/dev/null &
    zenity_pid=$!

    local cmd_count=0 mem_count=0 proj_count=0
    local -a skipped_projects=()

    if [[ -d "$selected_snapshot/commands" ]]; then
        mkdir -p "$HOME/.claude/commands"
        rsync -a "$selected_snapshot/commands/" "$HOME/.claude/commands/"
        cmd_count=$(find "$selected_snapshot/commands" -name "*.md" 2>/dev/null | wc -l)
    fi

    if [[ -f "$selected_snapshot/settings/settings.json" ]]; then
        local backup_json="$selected_snapshot/settings/settings.json"
        local current_json="$HOME/.claude/settings.json"
        if command -v jq &>/dev/null && [[ -f "$current_json" ]]; then
            jq -s '.[0] * .[1]' "$current_json" "$backup_json" \
                > /tmp/merged_settings.json \
                && mv /tmp/merged_settings.json "$current_json"
        else
            cp "$backup_json" "$HOME/.claude/settings.json"
        fi
    fi

    [[ -f "$selected_snapshot/settings/CLAUDE.md" ]] && \
        cp "$selected_snapshot/settings/CLAUDE.md" "$HOME/.claude/CLAUDE.md"

    for proj_dir in "$selected_snapshot/projects"/*/; do
        [[ -d "$proj_dir" ]] || continue
        local proj_name
        proj_name=$(basename "$proj_dir")
        # Guard against glob metacharacters in snapshot-sourced names
        if [[ ! "$proj_name" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
            skipped_projects+=("$proj_name (invalid name)")
            continue
        fi
        local match
        match=$(find "$HOME/.claude/projects" -maxdepth 1 -type d \
            -name "*${proj_name}" 2>/dev/null | head -1)

        if [[ -z "$match" ]]; then
            skipped_projects+=("$proj_name")
            continue
        fi

        if [[ -d "$proj_dir/memory" ]]; then
            mkdir -p "$match/memory"
            rsync -a "$proj_dir/memory/" "$match/memory/"
            local count
            count=$(find "$proj_dir/memory" -name "*.md" 2>/dev/null | wc -l)
            mem_count=$((mem_count + count))
        fi

        [[ -f "$proj_dir/CLAUDE.md" ]] && cp "$proj_dir/CLAUDE.md" "$match/CLAUDE.md"
        proj_count=$((proj_count + 1))
    done

    kill "$zenity_pid" 2>/dev/null || true
    wait "$zenity_pid" 2>/dev/null || true

    local summary="<b>Restored from:</b> <tt>$selected_name</tt>\n"
    summary+="<b>Safety backup:</b> <tt>$(basename "$pre_restore")</tt>\n\n"
    summary+="Commands restored: $cmd_count\n"
    summary+="Projects restored: $proj_count\n"
    summary+="Memory files: $mem_count"

    if [[ ${#skipped_projects[@]} -gt 0 ]]; then
        summary+="\n\n<b>Skipped (no matching project):</b>"
        for p in "${skipped_projects[@]}"; do summary+="\n  $p"; done
    fi

    notify-send --urgency=normal "Restore Memory complete" \
        "$proj_count project(s), $mem_count memory file(s) restored" 2>/dev/null || true
    zenity --info --title="Restore Memory — done" --text="$summary"
}

main
