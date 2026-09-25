#!/bin/bash
# Classifies a dev-loop round's read failure or CodeRabbit roster notice into the ONE limit it
# actually hit (dotfiles-dev#407). Two distinct quotas share the substring "rate limit" and mean
# OPPOSITE things:
#
#   1. the GITHUB API/GraphQL budget (a failed `gh`/REST/GraphQL call, HTTP 403/429) — the board
#      itself is unreadable; nothing about the reviewer is known. Terminal for this round:
#      retrying in a loop against an already-exhausted budget cannot succeed. Measured
#      2026-09-20 18:20:02Z: "API rate limit exceeded for user ID 55053188", HTTP 403, on
#      repos/{o}/{r}/issues/comments — and a sibling agent once burned 261k tokens re-diagnosing
#      the identical 403 across ten sweeps instead of stopping.
#   2. the CODERABBIT review-slot quota — a roster COMMENT the board successfully returned,
#      saying the reviewer is busy. The board is readable; only the reviewer isn't done yet.
#
# Misreading (1) as (2) makes a live loop believe the reviewer is busy when it actually went
# blind; misreading (2) as (1) throws away a perfectly good busy-signal as "unknown/unreadable".
# An unrecognised notice must classify UNKNOWN and never default to OK — same rule
# hooks/lib/free_surface.sh and hooks/lib/review_thread_gate.sh already apply to their own reads.
#
# ⚠️ Never classify from `gh api rate_limit` alone — that endpoint has been measured reporting
# quota it does not have. The ground truth is a REAL call's captured exit code/HTTP status/body;
# this library calls no API itself, it only classifies text a caller already captured.
set -u

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	echo "gh_budget.sh is meant to be sourced, not executed." >&2
	exit 1
fi

# gh_budget_classify TEXT
# Sets GH_BUDGET_CLASS to exactly one of:
#   github-api-limit        — the GitHub API/GraphQL budget is exhausted: the board is UNKNOWN
#                              this round, terminal, do not retry in a loop.
#   coderabbit-review-limit — CodeRabbit's own review-slot quota; board readable, reviewer busy.
#   coderabbit-chat-limit   — CodeRabbit's SEPARATE chat quota; review slot is untouched/free.
#   unknown                 — matched neither known signature; never treat as OK.
# Always returns 0 — classifying never fails, only the RESULT can be "unknown".
gh_budget_classify() {
	local text_lc
	text_lc="${1,,}"
	GH_BUDGET_CLASS="unknown"

	# GitHub's OWN api/graphql rate-limit error text, checked FIRST because it also contains the
	# substring "rate limit" that CodeRabbit's unrelated review-slot notice uses below.
	if [[ "$text_lc" == *"api rate limit exceeded"* ]] || [[ "$text_lc" == *"secondary rate limit"* ]]; then
		GH_BUDGET_CLASS="github-api-limit"
		return 0
	fi

	# CodeRabbit's chat quota, checked before the generic "rate limit" match below: its own
	# notice is identified by "chat message", independent of whether "rate limit" also appears.
	if [[ "$text_lc" == *"chat message"* ]]; then
		GH_BUDGET_CLASS="coderabbit-chat-limit"
		return 0
	fi

	if [[ "$text_lc" == *"rate limit"* ]]; then
		GH_BUDGET_CLASS="coderabbit-review-limit"
		return 0
	fi

	return 0
}

# gh_budget_is_terminal
# True (0) only right after gh_budget_classify found the GITHUB API budget itself exhausted —
# the signal that a round must stop and report UNKNOWN rather than retry (dotfiles-dev#407).
gh_budget_is_terminal() {
	[[ "${GH_BUDGET_CLASS:-}" == "github-api-limit" ]]
}

# --- 403 latch (dotfiles-dev#445) -----------------------------------------------------------------
# A hook-side twin of the agent-side lesson "the completion sweep retries a dead API until the
# agent's budget is spent": a 403 is terminal until GitHub's own reset, so re-probing every time a
# SubagentStop fires (measured: more than once per finished agent, unbounded with N agents) is pure
# waste. These three functions are the whole latch — write a marker on a real 403, and let any
# caller check it before spending a single gh call.

