#!/usr/bin/env bats
#
# Unit tests for ai_clients/claude/hooks/session_capture_audit.sh
#
# Focus: the both-directions completeness table (dotfiles-dev#81). A one-directional
# lessons→issues audit hid an OPEN ISSUE with no lesson (#75); these tests pin both rows.
#
# Strategy:
#   - Point the hook's store at a throwaway CLAUDE_CONFIG_DIR so we control the lessons.
#   - Run inside a git repo whose basename is a real store target ("dotfiles-dev") with a
#     github origin, so store_dir_for_repo + repo_slug resolve.
#   - Stub `gh` on PATH to feed a deterministic open-issue list (no network).
#
# Run locally:  bats tests/            (install with: sudo apt-get install -y bats)

setup() {
	HOOK="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/ai_clients/claude/hooks/session_capture_audit.sh"
	TEST_TMP="$(mktemp -d)"

	# Throwaway store, matching the dotfiles-dev lesson-store layout.
	export CLAUDE_CONFIG_DIR="$TEST_TMP/claude"
	STORE="$CLAUDE_CONFIG_DIR/memory/lessons-dotfiles"
	mkdir -p "$STORE"
	printf '# index\n' >"$STORE/README.md"

	# A repo whose basename is a store target, with a github origin.
	REPO="$TEST_TMP/dotfiles-dev"
	mkdir -p "$REPO"
	git -C "$REPO" init -q
	git -C "$REPO" remote add origin https://github.com/guilhermegor/dotfiles-dev.git

	# gh stub: prints whatever issue numbers $GH_ISSUES holds, as the --json/--jq path does.
	mkdir -p "$TEST_TMP/bin"
	cat >"$TEST_TMP/bin/gh" <<'STUB'
#!/bin/bash
# Only implements `gh issue list … --jq '.[].number'` → one number per line.
# Records its own argv so a test can prove the caller bounded the page explicitly.
printf '%s\n' "$*" >>"$GH_ARGV_LOG"
printf '%s\n' $GH_ISSUES
STUB
	chmod +x "$TEST_TMP/bin/gh"
}

teardown() {
	rm -rf "$TEST_TMP"
}

# Indexed lesson referencing the given dotfiles-dev issue number (or none if $2 empty).
lesson() {
	local name="$1" issue="$2"
	printf '# %s\n\n- **Tier:** language-common\n' "$name" >"$STORE/$name"
	[ -n "$issue" ] && printf -- '- **PR:** guilhermegor/dotfiles-dev#%s\n' "$issue" >>"$STORE/$name"
	printf -- '- %s\n' "$name" >>"$STORE/README.md"
}

# Lesson carrying an explicit `Status:` line — the disposition, not just a citation.
lesson_status() {
	local name="$1" status="$2"
	printf '# %s\n\n- **Tier:** language-common\n- **Status:** %s\n' "$name" "$status" \
		>"$STORE/$name"
	printf -- '- %s\n' "$name" >>"$STORE/README.md"
}

run_report() {
	run bash -c "cd '$REPO' && PATH='$TEST_TMP/bin:$PATH' GH_ISSUES='$1' \
		GH_ARGV_LOG='$TEST_TMP/gh_argv' bash '$HOOK' </dev/null"
}

# --- row 1: lessons → issues (store-internal, no network) ---------------------------------------

@test "row 1 flags a lesson with no Status and no reference as undeclared" {
	lesson "orphan-lesson.md" ""
	run_report ""
	[ "$status" -eq 0 ]
	[[ "$output" == *"lessons → issues : 1 in store, 0 declared (0 still queued), 1 undeclared"* ]]
	[[ "$output" == *"lessons with no Status: line"*"orphan-lesson.md"* ]]
}

@test "row 1 counts a lesson that references its issue as declared" {
	lesson "tracked-lesson.md" "42"
	run_report ""
	[[ "$output" == *"lessons → issues : 1 in store, 1 declared (0 still queued), 0 undeclared"* ]]
	[[ "$output" != *"lessons with no Status: line"* ]]
}

