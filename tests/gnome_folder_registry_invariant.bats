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

# A snap's .desktop file is named `<snap>_<app>.desktop`, never `<app>.desktop`. Declaring the
# unmangled name places nothing: figma-linux sat loose in the app grid for as long as the registry
# said `figma-linux.desktop` while snapd had written `figma-linux_figma-linux.desktop`.
# Enforced only where snap is the SOLE install method — when a function can also install via
# flatpak/apt/.deb, which id is correct depends on the path that ran, so it cannot be decided here.
@test "a snap-only registry app declares the snap-mangled <snap>_*.desktop id" {
    local entry fn _label _folder desktop body snap others bad=""
    for entry in "${INSTALL_REGISTRY[@]}"; do
        IFS=':' read -r fn _label _folder desktop <<< "$entry"
        [ -n "$desktop" ] || continue
        body="$(declare -f "$fn" 2>/dev/null)" || continue
        snap="$(grep -oE 'snap install( --classic)? [a-z0-9-]+' <<<"$body" | awk '{print $NF}' | head -n1)"
        [ -n "$snap" ] || continue
        others="$(grep -cE 'flatpak install|apt(-get)? install|dpkg -i|\.deb' <<<"$body" || true)"
        [ "$others" -eq 0 ] || continue
        [[ "$desktop" == "${snap}_"*.desktop ]] || bad+=" $fn($desktop, snap=$snap)"
    done
    [ -z "$bad" ] || { echo "snap-only apps with an unmangled desktop id:$bad"; return 1; }
}

@test "an unresolved registry desktop id is reported, not dropped in silence" {
    local fn_body
    fn_body="$(declare -f organize_app_folders)"
    [[ "$fn_body" == *'MISSING_DESKTOP_IDS+=('* ]]
    [[ "$fn_body" == *'Registry apps not placed'* ]]
}
