# Env & Memory Backup/Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create four standalone zenity-based bash scripts (`backup_env`, `export_memory`,
`restore_env`, `restore_memory`) in `storage/`, wire them into the existing GNOME shortcut
system via `distro_config/set_custom_shortcuts.sh`, and bind them to four `<Super>` combos.

**Architecture:** Each script is self-contained, reads `CLAUDE_BACKUP_DIR` from
`~/.claude/.env`, and uses zenity for all user interaction (no terminal required). Four
`create_*_script` functions in `set_custom_shortcuts.sh` copy the scripts to `~/.local/bin/`
at setup time; four new `set_individual_keybinding` calls register the GNOME shortcuts.

**Tech Stack:** Bash, zenity, rsync, git, gsettings (GNOME), notify-send.

---

## File Map

| Action | Path |
|--------|------|
| Create | `storage/backup_env.sh` |
| Create | `storage/export_memory.sh` |
| Create | `storage/restore_env.sh` |
| Create | `storage/restore_memory.sh` |
| Modify | `distro_config/set_custom_shortcuts.sh` |

No Makefile changes — `make set_shortcuts` already runs `set_custom_shortcuts.sh`.

---

## Task 1: backup_env.sh

Scans all git repos under `~/github` (up to 2 levels deep), finds git-ignored `.env*`
files, presents a zenity checklist, and copies selected files to
`$CLAUDE_BACKUP_DIR/env_files/<project>.<env_name>_<timestamp>`.

**Files:**
- Create: `storage/backup_env.sh`

- [ ] **Step 1: Create `storage/backup_env.sh`**

```bash
#!/bin/bash
# Backs up git-ignored .env* files from all git repos under ~/github.
# Reads CLAUDE_BACKUP_DIR from ~/.claude/.env for the backup destination.

GITHUB_DIR="$HOME/github"

read_backup_dir() {
    grep '^CLAUDE_BACKUP_DIR=' "$HOME/.claude/.env" 2>/dev/null | cut -d= -f2-
}

find_git_repos() {
    find "$GITHUB_DIR" -maxdepth 2 -name ".git" -type d 2>/dev/null | \
        while IFS= read -r gitdir; do dirname "$gitdir"; done
}

find_ignored_env_files() {
    local repo="$1"
    find "$repo" -maxdepth 1 -name ".env*" ! -name "*.md" 2>/dev/null | \
        while IFS= read -r file; do
            if git -C "$repo" check-ignore --quiet "$file" 2>/dev/null; then
                echo "$file"
            fi
        done
}

main() {
    local backup_dir
    backup_dir=$(read_backup_dir)

    if [[ -z "$backup_dir" ]]; then
        zenity --error --title="Backup Env" \
            --text="<b>CLAUDE_BACKUP_DIR</b> is not set.\n\nAdd it to <tt>~/.claude/.env</tt>."
        exit 1
    fi

    local target="$backup_dir/env_files"

    if ! mkdir -p "$target" 2>/dev/null; then
        zenity --error --title="Backup Env" \
            --text="Cannot create target directory:\n<tt>$target</tt>\n\nCheck permissions."
        exit 1
    fi

    notify-send --urgency=low "Env Backup" "Scanning repos under $GITHUB_DIR..." 2>/dev/null || true

    local -a checklist_args=()
    local found=0

    while IFS= read -r repo; do
        local project_name
        project_name=$(basename "$repo")
        while IFS= read -r file; do
            local filename
            filename=$(basename "$file")
            checklist_args+=(TRUE "$project_name" "$filename" "$file")
            found=$((found + 1))
        done < <(find_ignored_env_files "$repo")
    done < <(find_git_repos)

    if [[ $found -eq 0 ]]; then
        zenity --info --title="Backup Env" \
            --text="No git-ignored <tt>.env</tt> files found under <tt>$GITHUB_DIR</tt>."
        exit 0
    fi

    local selected
    selected=$(
        zenity --list \
            --checklist \
            --title="Backup Env — select files" \
            --text="Found <b>$found</b> git-ignored env file(s). Select files to back up:" \
            --column="Backup?" \
            --column="Project" \
            --column="File" \
            --column="Full path" \
            --hide-column=4 \
            --print-column=4 \
            --separator=$'\n' \
            "${checklist_args[@]}"
    ) || exit 0

    if [[ -z "$selected" ]]; then
        zenity --info --title="Backup Env" --text="No files selected. Nothing to back up."
        exit 0
    fi

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local -a backed_up=()
    local -a failed=()

    while IFS= read -r file_path; do
        [[ -z "$file_path" ]] && continue
        local repo
        repo=$(dirname "$file_path")
        local project_name
        project_name=$(basename "$repo")
        local filename
        filename=$(basename "$file_path")
        local env_name="${filename#.}"
        local dest="$target/${project_name}.${env_name}_${timestamp}"

        if cp "$file_path" "$dest" 2>/tmp/backup_env_err; then
            backed_up+=("$filename ($project_name) → $dest")
        else
            failed+=("$filename ($project_name): $(cat /tmp/backup_env_err)")
        fi
    done <<< "$selected"

    local summary="<b>Backed up ${#backed_up[@]} file(s)</b> to <tt>$target</tt>"

    if [[ ${#backed_up[@]} -gt 0 ]]; then
        summary+="\n\n<b>Backed up:</b>"
        for item in "${backed_up[@]}"; do summary+="\n  $item"; done
    fi

    if [[ ${#failed[@]} -gt 0 ]]; then
        summary+="\n\n<b>Failed:</b>"
        for item in "${failed[@]}"; do summary+="\n  $item"; done
    fi

    notify-send --urgency=normal "Env Backup complete" \
        "${#backed_up[@]} file(s) backed up" 2>/dev/null || true
    zenity --info --title="Backup Env — done" --text="$summary"
}

main
```

