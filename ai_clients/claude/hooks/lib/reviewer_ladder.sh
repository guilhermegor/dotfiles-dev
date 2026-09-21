#!/bin/bash
# Reviewer fallback ladder (dotfiles-dev#444): s:dev-loop step 4b has exactly one
# reviewer and stalls whenever its window is closed (measured on blueprintx
# 2026-09-21: 44 of 56 open PRs never reviewed while the primary reviewer's slot
# was rate-limited most of the day). This lib resolves the two fallback rungs —
# qwen, then codex — by MEASURED capability at run time, never by a hardcoded
# model name. The primary review bot stays step 4b's own existing item 3/4 logic
# (human request / bot ask); this lib only covers what happens when that rung is
# BUSY.
#
# 🔴 `priority` in ~/.codex/models_cache.json is NOT a capability rank — REJECTED
# as the selector. Measured 2026-09-21 on this account: `codex-auto-review`
# (a model named for reviewing) sits at priority 43; `gpt-5.5`, a general model,
# sits at 12. Ranking by priority would pick the general model over the
# review-specialised one while looking principled. Never read `.priority` below.
#
# 🔴 `visibility: list` is ALSO REJECTED as an entitlement proxy, for the same
# reason `priority` is rejected: it looked plausible and measurement disproved
# it. `codex-auto-review` is `visibility: hide` on this account and a live probe
# (`codex exec -m codex-auto-review "reply with the single word OK"`) returned
# OK anyway — hide means "not advertised in the picker", not "not entitled".
# Filtering on visibility would have discarded the one model actually built for
# this job. The only trustworthy entitlement signal is a live trivial call
# (_codex_entitlement_probe / _qwen_entitlement_probe below) — the cache and the
# settings file both list what EXISTS, never what this account is ENTITLED to
# call.
#
# Accepted capability signal, in priority order:
#   1. review-specialised slug (name matches /review/i) that PASSES the live
#      entitlement probe — the most specific evidence available.
#   2. richest `supported_reasoning_levels` set among the remaining models that
#      pass the probe — the only other machine-readable capability field the
#      cache exposes ("number of parameters" is not a field at all).
# Never falls back to guessing a name — a rung that resolves nothing is skipped
# and the ladder falls through to the next rung (fail closed).
#
# qwen exposes no cache-with-visibility/priority equivalent: `~/.qwen/settings.json`
# .modelProviders.openai[] is a flat id list with no rank field to reject. The
# account's own configured default (`.model.name`) is ranked first — it is
# already the entitled choice this account picked — then the rest ordered by
# richer reasoning support, and the winner is still live-probed like codex's.
# qwen ships a NATIVE `--fallback-model` flag (repeatable, max 3, for capacity
# errors 429/503/529) — this lib hands the runner-up candidates to THAT flag
# instead of reimplementing per-model retry; it only entitlement-probes the
# PRIMARY qwen candidate, not each fallback, because --fallback-model already
# covers the capacity-error case for the others.
set -u

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	echo "reviewer_ladder.sh is meant to be sourced, not executed." >&2
	exit 1
fi

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../../lib/common.sh
source "$LIB_DIR/../../../../lib/common.sh" 2>/dev/null || true
declare -F print_status >/dev/null 2>&1 || print_status() { :; }

# --- codex rung --------------------------------------------------------------

_codex_cache_path() {
	printf '%s\n' "${REVIEWER_LADDER_CODEX_CACHE:-$HOME/.codex/models_cache.json}"
}

# _codex_entitlement_probe SLUG
# A trivial live call, never a guess from the cache's own fields. Override via
# REVIEWER_LADDER_CODEX_PROBE for tests/dry-run — real tests and DRY_RUN=1 must
# never shell out to the real `codex` binary.
_codex_entitlement_probe() {
	local slug="$1"
	if [ -n "${REVIEWER_LADDER_CODEX_PROBE:-}" ]; then
		"$REVIEWER_LADDER_CODEX_PROBE" "$slug"
		return $?
	fi
	local out
	out="$(timeout "${REVIEWER_LADDER_PROBE_TIMEOUT:-30}" codex exec -m "$slug" \
		--skip-git-repo-check "reply with the single word OK" 2>/dev/null)" || return 1
	[[ "$out" == *OK* ]]
}

