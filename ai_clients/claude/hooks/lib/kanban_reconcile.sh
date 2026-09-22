#!/bin/bash
# Shared kanban board helpers + reconcile (dotfiles-dev#448).
#
# owner_repo/cache_file/discover_board/board_config/move_card used to live only in
# kanban_lifecycle.sh. Moved here so the event hook and the reconcile below share ONE
# implementation instead of two copies that drift (same seam as free_surface.sh /
# review_thread_gate.sh: a shared gate/helper file sourced by more than one hook).
#
# Why a reconcile, not a better event hook: kanban_lifecycle.sh's PostToolUse hook only fires
# when the harness observes the EVENT (`gh pr create`) in ITS OWN Bash tool call, in the right
# cwd. Measured 2026-09-21: 8 of 8 issues with an open PR sat in Backlog because the PR was
# opened by a dispatched agent (cwd reset mid-session, dotfiles-dev#229), during a `gh` 403
# window (#445), or by a rescue committing on someone else's branch — all the same defect: an
# event-only transition has no recovery when the event is missed. Same seam as
# hooks/lib/roadmap_unblock.sh (#369): the correct Status is derivable from the forge at any
# time, so re-derive it every round instead of trusting only the event.
#
# Contract:
#   reconcile_kanban OWNER REPO
#     For every OPEN pull request in OWNER/REPO, resolves its linked issue(s) via
#     `closingIssuesReferences` (GraphQL — NOT the branch-name heuristic; free_surface.sh's own
#     header explains why that heuristic is disqualified) and moves each linked OPEN issue's
#     card to "In review" when its current Status is BEHIND "In review" in the board's own
#     column order. Never moves a card backwards: an issue already In review, Done, or any
#     column at/after In review is left untouched. Column order is read fresh from
#     `gh project field-list` every call, never hardcoded, so a renamed/reordered board is
#     still handled correctly.
#
#     Sets two globals (never partial):
#       RECONCILE_KANBAN_STATUS = ok | unknown
#       RECONCILE_KANBAN_REPORT = newline-separated "moved issue #N ..." lines, or empty when
#                                 nothing needed to move. An empty report on STATUS=ok is a
#                                 real, ordinary answer ("no kanban cards changed"), never
#                                 treated as a failure.
#     Returns 1 and sets RECONCILE_KANBAN_STATUS=unknown (REPORT holding one explanatory line)
#     only when the board itself, the open-PR list, or the Status column order can't be read.
#     A single PR's own closingIssuesReferences read failure does not abort the round — it is
#     reported as an "UNKNOWN PR #N" line and the next PR is still processed (same
#     fail-closed-per-item shape as roadmap_unblock.sh).
set -u

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	echo "kanban_reconcile.sh is meant to be sourced, not executed." >&2
	exit 1
fi

: "${CACHE_DIR:=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/kanban-boards}"

owner_repo() {
	gh repo view --json owner,name -q '.owner.login + " " + .name' 2>/dev/null
}

cache_file() {
	printf '%s/%s-%s.json' "$CACHE_DIR" "$1" "$2"
}

discover_board() {
	# Find the `<repo> kanban` project, resolve its Status field + option ids, cache the result, and
	# echo it as one JSON object. Returns: 0 + config on success, 1 when no such board exists, and
	# 2 when MORE THAN ONE board carries that title (refuse to guess — the caller surfaces this).
	local owner="$1" repo="$2" projects matches count num node fields field_id options config
	projects="$(gh project list --owner "$owner" --format json 2>/dev/null)" || return 1

	matches="$(printf '%s' "$projects" \
		| jq -r --arg t "$repo kanban" '.projects[] | select(.title==$t) | "\(.number) \(.id)"')"
	count="$(printf '%s\n' "$matches" | grep -c .)"
	(( count == 0 )) && return 1
	if (( count > 1 )); then
		# A silent head -n1 pick here would move a random board's card. Refuse instead — issue.md
		# now prevents duplicate-titled boards, so this is the safety net for one already out there.
		return 2
	fi

	read -r num node <<< "$matches"
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

	local rc
	line="$(discover_board "$owner" "$repo")"; rc=$?   # writes the cache as a side effect
	(( rc == 2 )) && { printf 'AMBIGUOUS\n'; return 0; }   # >1 same-named board — let the caller warn
	(( rc == 0 )) || return 1
	opt="$(printf '%s' "$line" | jq -r --arg t "$target" '.options[$t] // empty' 2>/dev/null)"
	[[ -n "$opt" ]] || return 1
	printf '%s %s %s %s\n' \
		"$(printf '%s' "$line" | jq -r '.project_number')" \
		"$(printf '%s' "$line" | jq -r '.project_node_id')" \
		"$(printf '%s' "$line" | jq -r '.status_field_id')" \
		"$opt"
}

move_card() {
	local node="$1" item="$2" field="$3" option="$4"
	gh project item-edit --project-id "$node" --id "$item" \
		--field-id "$field" --single-select-option-id "$option" >/dev/null 2>&1
}

# _kr_status_names OWNER PROJECT
# Ordered list of Status column names, one per line, straight from the ARRAY `gh project
# field-list` returns. Arrays preserve order; this deliberately does not reconstruct order from
# an object (board_config's cached `.options` map), whose key order this file does not want to
# depend on.
_kr_status_names() {
	local owner="$1" project="$2"
	gh project field-list "$project" --owner "$owner" --format json 2>/dev/null \
		| jq -r '.fields[] | select(.name=="Status") | .options[].name' 2>/dev/null
}

