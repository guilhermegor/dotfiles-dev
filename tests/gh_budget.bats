#!/usr/bin/env bats
#
# Unit tests for ai_clients/claude/hooks/lib/gh_budget.sh (dotfiles-dev#407) — pure text
# classification, no network. Fixtures are captured response bodies, not live API calls, so the
# suite stays deterministic in CI. Covers all four required cases: a real GitHub API 403, a
# CodeRabbit review-slot notice, a CodeRabbit chat-quota notice, and an unrecognised notice.

setup() {
	source "$BATS_TEST_DIRNAME/../ai_clients/claude/hooks/lib/gh_budget.sh"
	LATCH_DIR="$(mktemp -d)"
	export GH_BUDGET_LATCH_FILE="$LATCH_DIR/latch"
}

teardown() {
	rm -rf "$LATCH_DIR"
}

@test "the exact measured 2026-09-20 18:20:02Z GitHub 403 classifies as github-api-limit" {
	gh_budget_classify 'API rate limit exceeded for user ID 55053188'
	[ "$GH_BUDGET_CLASS" = "github-api-limit" ]
}

@test "gh CLI's GraphQL-prefixed form of the same error also classifies as github-api-limit" {
	gh_budget_classify 'GraphQL: API rate limit exceeded for user ID 55053188.'
	[ "$GH_BUDGET_CLASS" = "github-api-limit" ]
}

@test "GitHub's secondary rate limit (abuse detection) also classifies as github-api-limit" {
	gh_budget_classify 'You have exceeded a secondary rate limit. Please wait a few minutes.'
	[ "$GH_BUDGET_CLASS" = "github-api-limit" ]
}

@test "a CodeRabbit review-slot notice classifies as coderabbit-review-limit, not github" {
	gh_budget_classify '⚠️ Rate limit exceeded — please wait 4 minutes and 37 seconds before requesting another review.'
	[ "$GH_BUDGET_CLASS" = "coderabbit-review-limit" ]
}

@test "a CodeRabbit chat-quota notice classifies as coderabbit-chat-limit, a DIFFERENT limit" {
	gh_budget_classify 'You have exceeded the maximum number of chat messages per hour. Please wait before sending another chat message.'
	[ "$GH_BUDGET_CLASS" = "coderabbit-chat-limit" ]
}

@test "an unrecognised notice classifies as unknown, never defaults to ok" {
	gh_budget_classify 'CodeRabbit is reviewing your changes...'
	[ "$GH_BUDGET_CLASS" = "unknown" ]
}

@test "empty text classifies as unknown" {
	gh_budget_classify ''
	[ "$GH_BUDGET_CLASS" = "unknown" ]
}

@test "gh_budget_is_terminal is true only for github-api-limit" {
	gh_budget_classify 'API rate limit exceeded for user ID 55053188'
	gh_budget_is_terminal
}

@test "gh_budget_is_terminal is false for a CodeRabbit review-limit notice" {
	gh_budget_classify 'Rate limit exceeded — please wait before requesting another review.'
	run gh_budget_is_terminal
	[ "$status" -ne 0 ]
}

@test "gh_budget_is_terminal is false for a CodeRabbit chat-limit notice" {
	gh_budget_classify 'exceeded the maximum number of chat messages per hour'
	run gh_budget_is_terminal
	[ "$status" -ne 0 ]
}

@test "gh_budget_is_terminal is false for unknown" {
	gh_budget_classify 'something unrelated entirely'
	run gh_budget_is_terminal
	[ "$status" -ne 0 ]
}

# --- 403 latch (dotfiles-dev#445) -----------------------------------------------------------------

@test "gh_budget_latch_path honours GH_BUDGET_LATCH_FILE" {
	[ "$(gh_budget_latch_path)" = "$GH_BUDGET_LATCH_FILE" ]
}

@test "no marker file means the latch is not active" {
	run gh_budget_latch_active
	[ "$status" -ne 0 ]
}

@test "a freshly written latch is active" {
	gh_budget_latch_write 300
	run gh_budget_latch_active
	[ "$status" -eq 0 ]
}

@test "a latch written with a negative TTL is already expired" {
	gh_budget_latch_write -5
	run gh_budget_latch_active
	[ "$status" -ne 0 ]
}

@test "an unparsable marker file is treated as not active" {
	echo "not-a-number" > "$GH_BUDGET_LATCH_FILE"
	run gh_budget_latch_active
	[ "$status" -ne 0 ]
}

@test "gh_budget_latch_write defaults to a 300s TTL" {
	gh_budget_latch_write
	now="$(date +%s)"
	until="$(cat "$GH_BUDGET_LATCH_FILE")"
	diff=$((until - now))
	[ "$diff" -gt 290 ]
	[ "$diff" -le 300 ]
}