- [ ] **Step 2: Syntax-check**

```bash
bash -n storage/backup_env.sh
```

Expected: no output (exit 0).

- [ ] **Step 3: Commit**

```bash
git add storage/backup_env.sh
git commit -m "feat(storage): Add backup_env zenity script for all ~/github repos"
```

---

## Task 2: export_memory.sh

Exports `~/.claude/commands/`, `settings.json`, `CLAUDE.md`, and all project `memory/`
dirs to a timestamped snapshot under `$CLAUDE_BACKUP_DIR/`. Updates a `latest` symlink.

**Files:**
- Create: `storage/export_memory.sh`

- [ ] **Step 1: Create `storage/export_memory.sh`**

```bash
#!/bin/bash
# Exports ~/.claude/ memory, commands, and settings to a timestamped snapshot.
# Reads CLAUDE_BACKUP_DIR from ~/.claude/.env.

read_backup_dir() {
    grep '^CLAUDE_BACKUP_DIR=' "$HOME/.claude/.env" 2>/dev/null | cut -d= -f2-
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
```

- [ ] **Step 2: Syntax-check**

```bash
bash -n storage/export_memory.sh
```

Expected: no output (exit 0).

- [ ] **Step 3: Commit**

```bash
git add storage/export_memory.sh
git commit -m "feat(storage): Add export_memory zenity script for ~/.claude snapshot"
```

---

## Task 3: restore_env.sh

Lists the latest backup per project+env type from `$CLAUDE_BACKUP_DIR/env_files/`,
shows a zenity checklist, asks for confirmation, handles existing-file conflicts with
a radio dialog (overwrite / back up first / skip), then copies and reports.

**Files:**
- Create: `storage/restore_env.sh`

- [ ] **Step 1: Create `storage/restore_env.sh`**

