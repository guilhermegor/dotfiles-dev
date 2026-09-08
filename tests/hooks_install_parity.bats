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
# Direction asserted: registered => installed. The reverse is deliberately NOT asserted --
# lib/review_thread_gate.sh is a shared library that is installed but never registered as a
# hook entry, and that is correct.
#
# Run locally:  bats tests/            (install with: sudo apt-get install -y bats)

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SETTINGS="$REPO_ROOT/ai_clients/claude/settings.json"
    HOOKS_LIB="$REPO_ROOT/ai_clients/claude/lib/hooks.sh"
}

# Every "hooks/<name>.sh" path named in settings.json, deduped.
registered_hooks() {
    grep -oE 'hooks/[A-Za-z0-9_./-]+\.sh' "$SETTINGS" \
        | sed 's|^hooks/||' \
        | sort -u
}

# Every name passed to copy_hook_file in install_hooks().
# Comment lines are stripped first: the file header documents the convention with a literal
# `copy_hook_file "<name>.sh"` example, which an unfiltered grep picks up as a real call.
installed_hooks() {
    grep -v '^[[:space:]]*#' "$HOOKS_LIB" \
        | grep -oE 'copy_hook_file[[:space:]]+"[^"]+"' \
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
