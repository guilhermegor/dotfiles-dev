#!/bin/bash
# Shared roadmap-unblock reconcile (dotfiles-dev#369): closes the gap where a board item's
# Status/label/"Blocked by" field do not follow the native issue-dependency relationship when the
# last blocker closes. GitHub resolves the native relationship
# (repos/<o>/<r>/issues/<n>/dependencies/blocked_by) on its own; nothing else does — the board
# Status stays Blocked, the `state:blocked` label stays, and the "Blocked by" text field goes
# stale (measured on the greenfield roadmap: an item still named a scaffold issue long after that
# issue had closed).
#
# Why a reconcile step, not an event trigger: blockers cross repositories (one project's item can
# be blocked by an issue in a different repo entirely), so an `issues: closed` workflow in one
# repo never sees the other repo's close event; and a `schedule:` workflow was separately measured
# firing 6 times in 21 hours on a quiet repo — GitHub throttles scheduled workflows hardest where
# they're needed most. An idempotent reconcile called once per `s:dev-loop` round has neither
# problem: it is one more read per round, on a trigger that already exists.
#
# Generic across projects: OWNER and PROJECT (number) are arguments — nothing board-specific
# (repo name, board id) is hardcoded. The `state:ready|blocked|deferred` label triad and the
# "Status"/"Blocked by" field names are the one convention this file assumes, per the issue spec.
#
# Contract:
#   reconcile_roadmap_unblock OWNER PROJECT
#     Sets two globals (never partial):
#       RECONCILE_STATUS = ok | unknown
#       RECONCILE_REPORT = newline-separated lines, one per item that changed OR needs a human
#                          look (still blocked, blocked by nothing, decision, unknown) — nothing
#                          is printed for an item left alone with no new information.
#     Returns 1 and sets RECONCILE_STATUS=unknown (RECONCILE_REPORT holding one explanatory line)
#     only when the BOARD ITSELF cannot be read (`gh project item-list` failure or unparseable
#     output). A single item's own read failure (`dependencies/blocked_by`) does not abort the
#     round — it is reported as an "UNKNOWN <item>" line and the next item is still processed.
#
# ⚠️ Fail closed on every read error: an item whose native-blocker read fails is reported UNKNOWN
# and left untouched. Reading a failure as "no blockers" would move the item the one direction
# that has no undo.
#
# ⚠️ A `decision:` blocker — the literal prefix, case-insensitive, recorded in the "Blocked by"
# project text field or the issue body's own "**Blocked by:**" line — is NEVER auto-cleared,
# closed native blockers or not. By definition only a person removes a decision blocker.
set -u

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	echo "roadmap_unblock.sh is meant to be sourced, not executed." >&2
	exit 1
fi

_ru_is_decision() {
	# Case-insensitive "decision:" anywhere in the text — checked against both the project's
	# "Blocked by" text field and the issue body's own "**Blocked by:**" line, since either one
	# recording it makes this a decision blocker.
	printf '%s' "$1" | grep -qi 'decision:'
}

_ru_body_blocked_line() {
	# The issue body's own "**Blocked by:**" line, if present — a second place a blocker (decision
	# or otherwise) can be recorded besides the project's text field. `|| true`: grep's "no match"
	# exit status must never propagate as a failure of this always-succeeds helper.
	printf '%s' "$1" | grep -im1 '^\*\*Blocked by:\*\*' || true
}

# _ru_native_blockers REPO NUMBER
# Prints "state<TAB>owner/repo#number" one per line for every native blocker, or nothing if there
# are none. Returns 1 on any read/parse failure — the caller's fail-closed signal.
#
# ⚠️ `--paginate` is load-bearing, not tidiness: the endpoint returns 30 per page by default, and
# a single open blocker sitting on page 2 would be invisible while page 1 read all-closed — the
# caller would then unblock the item, the one direction with no undo (PR #376 review).
_ru_native_blockers() {
	local repo="$1" number="$2" json
	# The flag goes AFTER the endpoint so a fake `gh` matching on $2 still sees the path.
	json="$(gh api "repos/$repo/issues/$number/dependencies/blocked_by?per_page=100" \
		--paginate 2>/dev/null)" || return 1
	# -s: --paginate emits one array per page, so slurp before validating or reading.
	printf '%s' "$json" | jq -se 'length > 0 and all(type == "array")' >/dev/null 2>&1 || return 1
	printf '%s' "$json" | jq -sr '.[][] | "\(.state)\t\(.repository.full_name)#\(.number)"' 2>/dev/null
}

# _ru_has_comment REPO NUMBER TEXT
# True when TEXT is already the body of a comment on the issue. A read failure counts as "absent":
# a duplicate audit comment is visible and harmless, a suppressed one is silent.
_ru_has_comment() {
	gh issue view "$2" --repo "$1" --json comments --jq '.comments[].body' 2>/dev/null \
		| grep -qxF "$3"
}

