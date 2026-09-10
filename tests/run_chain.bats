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

# ---------------------------------------------------------------------------
# Ordering (issue #298): the network-free, idempotent, $HOME/gsettings-only
# targets run ahead of the failure-prone installs, so a hang or failure
# further down the chain does not also cost them. These tests inspect the
# *default* RUN_CHAIN_TARGETS list, so each spawns a fresh bash process that
# sources lib/run_chain.sh with RUN_CHAIN_TARGETS unset — setup()'s stub
# override (alpha/beta/gamma) must not leak in.
# ---------------------------------------------------------------------------

# Print the default RUN_CHAIN_TARGETS array, one target per line.
default_chain_targets() {
    bash -c '
        unset RUN_CHAIN_TARGETS
        # shellcheck source=../lib/run_chain.sh
        source "'"$REPO_ROOT"'/lib/run_chain.sh"
        printf "%s\n" "${RUN_CHAIN_TARGETS[@]}"
    '
}

# Index (0-based) of $1 in the newline-separated target list $2.
target_index() {
    local target="$1" list="$2"
    local i=0 line
    while IFS= read -r line; do
        [ "$line" = "$target" ] && { echo "$i"; return 0; }
        i=$((i + 1))
    done <<< "$list"
    return 1
}

@test "default chain: bash_profile and set_shortcuts run before every install target" {
    run default_chain_targets
    [ "$status" -eq 0 ]
    local targets="$output"

    local bash_profile_idx set_shortcuts_idx
    bash_profile_idx="$(target_index bash_profile "$targets")"
    set_shortcuts_idx="$(target_index set_shortcuts "$targets")"

    local installer
    for installer in install_programs install_espanso_packages install_coding editors_setup; do
        local installer_idx
        installer_idx="$(target_index "$installer" "$targets")"
        [ "$bash_profile_idx" -lt "$installer_idx" ]
        [ "$set_shortcuts_idx" -lt "$installer_idx" ]
    done
}

@test "default chain: install_coding runs before ai_clients (claude CLI prerequisite)" {
    run default_chain_targets
    [ "$status" -eq 0 ]
    local targets="$output"

    local install_coding_idx ai_clients_idx
    install_coding_idx="$(target_index install_coding "$targets")"
    ai_clients_idx="$(target_index ai_clients "$targets")"
    [ "$install_coding_idx" -lt "$ai_clients_idx" ]
}

@test "default chain: install_coding runs before editors_setup (VS Code prerequisite)" {
    run default_chain_targets
    [ "$status" -eq 0 ]
    local targets="$output"

    local install_coding_idx editors_setup_idx
    install_coding_idx="$(target_index install_coding "$targets")"
    editors_setup_idx="$(target_index editors_setup "$targets")"
    [ "$install_coding_idx" -lt "$editors_setup_idx" ]
}

@test "default chain: install_programs runs before install_espanso_packages (espanso prerequisite)" {
    run default_chain_targets
    [ "$status" -eq 0 ]
    local targets="$output"

    local install_programs_idx install_espanso_packages_idx
    install_programs_idx="$(target_index install_programs "$targets")"
    install_espanso_packages_idx="$(target_index install_espanso_packages "$targets")"
    [ "$install_programs_idx" -lt "$install_espanso_packages_idx" ]
}

@test "default chain: ubuntu_workspace stays last (needs the full installed app set)" {
    run default_chain_targets
    [ "$status" -eq 0 ]
    local targets="$output"
    local last
    last="$(echo "$targets" | tail -n 1)"
    [ "$last" = "ubuntu_workspace" ]
}
