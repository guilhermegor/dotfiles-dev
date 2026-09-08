#!/usr/bin/env bats
#
# Unit tests for _merge_dock_favorites, the helper configure_dock uses to
# preserve hand-pinned dock apps instead of clobbering them (issue #103).
#
# Strategy: source ubuntu_workspace.sh (guarded — sourcing never runs main()
# or touches gsettings, see the BASH_SOURCE guard at the bottom of the file)
# and exercise the pure _merge_dock_favorites helper directly. No gsettings
# mocking needed since the helper takes the "live" value as a plain string.
#
# Run locally: bats tests/

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

    # shellcheck source=../distro_config/ubuntu_workspace.sh
    source "$REPO_ROOT/distro_config/ubuntu_workspace.sh"
}

@test "_merge_dock_favorites preserves an existing pinned app not in the declared list" {
    local -a declared=("'spotify.desktop'" "'firefox.desktop'")
    local existing_str="['spotify.desktop', 'custom-app.desktop']"

    _merge_dock_favorites declared "$existing_str"

    [ "${#declared[@]}" -eq 3 ]
    [ "${declared[0]}" = "'spotify.desktop'" ]
    [ "${declared[1]}" = "'firefox.desktop'" ]
    [ "${declared[2]}" = "'custom-app.desktop'" ]
}

@test "_merge_dock_favorites is idempotent across repeated runs" {
    local -a first_run=("'spotify.desktop'" "'firefox.desktop'")
    local existing_str="['spotify.desktop', 'custom-app.desktop']"
    _merge_dock_favorites first_run "$existing_str"

    # Simulate the next `make run` invocation: declared favorites are rebuilt
    # fresh from scratch, and the "live" gsettings value is now whatever the
    # first run wrote (declared + the hand-pinned extra).
    local first_run_str
    first_run_str=$(IFS=,; echo "${first_run[*]}")

    local -a second_run=("'spotify.desktop'" "'firefox.desktop'")
    _merge_dock_favorites second_run "[${first_run_str}]"

    [ "${#second_run[@]}" -eq "${#first_run[@]}" ]
    local i
    for i in "${!first_run[@]}"; do
        [ "${second_run[$i]}" = "${first_run[$i]}" ]
    done
}