# gh_budget_latch_path
# $GH_BUDGET_LATCH_FILE overrides it (tests, or a caller wanting a scoped marker); otherwise a
# fixed path under $XDG_RUNTIME_DIR (falls back to /tmp — not every host sets it) shared by every
# dotfiles-dev hook process on this machine, since the exhausted budget is account-wide, never
# per-repo.
gh_budget_latch_path() {
	printf '%s\n' "${GH_BUDGET_LATCH_FILE:-${XDG_RUNTIME_DIR:-/tmp}/dotfiles-dev-sweep-403-until}"
}

# gh_budget_latch_write [TTL_SECONDS]
# Marks the budget exhausted until now+TTL. Default is $GH_BUDGET_LATCH_TTL, or 45s — a short
# burst-backoff, not a long guess — because callers are expected to pass an explicit TTL from
# gh_budget_reset_ttl() below once a real 403 has fired; this default only covers a caller that
# skips that step.
gh_budget_latch_write() {
	local ttl="${1:-${GH_BUDGET_LATCH_TTL:-45}}"
	printf '%s\n' "$(($(date +%s) + ttl))" >"$(gh_budget_latch_path)" 2>/dev/null
}

# gh_budget_latch_active
# True (0) while a marker written by gh_budget_latch_write has not yet expired. False on no
# marker, an unparsable one, or an expired one — every one of those means "safe to call gh
# again", never "assume still exhausted".
gh_budget_latch_active() {
	local path until
	path="$(gh_budget_latch_path)"
	[ -f "$path" ] || return 1
	until="$(cat "$path" 2>/dev/null)"
	[[ "$until" =~ ^[0-9]+$ ]] || return 1
	[ "$(date +%s)" -lt "$until" ]
}

# gh_budget_reset_ttl [BURST_TTL]
# A measured TTL for gh_budget_latch_write, given a REAL 403/429 already fired — this never
# decides WHETHER the budget is exhausted (gh_budget_classify's job alone, off a real call's own
# error text, per this file's header). `gh api rate_limit` costs nothing against any budget, so
# once terminal is already known it is safe to spend one free call telling apart the two shapes
# a GitHub 403 actually has:
#   - primary exhaustion: `remaining` near zero on core or graphql — wait for the real `reset`.
#   - a secondary/concurrency burst: `remaining` still high — the documented quota was never
#     touched, and the right wait is seconds, not minutes.
# Measured dotfiles-dev#445 follow-up, 2026-09-25: two real 403s on this repo, both with core
# `remaining:5000/used:0` — a burst, not the documented quota, clearing in under a minute both
# times. A 300s fixed latch was suppressing the sweep ~5 minutes over a ~40s condition.
# Falls back to BURST_TTL (default 45s) on anything unreadable — an unreadable rate_limit read
# must never be upgraded to "assume primary exhaustion", since this file's own header already
# documents that endpoint reporting healthy quota it does not have; the failure mode of guessing
# wrong here is only an extra cheap probe, never a suppressed real 403.
gh_budget_reset_ttl() {
	local burst_ttl="${1:-45}" json now remaining reset resource ttl
	json="$(gh api rate_limit 2>/dev/null)" || {
		printf '%s\n' "$burst_ttl"
		return 0
	}
	now="$(date +%s)"
	for resource in core graphql; do
		remaining="$(printf '%s' "$json" | jq -r ".resources.$resource.remaining // empty" 2>/dev/null)"
		reset="$(printf '%s' "$json" | jq -r ".resources.$resource.reset // empty" 2>/dev/null)"
		if [[ "$remaining" =~ ^[0-9]+$ ]] && [ "$remaining" -lt 5 ] && [[ "$reset" =~ ^[0-9]+$ ]]; then
			ttl=$((reset - now))
			[ "$ttl" -gt 0 ] && printf '%s\n' "$ttl" && return 0
		fi
	done
	printf '%s\n' "$burst_ttl"
}
