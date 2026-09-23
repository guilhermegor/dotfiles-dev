#!/usr/bin/env bats
#
# Sloppy focus (issue #478): scrolling/interacting with the window under the
# pointer must not require clicking it first, and auto-raise must stay off —
# with sloppy focus, auto-raise true makes windows jump to front on hover,
# the pairing that gives sloppy focus its bad reputation.
#
# Strategy: grep the real script for both run_or_echo gsettings calls, on the
# org.gnome.desktop.wm.preferences schema the file already owns (theme,
# button-layout). No live dconf is touched.
#
# Run locally: bats tests/

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPT="$REPO_ROOT/distro_config/ubuntu_workspace.sh"
}

@test "focus-mode is set to sloppy via run_or_echo" {
    grep -qF \
        "run_or_echo gsettings set org.gnome.desktop.wm.preferences focus-mode 'sloppy'" \
        "$SCRIPT"
}

@test "auto-raise is explicitly set to false via run_or_echo" {
    grep -qF \
        "run_or_echo gsettings set org.gnome.desktop.wm.preferences auto-raise false" \
        "$SCRIPT"
}
