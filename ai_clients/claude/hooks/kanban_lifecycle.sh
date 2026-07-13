#!/bin/bash
# PostToolUse (Bash matcher) hook: drive the two GitHub Projects v2 card transitions that Projects'
# own workflows CANNOT trigger — leaving the rest to the native automation.
#
#   git checkout -b / git switch -c  (a linked branch opened) -> card to "In progress"
#   gh pr create                     (the PR opened)          -> card to "In review"
#
# NOT handled here — on purpose: "PR merged / issue closed -> Done" is a built-in GitHub Projects
# workflow (issue.md already relies on it via `Closes #N`). Duplicating it in a hook would race the
# native automation, so Done is left native. This hook fills only the two gaps.
#
# Why a hook: the lifecycle transitions are deterministic functions of git/gh actions the harness
# already sees as Bash tool calls, but were being set by hand (`gh project item-edit`) every time —
# pure toil, easy to forget, board goes stale. Match the VERB, then resolve the issue/card via gh —
# never scrape a flag out of the raw command string (hook-command-string-scraping-fragile).
#
# Per-repo board ids (project number/node, Status field id, option ids) are discovered live via
# `gh project field-list` and cached in a LOCAL, git-ignored file — same seam as the tracker map:
# selecting a repo's board needs zero in-repo config, so a restricted repo is unaffected. A repo
# with no `<repo> kanban` project simply finds nothing and no-ops (which also skips Linear/none
# repos for free). A cached id gone stale (board recreated / columns renamed) self-heals: a failed
# move refreshes the cache once and retries.
#
# Hook I/O contract: PostToolUse, so the tool already ran — this never blocks. It fails OPEN
# everywhere (no gh/jq, no repo, no board, no card, any gh error) by exiting 0 silently; on a
# successful move it emits an additionalContext note. Never exits non-zero.

set -u

CACHE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/kanban-boards"

command -v jq >/dev/null 2>&1 || exit 0
command -v gh >/dev/null 2>&1 || exit 0

main() {
    local payload tool command target owner repo issue
    local project_number project_node status_field option_id item_id

    payload="$(cat)"
    tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"
    [[ "$tool" == "Bash" ]] || exit 0

    command="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    [[ -n "$command" ]] || exit 0

    target="$(target_column "$command")" || exit 0     # not a lifecycle verb → nothing to do

    read -r owner repo < <(owner_repo) || exit 0
    [[ -n "$owner" && -n "$repo" ]] || exit 0

    # Both verbs run while HEAD is the feature branch (`checkout -b` checks it out; `gh pr create`
    # runs from it), and issue.md names branches `<type>/<N>-<slug>`, so the branch carries the ref.
    issue="$(issue_from_head)" || exit 0
    [[ -n "$issue" ]] || exit 0

    read -r project_number project_node status_field option_id \
        < <(board_config "$owner" "$repo" "$target") || exit 0
    [[ -n "$project_number" && -n "$option_id" ]] || exit 0

    item_id="$(card_item_id "$project_number" "$owner" "$issue")" || exit 0
    [[ -n "$item_id" ]] || exit 0     # issue not on the board → nothing to move

    if ! move_card "$project_node" "$item_id" "$status_field" "$option_id"; then
        # A stale cache is the likely cause — refresh once and retry before giving up.
        rm -f "$(cache_file "$owner" "$repo")"
        read -r project_number project_node status_field option_id \
            < <(board_config "$owner" "$repo" "$target") || exit 0
        move_card "$project_node" "$item_id" "$status_field" "$option_id" || exit 0
    fi

    announce "$issue" "$target"
}

target_column() {
    # Map the Bash verb to its target column, or return 1 when it is neither lifecycle verb.
    local cmd="$1"
    if printf '%s' "$cmd" \
        | grep -Eq '^[[:space:]]*(rtk[[:space:]]+)?git[[:space:]]+(checkout[[:space:]]+.*-b|switch[[:space:]]+.*-c)'; then
        printf 'In progress'; return 0
    fi
    if printf '%s' "$cmd" \
        | grep -Eq '^[[:space:]]*(rtk[[:space:]]+)?gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'; then
        printf 'In review'; return 0
    fi
    return 1
}

owner_repo() {
    gh repo view --json owner,name -q '.owner.login + " " + .name' 2>/dev/null
}

