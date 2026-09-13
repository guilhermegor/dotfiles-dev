#!/usr/bin/env bats
#
# npm_global_install_all_nvm_versions targets only Node versions nvm actually installed, and
# skips those below the package's engines.node floor.
#
# Measured 2026-09-12: `nvm ls` also prints the LTS alias table, so the old version grep
# targeted eleven never-installed versions (`N/A: version "v8.17.0" is not yet installed`) and
# the install reported failure; the two v20 installs "succeeded" under an EBADENGINE warning for
# a package requiring Node >=22.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TMP="$(mktemp -d)"
    export NVM_DIR="$TMP/nvm" LOG_FILE="$TMP/log" CALLS="$TMP/calls"
    mkdir -p "$NVM_DIR/versions/node/v20.14.0" "$NVM_DIR/versions/node/v24.13.0" "$TMP/bin"

    # A stub nvm whose `ls` prints the alias table verbatim from a real run.
    cat > "$NVM_DIR/nvm.sh" <<'NVM'
nvm() {
    case "$1" in
    ls) printf '%s\n' '       v20.14.0 *' '       v24.13.0 *' \
            'lts/carbon -> v8.17.0 (-> N/A)' 'lts/jod -> v22.22.2 (-> N/A)' ;;
    exec) echo "exec $2 ${*:3}" >> "$CALLS" ;;
    esac
}
NVM
    printf '#!/bin/bash\n[ "$1" = view ] && echo "${ENGINES->=22.0.0}"\n' > "$TMP/bin/npm"
    chmod +x "$TMP/bin/npm"
    export PATH="$TMP/bin:$PATH"

    source "$REPO_ROOT/lib/common.sh"
    source "$REPO_ROOT/distro_config/install_coding_lib/languages.sh"
}

teardown() {
    rm -rf "$TMP"
}

@test "installed versions come from the install dir, never the alias table" {
    run nvm_installed_versions
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf 'v20.14.0\nv24.13.0')" ]
}

@test "only installed versions meeting the engine floor are installed into" {
    run npm_global_install_all_nvm_versions "@anthropic-ai/claude-code"
    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS")" = "exec 24.13.0 npm install -g @anthropic-ai/claude-code" ]
    [[ "$output" == *"v20.14.0: skipped"* ]]
}

@test "no engine floor declared installs into every installed version" {
    ENGINES="" run npm_global_install_all_nvm_versions "some-pkg"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$CALLS")" -eq 2 ]
}

@test "no installed version satisfying the floor is a failure, not an all-clear" {
    ENGINES=">=26" run npm_global_install_all_nvm_versions "some-pkg"
    [ "$status" -eq 1 ]
    [ ! -e "$CALLS" ]
}
