#!/bin/bash
# Exports ~/.claude/ to a timestamped snapshot. Reads CLAUDE_BACKUP_DIR from ~/.claude/.env.
#
# The exclusion list below is a DENYLIST on purpose. This script used to name the
# seven things worth keeping, which meant every artifact type added afterwards was
# silently absent from every backup: skills/, agents/, hooks/, rules/, specs/,
# kanban-boards/, teams/, settings.local.json — and memory/, which holds the
# lessons stores that exist nowhere else. Nothing failed; the snapshot just quietly
# stopped being a backup. An allowlist omits what nobody remembered to enumerate,
# and the omission is invisible precisely because it produces no error.
#
# Inverted, the default is "keep it" and each exclusion has to earn its line.

# Regenerable, enormous, or pure churn — restoring these is worse than refetching.
#   plugins/   573M, reinstalled from the marketplace by `make ai_clients`
#   projects/  446M of transcripts; the part worth keeping (projects/*/memory) is
#              copied explicitly below, so the bulk exclusion is not a data loss
#   *.backup_* ~180 rotated settings.json/.env copies, superseded by this snapshot
readonly -a EXCLUDES=(
    --exclude='plugins/'
    --exclude='projects/'
    --exclude='cache/'
    --exclude='paste-cache/'
    --exclude='image-cache/'
    --exclude='file-history/'
    --exclude='shell-snapshots/'
    --exclude='sessions/'
    --exclude='session-env/'
    --exclude='daemon/'
    --exclude='ide/'
    --exclude='chrome/'
    --exclude='backups/'
    --exclude='*.backup_*'
    --exclude='*.bak'
    --exclude='history.jsonl'
    --exclude='daemon.log'
    --exclude='security_warnings_state_*.json'
    # A Python virtualenv (267M, 94% of an otherwise ~18M snapshot). Rebuilt by
    # the tool that made it; restoring one is also wrong across machines, since a
    # venv hardcodes absolute interpreter paths.
    --exclude='security/agent-sdk-venv/'
    --exclude='*.log'
    --exclude='*.log.[0-9]'
    --exclude='*-cache.json'
    --exclude='.last-*'
    # ⚠️ Credentials are deliberately NOT snapshotted. The backup target is an
    # external drive that travels; a live OAuth token on it is a bigger loss than
    # re-authenticating with `claude login`, which costs one command.
    --exclude='.credentials.json'
)

read_backup_dir() {
    grep '^CLAUDE_BACKUP_DIR=' "$HOME/.claude/.env" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]'
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

    local snapshot
    snapshot="$backup_dir/$(date +%Y-%m-%d_%H%M%S)"

    if ! mkdir -p "$snapshot/claude"; then
        zenity --error --title="Export Memory" \
            --text="Cannot create snapshot directory:\n<tt>$snapshot</tt>\n\nCheck permissions."
        exit 1
    fi

    zenity --progress --pulsate --no-cancel --auto-close \
        --title="Export Memory" \
        --text="Exporting Claude Code memory to:\n<tt>$snapshot</tt>" 2>/dev/null &
    local zenity_pid=$!

    notify-send --urgency=low "Export Memory" "Starting export..." 2>/dev/null || true

    # Everything under ~/.claude that the denylist does not exclude. `.env` rides
    # along here (machine-specific config; restore is guarded against clobbering).
    rsync -a "${EXCLUDES[@]}" "$HOME/.claude/" "$snapshot/claude/"

    # Counted for the summary: silence is how the old allowlist hid its gaps, so
    # the report names what landed rather than just declaring success.
    local lessons_count=0
    if [[ -f "$HOME/.claude/tasks/lessons.md" ]]; then
        lessons_count=$(grep -c '^## [0-9]' "$HOME/.claude/tasks/lessons.md" 2>/dev/null || echo 0)
    fi

    local plans_count=0
    if [[ -d "$HOME/.claude/plans" ]]; then
        plans_count=$(find "$HOME/.claude/plans" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l)
    fi

    # The lessons stores live only here — they are the reason this snapshot exists.
    local store_lessons=0
    if [[ -d "$HOME/.claude/memory" ]]; then
        store_lessons=$(find "$HOME/.claude/memory" -name '*.md' 2>/dev/null | wc -l)
    fi

    local skills_count=0
    if [[ -d "$HOME/.claude/skills" ]]; then
        skills_count=$(find "$HOME/.claude/skills" -name 'SKILL.md' 2>/dev/null | wc -l)
    fi

    local project_count=0
    local memory_count=0

    for project_dir in "$HOME/.claude/projects"/*/; do
        [[ -d "$project_dir" ]] || continue

        local project_name
        project_name=$(basename "$project_dir")

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
        "$project_count project(s), $memory_count memory file(s), $store_lessons store lesson(s), $skills_count skill(s), $lessons_count correction(s), $plans_count plan(s)" 2>/dev/null || true
    zenity --info --title="Export Memory — done" \
        --text="Export complete.\n\n<b>Snapshot:</b> <tt>$(basename "$snapshot")</tt>\n<b>Projects:</b> $project_count\n<b>Project memory files:</b> $memory_count\n<b>Store lessons:</b> $store_lessons\n<b>Skills:</b> $skills_count\n<b>Corrections:</b> $lessons_count\n<b>Plans:</b> $plans_count\n<b>Total size:</b> $size\n<b>Path:</b> <tt>$snapshot</tt>"
}

main
