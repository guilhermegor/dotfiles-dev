#!/usr/bin/env bats
#
# Unit tests for _reset_orphaned_app_folders, the helper organize_app_folders
# uses (issue #293) to reset the relocatable-schema state of any app-folder id
# a run no longer produces, before writing the new folder-children list.
#
# Strategy: source ubuntu_workspace.sh (guarded — sourcing never runs main()
# or touches gsettings) and exercise the pure _reset_orphaned_app_folders
# helper directly. BOTH external commands it consults are stubbed so no test
# ever touches live dconf state:
#   * `gsettings` — the write path (reset-recursively), logged not executed;
#   * `dconf`     — the read path (which folder ids actually exist).
# Stubbing only the first is not enough: the helper enumerates candidates from
# `dconf list`, so an unstubbed `dconf` makes every test read the developer's
# real folder set and assert against it.
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

    # Stub: the set of folder ids "defined in dconf". Each test sets
    # DCONF_FOLDERS to the ids it wants to exist, in `dconf list` format.
    DCONF_FOLDERS=""
    export DCONF_FOLDERS
    dconf() {
        if [ "$1" = "list" ]; then
            local id
            for id in $DCONF_FOLDERS; do echo "$id/"; done
        fi
    }
    export -f dconf

    # shellcheck source=../distro_config/ubuntu_workspace.sh
    source "$REPO_ROOT/distro_config/ubuntu_workspace.sh"
}

teardown() {
    rm -f "$GSETTINGS_LOG"
}

@test "_reset_orphaned_app_folders resets an id present before the run and absent from the produced set" {
    DCONF_FOLDERS="Sistema DEV Code"
    local -a produced=("'Sistema'" "'Code'")
    _reset_orphaned_app_folders produced "['Sistema', 'DEV', 'Code']"

    run grep -c "reset-recursively.*folders/DEV/" "$GSETTINGS_LOG"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "_reset_orphaned_app_folders never resets an id this run produced (fail-open)" {
    DCONF_FOLDERS="Sistema Code"
    local -a produced=("'Sistema'" "'Code'")
    _reset_orphaned_app_folders produced "['Sistema', 'Code']"

    [ ! -s "$GSETTINGS_LOG" ]
}

@test "_reset_orphaned_app_folders performs no reset under DRY_RUN=1" {
    export DRY_RUN=1
    DCONF_FOLDERS="Sistema DEV"
    local -a produced=("'Sistema'")
    _reset_orphaned_app_folders produced "['Sistema', 'DEV']"

    [ ! -s "$GSETTINGS_LOG" ]
}

# --- the gap PR #294 left: an ALREADY-orphaned id ------------------------------
# An orphan is by definition absent from folder-children, so a candidate set
# derived from folder-children can only ever catch the id on the single run that
# drops it. This is the regression guard for that: DEV exists in dconf and is
# NOT in folder-children, which is exactly the state the first fix could not see.

@test "resets a PRE-EXISTING orphan: in dconf, already absent from folder-children" {
    DCONF_FOLDERS="Sistema Code DEV Newsletter"
    local -a produced=("'Sistema'" "'Code'")
    _reset_orphaned_app_folders produced "['Sistema', 'Code']"

    run grep -c "reset-recursively.*folders/DEV/" "$GSETTINGS_LOG"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]

    run grep -c "reset-recursively.*folders/Newsletter/" "$GSETTINGS_LOG"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

# --- the allowlist is what keeps this a cleanup and not a dconf sweep ----------

@test "never resets an id this script never created (distro/GNOME stock folders)" {
    DCONF_FOLDERS="Sistema Pardus YaST Utilities"
    local -a produced=("'Sistema'")
    _reset_orphaned_app_folders produced "['Sistema']"

    [ ! -s "$GSETTINGS_LOG" ]
}

@test "never resets a folder the user created by hand in the Shell" {
    DCONF_FOLDERS="Sistema MinhaPastaPessoal"
    local -a produced=("'Sistema'")
    _reset_orphaned_app_folders produced "['Sistema']"

    [ ! -s "$GSETTINGS_LOG" ]
}

@test "falls back to folder-children when dconf is unavailable" {
    # Simulate a machine with no dconf CLI: the helper degrades to the
    # transition-only behaviour rather than doing nothing at all.
    command_exists() { [ "$1" != "dconf" ]; }
    export -f command_exists

    local -a produced=("'Sistema'")
    _reset_orphaned_app_folders produced "['Sistema', 'DEV']"

    run grep -c "reset-recursively.*folders/DEV/" "$GSETTINGS_LOG"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}
