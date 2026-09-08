#!/usr/bin/env bats
#
# Unit tests for distro_config/setup_env.sh's ~/.claude/.env generation
# (issue #258, items 2 and 3).
#
# Context: the project-root .env is the single AUTHORED source of truth;
# ~/.claude/.env is a file setup_env.sh GENERATES from it, so the two files
# cannot drift. Both must land mode 600 — they hold credentials.
#
# Strategy: never touch the real .env / ~/.claude/.env. Build a throwaway
# "fake repo" tree (distro_config/setup_env.sh + lib/common.sh copied from
# the real repo, so REPO_ROOT — derived from the script's own path — resolves
# inside the sandbox) with a fixture .env holding placeholder keys only, then
# run the real script as a subprocess against a throwaway $HOME.
#
# Run locally: bats tests/   (install with: sudo apt-get install -y bats)

setup() {
    REPO_ROOT_REAL="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

    FAKE_REPO="$(mktemp -d)"
    mkdir -p "$FAKE_REPO/distro_config" "$FAKE_REPO/lib"
    cp "$REPO_ROOT_REAL/distro_config/setup_env.sh" "$FAKE_REPO/distro_config/setup_env.sh"
    cp "$REPO_ROOT_REAL/lib/common.sh" "$FAKE_REPO/lib/common.sh"

    printf 'FIXTURE_KEY=fixture-value\nANOTHER_KEY=another-fixture\n' > "$FAKE_REPO/.env"

    HOME="$(mktemp -d)"
    export HOME
}

teardown() {
    rm -rf "$FAKE_REPO" "$HOME"
}

@test "generates ~/.claude/.env whose contents match the project .env" {
    run bash "$FAKE_REPO/distro_config/setup_env.sh"
    [ "$status" -eq 0 ]
    [ -f "$HOME/.claude/.env" ]

    # Drop the generator's leading "do not edit by hand" comment line before comparing.
    run tail -n +2 "$HOME/.claude/.env"
    [ "$status" -eq 0 ]
    [ "$output" = "$(cat "$FAKE_REPO/.env")" ]
}

@test "generated ~/.claude/.env is mode 600" {
    run bash "$FAKE_REPO/distro_config/setup_env.sh"
    [ "$status" -eq 0 ]
    [ "$(stat -c '%a' "$HOME/.claude/.env")" = "600" ]
}

@test "regenerating after the project .env changes overwrites the old copy (no drift)" {
    run bash "$FAKE_REPO/distro_config/setup_env.sh"
    [ "$status" -eq 0 ]

    printf 'FIXTURE_KEY=changed-value\n' > "$FAKE_REPO/.env"
    run bash "$FAKE_REPO/distro_config/setup_env.sh"
    [ "$status" -eq 0 ]

    run tail -n +2 "$HOME/.claude/.env"
    [ "$status" -eq 0 ]
    [ "$output" = "FIXTURE_KEY=changed-value" ]
}

@test "project .env created from .env.example is mode 600" {
    rm -f "$FAKE_REPO/.env"
    cp "$REPO_ROOT_REAL/.env.example" "$FAKE_REPO/.env.example"

    run bash "$FAKE_REPO/distro_config/setup_env.sh" <<< "y"
    [ "$status" -eq 0 ]
    [ "$(stat -c '%a' "$FAKE_REPO/.env")" = "600" ]
}
