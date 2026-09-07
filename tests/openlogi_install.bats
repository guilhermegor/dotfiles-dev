#!/usr/bin/env bats
#
# Unit tests for the Solaar -> openlogi swap (issues #235, #236, #237).
#
# Strategy: source the real install_lib/_common.sh + system_utils.sh and
# assert on the resulting function/registry state, plus the tracked
# config.toml symlink behaviour. No test invokes install_openlogi() itself
# (that would download/apt-install for real), only the pure _link_openlogi_config
# helper against a throwaway $HOME.
#
# Run locally: bats tests/

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

    HOME="$(mktemp -d)"
    export HOME

    # shellcheck source=../distro_config/install_lib/_common.sh
    source "$REPO_ROOT/distro_config/install_lib/_common.sh"
    PACKAGE_MANAGER="apt"
    INSTALL_CMD="run_or_echo sudo apt-get install -y"

    # shellcheck source=../distro_config/install_lib/system_utils.sh
    source "$REPO_ROOT/distro_config/install_lib/system_utils.sh"
}

teardown() {
    rm -rf "$HOME"
}

# --- openlogi is wired up -----------------------------------------------------

@test "install_openlogi and verify_openlogi are defined" {
    declare -F install_openlogi
    declare -F verify_openlogi
}

@test "INSTALL_REGISTRY has an install_openlogi entry" {
    local found=0
    for entry in "${INSTALL_REGISTRY[@]}"; do
        [[ "$entry" == install_openlogi:* ]] && found=1
    done
    [ "$found" -eq 1 ]
}

@test "validate_registry passes with install_openlogi registered" {
    run validate_registry
    [ "$status" -eq 0 ]
}

@test "the tracked openlogi config.toml exists in the repo" {
    [ -f "$REPO_ROOT/distro_config/dotfiles/openlogi/config.toml" ]
}

@test "_link_openlogi_config symlinks the tracked config.toml into place" {
    _link_openlogi_config
    [ -L "$HOME/.config/openlogi/config.toml" ]
    [ "$(readlink -f "$HOME/.config/openlogi/config.toml")" = \
      "$(readlink -f "$REPO_ROOT/distro_config/dotfiles/openlogi/config.toml")" ]
}

@test "_link_openlogi_config backs up a pre-existing non-symlink config" {
    mkdir -p "$HOME/.config/openlogi"
    echo "pre-existing" > "$HOME/.config/openlogi/config.toml"

    _link_openlogi_config

    [ -L "$HOME/.config/openlogi/config.toml" ]
    compgen -G "$HOME/.config/openlogi/config.toml.bak.*" > /dev/null
}

# --- Solaar is fully removed ---------------------------------------------------

@test "install_solaar no longer exists" {
    ! declare -F install_solaar
}

@test "INSTALL_REGISTRY has no solaar entry" {
    local entry
    for entry in "${INSTALL_REGISTRY[@]}"; do
        [[ "$entry" != *solaar* ]]
    done
}

@test "the utilities rollup no longer installs solaar" {
    ! grep -q "solaar" "$REPO_ROOT/distro_config/install_lib/system_utils.sh"
}

@test "ubuntu_workspace.sh no longer places a solaar .desktop entry" {
    ! grep -q "solaar" "$REPO_ROOT/distro_config/ubuntu_workspace.sh"
}
