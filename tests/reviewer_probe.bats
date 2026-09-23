#!/usr/bin/env bats
#
# Unit tests for ai_clients/claude/hooks/lib/reviewer_probe.sh — the once-per-session
# reviewer-rung capability probe added for dotfiles-dev#479 (measured: kimi sits on
# PATH with `grep -c kimi reviewer_ladder.sh` returning 0 — installed, never wired;
# the CodeRabbit CLI sits on PATH, wired nowhere, and `coderabbit auth status`
# reports "signed out" — installed, unusable. Neither gap was visible before this).
#
# PATH is pinned to a stub bin dir plus /usr/bin:/bin for every test so real
# codex/qwen/kimi/coderabbit installs on the dev machine never leak into a result —
# only the fixtures each test stubs onto PATH are "on PATH" as far as the probe
# can tell.
#
# Run locally:  bats tests/

setup() {
	LIB="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/ai_clients/claude/hooks/lib/reviewer_probe.sh"
	TEST_TMP="$(mktemp -d)"
	STUB_BIN="$TEST_TMP/bin"
	mkdir -p "$STUB_BIN"
	LADDER="$TEST_TMP/reviewer_ladder.sh"
	PATH="$STUB_BIN:/usr/bin:/bin"

	source "$LIB"
}

teardown() {
	rm -rf "$TEST_TMP"
}

stub_bin() {
	printf '#!/bin/bash\nexit 0\n' >"$STUB_BIN/$1"
	chmod +x "$STUB_BIN/$1"
}

# --- installed-but-unwired produces the warning ----------------------------------

@test "an installed-but-unwired rung produces the [reviewers] warning" {
	stub_bin kimi
	printf 'this ladder never mentions that runtime\n' >"$LADDER"
	REVIEWER_PROBE_LADDER_FILE="$LADDER"

	run emit_reviewer_probe_status
	[ "$status" -eq 0 ]
	[[ "$output" == *"[reviewers]"* ]]
	[[ "$output" == *"kimi: on PATH, not wired into the ladder"* ]]
}

@test "an installed-and-wired-but-unauthenticated rung produces the warning" {
	stub_bin coderabbit
	printf 'coderabbit is mentioned right here\n' >"$LADDER"
	fake_signed_out() { printf 'Status : signed out\n'; }
	REVIEWER_PROBE_LADDER_FILE="$LADDER"
	REVIEWER_PROBE_CODERABBIT_AUTH_CMD=fake_signed_out

	run emit_reviewer_probe_status
	[ "$status" -eq 0 ]
	[[ "$output" == *"[reviewers]"* ]]
	[[ "$output" == *"coderabbit: on PATH, wired, NOT authenticated"* ]]
}

# --- every rung fine → silent -----------------------------------------------------

@test "every rung on PATH, wired, and not known-unauthenticated produces no [reviewers] noise" {
	stub_bin codex
	stub_bin qwen
	stub_bin kimi
	stub_bin coderabbit
	printf 'codex qwen kimi coderabbit all mentioned here\n' >"$LADDER"
	fake_logged_in() { printf 'Status : logged in\n'; }
	REVIEWER_PROBE_LADDER_FILE="$LADDER"
	REVIEWER_PROBE_CODERABBIT_AUTH_CMD=fake_logged_in

	run emit_reviewer_probe_status
	[ "$status" -eq 0 ]
	[[ "$output" != *"[reviewers]"* ]]
}

@test "a rung that is simply absent from PATH is never reported" {
	printf 'nothing wired at all\n' >"$LADDER"
	REVIEWER_PROBE_LADDER_FILE="$LADDER"

	run emit_reviewer_probe_status
	[ "$status" -eq 0 ]
	[[ "$output" != *"[reviewers]"* ]]
}

# --- an unreadable rung reports unknown, the rest of the line still prints -------

@test "an unreadable ladder file reports unknown wiring but still prints every on-PATH rung" {
	stub_bin kimi
	stub_bin coderabbit
	fake_signed_out() { printf 'Status : signed out\n'; }
	REVIEWER_PROBE_LADDER_FILE="$TEST_TMP/does-not-exist.sh"
	REVIEWER_PROBE_CODERABBIT_AUTH_CMD=fake_signed_out

	run emit_reviewer_probe_status
	[ "$status" -eq 0 ]
	[[ "$output" == *"[reviewers]"* ]]
	[[ "$output" == *"kimi: on PATH, wiring state unknown (ladder file unreadable)"* ]]
	# coderabbit's own column still resolves despite the ladder being unreadable —
	# one column's failure doesn't blank out another column on the same line.
	[[ "$output" == *"coderabbit: on PATH, wiring state unknown (ladder file unreadable), NOT authenticated"* ]]
}
