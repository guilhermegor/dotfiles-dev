#!/usr/bin/env bats
#
# Unit tests for _merge_dock_favorites, the helper configure_dock uses to
# preserve hand-pinned dock apps instead of clobbering them (issue #103).
#
# Strategy: source ubuntu_workspace.sh (guarded — sourcing never runs main()
# or touches gsettings, see the BASH_SOURCE guard at the bottom of the file)
# and exercise the pure _merge_dock_favorites helper directly. No gsettings
# mocking needed since the helper takes the "live" value as a plain string.
#
# Run locally: bats tests/

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

    # shellcheck source=../distro_config/ubuntu_workspace.sh
    source "$REPO_ROOT/distro_config/ubuntu_workspace.sh"
}

@test "_merge_dock_favorites preserves an existing pinned app not in the declared list" {
    local -a declared=("'spotify.desktop'" "'firefox.desktop'")
    local existing_str="['spotify.desktop', 'custom-app.desktop']"

    _merge_dock_favorites declared "$existing_str"

    [ "${#declared[@]}" -eq 3 ]
    [ "${declared[0]}" = "'spotify.desktop'" ]
    [ "${declared[1]}" = "'firefox.desktop'" ]
    [ "${declared[2]}" = "'custom-app.desktop'" ]
}

@test "_merge_dock_favorites is idempotent across repeated runs" {
    local -a first_run=("'spotify.desktop'" "'firefox.desktop'")
    local existing_str="['spotify.desktop', 'custom-app.desktop']"
    _merge_dock_favorites first_run "$existing_str"

    # Simulate the next `make run` invocation: declared favorites are rebuilt
    # fresh from scratch, and the "live" gsettings value is now whatever the
    # first run wrote (declared + the hand-pinned extra).
    local first_run_str
    first_run_str=$(IFS=,; echo "${first_run[*]}")

    local -a second_run=("'spotify.desktop'" "'firefox.desktop'")
    _merge_dock_favorites second_run "[${first_run_str}]"

    [ "${#second_run[@]}" -eq "${#first_run[@]}" ]
    local i
    for i in "${!first_run[@]}"; do
        [ "${second_run[$i]}" = "${first_run[$i]}" ]
    done
}

# --- #392: DOCK_UNPINNED ----------------------------------------------------
#
# _merge_dock_favorites takes an optional 3rd arg naming an array of quoted
# ids to skip when merging the live value back in. Without this, undeclaring
# an app (removing its favorites block) is not enough — the merge above would
# re-add it from the live dock forever, which is exactly the trap #392 exists
# to avoid.

@test "_merge_dock_favorites drops a live app that is in the unpin list" {
    local -a declared=("'spotify.desktop'" "'firefox.desktop'")
    local existing_str="['spotify.desktop', 'firefox.desktop', 'postman_postman.desktop', 'docker-desktop.desktop']"
    local -a unpinned=("'postman_postman.desktop'" "'docker-desktop.desktop'")

    _merge_dock_favorites declared "$existing_str" unpinned

    [ "${#declared[@]}" -eq 2 ]
    [ "${declared[0]}" = "'spotify.desktop'" ]
    [ "${declared[1]}" = "'firefox.desktop'" ]
}

@test "_merge_dock_favorites still preserves a hand-pinned app that is NOT in the unpin list" {
    local -a declared=("'spotify.desktop'")
    local existing_str="['spotify.desktop', 'postman_postman.desktop', 'custom-app.desktop']"
    local -a unpinned=("'postman_postman.desktop'")

    _merge_dock_favorites declared "$existing_str" unpinned

    [ "${#declared[@]}" -eq 2 ]
    [ "${declared[0]}" = "'spotify.desktop'" ]
    [ "${declared[1]}" = "'custom-app.desktop'" ]
}

@test "_merge_dock_favorites unpin is idempotent: a second run stays unpinned" {
    local -a first_run=("'spotify.desktop'")
    local existing_str="['spotify.desktop', 'postman_postman.desktop']"
    local -a unpinned=("'postman_postman.desktop'")
    _merge_dock_favorites first_run "$existing_str" unpinned

    # Simulate the next run: declared favorites rebuilt fresh, live value is
    # now whatever the first run wrote (postman already gone).
    local first_run_str
    first_run_str=$(IFS=,; echo "${first_run[*]}")

    local -a second_run=("'spotify.desktop'")
    _merge_dock_favorites second_run "[${first_run_str}]" unpinned

    [ "${#second_run[@]}" -eq 1 ]
    [ "${second_run[0]}" = "'spotify.desktop'" ]
}

