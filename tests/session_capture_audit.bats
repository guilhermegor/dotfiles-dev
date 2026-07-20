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

run_report() {
	run bash -c "cd '$REPO' && PATH='$TEST_TMP/bin:$PATH' GH_ISSUES='$1' bash '$HOOK' </dev/null"
}

# --- row 1: lessons → issues (store-internal, no network) ---------------------------------------

@test "row 1 flags a lesson with no issue/PR reference as unaccounted" {
	lesson "orphan-lesson.md" ""
	run_report ""
	[ "$status" -eq 0 ]
	[[ "$output" == *"lessons → issues : 1 in store, 0 reference an issue/PR, 1 unaccounted"* ]]
	[[ "$output" == *"lessons with no issue/PR reference: orphan-lesson.md"* ]]
}

@test "row 1 counts a lesson that references its issue as tracked" {
	lesson "tracked-lesson.md" "42"
	run_report ""
	[[ "$output" == *"lessons → issues : 1 in store, 1 reference an issue/PR, 0 unaccounted"* ]]
	[[ "$output" != *"lessons with no issue/PR reference"* ]]
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
