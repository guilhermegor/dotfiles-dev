#!/bin/bash
# Exports ~/.claude/ memory, commands, and settings to a timestamped snapshot.
# Reads CLAUDE_BACKUP_DIR from ~/.claude/.env.

read_backup_dir() {
    grep '^CLAUDE_BACKUP_DIR=' "$HOME/.claude/.env" 2>/dev/null \
        | cut -d= -f2- \
        | tr -d '[:space:]'
}

main() {
    local backup_dir
    backup_dir=$(read_backup_dir)

    if [[ -z "$backup_dir" ]]; then
        zenity --error --title="Export Memory" \
            --text="<b>CLAUDE_BACKUP_DIR</b> is not set.\n\nAdd it to <tt>~/.claude/.env</tt>."
        exit 1
    fi

    if [[ ! -d "$backup_dir" ]]; then
        zenity --error --title="Export Memory" \
            --text="Backup directory not accessible:\n<tt>$backup_dir</tt>\n\nCheck that the drive is mounted."
        exit 1
    fi

    local snapshot="$backup_dir/$(date +%Y-%m-%d_%H%M%S)"

    zenity --progress --pulsate --no-cancel --auto-close \
        --title="Export Memory" \
        --text="Exporting Claude Code memory to:\n<tt>$snapshot</tt>" 2>/dev/null &
    local zenity_pid=$!

    notify-send --urgency=low "Export Memory" "Starting export..." 2>/dev/null || true

    mkdir -p "$snapshot/commands" "$snapshot/settings"

    if ls "$HOME/.claude/commands/"*.md &>/dev/null 2>&1; then
        rsync -a "$HOME/.claude/commands/"*.md "$snapshot/commands/"
    fi

    [[ -f "$HOME/.claude/settings.json" ]] && \
        cp "$HOME/.claude/settings.json" "$snapshot/settings/"
    [[ -f "$HOME/.claude/CLAUDE.md" ]] && \
        cp "$HOME/.claude/CLAUDE.md" "$snapshot/settings/"

    local project_count=0
    local memory_count=0

    for project_dir in "$HOME/.claude/projects"/*/; do
        [[ -d "$project_dir" ]] || continue

        local dir_name
        dir_name=$(basename "$project_dir")
        local project_name="${dir_name##*-}"

        if [[ ! -d "$project_dir/memory" ]] && [[ ! -f "$project_dir/CLAUDE.md" ]]; then
            continue
        fi

        mkdir -p "$snapshot/projects/$project_name/memory"

        if [[ -d "$project_dir/memory" ]]; then
            rsync -a "$project_dir/memory/" "$snapshot/projects/$project_name/memory/"
            local count
            count=$(find "$project_dir/memory" -name "*.md" 2>/dev/null | wc -l)
            memory_count=$((memory_count + count))
        fi

        [[ -f "$project_dir/CLAUDE.md" ]] && \
            cp "$project_dir/CLAUDE.md" "$snapshot/projects/$project_name/"

        project_count=$((project_count + 1))
    done

    ln -sfn "$snapshot" "$backup_dir/latest"

    kill "$zenity_pid" 2>/dev/null || true
    wait "$zenity_pid" 2>/dev/null || true

    local size
    size=$(du -sh "$snapshot" 2>/dev/null | cut -f1)

    notify-send --urgency=normal "Export Memory complete" \
        "$project_count project(s), $memory_count memory file(s)" 2>/dev/null || true
    zenity --info --title="Export Memory — done" \
        --text="Export complete.\n\n<b>Snapshot:</b> <tt>$(basename "$snapshot")</tt>\n<b>Projects:</b> $project_count\n<b>Memory files:</b> $memory_count\n<b>Total size:</b> $size\n<b>Path:</b> <tt>$snapshot</tt>"
}

main
