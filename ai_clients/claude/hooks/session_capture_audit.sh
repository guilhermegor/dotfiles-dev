#!/bin/bash
# Session capture audit — the deterministic "did I capture everything?" check.
#
# Two consumers, one script:
#   1. The `/wrap-up` skill runs it WHILE the session is live and FIXES what it
#      finds (writes the missing lesson, files the missing issue, updates the
#      checkpoint). That is where the value is — default (no-arg) mode prints the
#      findings to stdout for the skill to act on.
#   2. A `SessionEnd` hook runs it with `--handoff` on `/exit` / `/clear` / close.
#      SessionEnd is TOO LATE TO FIX ANYTHING — the session is over: it cannot ask,
#      cannot write a lesson, cannot open an issue. So `--handoff` only REPORTS
#      FORWARD: if it finds gaps it writes them to a handoff file that the existing
#      `session_start_context.sh` hook surfaces (and clears) next session. It never
#      blocks the exit — it can't, and shouldn't.
#
# Every check here is DETERMINISTIC (git / lesson-index integrity / mirror
# presence) — no LLM judgment. The judgment-only checks (superseded rules,
# checkpoint freshness, board columns) are emitted as a checklist for a human or
# for `/wrap-up` to act on; the script never decides them.
#
# I/O contract (matching session_start_context.sh / lesson_capture_checkpoint.sh):
# the findings ARE this script's stdout payload, so they are printed with `printf`
# to stdout — NOT via `print_status` (status/diagnostics go to stderr). Kept
# dependency-free (no lib/common.sh) so it runs early and never fails a session.
# Fails OPEN everywhere: any uncertainty is skipped, never a hard error.
set -uo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Both generalizable-lessons stores, each as "dir|mirror-basename|kind".
# kind=blueprintx also gets the Tier-line presence check (tier is an OPEN field:
# an unknown tier value is a no-op, never a rejection — only a MISSING line flags).
LESSON_STORES=(
	"$CLAUDE_DIR/memory/lessons|blueprintx-lessons|blueprintx"
	"$CLAUDE_DIR/memory/lessons-dotfiles|dotfiles-dev-lessons|dotfiles"
)

resolve_cwd() {
	# SessionEnd feeds JSON on stdin with a `cwd`; prefer it, then env, then PWD.
	local payload="$1" cwd=""
	if [ -n "$payload" ] && command -v jq >/dev/null 2>&1; then
		cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"
	fi
	[ -n "$cwd" ] && { printf '%s\n' "$cwd"; return; }
	printf '%s\n' "${CLAUDE_PROJECT_DIR:-$PWD}"
}

default_branch() {
	local cwd="$1" db
	db="$(git -C "$cwd" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
	[ -n "$db" ] && { printf '%s\n' "$db"; return; }
	for db in main master; do
		git -C "$cwd" show-ref --verify --quiet "refs/heads/$db" && { printf '%s\n' "$db"; return; }
	done
	printf '%s\n' ""
}

# Appends a gap line to the global GAPS array (mechanical, blocks a "clean" audit).
GAPS=()
add_gap() { GAPS+=("$1"); }

check_git() {
	# Audit the RESOLVED project dir, not the process's working dir — at SessionEnd
	# the hook's own cwd is not guaranteed to be the project.
	local cwd="$1"
	git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

	[ -n "$(git -C "$cwd" status --porcelain 2>/dev/null)" ] &&
		add_gap "[git] uncommitted changes in the working tree"

	local branch default
	branch="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)"
	default="$(default_branch "$cwd")"
	if [ -n "$default" ] && [ -n "$branch" ] && [ "$branch" != "$default" ]; then
		add_gap "[git] on branch '$branch' (not '$default') — work may be stranded if unmerged"
	fi

	# Unpushed commits — only when an upstream is configured for this branch.
	local ahead
	if git -C "$cwd" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
		ahead="$(git -C "$cwd" rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo 0)"
		[ "${ahead:-0}" -gt 0 ] && add_gap "[git] $ahead commit(s) not pushed to upstream"
	fi
}

