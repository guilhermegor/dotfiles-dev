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

# Both generalizable-lessons stores, each as "dir|mirror-basename|kind|target-repo".
# kind=blueprintx also gets the Tier-line presence check (tier is an OPEN field:
# an unknown tier value is a no-op, never a rejection — only a MISSING line flags).
# target-repo is the store's backport target: a lesson that ORIGINATED in that repo
# needs no mirror there (the mirror would be redundant), so the mirror check skips it.
LESSON_STORES=(
	"$CLAUDE_DIR/memory/lessons|blueprintx-lessons|blueprintx|blueprintx"
	"$CLAUDE_DIR/memory/lessons-dotfiles|dotfiles-dev-lessons|dotfiles|dotfiles-dev"
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
	local entry store mirror_base kind target_repo readme file name
	for entry in "${LESSON_STORES[@]}"; do
		IFS='|' read -r store mirror_base kind target_repo <<<"$entry"
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
			# an unrecognized value — a new tier must be a no-op for this tool. The
			# leading bullet is optional: the store uses both "- **Tier:**" and a bare
			# "**Tier:**", and demanding the bullet was a false positive.
			if [ "$kind" = "blueprintx" ] && ! grep -qE '^[[:space:]]*([-*][[:space:]]+)?\*\*Tier:\*\*' "$file"; then
				add_gap "[lessons] '$name' has no **Tier:** line"
			fi

			# Status is what tells emit_completeness a lesson landed (delivered/advisory/
			# superseded) versus is still owed (queued/tracked) — the same missing-field
			# blindness the Tier check above catches, so it gets the same treatment: flag
			# only a MISSING line, never an unrecognized value.
			if ! grep -qE '^[[:space:]]*([-*][[:space:]]+)?\*\*Status:\*\*' "$file"; then
				add_gap "[lessons] '$name' has no **Status:** line"
			fi
		done
	done
}