```bash
#!/bin/bash
# Restores git-ignored .env* files from backup to ~/github/<project>/ roots.
# Reads CLAUDE_BACKUP_DIR from ~/.claude/.env.

GITHUB_DIR="$HOME/github"

read_backup_dir() {
    grep '^CLAUDE_BACKUP_DIR=' "$HOME/.claude/.env" 2>/dev/null | cut -d= -f2-
}

format_timestamp() {
    # _20260411_080312 → 2026-04-11 08:03:12
    local ts="${1#_}"
    echo "${ts:0:4}-${ts:4:2}-${ts:6:2} ${ts:9:2}:${ts:11:2}:${ts:13:2}"
}

main() {
    local backup_dir
    backup_dir=$(read_backup_dir)

    if [[ -z "$backup_dir" ]]; then
        zenity --error --title="Restore Env" \
            --text="<b>CLAUDE_BACKUP_DIR</b> is not set.\n\nAdd it to <tt>~/.claude/.env</tt>."
        exit 1
    fi

    local source="$backup_dir/env_files"

    if ! ls "$source" &>/dev/null 2>&1; then
        zenity --error --title="Restore Env" \
            --text="Cannot access source directory:\n<tt>$source</tt>\n\nCheck that the drive is mounted."
        exit 1
    fi

    declare -A latest_ts_per_key
    declare -A latest_path_per_key

    while IFS= read -r file_path; do
        local filename
        filename=$(basename "$file_path")
        local timestamp
        timestamp=$(echo "$filename" | grep -oE '_[0-9]{8}_[0-9]{6}$')
        [[ -z "$timestamp" ]] && continue
        local prefix="${filename%$timestamp}"
        local project_name="${prefix%%.*}"
        local env_name="${prefix#*.}"
        local key="${project_name}|${env_name}"

        if [[ -z "${latest_ts_per_key[$key]+x}" ]] || \
           [[ "$timestamp" > "${latest_ts_per_key[$key]}" ]]; then
            latest_ts_per_key["$key"]="$timestamp"
            latest_path_per_key["$key"]="$file_path"
        fi
    done < <(find "$source" -maxdepth 1 -type f 2>/dev/null | sort)

    if [[ ${#latest_path_per_key[@]} -eq 0 ]]; then
        zenity --info --title="Restore Env" \
            --text="No backup files found in:\n<tt>$source</tt>"
        exit 0
    fi

    local -a checklist_args=()

    for key in "${!latest_path_per_key[@]}"; do
        local project_name="${key%%|*}"
        local env_name="${key#*|}"
        local ts_display
        ts_display=$(format_timestamp "${latest_ts_per_key[$key]}")
        local file_path="${latest_path_per_key[$key]}"
        checklist_args+=(TRUE "$project_name" ".$env_name" "$ts_display" "$file_path")
    done

    local selected
    selected=$(
        zenity --list \
            --checklist \
            --title="Restore Env — select backups" \
            --text="Select env backups to restore (latest version per type shown):" \
            --column="Restore?" \
            --column="Project" \
            --column="Env file" \
            --column="Backed up on" \
            --column="Backup path" \
            --hide-column=5 \
            --print-column=5 \
            --separator=$'\n' \
            "${checklist_args[@]}"
    ) || exit 0

    if [[ -z "$selected" ]]; then
        zenity --info --title="Restore Env" --text="No files selected."
        exit 0
    fi

    local sel_count
    sel_count=$(grep -c . <<< "$selected")
    zenity --question \
        --title="Restore Env — confirm" \
        --text="Restore <b>$sel_count</b> env file(s) to your project roots?\n\nThis will modify files under <tt>$GITHUB_DIR</tt>." \
        --ok-label="Restore" --cancel-label="Cancel" || exit 0

    local -a restored=()
    local -a skipped=()
    local -a failed=()

    while IFS= read -r file_path; do
        [[ -z "$file_path" ]] && continue
        local filename
        filename=$(basename "$file_path")
        local timestamp
        timestamp=$(echo "$filename" | grep -oE '_[0-9]{8}_[0-9]{6}$')
        local prefix="${filename%$timestamp}"
        local project_name="${prefix%%.*}"
        local env_name="${prefix#*.}"
        local dest_dir="$GITHUB_DIR/$project_name"
        local dest="$dest_dir/.$env_name"

        if [[ ! -d "$dest_dir" ]]; then
            failed+=(".$env_name ($project_name): project dir not found at $dest_dir")
            continue
        fi

        if [[ -f "$dest" ]]; then
            local choice
            choice=$(zenity --list \
                --radiolist \
                --title="Conflict: $project_name/.$env_name" \
                --text="<tt>.$env_name</tt> already exists in <tt>$project_name</tt>.\nWhat would you like to do?" \
                --column="Select" --column="Action" \
                TRUE "Overwrite it" \
                FALSE "Back it up first, then restore" \
                FALSE "Skip this file" \
            ) || { skipped+=(".$env_name ($project_name): cancelled"); continue; }

            case "$choice" in
                "Back it up first, then restore")
                    local bak="$dest.bak_$(date +%Y%m%d_%H%M%S)"
                    if ! mv "$dest" "$bak" 2>/tmp/restore_env_err; then
                        failed+=(".$env_name ($project_name): could not back up — $(cat /tmp/restore_env_err)")
                        continue
                    fi
                    ;;
                "Skip this file")
                    skipped+=(".$env_name ($project_name): skipped by user")
                    continue
                    ;;
            esac
        fi

        if cp "$file_path" "$dest" 2>/tmp/restore_env_err; then
            restored+=("$(basename "$file_path") → $dest")
        else
            failed+=(".$env_name ($project_name): $(cat /tmp/restore_env_err)")
        fi
    done <<< "$selected"

    local summary=""
    if [[ ${#restored[@]} -gt 0 ]]; then
        summary+="<b>Restored:</b>"
        for item in "${restored[@]}"; do summary+="\n  $item"; done
        summary+="\n\n"
    fi
    if [[ ${#skipped[@]} -gt 0 ]]; then
        summary+="<b>Skipped:</b>"
        for item in "${skipped[@]}"; do summary+="\n  $item"; done
        summary+="\n\n"
    fi
    if [[ ${#failed[@]} -gt 0 ]]; then
        summary+="<b>Failed:</b>"
        for item in "${failed[@]}"; do summary+="\n  $item"; done
    fi

    notify-send --urgency=normal "Restore Env complete" \
        "${#restored[@]} restored, ${#skipped[@]} skipped, ${#failed[@]} failed" 2>/dev/null || true
    zenity --info --title="Restore Env — done" --text="${summary:-No changes made.}"
}

main
```