check_lessons() {
	local entry store mirror_base kind readme file name
	for entry in "${LESSON_STORES[@]}"; do
		IFS='|' read -r store mirror_base kind <<<"$entry"
		readme="$store/README.md"
		[ -d "$store" ] || continue
		[ -f "$readme" ] || { add_gap "[lessons] $store has lesson files but no README index"; continue; }

		for file in "$store"/*.md; do
			[ -e "$file" ] || continue          # glob matched nothing
			name="$(basename "$file")"
			[ "$name" = "README.md" ] && continue

			# Triple-check part 1: file must be referenced in its store's README index.
			grep -qF "$name" "$readme" ||
				add_gap "[lessons] '$name' is not in the $(basename "$store") README index (a lost lesson)"

			# BlueprintX tier is an OPEN field: flag only a MISSING Tier line, never
			# an unrecognized value — a new tier must be a no-op for this tool.
			if [ "$kind" = "blueprintx" ] && ! grep -qE '^\s*[-*]\s*\*\*Tier:\*\*' "$file"; then
				add_gap "[lessons] '$name' has no **Tier:** line"
			fi
		done
	done
}

check_mirrors() {
	# Triple-check part 2: a lesson whose Origin names THIS repo must also live in
	# this repo's git-ignored mirror. We can only verify the current repo's mirror
	# (the mirror is per-origin-repo); other repos' mirrors are out of reach here.
	local cwd="$1" repo entry store mirror_base kind mirror file name
	repo="$(basename "$cwd")"
	for entry in "${LESSON_STORES[@]}"; do
		IFS='|' read -r store mirror_base kind <<<"$entry"
		[ -d "$store" ] || continue
		mirror="$cwd/docs/$mirror_base.md"
		for file in "$store"/*.md; do
			[ -e "$file" ] || continue
			name="$(basename "$file")"
			[ "$name" = "README.md" ] && continue
			# Only lessons that originated in THIS repo are expected in its mirror.
			grep -qiE "^\s*[-*]\s*\*\*Origin:\*\*.*\b${repo}\b" "$file" || continue
			if [ ! -f "$mirror" ]; then
				add_gap "[lessons] '$name' originated here but docs/$mirror_base.md mirror is missing"
			elif ! grep -qF "$name" "$mirror"; then
				add_gap "[lessons] '$name' originated here but is not in docs/$mirror_base.md"
			fi
		done
	done
}

emit_report() {
	local cwd="$1" repo date_str
	repo="$(basename "$cwd")"
	date_str="$(date +%Y-%m-%d)"

	printf '%s\n' "=== Session capture audit — $repo ($date_str) ==="
	if [ "${#GAPS[@]}" -eq 0 ]; then
		printf '%s\n' "Mechanical checks: clean (git, lesson index, mirrors)."
	else
		printf '%s\n' "Mechanical gaps found — resolve before ending:"
		local gap
		for gap in "${GAPS[@]}"; do
			printf '  - %s\n' "$gap"
		done
	fi

	# Judgment-only checks: the script cannot decide these — it hands them to a
	# human or to `/wrap-up`. The superseded-rule grep is the highest-value one and
	# the one nobody remembers (a real audit found a revoked release rule still
	# living in a tracked ledger).
	printf '%s\n' "--- verify manually or via /wrap-up (need judgment) ---"
	printf '%s\n' "  - [ ] Superseded rules: did this session CHANGE a standing rule? grep tracked docs/README/ledgers for the OLD rule — a tracked doc outranks memory next session."
	printf '%s\n' "  - [ ] Issues/PRs: every issue created this session is on the board and its card is in the right column; open PRs are accounted for."
	printf '%s\n' "  - [ ] Checkpoint: project memory has a resume point covering this session's work."
	printf '%s\n' "  - [ ] Lessons: every generalizable finding is captured in the right store (BlueprintX vs dotfiles-dev) — routed by where the fix lands."
}

write_handoff() {
	# --handoff (SessionEnd): report FORWARD. Write only when there are mechanical
	# gaps to recover; otherwise clear any stale handoff. Never blocks the exit.
	local cwd="$1" audit_dir slug handoff
	audit_dir="$CLAUDE_DIR/session-audit"
	slug="$(printf '%s' "$cwd" | tr '/' '-')"
	handoff="$audit_dir/$slug.md"

	if [ "${#GAPS[@]}" -eq 0 ]; then
		rm -f "$handoff" 2>/dev/null || true
		return 0
	fi
	mkdir -p "$audit_dir" 2>/dev/null || return 0
	emit_report "$cwd" >"$handoff" 2>/dev/null || true
}

main() {
	local mode="report" payload=""
	[ "${1:-}" = "--handoff" ] && mode="handoff"

	# Drain stdin (SessionEnd sends a JSON payload); harmless when there is none.
	if [ ! -t 0 ]; then payload="$(cat)"; fi

	local cwd
	cwd="$(resolve_cwd "$payload")"

	check_git "$cwd"
	check_lessons
	check_mirrors "$cwd"

	if [ "$mode" = "handoff" ]; then
		write_handoff "$cwd"
	else
		emit_report "$cwd"
	fi
	exit 0
}

main "$@"
