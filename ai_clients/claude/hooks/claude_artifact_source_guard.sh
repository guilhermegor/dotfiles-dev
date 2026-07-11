#!/bin/bash
# PreToolUse (Write|Edit matcher) hook: block authoring a durable Claude artifact directly into the
# live ~/.claude/ tree, steering the edit to the version-controlled source under dotfiles-dev.
#
# Why this exists: ~/.claude/ is machine-local and non-symlinked — a command / skill / agent / rule /
# hook / global CLAUDE.md written there is lost on the next OS install and never reproduced by the
# installer. The "author in dotfiles-dev" rule is only advisory in CLAUDE.md; this hook makes it
# deterministic by refusing the Write/Edit and naming the correct source path.
#
# Hook I/O contract (same as commit_title_length_guard.sh): silent on stdout, speaks only through
# exit code + stderr — no lib/common.sh / print_status. It fails OPEN: no jq, no file_path, or a path
# that is not one of the guarded durable-artifact locations exits 0 and lets the write proceed.
#
# Deliberately NOT guarded (these are meant to be written live, per the rule's exemptions):
#   * ~/.claude/projects/**  (project memory)   * ~/.claude/tasks/**  (lessons.md)
#   * ~/.claude/plans/**                          * settings*.json     * a project's own .claude/
# Only Write/Edit *tool* calls are caught; the correct deploy step (`cp` via Bash) is not, so
# "edit source, then cp into place" keeps working.

set -u

command -v jq >/dev/null 2>&1 || exit 0

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

main() {
    local payload tool path rel

    payload="$(cat)"
    tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"
    case "$tool" in
        Write | Edit) ;;
        *) exit 0 ;;
    esac

    path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
    [[ -n "$path" ]] || exit 0

    # Only paths inside the live global config dir are candidates.
    case "$path" in
        "$CLAUDE_DIR"/*) rel="${path#"$CLAUDE_DIR"/}" ;;
        *) exit 0 ;;
    esac

    # ponytail: prefix match on the durable-artifact subdirs + the global CLAUDE.md. Anything else
    # under ~/.claude/ (projects/, tasks/, plans/, settings*.json) is intentionally allowed.
    local src
    case "$rel" in
        commands/* | skills/* | agents/* | rules/* | hooks/*) src="ai_clients/claude/$rel" ;;
        CLAUDE.md) src="ai_clients/claude/config/CLAUDE.md" ;;   # global CLAUDE.md source lives under config/
        *) exit 0 ;;
    esac

    {
        echo "BLOCKED: refusing to author a durable Claude artifact directly in ${CLAUDE_DIR}/."
        echo
        echo "  Target: ${path}"
        echo
        echo "${CLAUDE_DIR}/ is machine-local and non-symlinked — this file is lost on the next OS"
        echo "install and never recreated by the installer. Edit the version-controlled source instead:"
        echo
        echo "  ~/github/dotfiles-dev/${src}"
        echo
        echo "then run 'make ai_clients' (or cp it into place) to deploy. See the \"Author Claude"
        echo "artifacts in dotfiles-dev\" rule in CLAUDE.md."
    } >&2
    exit 2
}

main "$@"