# resolve_codex_model
# Sets CODEX_MODEL / CODEX_MODEL_SIGNAL on success; both empty and returns 1 on
# failure (fail closed — malformed/missing cache, or nothing probes usable).
resolve_codex_model() {
	CODEX_MODEL=""
	CODEX_MODEL_SIGNAL=""
	local cache
	cache="$(_codex_cache_path)"
	[ -r "$cache" ] || return 1
	jq -e '.models | type == "array"' "$cache" >/dev/null 2>&1 || return 1

	local review_slugs slug
	review_slugs="$(jq -r '.models[] | select(.slug != null) | select(.slug | test("review"; "i")) | .slug' "$cache" 2>/dev/null)"
	while read -r slug; do
		[ -n "$slug" ] || continue
		if _codex_entitlement_probe "$slug"; then
			CODEX_MODEL="$slug"
			CODEX_MODEL_SIGNAL="review-specialized-slug"
			return 0
		fi
	done <<<"$review_slugs"

	# No review-specialised slug was invocable — rank the rest by the richest
	# supported_reasoning_levels set (descending count, slug as a deterministic
	# tie-break). `priority`/`visibility` are deliberately never read here —
	# see the header comment for the measured rejection of both.
	local ranked
	ranked="$(jq -r '
		.models
		| map(select(.slug != null))
		| sort_by([(- (.supported_reasoning_levels | length)), .slug])
		| .[].slug' "$cache" 2>/dev/null)"
	while read -r slug; do
		[ -n "$slug" ] || continue
		if _codex_entitlement_probe "$slug"; then
			CODEX_MODEL="$slug"
			CODEX_MODEL_SIGNAL="reasoning-levels-richness"
			return 0
		fi
	done <<<"$ranked"

	return 1
}

# --- qwen rung -----------------------------------------------------------

_qwen_settings_path() {
	printf '%s\n' "${REVIEWER_LADDER_QWEN_SETTINGS:-$HOME/.qwen/settings.json}"
}

# _qwen_entitlement_probe ID — same contract as the codex probe above.
_qwen_entitlement_probe() {
	local id="$1"
	if [ -n "${REVIEWER_LADDER_QWEN_PROBE:-}" ]; then
		"$REVIEWER_LADDER_QWEN_PROBE" "$id"
		return $?
	fi
	local out
	out="$(timeout "${REVIEWER_LADDER_PROBE_TIMEOUT:-30}" qwen -m "$id" \
		-p "reply with the single word OK" --output-format text 2>/dev/null)" || return 1
	[[ "$out" == *OK* ]]
}

