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

# rclone is on PATH on a machine that already has it installed (/usr/bin/rclone), so a test
# that needs "not installed" cannot rely on the stub directory being absent. Hide it
# explicitly, delegating every other name to the real check.
_hide_rclone() {
    command_exists() { [ "$1" = rclone ] && return 1; command -v "$1" &>/dev/null; }
}

teardown() {
    rm -rf "$TMP"
}

# refute_rclone_log PATTERN
# Asserts PATTERN never appears in the fake rclone's invocation log. NOT
# `! grep -q …`: bash exempts a `!`-inverted command from `set -e`, so such
# a line is not a real assertion unless it happens to be the test's last
# statement (issue #380).
refute_rclone_log() {
    run grep -q -- "$1" "$RCLONE_LOG"
    [ "$status" -ne 0 ]
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
    _hide_rclone
    INSTALL_CMD="false"
    run install_rclone
    [ "$status" -eq 1 ]
}

@test "install_rclone returns 1 when rclone is still not on PATH after a reported install" {
    _hide_rclone
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
        refute_rclone_log '^config'
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
    _hide_rclone
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
    # The directives (from [Unit] onward) are fully substituted; the header
    # comments above them deliberately keep the literal placeholders (#365
    # — asserted separately below).
    local directives
    directives="$(sed -n '/^\[Unit\]/,$p' "$unit")"
    [[ "$directives" != *'{{'* ]]
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

# --- issue #365: default mount point, folder creation, non-empty refusal ---

@test "install_rclone_mount_unit creates the mount point folder when absent" {
    _write_rclone_stub
    [ ! -d "$HOME/OneDrive" ]

    run install_rclone_mount_unit "onedrive" "$HOME/OneDrive"

    [ "$status" -eq 0 ]
    [ -d "$HOME/OneDrive" ]
    [ -f "$HOME/.config/systemd/user/rclone-onedrive.service" ]
}

@test "install_rclone_mount_unit refuses when the mount point exists and is non-empty" {
    _write_rclone_stub
    mkdir -p "$HOME/OneDrive"
    echo "keep me" > "$HOME/OneDrive/existing-file.txt"

    run install_rclone_mount_unit "onedrive" "$HOME/OneDrive"

    [ "$status" -ne 0 ]
    [[ "$output" == *"not empty"* ]]
    [ -f "$HOME/OneDrive/existing-file.txt" ]
    [ ! -f "$HOME/.config/systemd/user/rclone-onedrive.service" ]
}

@test "install_rclone_mount_unit falls back to RCLONE_REMOTE and RCLONE_MOUNT_POINT env vars" {
    _write_rclone_stub
    export RCLONE_REMOTE="workdrive"
    export RCLONE_MOUNT_POINT="$HOME/WorkDrive"

    run install_rclone_mount_unit

    [ "$status" -eq 0 ]
    [ -d "$HOME/WorkDrive" ]
    local unit="$HOME/.config/systemd/user/rclone-workdrive.service"
    [ -f "$unit" ]
    grep -qF "rclone mount workdrive: $HOME/WorkDrive" "$unit"
}

@test "install_rclone_mount_unit default with no args and no env vars uses onedrive / ~/OneDrive" {
    _write_rclone_stub

    run install_rclone_mount_unit

    [ "$status" -eq 0 ]
    [ -d "$HOME/OneDrive" ]
    [ -f "$HOME/.config/systemd/user/rclone-onedrive.service" ]
}

@test "install_rclone_mount_unit keeps the header placeholders literal after substitution" {
    _write_rclone_stub

    install_rclone_mount_unit "onedrive" "$HOME/OneDrive"

    local unit="$HOME/.config/systemd/user/rclone-onedrive.service"
    local header
    header="$(sed -n '1,/^\[Unit\]/p' "$unit")"
    [[ "$header" == *"{{REMOTE}}"* ]]
    [[ "$header" == *"{{MOUNTPOINT}}"* ]]
    grep -qF "AssertPathIsDirectory=$HOME/OneDrive" "$unit"
    grep -qF "Description=rclone on-demand mount: onedrive" "$unit"
}

# --- issue #365: rclone.conf skeleton, mode 600, no overwrite, reconnect ----

@test "install_rclone_config writes the skeleton with mode 600" {
    _write_rclone_stub

    run install_rclone_config "onedrive" "onedrive" "global" < /dev/null

    [ "$status" -eq 0 ]
    local conf="$HOME/.config/rclone/rclone.conf"
    [ -f "$conf" ]
    grep -qF "[onedrive]" "$conf"
    grep -qF "type = onedrive" "$conf"
    grep -qF "region = global" "$conf"
    [ "$(stat -c '%a' "$conf")" = "600" ]
}

@test "install_rclone_config refuses to overwrite an existing rclone.conf" {
    _write_rclone_stub
    mkdir -p "$HOME/.config/rclone"
    printf '[onedrive]\ntype = onedrive\ntoken = {"already":"configured"}\n' \
        > "$HOME/.config/rclone/rclone.conf"

    run install_rclone_config "onedrive" < /dev/null

    [ "$status" -ne 0 ]
    grep -qF 'token' "$HOME/.config/rclone/rclone.conf"
}

@test "install_rclone_config skips the browser reconnect and prints the command when not interactive" {
    _write_rclone_stub

    run install_rclone_config "onedrive" < /dev/null

    [ "$status" -eq 0 ]
    [[ "$output" == *"rclone config reconnect onedrive:"* ]]
    if [ -f "$RCLONE_LOG" ]; then
        refute_rclone_log '^config reconnect'
    fi
}

@test "install_rclone_config invokes only 'rclone config reconnect', never the bare wizard" {
    # The bare 'rclone config' wizard is what offers "set configuration
    # password", which the systemd mount cannot unlock at boot (#365).
    local fn
    fn="$(sed -n '/^install_rclone_config()/,/^}/p' "$REPO_ROOT/distro_config/install_lib/sharing.sh")"
    [[ "$fn" == *'rclone config reconnect'* ]]
    [[ "$fn" != *'run_or_echo rclone config"'* ]]
}
