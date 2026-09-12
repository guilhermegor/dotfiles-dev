#!/usr/bin/env bats
#
# Invariant for issue #114 (GNOME app folders regrouped by artifact produced).
#
# Folder placement is driven by TWO sources that must stay in sync: the
# `gnome_folder` field on INSTALL_REGISTRY entries, and the folder IDs that
# organize_app_folders() actually creates (gsettings folder-children) in
# distro_config/ubuntu_workspace.sh. Renaming/removing a folder in one place
# but not the other silently drops apps from the GNOME app grid — this test
# catches that drift.
#
# Sourcing (not executing) ubuntu_workspace.sh populates INSTALL_REGISTRY
# from install_lib/*.sh + install_coding_lib/*.sh and defines
# organize_app_folders() without running main() or touching gsettings.
#
# Run locally: bats tests/

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

    HOME="$(mktemp -d)"
    export HOME
    export DRY_RUN=1

    # shellcheck source=../distro_config/ubuntu_workspace.sh
    source "$REPO_ROOT/distro_config/ubuntu_workspace.sh"
}

teardown() {
    rm -rf "$HOME"
}

@test "organize_app_folders creates at least one folder" {
    local created
    created=$(declare -f organize_app_folders | grep -oE "folder_ids\+=\(\"'[A-Za-z]+'\"\)")
    [ -n "$created" ]
}

@test "every non-empty INSTALL_REGISTRY gnome_folder is a folder organize_app_folders creates" {
    local created
    created=$(declare -f organize_app_folders \
        | grep -oE "folder_ids\+=\(\"'[A-Za-z]+'\"\)" \
        | grep -oE "'[A-Za-z]+'" \
        | tr -d "'")

    local entry fn _label folder _desktop
    for entry in "${INSTALL_REGISTRY[@]}"; do
        IFS=':' read -r fn _label folder _desktop <<< "$entry"
        [ -z "$folder" ] && continue
        if ! grep -qx "$folder" <<< "$created"; then
            echo "gnome_folder '$folder' (from '$fn') is not created by organize_app_folders" >&2
            return 1
        fi
    done
}

# Issue #342: an uninstall_* entry placed after its install_* counterpart in
# INSTALL_REGISTRY runs during Full Installation too (entry order = run
# order), immediately undoing the install it just did. Uninstallers must stay
# plain functions the user invokes manually, never registry entries.
@test "no INSTALL_REGISTRY entry runs an uninstall_* function in Full Installation" {
    local entry fn _label _folder _desktop
    for entry in "${INSTALL_REGISTRY[@]}"; do
        IFS=':' read -r fn _label _folder _desktop <<< "$entry"
        if [[ "$fn" == uninstall_* ]]; then
            echo "INSTALL_REGISTRY runs '$fn' during Full Installation — uninstallers must not be registered" >&2
            return 1
        fi
    done
}
