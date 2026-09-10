#!/bin/bash
#
# lib/run_chain.sh
#
# Drives the `make run` target chain with -k-style resilience: a failing
# target does not stop the ones after it, and the run still reports (and
# exits non-zero) when anything failed. Mirrors run_install/report_failures
# from distro_config/install_lib/_common.sh — same collect-into-array +
# report-at-the-end shape, renamed for the target-chain domain instead of
# inventing a second idiom.
#
# Overridable (tests use this to stub the chain instead of invoking the
# real installers):
#   MAKE_BIN          — the make binary to invoke (default: make)
#   RUN_CHAIN_TARGETS — array of target names to run, in order
#                       (default: the 14 `make run` targets)
#
# Ordering (issue #298): the network-free, idempotent, $HOME/gsettings-only
# targets `bash_profile` and `set_shortcuts` run early, ahead of the
# long/failure-prone installs, so a hang or failure further down the chain
# (#299 makes a *failure* non-fatal, but not a *hang*) does not also cost
# them. `ubuntu_workspace` stays last on purpose: it places .desktop entries
# for apps the installs above provide (distro_config/ubuntu_workspace.sh
# find_desktop_file), so moving it earlier means placing against a smaller
# app set. Every other target's position is unchanged — each was verified
# against the code it depends on (see PR #298 description), not assumed.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -euo pipefail
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

MAKE_BIN="${MAKE_BIN:-make}"

# ponytail: each target below is now its own `make` invocation (needed so a
# failure in one can be caught without aborting the rest), so `editors_setup`
# re-runs its own prereqs (vscode_setup, ai_clients) even though ai_clients
# already ran earlier in this list. Both are idempotent, so it's a redundant
# re-check, not a double install — the single-process prereq dedup a plain
# `make run` used to get for free. Upgrade to a shared "already ran" marker
# if that redundancy ever gets expensive.
if [ -z "${RUN_CHAIN_TARGETS+set}" ]; then
    RUN_CHAIN_TARGETS=(
        banner
        restore_env_prompt
        permissions
        setup_env
        bash_profile
        set_shortcuts
        install_programs
        install_espanso_packages
        install_coding
        ai_clients
        starship_setup
        editors_setup
        irpf_download
        ubuntu_workspace
    )
fi

RUN_FAILURES=()

# Run one make target; a failure is caught and recorded, never propagated.
run_target() {
    local target="$1"

    if ( set -e; "$MAKE_BIN" "$target" ); then
        return 0
    else
        local rc=$?
        RUN_FAILURES+=("$target")
        print_status "warning" "Failed: $target (exit code $rc) — continuing"
        return 0
    fi
}

# Print a summary of any targets that failed during this run.
report_run_failures() {
    if [ ${#RUN_FAILURES[@]} -eq 0 ]; then
        print_status "success" "All run targets completed without errors"
        return 0
    fi

    print_status "section" "RUN FAILURES"
    print_status "warning" "${#RUN_FAILURES[@]} target(s) failed:"
    local f
    for f in "${RUN_FAILURES[@]}"; do
        print_status "error" "  - $f"
    done
}

main() {
    local target
    for target in "${RUN_CHAIN_TARGETS[@]}"; do
        run_target "$target"
    done

    report_run_failures

    [ ${#RUN_FAILURES[@]} -eq 0 ]
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
