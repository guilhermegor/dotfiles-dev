#!/usr/bin/env bats
#
# Resilience for issue #298 (a mid-chain failure in `make run` costs every
# target after it).
#
# lib/run_chain.sh drives the `make run` target chain: a failing target must
# not stop the ones after it, the end-of-run summary must name it, and the
# overall exit status must still be non-zero. Mirrors run_install /
# report_failures (distro_config/install_lib/_common.sh) — collect failures
# into an array, report them at the end.
#
# Never invokes the real installers: MAKE_BIN points at a stub "make" script
# that just records which fake target it was called with, and
# RUN_CHAIN_TARGETS overrides the real 14-target chain with fake names.
#
# Run locally: bats tests/

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK_DIR="$(mktemp -d)"
    CALL_LOG="$WORK_DIR/calls.log"

    # Stub `make`: records the target it was asked to build, then succeeds
    # unless the target name is listed in $FAIL_TARGETS (space-separated).
    STUB_MAKE="$WORK_DIR/fake_make.sh"
    cat > "$STUB_MAKE" <<'EOF'
#!/bin/bash
echo "$1" >> "$CALL_LOG"
for bad in ${FAIL_TARGETS:-}; do
    [ "$1" = "$bad" ] && exit 1
done
exit 0
EOF
    chmod +x "$STUB_MAKE"

    export CALL_LOG
    export MAKE_BIN="$STUB_MAKE"
    RUN_CHAIN_TARGETS=(alpha beta gamma)

    # shellcheck source=../lib/run_chain.sh
    source "$REPO_ROOT/lib/run_chain.sh"
}

teardown() {
    rm -rf "$WORK_DIR"
}

@test "a failing target does not stop later targets from running" {
    FAIL_TARGETS="beta" run main
    [ "$(cat "$CALL_LOG")" = "$(printf 'alpha\nbeta\ngamma')" ]
}

@test "the summary names the failed target" {
    FAIL_TARGETS="beta" run main
    [[ "$output" == *"beta"* ]]
}

@test "the overall exit status is non-zero when a target failed" {
    FAIL_TARGETS="beta" run main
    [ "$status" -ne 0 ]
}

@test "a fully successful run prints no failure summary and exits 0" {
    run main
    [ "$status" -eq 0 ]
    [[ "$output" != *"RUN FAILURES"* ]]
    [[ "$output" == *"All run targets completed without errors"* ]]
}
