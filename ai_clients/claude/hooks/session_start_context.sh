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

	# Always (when present): the per-project corrections log. Surfaced here (not in CLAUDE.md)
	# so the always-on prompt stays lean; read it and apply entries scoped to this cwd or global.
	if [ -f "$claude_dir/tasks/lessons.md" ]; then
		printf '%s\n' "[cross-project-context] Corrections log (NOT auto-loaded): $claude_dir/tasks/lessons.md — read it and immediately apply any entry whose Scope matches this working directory or is 'global'. Append a new entry whenever the user corrects a mistake (see the s:capturing-lessons skill)."
	fi

	# When present: the capture-audit handoff written by session_capture_audit.sh at
	# the LAST session's end (it can only report forward — the session was over). Surface
	# the unresolved gaps as the first thing this session sees, then clear the file so it
	# fires once. The fixer is /wrap-up, run live.
	local slug handoff
	slug="$(printf '%s' "$cwd" | tr '/' '-')"
	handoff="$claude_dir/session-audit/$slug.md"
	if [ -f "$handoff" ]; then
		printf '%s\n' "[session-capture-audit] Unresolved capture gaps from your last session in this repo (run /wrap-up to resolve):"
		cat "$handoff"
		rm -f "$handoff" 2>/dev/null || true
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

# owner/repo parsed from the origin remote URL, no network call. Empty when there is no
# GitHub origin (a non-GitHub repo skips the whole GitHub half, silently).
fanout_repo_slug() {
	local cwd="$1" url
	url="$(git -C "$cwd" remote get-url origin 2>/dev/null)" || return 1
	[ -n "$url" ] || return 1
	url="${url%.git}"
	case "$url" in
	*github.com[:/]*) printf '%s\n' "${url#*github.com}" | sed 's#^[:/]##' ;;
	*) return 1 ;;
	esac
}

# "Awaiting review" = no review lands on the CURRENT head commit (a review of a superseded
# commit is not a review — blueprintx#220). $json is `gh pr list --state all --json
# number,url,state,headRefName,headRefOid,reviews,createdAt` — the SAME payload the worktree
# loop below reuses for the "no PR" branch check, so this is the repo's only `gh` call.
fanout_pr_summary() {
	local json="$1"
	printf '%s' "$json" | jq -r '
		[ .[] | select(.state=="OPEN") ] as $open
		| ($open | length) as $nopen
		| [ $open[] | . as $pr
		    | select((($pr.reviews // []) | any(.commit.oid == $pr.headRefOid)) | not) ] as $awaiting
		| ($awaiting | length) as $nawait
		| if $nawait == 0 then empty else
		    ($awaiting | sort_by(.createdAt) | .[0]) as $oldest
		    | ((now - ($oldest.createdAt | fromdateiso8601)) / 3600 | floor) as $hrs
		    | "[fan-out] \($nopen) PR(s) open · \($nawait) awaiting review (oldest #\($oldest.number), \($hrs)h)"
		  end
	' 2>/dev/null
}

# `git worktree list` entries for THIS repo (parallel-agent worktrees included) — unpushed
# commits, uncommitted files, and (when the GitHub half answered) a branch that was pushed but
# never got a PR. One walk, no per-branch `gh` calls.
fanout_worktrees() {
	local cwd="$1" github_ok="$2" json="$3"
	local pr_branches="" default_branch path="" branch="" name uncommitted ahead has_upstream

	[ "$github_ok" = "1" ] && pr_branches="$(printf '%s' "$json" | jq -r '.[].headRefName' 2>/dev/null)"
	default_branch="$(git -C "$cwd" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
	default_branch="${default_branch#origin/}"

	while IFS= read -r line; do
		case "$line" in
		"worktree "*)
			path="${line#worktree }"
			branch=""
			;;
		"branch "*)
			branch="${line#branch refs/heads/}"
			;;
		"")
			if [ -n "$path" ] && [ -d "$path" ]; then
				name="$(basename "$path")"
				uncommitted="$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d '[:space:]')"
				[ -n "$uncommitted" ] || uncommitted=0
				ahead=0
				has_upstream=0
				if git -C "$path" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
					has_upstream=1
					ahead="$(git -C "$path" rev-list --count '@{upstream}..HEAD' 2>/dev/null)"
					[ -n "$ahead" ] || ahead=0
				fi

				[ "$ahead" -gt 0 ] && printf '[fan-out] worktree %s: %s commit(s) not pushed\n' "$name" "$ahead"
				[ "$uncommitted" -gt 0 ] && printf '[fan-out] worktree %s: %s uncommitted file(s)\n' "$name" "$uncommitted"

				if [ "$github_ok" = "1" ] && [ "$has_upstream" = "1" ] && [ -n "$branch" ] \
					&& [ "$branch" != "$default_branch" ] \
					&& ! printf '%s\n' "$pr_branches" | grep -qxF "$branch"; then
					printf '[fan-out] branch %s pushed with NO PR\n' "$branch"
				fi
			fi
			path=""
			branch=""
			;;
		esac
	done < <(git -C "$cwd" worktree list --porcelain 2>/dev/null; printf '\n')
}

# Outstanding fan-out state (dotfiles-dev#160): PRs waiting on a review of the current head
# commit, worktrees with unpushed commits or uncommitted files, and branches pushed with no PR.
# Silent when clean — this is a janitor, never a gate (bin/CLAUDE.md): report and exit 0, never
# block, never fail the session. A `gh` failure prints an explicit "could not reach GitHub" line
# so it is never confused with the true "nothing open" silence.
emit_fanout_status() {
	local cwd
	cwd="${CLAUDE_PROJECT_DIR:-$PWD}"
	git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

	local slug="" json="" github_ok=0
	slug="$(fanout_repo_slug "$cwd")"
	if [ -n "$slug" ]; then
		if ! command -v gh >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
			printf '%s\n' "[fan-out] gh/jq not available — could not reach GitHub for PR/review status"
		else
			if command -v timeout >/dev/null 2>&1; then
				json="$(timeout 8 gh pr list --repo "$slug" --state all \
					--json number,url,state,headRefName,headRefOid,reviews,createdAt 2>/dev/null)"
			else
				json="$(gh pr list --repo "$slug" --state all \
					--json number,url,state,headRefName,headRefOid,reviews,createdAt 2>/dev/null)"
			fi
			if printf '%s' "$json" | jq -e 'type=="array"' >/dev/null 2>&1; then
				github_ok=1
				fanout_pr_summary "$json"
			else
				printf '%s\n' "[fan-out] could not reach GitHub — PR/review status unknown"
			fi
		fi
	fi

	fanout_worktrees "$cwd" "$github_ok" "$json"
}

main() {
	emit_cross_project_context
	emit_fanout_status
	exit 0
}

main "$@"
