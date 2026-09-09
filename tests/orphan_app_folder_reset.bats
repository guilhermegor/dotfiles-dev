#!/usr/bin/env bats
#
# Unit tests for _reset_orphaned_app_folders, the helper organize_app_folders
# uses (issue #293) to reset the relocatable-schema state of any app-folder id
# a run no longer produces, before writing the new folder-children list.
#
# Strategy: source ubuntu_workspace.sh (guarded — sourcing never runs main()
# or touches gsettings) and exercise the pure _reset_orphaned_app_folders
# helper directly, with a stubbed `gsettings` shell function so no test ever
# touches live dconf state.
#
# Run locally: bats tests/

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

    GSETTINGS_LOG="$(mktemp)"
    export GSETTINGS_LOG

    # Stub: log every invocation instead of touching real dconf.
    gsettings() {
        echo "$*" >> "$GSETTINGS_LOG"
    }
    export -f gsettings

    # shellcheck source=../distro_config/ubuntu_workspace.sh
    source "$REPO_ROOT/distro_config/ubuntu_workspace.sh"
}

teardown() {
    rm -f "$GSETTINGS_LOG"
}

@test "_reset_orphaned_app_folders resets an id present before the run and absent from the produced set" {
    local -a produced=("'Sistema'" "'Code'")
    _reset_orphaned_app_folders produced "['Sistema', 'DEV', 'Code']"

    run grep -c "reset-recursively.*folders/DEV/" "$GSETTINGS_LOG"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "_reset_orphaned_app_folders never resets an id this run produced (fail-open)" {
    local -a produced=("'Sistema'" "'Code'")
    _reset_orphaned_app_folders produced "['Sistema', 'Code']"

    [ ! -s "$GSETTINGS_LOG" ]
}

@test "_reset_orphaned_app_folders performs no reset under DRY_RUN=1" {
    export DRY_RUN=1
    local -a produced=("'Sistema'")
    _reset_orphaned_app_folders produced "['Sistema', 'DEV']"

    [ ! -s "$GSETTINGS_LOG" ]
}