# resolve_qwen_model
# Sets QWEN_MODEL / QWEN_MODEL_SIGNAL / QWEN_FALLBACK_MODELS (newline list, up
# to 2, handed to the native --fallback-model flag by the caller) on success;
# all empty and returns 1 on failure.
resolve_qwen_model() {
	QWEN_MODEL=""
	QWEN_MODEL_SIGNAL=""
	QWEN_FALLBACK_MODELS=""
	local settings
	settings="$(_qwen_settings_path)"
	[ -r "$settings" ] || return 1
	jq -e '.modelProviders.openai | type == "array"' "$settings" >/dev/null 2>&1 || return 1

	local default_id
	default_id="$(jq -r '.model.name // empty' "$settings" 2>/dev/null)"
	local ranked
	ranked="$(jq -r --arg def "$default_id" '
		.modelProviders.openai
		| map(select(.id != null))
		| sort_by([(if .id == $def then 0 else 1 end),
		           (if (.capabilities.reasoning.thinking // false) then 0 else 1 end),
		           .id])
		| .[].id' "$settings" 2>/dev/null)"

	local id winner="" fallbacks="" fallback_count=0
	while read -r id; do
		[ -n "$id" ] || continue
		if [ -z "$winner" ]; then
			if _qwen_entitlement_probe "$id"; then
				winner="$id"
				if [ "$id" = "$default_id" ]; then
					QWEN_MODEL_SIGNAL="configured-default"
				else
					QWEN_MODEL_SIGNAL="reasoning-capable"
				fi
			fi
		elif [ "$fallback_count" -lt 2 ]; then
			fallbacks="$(printf '%s\n%s' "$fallbacks" "$id" | sed '/^$/d')"
			fallback_count=$((fallback_count + 1))
		fi
	done <<<"$ranked"

	[ -n "$winner" ] || return 1
	QWEN_MODEL="$winner"
	QWEN_FALLBACK_MODELS="$fallbacks"
	return 0
}

# --- the ladder ------------------------------------------------------------

# resolve_fallback_reviewer
# Tries qwen, then codex — the two rungs below the primary review bot. Sets
# LADDER_RUNTIME (qwen|codex|none), LADDER_MODEL, LADDER_SIGNAL,
# LADDER_FALLBACK_MODELS (qwen only). Returns 1 with LADDER_RUNTIME=none when
# neither rung resolves — the ladder falls through, it never guesses a name.
resolve_fallback_reviewer() {
	LADDER_RUNTIME="none"
	LADDER_MODEL=""
	LADDER_SIGNAL=""
	LADDER_FALLBACK_MODELS=""

	if resolve_qwen_model; then
		LADDER_RUNTIME="qwen"
		LADDER_MODEL="$QWEN_MODEL"
		LADDER_SIGNAL="$QWEN_MODEL_SIGNAL"
		LADDER_FALLBACK_MODELS="$QWEN_FALLBACK_MODELS"
		return 0
	fi

	if resolve_codex_model; then
		LADDER_RUNTIME="codex"
		LADDER_MODEL="$CODEX_MODEL"
		LADDER_SIGNAL="$CODEX_MODEL_SIGNAL"
		return 0
	fi

	return 1
}

# --- attribution, blast radius, posting -------------------------------------

# ladder_attribution_line RUNTIME MODEL SIGNAL
# The line every fallback review posts (issue #444 item 5) — a reader must
# never have to guess which reviewer produced a finding.
ladder_attribution_line() {
	local runtime="$1" model="$2" signal="$3"
	printf 'Fallback review — runtime: %s, model: %s (selected by: %s)\n' \
		"$runtime" "$model" "$signal"
}

# ladder_poster_login
# The account _post_pr_comment posts as — `gh`'s authenticated user. Override
# via REVIEWER_LADDER_POSTER for tests. Empty on any gh error (the caller then
# matches no author, i.e. fails closed into "not covered").
ladder_poster_login() {
	if [ -n "${REVIEWER_LADDER_POSTER:-}" ]; then
		printf '%s\n' "$REVIEWER_LADDER_POSTER"
		return 0
	fi
	gh api user --jq '.login' 2>/dev/null
}

# ladder_already_covered COMMENTS_JSON
# True when a fallback attribution line already exists among a PR's comments,
# AUTHORED BY THE LADDER'S OWN POSTING ACCOUNT — a lower rung never re-reviews
# what a higher one already covered. COMMENTS_JSON is the `gh api
# .../issues/N/comments` array (or any `[{author|user.login, body}]` list);
# structured, never joined text, because any PR commenter can type the marker
# line and a text match would let them skip the review (CWE-345).
ladder_already_covered() {
	local comments="$1" poster
	poster="$(ladder_poster_login)"
	[ -n "$poster" ] || return 1
	printf '%s' "$comments" | jq -e --arg who "$poster" '
		type == "array" and any(.[];
			((.author.login // .user.login // "") == $who)
			and ((.body // "") | test("^Fallback review — runtime:"; "m")))
	' >/dev/null 2>&1 || return 1
}

# ladder_recently_pushed PUSHED_EPOCH NOW_EPOCH
# Mirrors step 4b's own "skip if pushed in the last ~10 minutes" rule (a push
# already triggers a re-review, so a fallback ask on top spends a rung for
# nothing).
ladder_recently_pushed() {
	local pushed="$1" now="$2"
	[ -n "$pushed" ] || return 1
	local age=$((now - pushed))
	[ "$age" -lt "${REVIEWER_LADDER_RECENT_PUSH_SECONDS:-600}" ]
}

# ladder_candidate_ok MERGE_STATE_STATUS PUSHED_EPOCH NOW_EPOCH
# The blast-radius gate (issue #444 item 6): not DIRTY, not pushed in the last
# ~10 minutes. "Sole blocker is the review gate" stays where step 4b already
# computes it (its own gh query in the skill) — not duplicated here.
ladder_candidate_ok() {
	local merge_state="$1" pushed="$2" now="$3"
	[ "$merge_state" != "DIRTY" ] || return 1
	! ladder_recently_pushed "$pushed" "$now"
}

# _run_runtime_review RUNTIME MODEL FALLBACKS PR_NUMBER
# Invokes the resolved CLI's own non-interactive review subcommand and prints
# its findings. Override via REVIEWER_LADDER_RUN_CMD for tests/dry-run — never
# executed when DRY_RUN=1 (run_fallback_review returns before reaching this).
_run_runtime_review() {
	local runtime="$1" model="$2" fallbacks="$3" pr_number="$4"
	if [ -n "${REVIEWER_LADDER_RUN_CMD:-}" ]; then
		"$REVIEWER_LADDER_RUN_CMD" "$runtime" "$model" "$fallbacks" "$pr_number"
		return $?
	fi
	case "$runtime" in
	codex)
		codex -m "$model" review --skip-git-repo-check "PR #$pr_number"
		;;
	qwen)
		local fb_args=() fb
		while read -r fb; do
			[ -n "$fb" ] || continue
			fb_args+=(--fallback-model "$fb")
		done <<<"$fallbacks"
		# No --json: that prints the raw result object, and the caller posts
		# this output verbatim as the review comment.
		qwen -m "$model" "${fb_args[@]}" review run "$pr_number"
		;;
	*)
		return 1
		;;
	esac
}

# _post_pr_comment OWNER REPO PR_NUMBER BODY
# Override via REVIEWER_LADDER_POST_CMD for tests/dry-run.
_post_pr_comment() {
	local owner="$1" repo="$2" pr_number="$3" body="$4"
	if [ -n "${REVIEWER_LADDER_POST_CMD:-}" ]; then
		"$REVIEWER_LADDER_POST_CMD" "$owner" "$repo" "$pr_number" "$body"
		return $?
	fi
	gh pr comment "$pr_number" --repo "$owner/$repo" --body "$body"
}

# run_fallback_review OWNER REPO PR_NUMBER MERGE_STATE PUSHED_EPOCH NOW_EPOCH COMMENTS_JSON [--dry-run]
# The one entrypoint callers use. One PR per call is the blast-radius cap
# (issue #444 item 6) — there is no loop-over-PRs form of this function.
# COMMENTS_JSON is the PR's issue-comment array as gh returns it (see
# ladder_already_covered). DRY_RUN=1 (env) or a trailing --dry-run resolves
# and prints the chosen rung+model WITHOUT invoking a runtime, probing, or
# posting anything (issue #444 item 7) — tests and manual verification MUST
# use this path. A dry run therefore reports the cache's top-ranked candidate
# UNPROBED: the probe is itself a live model call, and "no runtime" has to
# mean no runtime.
run_fallback_review() {
	local owner="$1" repo="$2" pr_number="$3" merge_state="$4" \
		pushed="$5" now="$6" comments="$7"
	local dry_run="${DRY_RUN:-0}"
	[ "${8:-}" = "--dry-run" ] && dry_run=1

	if ladder_already_covered "$comments"; then
		print_status "info" "PR #$pr_number already covered by a higher rung — skipping"
		return 0
	fi
	if ! ladder_candidate_ok "$merge_state" "$pushed" "$now"; then
		print_status "info" "PR #$pr_number is not a fallback candidate (DIRTY or recently pushed)"
		return 1
	fi

	# Dynamic scoping: these locals are what the probes read while we are on
	# the stack, so a dry run never reaches the real `codex`/`qwen` binaries.
	# `true` accepts every candidate, which is exactly "unprobed".
	local REVIEWER_LADDER_CODEX_PROBE="${REVIEWER_LADDER_CODEX_PROBE:-}" \
		REVIEWER_LADDER_QWEN_PROBE="${REVIEWER_LADDER_QWEN_PROBE:-}"
	if [ "$dry_run" = "1" ]; then
		: "${REVIEWER_LADDER_CODEX_PROBE:=true}"
		: "${REVIEWER_LADDER_QWEN_PROBE:=true}"
	fi

	if ! resolve_fallback_reviewer; then
		print_status "warning" "no fallback rung resolved (qwen and codex both unavailable)"
		return 1
	fi

	local attribution
	attribution="$(ladder_attribution_line "$LADDER_RUNTIME" "$LADDER_MODEL" "$LADDER_SIGNAL")"

	if [ "$dry_run" = "1" ]; then
		print_status "info" "DRY RUN (candidates unprobed) — would probe, then post to PR #$pr_number: $attribution"
		return 0
	fi

	local findings body
	findings="$(_run_runtime_review "$LADDER_RUNTIME" "$LADDER_MODEL" "$LADDER_FALLBACK_MODELS" "$pr_number")" || return 1
	body="$attribution"$'\n\n'"$findings"
	_post_pr_comment "$owner" "$repo" "$pr_number" "$body"
}
