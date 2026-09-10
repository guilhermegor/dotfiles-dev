#!/usr/bin/env bats
#
# Unit tests for tests/spec_audit_gate.sh
#
# Strategy: the gate is a plain CLI filter, not a PreToolUse hook -- it takes
# feature-dir arguments (plus an optional --tests-dir) and reports exit 0 = aligned,
# exit 1 = findings on stdout/stderr. Every test builds a throwaway
# .specs/features/<name>/ + tests/ tree under a temp dir (never the real repo) and
# asserts on exit status + output. Covers each of the five findings firing AND not
# firing, so the suite cannot pass by always reporting something.
#
# Run locally: bats tests/spec_audit_gate.bats

setup() {
    GATE="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/tests/spec_audit_gate.sh"

    TEST_TMP="$(mktemp -d)"
    FEATURE_DIR="$TEST_TMP/feature"
    TESTS_DIR="$TEST_TMP/tests"
    mkdir -p "$FEATURE_DIR" "$TESTS_DIR"
}

teardown() {
    rm -rf "$TEST_TMP"
}

write_spec() {
    printf '%s' "$1" > "$FEATURE_DIR/spec.md"
}

write_test_file() {
    printf '%s' "$1" > "$TESTS_DIR/feature.bats"
}

run_gate() {
    run bash "$GATE" --tests-dir "$TESTS_DIR" "$FEATURE_DIR"
}

WELL_FORMED_SPEC='# Gadget

## Acceptance Criteria
- AC-1: user can create a gadget
- AC-2: gadget list is paginated

## Assumptions
- ASM-1: the DB has a unique index on gadget name (resolved)

## Open Questions
- Q-1: is soft-delete required? (answered) no, hard delete only.
'

# ⚠️ Every `@test` inside a fixture string is INDENTED on purpose. bats counts a
# file's tests by scanning for `@test` at column 0, so an unindented fixture line
# is counted as a real test and never run — "Executed N-1 instead of expected N",
# which fails the suite. The gate scans for `@AC-<n>` anywhere on a line, so the
# indentation costs the fixture nothing.
WELL_FORMED_TESTS='  @test "@AC-1 creates a gadget" {
    true
  }
  @test "@AC-2 paginates the list" {
    true
  }
'

# --- the base case: a fully aligned feature -> ALIGNED (exit 0) ---------------------------------

@test "ALIGNED: a well-formed feature exits 0" {
    write_spec "$WELL_FORMED_SPEC"
    write_test_file "$WELL_FORMED_TESTS"

    run_gate
    [ "$status" -eq 0 ]
    [[ "$output" == *"aligned"* ]]
}

# --- AC_WITHOUT_TEST -------------------------------------------------------------------------

@test "AC_WITHOUT_TEST: fires when an AC has no matching test tag" {
    write_spec "$WELL_FORMED_SPEC"$'\n- AC-3: gadget can be deleted\n'
    write_test_file "$WELL_FORMED_TESTS"

    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *"AC_WITHOUT_TEST AC-3"* ]]
    [[ "$output" == *"spec.md:13:"* ]]
}

@test "AC_WITHOUT_TEST: does not fire when every AC has a matching tag" {
    write_spec "$WELL_FORMED_SPEC"
    write_test_file "$WELL_FORMED_TESTS"

    run_gate
    [[ "$output" != *"AC_WITHOUT_TEST"* ]]
}

# --- TEST_WITHOUT_AC -------------------------------------------------------------------------

@test "TEST_WITHOUT_AC: fires when a test tags an id the spec doesn't define" {
    write_spec "$WELL_FORMED_SPEC"
    write_test_file "$WELL_FORMED_TESTS"$'@test "@AC-99 stray" {\n  true\n}\n'

    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *"TEST_WITHOUT_AC @AC-99"* ]]
    [[ "$output" == *"feature.bats:7:"* ]]
}

@test "TEST_WITHOUT_AC: does not fire when every tag matches a defined AC" {
    write_spec "$WELL_FORMED_SPEC"
    write_test_file "$WELL_FORMED_TESTS"

    run_gate
    [[ "$output" != *"TEST_WITHOUT_AC"* ]]
}

# --- ASSUMPTION_OPEN -------------------------------------------------------------------------