# _ru_unblock OWNER PROJECT REPO NUMBER URL DETAIL
# The one mutation path, in order: labels, board "Blocked by", audit comment, board Status LAST.
# The comment is the audit trail (dotfiles-dev#369): a status that changes silently is
# indistinguishable from one someone fat-fingered.
#
# ⚠️ Status is the completion marker, so it writes last (PR #376 review). Writing it first is what
# makes a partial failure permanent: this function is only ever reached for a Status=Blocked item,
# so Status=Ready removes the item from every later round's candidate set — a failed "Blocked by"
# clear or a missing audit comment would then never be retried by anyone, and the stale field
# survives indefinitely. With Status last, any earlier failure leaves the item Blocked and the next
# round redoes the whole sequence, which is safe because every earlier write is retry-safe: the
# label swap is a no-op once applied, `--clear` on an empty field is a no-op, and the comment is
# skipped when its exact text is already on the issue.
#
# ponytail: still no rollback — the caller reports FAILED and the next round re-runs it.
_ru_unblock() {
	local owner="$1" project="$2" repo="$3" number="$4" url="$5" detail="$6"
	local note="Unblocked: $detail. Status set to Ready."
	gh issue edit "$number" --repo "$repo" \
		--add-label "state:ready" --remove-label "state:blocked" >/dev/null 2>&1 || return 1
	gh project item-edit "$project" --owner "$owner" --url "$url" \
		--field "Blocked by" --clear >/dev/null 2>&1 || return 1
	if ! _ru_has_comment "$repo" "$number" "$note"; then
		gh issue comment "$number" --repo "$repo" --body "$note" >/dev/null 2>&1 || return 1
	fi
	gh project item-edit "$project" --owner "$owner" --url "$url" \
		--field "Status" --value "Ready" >/dev/null 2>&1 || return 1
}

# _ru_process_item OWNER PROJECT ITEM_JSON
# Prints exactly one report line for a single Blocked item, and calls _ru_unblock when every
# native blocker is closed and no decision blocker is recorded.
_ru_process_item() {
	local owner="$1" project="$2" item="$3"
	local number repo url body field_text body_line ident
	number="$(jq -r '.content.number' <<<"$item")"
	repo="$(jq -r '.content.repository' <<<"$item")"
	url="$(jq -r '.content.url' <<<"$item")"
	body="$(jq -r '.content.body // ""' <<<"$item")"
	field_text="$(jq -r '."blocked by" // ""' <<<"$item")"
	ident="$repo#$number"
	body_line="$(_ru_body_blocked_line "$body")"

	local native native_rc=0
	native="$(_ru_native_blockers "$repo" "$number")" || native_rc=1
	if ((native_rc != 0)); then
		printf 'UNKNOWN %s: could not read native blockers — left untouched\n' "$ident"
		return 0
	fi

	if _ru_is_decision "$field_text" || _ru_is_decision "$body_line"; then
		printf 'decision blocker %s: %s — left untouched (only a person clears this)\n' \
			"$ident" "${field_text:-$body_line}"
		return 0
	fi

	if [[ -n "$native" ]]; then
		local open_list closed_list
		open_list="$(printf '%s\n' "$native" | awk -F'\t' '$1 != "closed" {print $2}')"
		closed_list="$(printf '%s\n' "$native" | awk -F'\t' '$1 == "closed" {print $2}')"
		if [[ -z "$open_list" ]]; then
			local detail
			detail="$(printf '%s' "$closed_list" | paste -sd, -)"
			if _ru_unblock "$owner" "$project" "$repo" "$number" "$url" "$detail"; then
				printf 'unblocked %s: all native blockers closed (%s) -> Ready\n' "$ident" "$detail"
			else
				printf 'FAILED to unblock %s: a gh write failed partway — verify by hand\n' "$ident"
			fi
		else
			printf 'still blocked %s: open native blocker(s) %s\n' \
				"$ident" "$(printf '%s' "$open_list" | paste -sd, -)"
		fi
		return 0
	fi

	if [[ -n "$field_text" || -n "$body_line" ]]; then
		printf 'still blocked %s: recorded blocker %s\n' "$ident" "${field_text:-$body_line}"
		return 0
	fi

	printf 'blocked by nothing %s: Status=Blocked but no blocker recorded anywhere\n' "$ident"
}

reconcile_roadmap_unblock() {
	local owner="$1" project="$2"
	RECONCILE_STATUS="unknown"
	RECONCILE_REPORT=""

	local items_json blocked
	items_json="$(gh project item-list "$project" --owner "$owner" --format json --limit 500 2>/dev/null)" \
		|| { RECONCILE_REPORT="UNKNOWN: could not read project $owner/$project"; return 1; }
	# Shape-check before filtering: `.items[]?` exits 0 on `{}` and on `{"items": null}`, so
	# without this an unusable response would report ok having silently processed nothing —
	# indistinguishable from a board with no blocked items (PR #376 review).
	printf '%s' "$items_json" | jq -e 'type == "object" and (.items | type == "array")' \
		>/dev/null 2>&1 \
		|| { RECONCILE_REPORT="UNKNOWN: could not parse project $owner/$project"; return 1; }
	blocked="$(printf '%s' "$items_json" \
		| jq -c '.items[] | select(.status == "Blocked" and .content.type == "Issue")' 2>/dev/null)" \
		|| { RECONCILE_REPORT="UNKNOWN: could not parse project $owner/$project"; return 1; }

	local item line report=""
	while IFS= read -r item; do
		[[ -n "$item" ]] || continue
		line="$(_ru_process_item "$owner" "$project" "$item")"
		[[ -n "$line" ]] && report="$(printf '%s\n%s' "$report" "$line")"
	done <<<"$blocked"

	# shellcheck disable=SC2034 # read by callers after this returns, not within this file
	RECONCILE_STATUS="ok"
	# shellcheck disable=SC2034 # read by callers after this returns, not within this file
	RECONCILE_REPORT="$(printf '%s\n' "$report" | sed '/^$/d')"
	return 0
}
