#!/usr/bin/env bats
#
# Unit tests for ai_clients/claude/hooks/lib/generate_lesson_mirrors.sh
# (dotfiles-dev#386): the mirror under .specs/_lessons/ is GENERATED from the
# global lesson stores, never hand-typed. These tests pin:
#   - a lesson whose Origin names the target repo IS mirrored
#   - a lesson whose Origin does NOT name it is excluded
#   - the same-repo store (target_repo == repo) is skipped, matching the
#     convention session_capture_audit.sh's check_mirrors() already enforces
#   - lessons-other (the "-" sentinel) is never mirrored anywhere
#   - regeneration is idempotent (running twice produces byte-identical output)
#   - a repo with no .specs/ at all gets one created, holding only _lessons/
#
# Run locally:  bats tests/            (install with: sudo apt-get install -y bats)

setup() {
	GEN="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/ai_clients/claude/hooks/lib/generate_lesson_mirrors.sh"
	TEST_TMP="$(mktemp -d)"

	export CLAUDE_CONFIG_DIR="$TEST_TMP/claude"
	BX_STORE="$CLAUDE_CONFIG_DIR/memory/lessons"
	DF_STORE="$CLAUDE_CONFIG_DIR/memory/lessons-dotfiles"
	OTHER_STORE="$CLAUDE_CONFIG_DIR/memory/lessons-other"
	mkdir -p "$BX_STORE" "$DF_STORE" "$OTHER_STORE"

	REPO="$TEST_TMP/dotfiles-dev"
	mkdir -p "$REPO"
}

teardown() {
	rm -rf "$TEST_TMP"
}

# A minimal, well-formed lesson file in $1/$2.md with the given Origin ($3).
lesson() {
	local store="$1" name="$2" origin="$3"
	printf '# %s\n\n- **Tier:** language-common\n- **Lesson:** one sentence.\n- **Why:** one sentence.\n- **Origin:** %s\n' \
		"$name" "$origin" >"$store/$name.md"
}

@test "a lesson whose Origin names the repo is included in the mirror" {
	lesson "$BX_STORE" "matches-repo" "dotfiles-dev"
	run bash "$GEN" "$REPO"
	[ "$status" -eq 0 ]
	[ -f "$REPO/.specs/_lessons/blueprintx-lessons.md" ]
	grep -qF "matches-repo.md" "$REPO/.specs/_lessons/blueprintx-lessons.md"
}

@test "a lesson whose Origin does not name the repo is excluded" {
	lesson "$BX_STORE" "matches-repo" "dotfiles-dev"
	lesson "$BX_STORE" "other-origin" "filings-cvm"
	run bash "$GEN" "$REPO"
	[ "$status" -eq 0 ]
	run grep -qF "other-origin.md" "$REPO/.specs/_lessons/blueprintx-lessons.md"
	[ "$status" -ne 0 ]
}

@test "the same-repo store mirror is never generated (target_repo == repo)" {
	lesson "$DF_STORE" "toolchain-fix" "dotfiles-dev"
	run bash "$GEN" "$REPO"
	[ "$status" -eq 0 ]
	[ ! -e "$REPO/.specs/_lessons/dotfiles-dev-lessons.md" ]
}

@test "lessons-other is never mirrored, even when Origin matches the repo" {
	lesson "$OTHER_STORE" "standalone-fix" "dotfiles-dev"
	run bash "$GEN" "$REPO"
	[ "$status" -eq 0 ]
	[ ! -e "$REPO/.specs/_lessons/lessons-other.md" ]
}

@test "regeneration is idempotent: running twice produces byte-identical output" {
	lesson "$BX_STORE" "matches-repo" "dotfiles-dev"
	run bash "$GEN" "$REPO"
	[ "$status" -eq 0 ]
	cp "$REPO/.specs/_lessons/blueprintx-lessons.md" "$TEST_TMP/first-run.md"
	run bash "$GEN" "$REPO"
	[ "$status" -eq 0 ]
	diff "$TEST_TMP/first-run.md" "$REPO/.specs/_lessons/blueprintx-lessons.md"
}

@test "a repo with no .specs/ at all gets one created, holding only _lessons/" {
	lesson "$BX_STORE" "matches-repo" "dotfiles-dev"
	[ ! -e "$REPO/.specs" ]
	run bash "$GEN" "$REPO"
	[ "$status" -eq 0 ]
	[ -d "$REPO/.specs/_lessons" ]
	[ ! -e "$REPO/.specs/CLAUDE.md" ]
}

# Cross-check against the checker: what generate_lesson_mirrors.sh writes here must
# satisfy session_capture_audit.sh's check_mirrors() — both source the same predicate
# (lib/lesson_mirrors.sh), so this proves the sharing actually holds end to end.
@test "a generated mirror satisfies session_capture_audit.sh's check_mirrors" {
	AUDIT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/ai_clients/claude/hooks/session_capture_audit.sh"
	printf '# index\n- matches-repo.md\n' >"$BX_STORE/README.md"
	lesson "$BX_STORE" "matches-repo" "dotfiles-dev"
	run bash "$GEN" "$REPO"
	[ "$status" -eq 0 ]

	git -C "$REPO" init -q
	git -C "$REPO" remote add origin https://github.com/guilhermegor/dotfiles-dev.git
	run bash -c "cd '$REPO' && bash '$AUDIT' </dev/null"
	[ "$status" -eq 0 ]
	[[ "$output" != *"matches-repo.md' originated here but"* ]]
}