@test "ASSUMPTION_OPEN: fires when an ASM entry lacks (resolved)" {
    write_spec "$WELL_FORMED_SPEC"$'\n- ASM-2: the queue is durable across restarts\n'
    write_test_file "$WELL_FORMED_TESTS"

    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *"ASSUMPTION_OPEN ASM-2"* ]]
    [[ "$output" == *"spec.md:13:"* ]]
}

@test "ASSUMPTION_OPEN: does not fire when the assumption is marked (resolved)" {
    write_spec "$WELL_FORMED_SPEC"
    write_test_file "$WELL_FORMED_TESTS"

    run_gate
    [[ "$output" != *"ASSUMPTION_OPEN"* ]]
}

# --- QUESTION_OPEN ---------------------------------------------------------------------------

@test "QUESTION_OPEN: fires when a Q entry lacks (answered)" {
    write_spec "$WELL_FORMED_SPEC"$'\n- Q-2: who owns the retention policy?\n'
    write_test_file "$WELL_FORMED_TESTS"

    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *"QUESTION_OPEN Q-2"* ]]
    [[ "$output" == *"spec.md:13:"* ]]
}

@test "QUESTION_OPEN: does not fire when the question is marked (answered)" {
    write_spec "$WELL_FORMED_SPEC"
    write_test_file "$WELL_FORMED_TESTS"

    run_gate
    [[ "$output" != *"QUESTION_OPEN"* ]]
}

# --- SECTION_MISSING ---------------------------------------------------------------------------

@test "SECTION_MISSING: fires when the assumptions heading is absent entirely" {
    write_spec '# Gadget

## Acceptance Criteria
- AC-1: user can create a gadget

## Open Questions
- Q-1: anything unresolved? (answered) no.
'
    write_test_file '@test "@AC-1 creates a gadget" {
  true
}
'

    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *"SECTION_MISSING"* ]]
    [[ "$output" == *"spec.md:1:"* ]]
}

@test "SECTION_MISSING: does not fire when the heading exists and says None" {
    write_spec '# Gadget

## Acceptance Criteria
- AC-1: user can create a gadget

## Assumptions

None.

## Open Questions

None.
'
    write_test_file '@test "@AC-1 creates a gadget" {
  true
}
'

    run_gate
    [[ "$output" != *"SECTION_MISSING"* ]]
    [ "$status" -eq 0 ]
}

# --- missing spec file entirely -----------------------------------------------------------------

@test "SECTION_MISSING: fires (only) when spec.md itself is absent" {
    write_test_file "$WELL_FORMED_TESTS"
    # No spec.md written at all.

    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *"SECTION_MISSING"* ]]
    [[ "$output" == *"spec.md not found"* ]]
}

# --- discovery + no-op cases ----------------------------------------------------------------

@test "an explicit feature dir with no spec.md -> SECTION_MISSING (exit 1)" {
    run bash "$GATE" --tests-dir "$TESTS_DIR" "$TEST_TMP/does-not-exist-either"
    # A caller-supplied path that doesn't exist has no spec.md -> SECTION_MISSING, not a no-op.
    [ "$status" -eq 1 ]
    [[ "$output" == *"SECTION_MISSING"* ]]
}

@test "default discovery (no feature-dir args): empty fixture tree -> exit 0" {
    # SPEC_AUDIT_GATE_SPECS_DIR overrides the default .specs/features/ lookup so this
    # never touches the real repo tree (only an empty temp dir here).
    run bash -c "SPEC_AUDIT_GATE_SPECS_DIR='$TEST_TMP/empty-specs' bash '$GATE'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No .specs/features/"* ]]
}

@test "default discovery (no feature-dir args): finds a fixture feature dir" {
    mkdir -p "$TEST_TMP/fixture-specs/gadget"
    printf '%s' "$WELL_FORMED_SPEC" > "$TEST_TMP/fixture-specs/gadget/spec.md"
    write_test_file "$WELL_FORMED_TESTS"

    run bash -c "SPEC_AUDIT_GATE_SPECS_DIR='$TEST_TMP/fixture-specs' \
        bash '$GATE' --tests-dir '$TESTS_DIR'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"aligned -- 1 feature(s) checked"* ]]
}
