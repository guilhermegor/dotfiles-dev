#!/usr/bin/env bats
#
# refresh_github_cli_keyring (distro_config/install_coding_lib/vcs.sh): GitHub rotated the gh apt
# signing key (23F3D4EA75716059 expired 2026-09) and apt failed with EXPKEYSIG, because the
# keyring was only ever fetched on first install. curl and sudo are stubbed; no network, no root.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TMP="$(mktemp -d)"
    export LOG_FILE="$TMP/log" GITHUB_CLI_KEYRING="$TMP/keyring.gpg" SUDO_LOG="$TMP/sudo"
    mkdir -p "$TMP/bin"
    # curl stub: writes $PUBLISHED to the -o target, or fails when CURL_FAIL=1.
    cat > "$TMP/bin/curl" <<'STUB'
#!/bin/bash
[ "${CURL_FAIL:-0}" = 1 ] && exit 22
while [ $# -gt 0 ]; do [ "$1" = -o ] && { printf '%s' "$PUBLISHED" > "$2"; }; shift; done
STUB
    # sudo stub: records the call, then runs it unprivileged.
    printf '#!/bin/bash\necho "$*" >> "$SUDO_LOG"\n"$@"\n' > "$TMP/bin/sudo"
    chmod +x "$TMP/bin/curl" "$TMP/bin/sudo"
    export PATH="$TMP/bin:$PATH"
    source "$REPO_ROOT/distro_config/install_lib/_common.sh"
    source "$REPO_ROOT/distro_config/install_coding_lib/vcs.sh"
}

teardown() {
    rm -rf "$TMP"
}

@test "an unchanged published keyring is left alone" {
    printf 'same' > "$GITHUB_CLI_KEYRING"
    PUBLISHED=same run refresh_github_cli_keyring
    [ "$status" -eq 0 ]
    [ ! -e "$SUDO_LOG" ]
}

@test "a rotated published keyring replaces the installed one" {
    printf 'expired' > "$GITHUB_CLI_KEYRING"
    PUBLISHED=rotated run refresh_github_cli_keyring
    [ "$status" -eq 0 ]
    [ "$(cat "$GITHUB_CLI_KEYRING")" = rotated ]
}

@test "a failed download is a failure, not a silent keep" {
    printf 'expired' > "$GITHUB_CLI_KEYRING"
    CURL_FAIL=1 run refresh_github_cli_keyring
    [ "$status" -eq 1 ]
    [ "$(cat "$GITHUB_CLI_KEYRING")" = expired ]
}

@test "an already-installed apt gh still refreshes the keyring" {
    fn="$(sed -n '/^install_github_cli()/,/^}/p' "$REPO_ROOT/distro_config/install_coding_lib/vcs.sh")"
    already="$(printf '%s\n' "$fn" | sed -n '/command_exists gh/,/return 0/p')"
    [[ "$already" == *refresh_github_cli_keyring* ]]
}
