#!/bin/bash
# Backs up git-ignored .env* files from all git repos under ~/github.
# Reads CLAUDE_BACKUP_DIR from ~/.claude/.env for the backup destination.

GITHUB_DIR="$HOME/github"

read_backup_dir() {
    grep '^CLAUDE_BACKUP_DIR=' "$HOME/.claude/.env" 2>/dev/null \
        | cut -d= -f2- \
        | tr -d '[:space:]'
}

find_git_repos() {
    while IFS= read -r gitdir; do
        dirname "$gitdir"
    done < <(find "$GITHUB_DIR" -maxdepth 2 -name ".git" -type d 2>/dev/null)
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

        local err_msg
        if err_msg=$(cp "$file_path" "$dest" 2>&1); then
            backed_up+=("$filename ($project_name) → $dest")
        else
            failed+=("$filename ($project_name): $err_msg")
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