issue_from_head() {
    # Leftmost number run in the current branch name (feat/46-slug → 46), matching issue.md's
    # `<type>/<N>-<slug>` convention.
    local branch
    branch="$(git symbolic-ref --short HEAD 2>/dev/null)" || return 1
    [[ "$branch" =~ (^|[^0-9])([0-9]+)([^0-9]|$) ]] || return 1
    printf '%s' "${BASH_REMATCH[2]}"
}

cache_file() {
    printf '%s/%s-%s.json' "$CACHE_DIR" "$1" "$2"
}

board_config() {
    # Emit "<project_number> <project_node> <status_field_id> <option_id_for_target>". Reads the
    # per-repo cache, discovering + writing it on a miss. Returns 1 if there is no `<repo> kanban`
    # board or the target column does not exist.
    local owner="$1" repo="$2" target="$3" file line num node field opt
    file="$(cache_file "$owner" "$repo")"

    if [[ -r "$file" ]]; then
        opt="$(jq -r --arg t "$target" '.options[$t] // empty' "$file" 2>/dev/null)"
        if [[ -n "$opt" ]]; then
            num="$(jq -r '.project_number' "$file")"
            node="$(jq -r '.project_node_id' "$file")"
            field="$(jq -r '.status_field_id' "$file")"
            # Trailing newline is required: the caller uses `read`, which returns non-zero on EOF
            # before a delimiter and would trip its `|| exit 0` despite assigning the vars.
            printf '%s %s %s %s\n' "$num" "$node" "$field" "$opt"
            return 0
        fi
    fi

    line="$(discover_board "$owner" "$repo")" || return 1   # writes the cache as a side effect
    opt="$(printf '%s' "$line" | jq -r --arg t "$target" '.options[$t] // empty' 2>/dev/null)"
    [[ -n "$opt" ]] || return 1
    printf '%s %s %s %s\n' \
        "$(printf '%s' "$line" | jq -r '.project_number')" \
        "$(printf '%s' "$line" | jq -r '.project_node_id')" \
        "$(printf '%s' "$line" | jq -r '.status_field_id')" \
        "$opt"
}

discover_board() {
    # Find the `<repo> kanban` project, resolve its Status field + option ids, cache the result, and
    # echo it as one JSON object. Returns 1 when no such board exists.
    local owner="$1" repo="$2" projects num node fields field_id options config
    projects="$(gh project list --owner "$owner" --format json 2>/dev/null)" || return 1

    read -r num node < <(printf '%s' "$projects" \
        | jq -r --arg t "$repo kanban" '.projects[] | select(.title==$t) | "\(.number) \(.id)"' \
        | head -n1)
    [[ -n "$num" && -n "$node" ]] || return 1

    fields="$(gh project field-list "$num" --owner "$owner" --format json 2>/dev/null)" || return 1
    field_id="$(printf '%s' "$fields" | jq -r '.fields[] | select(.name=="Status") | .id' | head -n1)"
    [[ -n "$field_id" ]] || return 1
    options="$(printf '%s' "$fields" \
        | jq -c '[.fields[] | select(.name=="Status") | .options[]] | map({(.name): .id}) | add')"
    [[ -n "$options" && "$options" != "null" ]] || return 1

    config="$(jq -n --argjson num "$num" --arg node "$node" --arg field "$field_id" \
        --argjson options "$options" \
        '{project_number:$num, project_node_id:$node, status_field_id:$field, options:$options}')"

    mkdir -p "$CACHE_DIR" 2>/dev/null && printf '%s\n' "$config" > "$(cache_file "$owner" "$repo")" 2>/dev/null
    printf '%s' "$config"
}

card_item_id() {
    # Item id of the card whose content is issue <issue> on this board, or nothing.
    local num="$1" owner="$2" issue="$3"
    gh project item-list "$num" --owner "$owner" --format json --limit 500 2>/dev/null \
        | jq -r --argjson n "$issue" \
            'first(.items[] | select(.content.type=="Issue" and .content.number==$n) | .id) // empty' \
            2>/dev/null
}

move_card() {
    local node="$1" item="$2" field="$3" option="$4"
    gh project item-edit --project-id "$node" --id "$item" \
        --field-id "$field" --single-select-option-id "$option" >/dev/null 2>&1
}

announce() {
    jq -n --argjson n "$1" --arg col "$2" '{
        hookSpecificOutput: {
            hookEventName: "PostToolUse",
            additionalContext: ("kanban_lifecycle: moved issue #\($n)'"'"'s card to \"\($col)\".")
        }
    }' 2>/dev/null || true
}

main "$@"
