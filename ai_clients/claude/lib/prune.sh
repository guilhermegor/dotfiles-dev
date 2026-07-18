#!/bin/bash
# Removes installed artifacts in ~/.claude/ that no longer exist in this repo.
#
# The install_* steps only ever copy, never delete, so every artifact removed
# from source stays behind in ~/.claude/ indefinitely. Those leftovers are not
# inert: a stale file that later regains a loadable layout silently resurrects
# a deleted artifact. This step is the delete path.
#
# Always interactive — it asks before removing anything. Source is the authority,
# so anything here is recoverable from git history.

# type → "<source subdir>:<source ext>:<dest subdir>:<layout>"
# layout: flat  → <dest>/<name><ext>
#         nested→ <dest>/<name>/SKILL.md
declare -A PRUNE_TARGETS=(
    [commands]="commands:.md:commands:flat"
    [skills]="skills:.md:skills:nested"
    [agents]="agents:.md:agents:flat"
    [rules]="rules:.md:rules:flat"
    [hooks]="hooks:.sh:hooks:flat"
)

# Echoes the installed artifact names for one type, one per line.
_installed_names() {
    local dest="$1" ext="$2" layout="$3"

    [[ -d "$dest" ]] || return 0

    if [[ "$layout" == "nested" ]]; then
        find "$dest" -mindepth 2 -maxdepth 2 -name 'SKILL.md' -printf '%h\n' \
            | xargs -r -n1 basename
        return 0
    fi

    find "$dest" -maxdepth 1 -type f -name "*$ext" -printf '%f\n' \
        | sed "s/${ext//./\\.}\$//"
}

# Echoes the source artifact names for one type, one per line.
_source_names() {
    local src="$1" ext="$2"

    [[ -d "$src" ]] || return 0

    find "$src" -maxdepth 1 -type f -name "*$ext" -printf '%f\n' \
        | sed "s/${ext//./\\.}\$//"
}

prune_orphans() {
    print_status "section" "PRUNING ORPHANED ARTIFACTS"

    local -a orphan_paths=()
    local -a orphan_labels=()
    local type spec src ext dest layout name

    for type in "${!PRUNE_TARGETS[@]}"; do
        spec="${PRUNE_TARGETS[$type]}"
        IFS=':' read -r src ext dest layout <<< "$spec"
        src="$SCRIPT_DIR/$src"
        dest="$CLAUDE_DIR/$dest"

        while read -r name; do
            [[ -n "$name" ]] || continue
            if [[ "$layout" == "nested" ]]; then
                orphan_paths+=("$dest/$name")
            else
                orphan_paths+=("$dest/$name$ext")
            fi
            orphan_labels+=("$type: $name")
        done < <(comm -13 \
            <(_source_names "$src" "$ext" | sort) \
            <(_installed_names "$dest" "$ext" "$layout" | sort))
    done

    if (( ${#orphan_paths[@]} == 0 )); then
        print_status "success" "No orphaned artifacts — ~/.claude matches source"
        return 0
    fi

    print_status "warning" "Found ${#orphan_paths[@]} artifact(s) installed but absent from source:"
    local label
    for label in "${orphan_labels[@]}"; do
        print_status "info" "  $label"
    done

    local reply
    read -r -p "Remove these? They are recoverable from git history. [y/N] " reply
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
        print_status "info" "Left in place — nothing removed"
        return 0
    fi

    local path
    for path in "${orphan_paths[@]}"; do
        rm -rf "$path"
    done
    print_status "success" "Removed ${#orphan_paths[@]} orphaned artifact(s)"
}