- [ ] **Step 2: Syntax-check**

```bash
bash -n storage/restore_env.sh
```

Expected: no output (exit 0).

- [ ] **Step 3: Commit**

```bash
git add storage/restore_env.sh
git commit -m "feat(storage): Add restore_env zenity script with conflict resolution"
```

---

## Task 4: restore_memory.sh

Lists last 10 `~/.claude/` snapshots from `$CLAUDE_BACKUP_DIR/`, user picks one,
confirms, creates a `pre-restore_<ts>` safety backup, then `rsync`-restores commands,
settings, and all matched project memory dirs.

**Files:**
- Create: `storage/restore_memory.sh`

- [ ] **Step 1: Create `storage/restore_memory.sh`**

```bash
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
```

- [ ] **Step 2: Syntax-check**

```bash
bash -n storage/restore_memory.sh
```

Expected: no output (exit 0).

- [ ] **Step 3: Commit**

```bash
git add storage/restore_memory.sh
git commit -m "feat(storage): Add restore_memory zenity script with safety backup"
```

---

## Task 5: Extend set_custom_shortcuts.sh

Add four `create_*_script` functions and four new `set_individual_keybinding` entries
(indices 11–14) to the existing file. Extend `set_keybindings_array` to `custom14`.

**Files:**
- Modify: `distro_config/set_custom_shortcuts.sh`

- [ ] **Step 1: Add four `create_*_script` functions after `create_backup_script()`**

Insert after line 172 (end of `create_backup_script`):

```bash
# function to install backup-env.sh to ~/.local/bin
create_backup_env_script() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local src_script="$script_dir/../storage/backup_env.sh"
    local dest_script="$HOME/.local/bin/backup-env.sh"

    print_status $BLUE "Installing backup-env.sh to $dest_script..."
    mkdir -p "$HOME/.local/bin"

    if [ ! -f "$src_script" ]; then
        print_status $RED "Source script not found: $src_script"
        return 1
    fi

    cp "$src_script" "$dest_script"
    chmod +x "$dest_script"
    print_status $GREEN "backup-env.sh installed at $dest_script"
}

# function to install export-memory.sh to ~/.local/bin
create_export_memory_script() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local src_script="$script_dir/../storage/export_memory.sh"
    local dest_script="$HOME/.local/bin/export-memory.sh"

    print_status $BLUE "Installing export-memory.sh to $dest_script..."
    mkdir -p "$HOME/.local/bin"

    if [ ! -f "$src_script" ]; then
        print_status $RED "Source script not found: $src_script"
        return 1
    fi

    cp "$src_script" "$dest_script"
    chmod +x "$dest_script"
    print_status $GREEN "export-memory.sh installed at $dest_script"
}

# function to install restore-env.sh to ~/.local/bin
create_restore_env_script() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local src_script="$script_dir/../storage/restore_env.sh"
    local dest_script="$HOME/.local/bin/restore-env.sh"

    print_status $BLUE "Installing restore-env.sh to $dest_script..."
    mkdir -p "$HOME/.local/bin"

    if [ ! -f "$src_script" ]; then
        print_status $RED "Source script not found: $src_script"
        return 1
    fi

    cp "$src_script" "$dest_script"
    chmod +x "$dest_script"
    print_status $GREEN "restore-env.sh installed at $dest_script"
}

# function to install restore-memory.sh to ~/.local/bin
create_restore_memory_script() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local src_script="$script_dir/../storage/restore_memory.sh"
    local dest_script="$HOME/.local/bin/restore-memory.sh"

    print_status $BLUE "Installing restore-memory.sh to $dest_script..."
    mkdir -p "$HOME/.local/bin"

    if [ ! -f "$src_script" ]; then
        print_status $RED "Source script not found: $src_script"
        return 1
    fi

    cp "$src_script" "$dest_script"
    chmod +x "$dest_script"
    print_status $GREEN "restore-memory.sh installed at $dest_script"
}
```

