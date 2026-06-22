#!/usr/bin/env bash
# SessionStart hook — injects cross-project context that Claude Code does NOT
# auto-load (only the current project's memory + the global CLAUDE.md load).
#
# It surfaces, every session:
#   - the rtk-lossy `ls`/`find` caveat (a recurring failure mode), and
#   - where the global scaffolding-lessons backport queue lives;
# and, when the repo is a BlueprintX template repo or a scaffolded project,
#   - the proving-ground project memory + this repo's git-ignored lessons file.
#
# SessionStart adds this script's PLAIN STDOUT to Claude's context (exit 0), so
# the payload is printed with `printf` to stdout — NOT via `print_status` (which
# is for diagnostics on stderr). Kept dependency-free so it runs early and never
# fails the session.
set -uo pipefail

emit_cross_project_context() {
	local claude_dir lessons_store proving_mem cwd
	claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
	lessons_store="$claude_dir/memory/lessons"
	proving_mem="$claude_dir/projects/-home-guilhermegor-dev-perfil-mensal-cvm/memory"
	cwd="${CLAUDE_PROJECT_DIR:-$PWD}"

	# Always: the recurring rtk-lossy failure mode.
	printf '%s\n' "[cross-project-context] rtk proxy can collapse real ls/find output to \"(empty)\". NEVER conclude a path is empty/absent from rtk-proxied ls/find — verify with the Read or Glob tool, or use 'rtk proxy ls'/'rtk proxy find' (raw). A \"(empty)\" from a lossy channel means UNKNOWN, not absent."

	# Always (when present): the cross-project backport queue.
	if [ -f "$lessons_store/README.md" ]; then
		printf '%s\n' "[cross-project-context] Global scaffolding-lessons store (backport queue, NOT auto-loaded): $lessons_store/README.md — read it before planning any BlueprintX template work."
	fi

	# BlueprintX template repo OR a scaffolded project → point at proving-ground memory.
	local is_blueprintx=0
	shopt -s nullglob
	local skeleton_metas=("$cwd"/templates/*/skeleton.meta)
	shopt -u nullglob
	if [ -f "$cwd/docs/blueprintx-lessons.md" ] || [ "${#skeleton_metas[@]}" -gt 0 ] || [ -f "$cwd/bin/blueprintx.sh" ]; then
		is_blueprintx=1
	fi

	if [ "$is_blueprintx" -eq 1 ]; then
		printf '%s\n' "[cross-project-context] This is a BlueprintX repo or a BlueprintX-scaffolded project:"
		[ -f "$cwd/docs/blueprintx-lessons.md" ] && printf '%s\n' "  - This repo's git-ignored lessons mirror: $cwd/docs/blueprintx-lessons.md"
		[ -d "$proving_mem" ] && printf '%s\n' "  - Proving-ground project memory (NOT auto-loaded here): $proving_mem"
		printf '%s\n' "  - Do NOT edit/branch/PR ~/github/blueprintx templates unless the user explicitly asks in the current request; capture generalizable findings in docs/blueprintx-lessons.md + the global store."
	fi
}

main() {
	emit_cross_project_context
	exit 0
}

main "$@"
