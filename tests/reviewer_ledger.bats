#!/usr/bin/env bats
#
# Unit tests for ai_clients/claude/hooks/lib/reviewer_ledger.sh -- the SQLite
# ledger of reviewer asks and accepted findings by class (dotfiles-dev#488).
#
# Every test points REVIEWER_LEDGER_DB at a per-test tmp file so a run never
# touches the real ~/.claude/reviewer_ledger.db.
#
# Run locally:  bats tests/

setup() {
	LEDGER="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/ai_clients/claude/hooks/lib/reviewer_ledger.sh"
	TEST_TMP="$(mktemp -d)"
	REVIEWER_LEDGER_DB="$TEST_TMP/ledger.db"
	export REVIEWER_LEDGER_DB
}

teardown() {
	rm -rf "$TEST_TMP"
}

# --- init --------------------------------------------------------------------

@test "init creates the db and is idempotent" {
	run "$LEDGER" init
	[ "$status" -eq 0 ]
	[ -f "$REVIEWER_LEDGER_DB" ]

	# a second init on the same db must not error (CREATE TABLE IF NOT EXISTS)
	run "$LEDGER" init
	[ "$status" -eq 0 ]
}

# --- validation ----------------------------------------------------------------

@test "ask rejects an outcome outside refused|clean|found" {
	run "$LEDGER" ask --rung codex --pr 1 --sha abc --outcome bogus
	[ "$status" -ne 0 ]
	[[ "$output" == *"outcome"* ]]
}

@test "finding rejects a class outside the closed vocabulary" {
	"$LEDGER" init
	ask_id="$("$LEDGER" ask --rung codex --pr 1 --sha abc --outcome found | tail -1)"

	run "$LEDGER" finding --ask-id "$ask_id" --severity major --verdict true --class not-a-real-class
	[ "$status" -ne 0 ]
	[[ "$output" == *"class"* ]]
}

@test "finding rejects a verdict outside true|false|partial" {
	"$LEDGER" init
	ask_id="$("$LEDGER" ask --rung codex --pr 1 --sha abc --outcome found | tail -1)"

	run "$LEDGER" finding --ask-id "$ask_id" --severity major --verdict maybe --class test-gap
	[ "$status" -ne 0 ]
	[[ "$output" == *"verdict"* ]]
}

# --- the two-halves assertion the issue asks for --------------------------------

@test "a recorded ask with a true finding shows in the rung-effectiveness report" {
	"$LEDGER" init
	ask_id="$("$LEDGER" ask --rung codex --pr 453 --sha aaa111 --outcome found | tail -1)"
	"$LEDGER" finding --ask-id "$ask_id" --severity major --verdict true --class fail-open

	run "$LEDGER" report rung-effectiveness
	[ "$status" -eq 0 ]
	[[ "$output" == *"codex"* ]]
	# 1 ask, 1 found, 1 true finding for the codex row
	[[ "$output" =~ codex[[:space:]]+1[[:space:]]+0[[:space:]]+0[[:space:]]+1[[:space:]]+1 ]]
}

@test "an ask with no findings shows as clean, not absent, in the report" {
	"$LEDGER" init
	"$LEDGER" ask --rung qwen --pr 453 --sha aaa111 --outcome clean

	run "$LEDGER" report rung-effectiveness
	[ "$status" -eq 0 ]
	[[ "$output" == *"qwen"* ]]
	# 1 ask, 0 refused, 1 clean, 0 found, 0 true findings
	[[ "$output" =~ qwen[[:space:]]+1[[:space:]]+0[[:space:]]+1[[:space:]]+0[[:space:]]+0 ]]
}

@test "a refused ask is never reported as clean or found" {
	"$LEDGER" init
	"$LEDGER" ask --rung kimi --pr 453 --sha aaa111 --outcome refused

	run "$LEDGER" report rung-effectiveness
	[ "$status" -eq 0 ]
	[[ "$output" =~ kimi[[:space:]]+1[[:space:]]+1[[:space:]]+0[[:space:]]+0[[:space:]]+0 ]]
}

# --- zero-true report ------------------------------------------------------------

@test "zero-true flags a rung with asks but no true findings, and excludes one with a true finding" {
	"$LEDGER" init
	"$LEDGER" ask --rung qwen --pr 453 --sha aaa111 --outcome clean
	ask_id="$("$LEDGER" ask --rung codex --pr 453 --sha aaa111 --outcome found | tail -1)"
	"$LEDGER" finding --ask-id "$ask_id" --severity major --verdict true --class fail-open

	run "$LEDGER" report zero-true --min-asks 1
	[ "$status" -eq 0 ]
	[[ "$output" == *"qwen"* ]]
	[[ "$output" != *"codex"* ]]
}

@test "report fails closed when no ledger exists yet" {
	run "$LEDGER" report rung-effectiveness
	[ "$status" -ne 0 ]
	[[ "$output" == *"no ledger"* ]]
}
