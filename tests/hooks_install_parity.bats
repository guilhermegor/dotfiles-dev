#!/usr/bin/env bats
#
# Parity between the hooks REGISTERED in ai_clients/claude/settings.json and the hooks
# INSTALLED by install_hooks() in ai_clients/claude/lib/hooks.sh.
#
# Why this exists (dotfiles-dev#266): pr_self_assign.sh was registered in settings.json by
# #153/PR #212 and had its own passing unit test (tests/pr_self_assign.bats) -- but no
# copy_hook_file call, so it was never copied to ~/.claude/hooks/. Claude Code was told to
# invoke a path that did not exist, on every PR creation, and nothing reported it: the deploy
# printed success for the 21 hooks it did copy. A green test proves a hook WORKS; it does not
# prove the hook is DEPLOYED.
#
# Both directions are asserted: registered => installed (below), AND installed => registered
# (dotfiles-dev#458). The second gap shipped in PR #452: rtk_worktree_passthrough.sh was
# installed by hooks.sh, had its own passing bats suite, and settings.json still invoked
# `rtk hook claude` directly -- no PreToolUse payload ever reached it. An installed file
# nothing references looks identical to a working hook from every place a test previously
# looked (file exists, is executable, its own suite passes).
#
# lib/ is the one legitimate exception to installed => registered: a lib is sourced by a
# hook, never registered as a hook entry itself. Any other exception must be an explicit
# allowlist entry with a reason, never an implicit pass.
#
# Run locally:  bats tests/            (install with: sudo apt-get install -y bats)

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SETTINGS="$REPO_ROOT/ai_clients/claude/settings.json"
    HOOKS_LIB="$REPO_ROOT/ai_clients/claude/lib/hooks.sh"
}

# Hooks installed by hooks.sh but intentionally not registered as a hook entry in
# settings.json. Empty today -- any future entry here must carry a one-line reason.
ORPHAN_ALLOWLIST=()

# Every "hooks/<name>.sh" path named in settings.json, deduped.
registered_hooks() {
    grep -oE 'hooks/[A-Za-z0-9_./-]+\.sh' "$SETTINGS" \
        | sed 's|^hooks/||' \
        | sort -u
}

# Every LITERAL name passed to copy_hook_file in install_hooks().
# Comment lines are stripped first: the file header documents the convention with a literal
# `copy_hook_file "<name>.sh"` example, which an unfiltered grep picks up as a real call.
# Interpolated calls are skipped too — lib/ is copied by a loop over the directory
# (`copy_hook_file "lib/$(basename "$f")"`), which no static extractor can enumerate; the
# "every lib/ file a hook sources is actually installed" test below covers that path by
# running the installer instead of reading it.
installed_hooks() {
    grep -v '^[[:space:]]*#' "$HOOKS_LIB" \
        | grep -oE 'copy_hook_file[[:space:]]+"[^"$]+"' \
        | sed -E 's/.*"([^"]+)".*/\1/' \
        | sort -u
}

@test "settings.json references at least one hook (guards against a broken extractor)" {
    run registered_hooks
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "hooks.sh installs at least one hook (guards against a broken extractor)" {
    run installed_hooks
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "every hook registered in settings.json is installed by hooks.sh" {
    local missing=""
    while IFS= read -r hook; do
        [ -n "$hook" ] || continue
        if ! installed_hooks | grep -qxF "$hook"; then
            missing="$missing $hook"
        fi
    done < <(registered_hooks)

    if [ -n "$missing" ]; then
        echo "Registered in settings.json but never copied by install_hooks():$missing"
        echo "Add a copy_hook_file call for each, per the header note in lib/hooks.sh."
        return 1
    fi
}

@test "every hook installed by hooks.sh is registered in settings.json" {
    local orphaned=""
    local hook
    while IFS= read -r hook; do
        [ -n "$hook" ] || continue
        [[ "$hook" == lib/* ]] && continue  # libs are sourced, never registered
        if printf '%s\n' "${ORPHAN_ALLOWLIST[@]-}" | grep -qxF "$hook"; then
            continue
        fi
        if ! registered_hooks | grep -qxF "$hook"; then
            orphaned="$orphaned $hook"
        fi
    done < <(installed_hooks)

    if [ -n "$orphaned" ]; then
        echo "Installed by hooks.sh but never registered in settings.json:$orphaned"
        echo "Add a settings.json hook entry, or add an ORPHAN_ALLOWLIST entry with a reason."
        return 1
    fi
}

# Every lib/ file a hook SOURCES must land in the installed tree. The registered=>installed
# check above cannot see this: a lib is never registered in settings.json, so a missing one is
# invisible there. Measured 2026-09-16: install_hooks() copied lib/ as a hand-kept list of 8
# names while hooks/lib/ held 10, so the installed subagent_stop_sweep.sh sourced a
# free_surface.sh that was never deployed, gate_free_surface was undefined, and DISPATCH
# reported "free surface UNKNOWN — (gh API failure)" every round — a missing file misreported
# as a network failure.
@test "every lib/ file a hook sources is actually installed" {
    local dest="$BATS_TEST_TMPDIR/claude-home"
    mkdir -p "$dest"

    run bash -c "
        print_status() { :; }
        CLAUDE_DIR='$dest'
        source '$HOOKS_LIB'
        install_hooks
    "
    [ "$status" -eq 0 ]

    local missing=""
    local lib
    while IFS= read -r lib; do
        [ -n "$lib" ] || continue
        [ -f "$dest/hooks/lib/$lib" ] || missing="$missing $lib"
    done < <(grep -hoE 'source[[:space:]]+"\$HOOK_DIR/lib/[A-Za-z0-9_.-]+"' \
        "$REPO_ROOT"/ai_clients/claude/hooks/*.sh \
        | sed -E 's|.*/lib/([^"]+)".*|\1|' | sort -u)

    if [ -n "$missing" ]; then
        echo "Sourced by a hook but never installed:$missing"
        return 1
    fi
}

@test "every hook installed by hooks.sh exists in the source tree" {
    local absent=""
    while IFS= read -r hook; do
        [ -n "$hook" ] || continue
        [ -f "$REPO_ROOT/ai_clients/claude/hooks/$hook" ] || absent="$absent $hook"
    done < <(installed_hooks)

    if [ -n "$absent" ]; then
        echo "copy_hook_file names a file that does not exist in hooks/:$absent"
        return 1
    fi
}