check_mirrors() {
	# Triple-check part 2: a lesson whose Origin names THIS repo must also live in
	# this repo's git-ignored mirror. We can only verify the current repo's mirror
	# (the mirror is per-origin-repo); other repos' mirrors are out of reach here.
	local cwd="$1" repo entry store mirror_base kind target_repo mirror file name
	repo="$(basename "$cwd")"
	for entry in "${LESSON_STORES[@]}"; do
		IFS='|' read -r store mirror_base kind target_repo <<<"$entry"
		[ -d "$store" ] || continue
		# When this repo IS the store's backport target, the same-repo mirror is
		# redundant by convention and deliberately absent — never flag it.
		[ "$repo" = "$target_repo" ] && continue
		mirror="$cwd/docs/$mirror_base.md"
		for file in "$store"/*.md; do
			[ -e "$file" ] || continue
			name="$(basename "$file")"
			[ "$name" = "README.md" ] && continue
			# Only lessons that originated in THIS repo are expected in its mirror
			# (bullet optional: the stores use both "- **Origin:**" and bare form).
			grep -qiE "^[[:space:]]*([-*][[:space:]]+)?\*\*Origin:\*\*.*\b${repo}\b" "$file" || continue
			if [ ! -f "$mirror" ]; then
				add_gap "[lessons] '$name' originated here but docs/$mirror_base.md mirror is missing"
			elif ! grep -qF "$name" "$mirror"; then
				add_gap "[lessons] '$name' originated here but is not in docs/$mirror_base.md"
			fi
		done
	done
}

# owner/repo from the origin remote — parsed from the URL, NO network call, so it is
# safe in the SessionEnd path. Empty when there is no GitHub origin.
repo_slug() {
	local cwd="$1" url
	url="$(git -C "$cwd" remote get-url origin 2>/dev/null)" || return 1
	[ -n "$url" ] || return 1
	url="${url%.git}"
	case "$url" in
	*github.com[:/]*) printf '%s\n' "${url#*github.com}" | sed 's#^[:/]##' ;;
	*) return 1 ;;
	esac
}

# The lesson store whose backport target is this repo (dotfiles-dev → lessons-dotfiles).
store_dir_for_repo() {
	local repo="$1" entry store mirror_base kind target_repo
	for entry in "${LESSON_STORES[@]}"; do
		IFS='|' read -r store mirror_base kind target_repo <<<"$entry"
		[ "$target_repo" = "$repo" ] && {
			printf '%s\n' "$store"
			return 0
		}
	done
	return 1
}

# The both-directions completeness table (dotfiles-dev#81). A one-directional
# lessons→issues audit proves only that no lesson lacks an index entry; it never sees
# the B-side orphan — an OPEN ISSUE with no lesson, where the rationale is already lost
# once the PR closes it. So print BOTH rows, never a single number.
#
# Direction split by cost, matching this script's contract:
#   Row 1 (lessons → issues) is store-internal text — always computed, no network.
#   Row 2 (issues → lessons) needs the live issue list, so it runs ONLY in report mode
#   (under /wrap-up, interactive) and only when gh is present; at SessionEnd it is
#   skipped so a network hang can never stall the exit. Fails OPEN.
#
# Orphans/unaccounted are JUDGMENT candidates, not add_gap()s: not every issue is
# lesson-born and not every lesson maps to an issue, so a hard gap would cry wolf (and
# fire at SessionEnd). They are surfaced for /wrap-up to resolve consciously.
emit_completeness() {
	local cwd="$1" mode="$2" repo store
	repo="$(basename "$cwd")"
	store="$(store_dir_for_repo "$repo")" || return 0
	[ -d "$store" ] || return 0

	printf '%s\n' "--- completeness (both directions, dotfiles-dev#81) ---"

	# Row 1 — lessons → issues (store text; no network).
	#
	# A citation says which issue exists; only a Status: VALUE says whether the work LANDED —
	# so a lesson with no PR citation is debt ONLY when its Status is queued/tracked/missing.
	# delivered/advisory/superseded mean the work shipped (or was never scaffold-shaped) with
	# no PR to cite (dotfiles-dev#138: pre-PR-flow direct commits, or advisory-only guidance).
	# Counting those as debt reports the store's age, not its debt (measured blueprintx
	# 2026-08-16: 170/243 "unaccounted", 156 delivered; dotfiles-dev 2026-08-23: 19/268, 15
	# delivered + 4 advisory — zero of the 19 were actually owed).
	local total=0 no_ref=0 delivered=0 advisory=0 superseded=0 file name
	local -a unaccounted=()
	for file in "$store"/*.md; do
		[ -e "$file" ] || continue
		name="$(basename "$file")"
		[ "$name" = "README.md" ] && continue
		total=$((total + 1))

		# A direct citation accounts for the lesson regardless of its Status value.
		grep -qE "${repo}#[0-9]+" "$file" && continue
		no_ref=$((no_ref + 1))

		if grep -qE '^[[:space:]]*([-*][[:space:]]+)?\*\*Status:\*\* *delivered' "$file"; then
			delivered=$((delivered + 1))
		elif grep -qE '^[[:space:]]*([-*][[:space:]]+)?\*\*Status:\*\* *advisory' "$file"; then
			advisory=$((advisory + 1))
		elif grep -qE '^[[:space:]]*([-*][[:space:]]+)?\*\*Status:\*\* *superseded' "$file"; then
			superseded=$((superseded + 1))
		else
			# queued, tracked, an unrecognized status, or no Status: line at all — every
			# one of these is genuinely still owed (a missing line defaults to owed, never
			# to "probably delivered" — check_lessons() flags the missing line separately).
			unaccounted+=("$name")
		fi
	done
	printf '  lessons → issues : %d in store, %d without a PR ref — %d delivered, %d advisory, %d superseded, %d genuinely unaccounted\n' \
		"$total" "$no_ref" "$delivered" "$advisory" "$superseded" "${#unaccounted[@]}"

	# Row 2 — issues → lessons (live issue list; report mode + gh only, fails open).
	local slug="" issues="" n sourced=0 icount=0
	local -a orphans=()
	if [ "$mode" = "report" ] && command -v gh >/dev/null 2>&1; then
		slug="$(repo_slug "$cwd" 2>/dev/null || true)"
	fi
	# `gh issue list` defaults to 30 rows. Without an explicit --limit the audit silently
	# reports on a SAMPLE and calls it the population: measured blueprintx 2026-08-16, the
	# repo had 46 open issues, so 16 were never examined and the orphan count was wrong by
	# construction. A checker that cannot see the whole set is the exact blindness this
	# script exists to catch, so it also says so when the page fills.
	local -i issue_limit=500
	if [ -n "$slug" ]; then
		issues="$(gh issue list --repo "$slug" --state open --limit "$issue_limit" --json number \
			--jq '.[].number' 2>/dev/null || true)"
		while IFS= read -r n; do
			[ -n "$n" ] || continue
			icount=$((icount + 1))
			if grep -qE "${repo}#${n}([^0-9]|\$)" "$store"/*.md 2>/dev/null; then
				sourced=$((sourced + 1))
			else
				orphans+=("#$n")
			fi
		done <<<"$issues"
		printf '  issues  → lessons: %d open, %d sourced by a lesson, %d orphan\n' \
			"$icount" "$sourced" "${#orphans[@]}"
		if [ "$icount" -ge "$issue_limit" ]; then
			printf '  ! issue list hit the --limit (%d) — the count above is a floor, not the total\n' \
				"$issue_limit"
		fi
	else
		printf '  issues  → lessons: skipped (needs gh + report mode; not run at SessionEnd)\n'
	fi

	if [ "${#orphans[@]}" -gt 0 ]; then
		printf '  ! open issues with no lesson — write one or mark not-lesson-worthy: %s\n' "${orphans[*]}"
	fi
	if [ "${#unaccounted[@]}" -gt 0 ]; then
		printf '  ! lessons genuinely unaccounted (no PR ref, no delivered/advisory/superseded Status): %s\n' \
			"${unaccounted[*]}"
	fi
}

emit_report() {
	local cwd="$1" mode="${2:-report}" repo date_str
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

	# Completeness in BOTH directions (dotfiles-dev#81) — printed between the decided
	# gaps and the judgment checklist because its orphans are judgment, not gaps.
	emit_completeness "$cwd" "$mode"

	# Judgment-only checks: the script cannot decide these — it hands them to a
	# human or to `/wrap-up`. The superseded-rule grep is the highest-value one and
	# the one nobody remembers (a real audit found a revoked release rule still
	# living in a tracked ledger).
	printf '%s\n' "--- verify manually or via /wrap-up (need judgment) ---"
	printf '%s\n' "  - [ ] Superseded rules: did this session CHANGE a standing rule? grep tracked docs/README/ledgers for the OLD rule — a tracked doc outranks memory next session."
	printf '%s\n' "  - [ ] Issues/PRs: every issue created this session is on the board and its card is in the right column; open PRs are accounted for."
	printf '%s\n' "  - [ ] Completeness BOTH ways (above): resolve each 'orphan' open issue (write its lesson or list it under the store README's 'Issues not born of a lesson') and each 'genuinely unaccounted' lesson (file the issue or record a delivered/advisory/superseded Status:) — a one-directional check hides the B-side orphan."
	printf '%s\n' "  - [ ] 'genuinely unaccounted' above is the debt that is real: no PR ref and no delivered/advisory/superseded Status. Zero is expected only right after a triage."
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
	emit_report "$cwd" "handoff" >"$handoff" 2>/dev/null || true
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
