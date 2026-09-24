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
