#!/usr/bin/env bats
#
# Unit tests for install_rclone / install_rclone_mount_unit (issue #360:
# replace Insync with an on-demand rclone mount).
#
# Strategy: throwaway $HOME, rclone/systemctl stubbed on PATH, no network,
# no root, no real ~/.config/rclone/ ever touched. install_rclone must never
# invoke `rclone config` (interactive, account-bound — operator work), and
# install_rclone_mount_unit must never invoke systemctl enable/start.
#
# Run locally: bats tests/

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TMP="$(mktemp -d)"
    HOME="$TMP/home"
    mkdir -p "$HOME"
    export HOME
    export LOG_FILE="$TMP/log"
    export RCLONE_LOG="$TMP/rclone_invocations.log"
    mkdir -p "$TMP/bin"
    export PATH="$TMP/bin:$PATH"

    # shellcheck source=../distro_config/install_lib/_common.sh
    source "$REPO_ROOT/distro_config/install_lib/_common.sh"
    PACKAGE_MANAGER="apt"

    # shellcheck source=../distro_config/install_lib/sharing.sh
    source "$REPO_ROOT/distro_config/install_lib/sharing.sh"
}

teardown() {
    rm -rf "$TMP"
}

_write_rclone_stub() {
    cat > "$TMP/bin/rclone" <<STUB
#!/bin/bash
echo "\$*" >> "$RCLONE_LOG"
case "\$1" in
    version) echo "rclone v1.60.1" ;;
    *) exit 0 ;;
esac
STUB
    chmod +x "$TMP/bin/rclone"
}

# --- install failure returns non-zero (#343 shape) ---------------------------

@test "install_rclone returns 1 when the package manager install fails" {
    INSTALL_CMD="false"
    run install_rclone
    [ "$status" -eq 1 ]
}

@test "install_rclone returns 1 when rclone is still not on PATH after a reported install" {
    INSTALL_CMD="true"
    run install_rclone
    [ "$status" -eq 1 ]
}

# --- install success path, and it never touches rclone config ---------------

@test "install_rclone succeeds and never invokes 'rclone config'" {
    _write_rclone_stub
    INSTALL_CMD="true"
    run install_rclone
    [ "$status" -eq 0 ]
    if [ -f "$RCLONE_LOG" ]; then
        ! grep -q '^config' "$RCLONE_LOG"
    fi
}

@test "install_rclone never writes anything under ~/.config/rclone" {
    _write_rclone_stub
    INSTALL_CMD="true"
    install_rclone
    [ ! -d "$HOME/.config/rclone" ]
}

@test "install_rclone is a no-op re-install when rclone already exists" {
    _write_rclone_stub
    INSTALL_CMD="false"
    run install_rclone
    [ "$status" -eq 0 ]
}

# --- registry entry shape (#357: CLI tool, empty gnome_folder/desktop_file) --

@test "INSTALL_REGISTRY has an install_rclone entry with empty folder and desktop fields" {
    local entry fn label folder desktop found=0
    for entry in "${INSTALL_REGISTRY[@]}"; do
        if [[ "$entry" == install_rclone:* ]]; then
            found=1
            IFS=':' read -r fn label folder desktop <<< "$entry"
            [ -z "$folder" ]
            [ -z "$desktop" ]
        fi
    done
    [ "$found" -eq 1 ]
}

@test "validate_registry passes with install_rclone registered" {
    run validate_registry
    [ "$status" -eq 0 ]
}

# --- install_rclone_mount_unit: writes but never enables/starts -------------

@test "install_rclone_mount_unit refuses without remote or mountpoint" {
    _write_rclone_stub
    run install_rclone_mount_unit "" ""
    [ "$status" -ne 0 ]
}

@test "install_rclone_mount_unit refuses when rclone is not installed" {
    run install_rclone_mount_unit "gdrive" "$HOME/GoogleDrive"
    [ "$status" -ne 0 ]
}

@test "install_rclone_mount_unit refuses to target ~/Insync as the mountpoint" {
    _write_rclone_stub
    run install_rclone_mount_unit "gdrive" "$HOME/Insync"
    [ "$status" -ne 0 ]
}

@test "install_rclone_mount_unit writes the unit with remote and mountpoint substituted" {
    _write_rclone_stub
    mkdir -p "$HOME/GoogleDrive"
    install_rclone_mount_unit "gdrive" "$HOME/GoogleDrive"

    local unit="$HOME/.config/systemd/user/rclone-gdrive.service"
    [ -f "$unit" ]
    grep -qF "rclone mount gdrive: $HOME/GoogleDrive" "$unit"
    ! grep -q '{{' "$unit"
}

@test "install_rclone_mount_unit never enables or starts the unit" {
    cat > "$TMP/bin/systemctl" <<STUB
#!/bin/bash
echo "\$*" >> "$TMP/systemctl_invocations.log"
STUB
    chmod +x "$TMP/bin/systemctl"
    _write_rclone_stub
    mkdir -p "$HOME/GoogleDrive"

    install_rclone_mount_unit "gdrive" "$HOME/GoogleDrive"

    [ ! -f "$TMP/systemctl_invocations.log" ]
}