@test "MUTATION-CHECK: without the unpin filter, the drop test fails" {
    # Proves the unpin-drop test above actually exercises the filter: mutate a
    # copy of ubuntu_workspace.sh (removing the unpin `continue` — the pre-#392
    # behaviour), source the copy, and show the same assertion now fails.
    #
    # ⚠️ The copy lives NEXT TO the original, not in $BATS_TEST_TMPDIR, and never
    # replaces it. Two constraints have to hold at once:
    #   - the script does `source "$SCRIPT_DIR/lib/common.sh"`, so a mutant in
    #     /tmp cannot resolve its own dependency — hence same-directory;
    #   - the ORIGINAL is tracked, so mutating it in place makes a hard kill
    #     (SIGKILL, a quota kill, Ctrl-C between the mutation and the restore)
    #     leave the working tree dirty with the feature silently removed. In
    #     this repo that is not a cosmetic risk: `s:dev-loop` step 1 RESCUE
    #     treats an uncommitted worktree as interrupted work and commits it, so
    #     the automation itself would ship the reverted guard. A trap does not
    #     cover a SIGKILL.
    # A leftover mutant file is untracked, inert, and named to be obvious.
    local real="$REPO_ROOT/distro_config/ubuntu_workspace.sh"
    local mutant="$REPO_ROOT/distro_config/.mutant-configure-dock-$$.sh"
    cp "$real" "$mutant"
    # shellcheck disable=SC2064  # intentionally expand $mutant now, not at trap time
    trap "rm -f '$mutant'" RETURN

    python3 - "$mutant" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
needle = '        if [[ " ${_merge_unpinned[*]} " == *" ${item} "* ]]; then\n            continue\n        fi\n'
assert text.count(needle) == 1, "unpin guard not found exactly once — mutation not applied"
open(path, "w").write(text.replace(needle, "", 1))
PY

    # Same directory as the original, so the script's own
    # `source "$SCRIPT_DIR/lib/common.sh"` still resolves.
    # shellcheck source=/dev/null
    source "$mutant"

    local -a declared=("'spotify.desktop'" "'firefox.desktop'")
    local existing_str="['spotify.desktop', 'firefox.desktop', 'postman_postman.desktop', 'docker-desktop.desktop']"
    local -a unpinned=("'postman_postman.desktop'" "'docker-desktop.desktop'")

    _merge_dock_favorites declared "$existing_str" unpinned

    # Mutated behaviour re-adds the unpinned ids — the count is now 4, not 2.
    run [ "${#declared[@]}" -eq 2 ]
    [ "$status" -ne 0 ]

    # The tracked original was never written to: assert it, rather than assert a
    # restore worked. Nothing to roll back is a stronger guarantee than rolling
    # back correctly.
    run git -C "$REPO_ROOT" diff --quiet -- distro_config/ubuntu_workspace.sh
    [ "$status" -eq 0 ]

    # And the mutant really was mutated — otherwise the failure above could come
    # from something else entirely and this test would prove nothing.
    run grep -q '_merge_unpinned\[\*\]' "$mutant"
    [ "$status" -ne 0 ]
}

# --- #429: SoundCloud moves from the dock to the Media app folder ----------
#
# Two independent things have to hold at once, or the app is either lost
# (placed nowhere) or duplicated (dock AND folder): the registry entry must
# now declare Media, and DOCK_UNPINNED must actually stop the live dock
# value from re-pinning it (see the ⚠️ block in distro_config/CLAUDE.md —
# deleting the declared dock block alone does NOT unpin an app).

@test "INSTALL_REGISTRY places soundcloud.desktop in the Media folder (#429)" {
    HOME="$(mktemp -d)"
    export HOME
    trap 'rm -rf "$HOME"' RETURN
    mkdir -p "$HOME/.local/share/applications"
    : > "$HOME/.local/share/applications/soundcloud.desktop"
    export DRY_RUN=1

    gsettings() { [ "$1" = "get" ] && { echo "''"; return 0; }; return 0; }
    export -f gsettings
    dconf() { return 0; }
    export -f dconf

    run organize_app_folders
    [ "$status" -eq 0 ]

    local media_line
    media_line=$(printf '%s\n' "$output" | grep -oE "folders/Media/ apps \[[^]]*\]")
    [[ "$media_line" == *"'soundcloud.desktop'"* ]]
}

@test "_merge_dock_favorites drops soundcloud.desktop via the real DOCK_UNPINNED list (#429)" {
    # Parse the production DOCK_UNPINNED array straight out of the source file
    # instead of hand-copying it here — a hand-copy would keep passing even if
    # the real edit to DOCK_UNPINNED were reverted or never made.
    local -a real_unpinned
    mapfile -t real_unpinned < <(
        sed -n '/local -a DOCK_UNPINNED=(/,/^    )/p' \
            "$REPO_ROOT/distro_config/ubuntu_workspace.sh" \
        | grep -oE "'[A-Za-z0-9_.-]+\.desktop'"
    )
    [ "${#real_unpinned[@]}" -ge 1 ]

    local -a declared=("'spotify.desktop'" "'firefox.desktop'")
    local existing_str="['spotify.desktop', 'firefox.desktop', 'soundcloud.desktop']"

    _merge_dock_favorites declared "$existing_str" real_unpinned

    [ "${#declared[@]}" -eq 2 ]
    [[ "${declared[*]}" != *"soundcloud.desktop"* ]]
}
