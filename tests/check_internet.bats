#!/usr/bin/env bats
#
# Unit tests for check_internet (lib/common.sh), issue #296.
#
# Strategy: source lib/common.sh and exercise check_internet with `curl` and
# `wget` stubbed, so no test ever touches the real network. A test that reached
# the network would assert about the developer's connection rather than about
# the function — the exact confusion this fix exists to remove.
#
# Run locally: bats tests/

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

    # shellcheck source=../lib/common.sh
    source "$REPO_ROOT/lib/common.sh"

    # Default: both downloaders exist. Individual tests narrow this.
    command_exists() { [ "$1" = "curl" ] || [ "$1" = "wget" ]; }
}

@test "returns 0 when the HTTPS probe succeeds" {
    curl() { return 0; }
    run check_internet
    [ "$status" -eq 0 ]
    [[ "$output" == *"Internet connection verified"* ]]
}

@test "returns 1 when the HTTPS probe fails" {
    curl() { return 7; }   # 7 = couldn't connect, the realistic failure
    run check_internet
    [ "$status" -eq 1 ]
    [[ "$output" == *"No internet connection detected"* ]]
}

# --- the regression guard for #296 --------------------------------------------
# ICMP being blocked must NOT be read as "no internet". A stubbed-away ping with
# a working HTTPS probe is exactly the machine this bug was measured on.

@test "a blocked ping does not affect the verdict (the #296 regression)" {
    ping() { return 1; }
    curl() { return 0; }
    run check_internet
    [ "$status" -eq 0 ]
    [[ "$output" == *"Internet connection verified"* ]]
}

@test "falls back to wget when curl is absent" {
    command_exists() { [ "$1" = "wget" ]; }
    wget() { return 0; }
    run check_internet
    [ "$status" -eq 0 ]
    [[ "$output" == *"Internet connection verified"* ]]
}

@test "wget fallback reports failure when its probe fails" {
    command_exists() { [ "$1" = "wget" ]; }
    wget() { return 4; }
    run check_internet
    [ "$status" -eq 1 ]
    [[ "$output" == *"No internet connection detected"* ]]
}

@test "names the real problem when neither curl nor wget exists" {
    command_exists() { return 1; }
    run check_internet
    [ "$status" -eq 1 ]
    [[ "$output" == *"Neither curl nor wget"* ]]
    # Must NOT blame connectivity for a missing dependency.
    [[ "$output" != *"No internet connection detected"* ]]
}

@test "the probe URL is overridable without editing the function" {
    CONNECTIVITY_PROBE_URL="http://example.invalid"
    seen=""
    curl() { seen="$*"; return 0; }
    check_internet >/dev/null
    [[ "$seen" == *"http://example.invalid"* ]]
}