- [ ] **Step 2: Update `set_keybindings_array` — replace the existing body with custom0–custom14**

Replace:
```bash
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings \
    "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom3/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom4/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom5/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom6/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom7/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom8/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom9/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom10/']"
```

With:
```bash
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings \
    "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom3/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom4/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom5/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom6/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom7/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom8/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom9/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom10/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom11/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom12/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom13/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom14/']"
```

- [ ] **Step 3: Update `bindings` array and add four `create_*_script` calls in `set_all_keybindings`**

Replace the `bindings` line:
```bash
    local bindings=("<Super>e" "<Super>r" "<Super>t" "<Super><Ctrl>s" "<Ctrl><Shift>c" "<Ctrl><Shift>v" "<Super>k" "<Ctrl><Shift>Escape" "<Super>c" "<Super>b" "<Super>j")
```

With:
```bash
    local bindings=("<Super>e" "<Super>r" "<Super>t" "<Super><Ctrl>s" "<Ctrl><Shift>c" "<Ctrl><Shift>v" "<Super>k" "<Ctrl><Shift>Escape" "<Super>c" "<Super>b" "<Super>j" "<Super><Shift>e" "<Super><Shift>m" "<Super><Alt>e" "<Super><Alt>m")
```

Then add four install calls after `create_backup_script`:
```bash
    create_backup_env_script
    create_export_memory_script
    create_restore_env_script
    create_restore_memory_script
```

- [ ] **Step 4: Add four `set_individual_keybinding` calls after index 10**

After:
```bash
    set_individual_keybinding 10 "Show All Shortcuts" "gnome-control-center keyboard" "<Super>j"
```

Add:
```bash
    set_individual_keybinding 11 "Backup Env Files" "$HOME/.local/bin/backup-env.sh" "<Super><Shift>e"
    set_individual_keybinding 12 "Export Claude Memory" "$HOME/.local/bin/export-memory.sh" "<Super><Shift>m"
    set_individual_keybinding 13 "Restore Env Files" "$HOME/.local/bin/restore-env.sh" "<Super><Alt>e"
    set_individual_keybinding 14 "Restore Claude Memory" "$HOME/.local/bin/restore-memory.sh" "<Super><Alt>m"
```

- [ ] **Step 5: Update summary print block**

After the existing `print_status $YELLOW "  - Super+J..."` line, add:
```bash
    print_status $YELLOW "  - Super+Shift+E to back up .env files from all ~/github repos"
    print_status $YELLOW "  - Super+Shift+M to export Claude Code memory to backup"
    print_status $YELLOW "  - Super+Alt+E to restore .env files from backup"
    print_status $YELLOW "  - Super+Alt+M to restore Claude Code memory from backup"
```

- [ ] **Step 6: Syntax-check**

```bash
bash -n distro_config/set_custom_shortcuts.sh
```

Expected: no output (exit 0).

- [ ] **Step 7: Commit**

```bash
git add distro_config/set_custom_shortcuts.sh
git commit -m "feat(distro_config): Wire backup/restore scripts into GNOME shortcuts"
```

---

## Deployment

After all tasks are committed, deploy with:

```bash
make permissions        # chmod +x the new storage/*.sh scripts
make set_shortcuts      # copy to ~/.local/bin + register GNOME bindings
```

Verify with:
```bash
ls -la ~/.local/bin/backup-env.sh ~/.local/bin/export-memory.sh \
       ~/.local/bin/restore-env.sh ~/.local/bin/restore-memory.sh
gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom11/ binding
# Expected: '<Super><Shift>e'
```