# _kr_closing_issues OWNER REPO NUMBER
# Prints the numbers of every OPEN issue this PR's closingIssuesReferences names, one per line,
# or nothing if it names none. Returns 1 on any GraphQL error — the caller's per-PR fail-closed
# signal, so one bad PR read never aborts the whole round.
_kr_closing_issues() {
	local owner="$1" repo="$2" number="$3" query result
	query="{repository(owner:\"$owner\",name:\"$repo\"){pullRequest(number:$number){closingIssuesReferences(first:20){nodes{number state}}}}}"
	result="$(gh api graphql -f query="$query" 2>/dev/null)" || return 1
	printf '%s' "$result" | jq -e '.errors' >/dev/null 2>&1 && return 1
	printf '%s' "$result" \
		| jq -r '.data.repository.pullRequest.closingIssuesReferences.nodes[] | select(.state=="OPEN") | .number' \
		2>/dev/null
}

reconcile_kanban() {
	local owner="$1" repo="$2"
	RECONCILE_KANBAN_STATUS="unknown"
	RECONCILE_KANBAN_REPORT=""

	local project_number project_node status_field target_option
	read -r project_number project_node status_field target_option \
		< <(board_config "$owner" "$repo" "In review") || {
		RECONCILE_KANBAN_REPORT="UNKNOWN: could not resolve board for $owner/$repo"
		return 1
	}
	if [[ "$project_number" == "AMBIGUOUS" ]]; then
		RECONCILE_KANBAN_REPORT="UNKNOWN: more than one \"$repo kanban\" board — refusing to guess"
		return 1
	fi
	if [[ -z "$project_number" || -z "$target_option" ]]; then
		RECONCILE_KANBAN_REPORT="UNKNOWN: no \"$repo kanban\" board or no In review column"
		return 1
	fi

	local order_list target_rank
	order_list="$(_kr_status_names "$owner" "$project_number")"
	if [[ -z "$order_list" ]]; then
		RECONCILE_KANBAN_REPORT="UNKNOWN: could not read Status column order for $owner/$repo"
		return 1
	fi
	target_rank="$(printf '%s\n' "$order_list" | grep -nxF "In review" | head -n1 | cut -d: -f1)"
	if [[ -z "$target_rank" ]]; then
		RECONCILE_KANBAN_REPORT="UNKNOWN: no In review column found for $owner/$repo"
		return 1
	fi

	local pr_numbers
	pr_numbers="$(gh pr list --repo "$owner/$repo" --state open --json number --limit 200 \
		--jq '.[].number' 2>/dev/null)" || {
		RECONCILE_KANBAN_REPORT="UNKNOWN: could not list open PRs for $owner/$repo"
		return 1
	}

	local items_json
	items_json="$(gh project item-list "$project_number" --owner "$owner" --format json --limit 500 2>/dev/null)" || {
		RECONCILE_KANBAN_REPORT="UNKNOWN: could not read project items for $owner/$repo"
		return 1
	}
	# Shape-check before use: `.items[]?` exits 0 on `{}`/`{"items": null}` too, which would
	# otherwise report ok having silently processed nothing (same trap PR #376 caught in
	# roadmap_unblock.sh).
	printf '%s' "$items_json" | jq -e 'type=="object" and (.items | type == "array")' \
		>/dev/null 2>&1 || {
		RECONCILE_KANBAN_REPORT="UNKNOWN: could not parse project items for $owner/$repo"
		return 1
	}

	local report="" n processed=""
	while IFS= read -r n; do
		[[ -n "$n" ]] || continue
		local issues
		if ! issues="$(_kr_closing_issues "$owner" "$repo" "$n")"; then
			report="$(printf '%s\nUNKNOWN PR #%s: could not resolve closing issues' "$report" "$n")"
			continue
		fi
		local issue
		while IFS= read -r issue; do
			[[ -n "$issue" ]] || continue
			# Several open PRs can close the same issue — process it once.
			printf '%s\n' "$processed" | grep -qxF "$issue" && continue
			processed="$(printf '%s\n%s' "$processed" "$issue")"

			local item_id current_status rank
			item_id="$(printf '%s' "$items_json" | jq -r --argjson num "$issue" \
				'first(.items[] | select(.content.type=="Issue" and .content.number==$num)) | .id // empty' 2>/dev/null)"
			[[ -n "$item_id" ]] || continue   # issue not on this board -> nothing to move

			current_status="$(printf '%s' "$items_json" | jq -r --argjson num "$issue" \
				'first(.items[] | select(.content.type=="Issue" and .content.number==$num)) | .status // empty' 2>/dev/null)"

			[[ "$current_status" == "In review" ]] && continue

			rank="$(printf '%s\n' "$order_list" | grep -nxF "$current_status" | head -n1 | cut -d: -f1)"
			if [[ -n "$rank" ]] && (( rank >= target_rank )); then
				continue   # already at or beyond In review -> never move backwards
			fi

			if move_card "$project_node" "$item_id" "$status_field" "$target_option"; then
				report="$(printf '%s\nmoved issue #%s to In review (was: %s, via PR #%s)' \
					"$report" "$issue" "${current_status:-none}" "$n")"
			else
				report="$(printf '%s\nFAILED to move issue #%s to In review (PR #%s) — verify by hand' \
					"$report" "$issue" "$n")"
			fi
		done <<<"$issues"
	done <<<"$pr_numbers"

	# shellcheck disable=SC2034 # read by callers after this returns, not within this file
	RECONCILE_KANBAN_STATUS="ok"
	# shellcheck disable=SC2034 # read by callers after this returns, not within this file
	RECONCILE_KANBAN_REPORT="$(printf '%s\n' "$report" | sed '/^$/d')"
	return 0
}
