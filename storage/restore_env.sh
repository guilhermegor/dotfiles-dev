#!/bin/bash
# Restores git-ignored .env* files from backup to ~/github/<project>/ roots.
# Reads CLAUDE_BACKUP_DIR from ~/.claude/.env.

GITHUB_DIR="$HOME/github"

read_backup_dir() {
    grep '^CLAUDE_BACKUP_DIR=' "$HOME/.claude/.env" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]'
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

    if [[ ! -d "$source" ]]; then
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
        local proj_key="${prefix%__*}"
        local env_name="${prefix##*__}"
        local key="${proj_key}|${env_name}"

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
        local proj_key="${key%%|*}"
        local env_name="${key#*|}"
        local project_rel="${proj_key//__//}"
        local ts_display
        ts_display=$(format_timestamp "${latest_ts_per_key[$key]}")
        local file_path="${latest_path_per_key[$key]}"
        checklist_args+=(TRUE "$project_rel" ".$env_name" "$ts_display" "$file_path")
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
        local proj_key="${prefix%__*}"
        local env_name="${prefix##*__}"
        local project_rel="${proj_key//__//}"
        local dest_dir="$GITHUB_DIR/$project_rel"
        local dest="$dest_dir/.$env_name"

        if [[ ! -d "$dest_dir" ]]; then
            failed+=(".$env_name ($project_rel): project dir not found at $dest_dir")
            continue
        fi

        if [[ -f "$dest" ]]; then
            local choice
            choice=$(zenity --list \
                --radiolist \
                --title="Conflict: $project_rel/.$env_name" \
                --text="<tt>.$env_name</tt> already exists in <tt>$project_rel</tt>.\nWhat would you like to do?" \
                --column="Select" --column="Action" \
                TRUE "Overwrite it" \
                FALSE "Back it up first, then restore" \
                FALSE "Skip this file" \
            ) || { skipped+=(".$env_name ($project_rel): cancelled"); continue; }

            case "$choice" in
                "Back it up first, then restore")
                    local bak="$dest.bak_$(date +%Y%m%d_%H%M%S)"
                    local bak_err
                    if ! bak_err=$(mv "$dest" "$bak" 2>&1); then
                        failed+=(".$env_name ($project_rel): could not back up — $bak_err")
                        continue
                    fi
                    ;;
                "Skip this file")
                    skipped+=(".$env_name ($project_rel): skipped by user")
                    continue
                    ;;
            esac
        fi

        local cp_err
        if cp_err=$(cp "$file_path" "$dest" 2>&1); then
            restored+=("$(basename "$file_path") → $dest")
        else
            failed+=(".$env_name ($project_rel): $cp_err")
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