@test "row 1 accepts a delivered Status with no issue number as declared" {
	# The whole point of the field: work that shipped before issues existed is not debt.
	lesson_status "shipped.md" "delivered — pre-PR (abc1234)"
	run_report ""
	[[ "$output" == *"lessons → issues : 1 in store, 1 declared (0 still queued), 0 undeclared"* ]]
}

@test "row 1 counts a queued Status separately as the debt still owed" {
	lesson_status "owed.md" "queued — no issue filed (target absent)"
	run_report ""
	[[ "$output" == *"lessons → issues : 1 in store, 1 declared (1 still queued), 0 undeclared"* ]]
}

@test "row 1 does not count advisory as queued" {
	lesson_status "judgment.md" "advisory — no scaffold target"
	run_report ""
	[[ "$output" == *"lessons → issues : 1 in store, 1 declared (0 still queued), 0 undeclared"* ]]
}

# --- row 2: issues → lessons (the B-side orphan the old audit could not see) --------------------

@test "row 2 flags an open issue with no lesson as an orphan" {
	lesson "some-lesson.md" "42"
	run_report "77"
	[[ "$output" == *"issues  → lessons: 1 open, 0 sourced by a lesson, 1 orphan"* ]]
	[[ "$output" == *"open issues with no lesson"*"#77"* ]]
}

@test "row 2 counts an open issue referenced by a lesson as sourced" {
	lesson "some-lesson.md" "42"
	run_report "42"
	[[ "$output" == *"issues  → lessons: 1 open, 1 sourced by a lesson, 0 orphan"* ]]
	[[ "$output" != *"open issues with no lesson"* ]]
}

@test "issue #7 is not matched by a lesson referencing #75 (digit-boundary)" {
	lesson "seventyfive.md" "75"
	run_report "7"
	[[ "$output" == *"1 open, 0 sourced by a lesson, 1 orphan"* ]]
	[[ "$output" == *"#7"* ]]
}

@test "row 2 bounds the issue page explicitly instead of taking gh's default 30" {
	# Measured blueprintx 2026-08-16: without --limit the audit saw 30 of 46 open issues and
	# reported the orphan count over that silent sample.
	lesson "some-lesson.md" "42"
	run_report "42"
	[[ "$(cat "$TEST_TMP/gh_argv")" == *"--limit"* ]]
}

# --- SessionEnd must NEVER hit the network (the fail-open guarantee) ----------------------------

@test "handoff mode does not invoke gh (no network at SessionEnd)" {
	lesson "some-lesson.md" "42"
	# A gh that records the fact it was called; handoff mode must never trigger it.
	cat >"$TEST_TMP/bin/gh" <<STUB
#!/bin/bash
touch "$TEST_TMP/gh-was-called"
STUB
	chmod +x "$TEST_TMP/bin/gh"
	# --handoff writes to a file (not stdout) and only when there are gaps; the point
	# of the test is the side effect, so we just assert gh was never reached.
	run bash -c "cd '$REPO' && PATH='$TEST_TMP/bin:$PATH' bash '$HOOK' --handoff </dev/null"
	[ "$status" -eq 0 ]
	[ ! -e "$TEST_TMP/gh-was-called" ]
}

# --- report mode with no resolvable repo: row 2 skipped, never an error -------------------------

@test "row 2 is skipped (not errored) when the repo has no github origin" {
	lesson "some-lesson.md" "42"
	# Drop the origin: repo_slug returns empty, so row 2 has nothing to query. The
	# basename stays "dotfiles-dev" so the table still renders (row 1 unaffected).
	git -C "$REPO" remote remove origin
	run bash -c "cd '$REPO' && PATH='$TEST_TMP/bin:$PATH' bash '$HOOK' </dev/null"
	[ "$status" -eq 0 ]
	[[ "$output" == *"issues  → lessons: skipped"* ]]
}
