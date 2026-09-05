#!/usr/bin/env bats
#
# Unit tests for ai_clients/claude/hooks/pr_template_guard.sh
#
# Strategy:
#   - The hook is a stdin->exit-code filter: it reads a PreToolUse JSON payload and exits 0 (allow)
#     or 2 (block), speaking only through stderr.
#   - find_template() resolves the template via `git rev-parse --show-toplevel`, so every test runs
#     inside a throwaway git repo that ships a known .github/PULL_REQUEST_TEMPLATE.md. That gives us
#     deterministic section headers (## Description / ## Testing) to satisfy or withhold.
#   - `payload <command>` builds the JSON the harness would send.
#
# Run locally:  bats tests/            (install with: sudo apt-get install -y bats)

setup() {
    GUARD="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/ai_clients/claude/hooks/pr_template_guard.sh"
    REPO="$(mktemp -d)"
    cd "$REPO"
    git init -q .
    mkdir -p .github
    printf '## Description\n\n## Testing\n' > .github/PULL_REQUEST_TEMPLATE.md
    export -f payload   # make it visible to the `bash -c` subshells that `run` spawns
}

teardown() {
    rm -rf "$REPO"
}

payload() {
    jq -nc --arg cmd "$1" '{tool_name: "Bash", tool_input: {command: $cmd}}'
}

# --- body-file resolution: the #78 fix ---------------------------------------------------------

@test "fails loud when --body-file points to a missing path" {
    run bash -c "payload 'gh pr create --title x --body-file $REPO/nope.md' | '$GUARD'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"could not be read"* ]]
}

@test "does not false-pass when the missing body-file path is named in the title" {
    # The header texts appear in the command (via --title), which the old fallback would have
    # scanned and passed. An unresolved body-file must fail loud regardless.
    run bash -c "payload 'gh pr create --title \"Description and Testing\" --body-file $REPO/nope.md' | '$GUARD'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"could not be read"* ]]
}

@test "fails loud and names the cause for an unexpanded shell variable in --body-file" {
    # PreToolUse sees the command before expansion, so $VAR arrives literal and unreadable.
    run bash -c "payload 'gh pr create --title x --body-file \$SP/body.md' | '$GUARD'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"unexpanded shell variable"* ]]
}

@test "passes a readable compliant --body-file" {
    printf '## Description\nx\n## Testing\ny\n' > "$REPO/body.md"
    run bash -c "payload 'gh pr create --title x --body-file $REPO/body.md' | '$GUARD'"
    [ "$status" -eq 0 ]
}

@test "blocks a readable non-compliant --body-file (missing sections)" {
    printf 'just some text, no headers\n' > "$REPO/body.md"
    run bash -c "payload 'gh pr create --title x --body-file $REPO/body.md' | '$GUARD'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Missing required sections"* ]]
}

# --- inline --body: scanning the command string is still correct -------------------------------

@test "passes an inline --body that has every section" {
    run bash -c "payload 'gh pr create --title x --body \"## Description\\nx\\n## Testing\\ny\"' | '$GUARD'"
    [ "$status" -eq 0 ]
}

@test "blocks an inline --body missing sections" {
    run bash -c "payload 'gh pr create --title x --body \"nothing useful\"' | '$GUARD'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Missing required sections"* ]]
}

# --- pass-through: not our concern -------------------------------------------------------------

@test "ignores non-gh commands" {
    run bash -c "payload 'echo gh pr create --body-file $REPO/nope.md' | '$GUARD'"
    [ "$status" -eq 0 ]
}

@test "ignores a gh pr edit with no body flag (title-only)" {
    run bash -c "payload 'gh pr edit 5 --title x' | '$GUARD'"
    [ "$status" -eq 0 ]
}

@test "ignores gh issue create even with a body flag (dotfiles-dev#154 defect 1)" {
    # An issue has no PR-template obligation; the anchored 'gh pr create|edit' match must not
    # widen to any gh create/edit carrying a body.
    run bash -c "payload 'gh issue create --repo guilhermegor/dotfiles-dev --title x --body \"nothing useful\"' | '$GUARD'"
    [ "$status" -eq 0 ]
}

# --- --repo resolution: dotfiles-dev#154 defect 2 -----------------------------------------------
#
# These override HOME to a throwaway directory so ~/github/<name> resolves to a fixture repo
# instead of the real checkout tree, keeping the tests hermetic.

@test "judges a gh pr create --repo TARGET against TARGET's template, not the session cwd's" {
    local fake_home target
    fake_home="$(mktemp -d)"
    target="$fake_home/github/other-repo"
    mkdir -p "$target/.github"
    git init -q "$target"
    printf '## Sign-off\n' > "$target/.github/PULL_REQUEST_TEMPLATE.md"

    # $REPO (session cwd) requires Description/Testing; a body satisfying ONLY the target
    # repo's Sign-off section must still pass — proving the target's template was used.
    run env HOME="$fake_home" bash -c "payload 'gh pr create --repo someowner/other-repo --title x --body \"## Sign-off\"' | '$GUARD'"
    [ "$status" -eq 0 ]
    rm -rf "$fake_home"
}

@test "blocks against the --repo TARGET's sections even when cwd's template would pass" {
    local fake_home target
    fake_home="$(mktemp -d)"
    target="$fake_home/github/other-repo"
    mkdir -p "$target/.github"
    git init -q "$target"
    printf '## Sign-off\n' > "$target/.github/PULL_REQUEST_TEMPLATE.md"

    # This body satisfies $REPO's own Description/Testing template but NOT the target's
    # Sign-off — must block, proving the cwd's template was not the one enforced.
    run env HOME="$fake_home" bash -c "payload 'gh pr create --repo someowner/other-repo --title x --body \"## Description\\n## Testing\"' | '$GUARD'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Sign-off"* ]]
    rm -rf "$fake_home"
}

@test "reports unresolvable (not non-compliant) when --repo has no local checkout" {
    local fake_home
    fake_home="$(mktemp -d)"
    run env HOME="$fake_home" bash -c "payload 'gh pr create --repo someowner/ghost-repo --title x --body \"whatever\"' | '$GUARD'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"could not"* ]]
    [[ "$output" != *"Missing required sections"* ]]
    rm -rf "$fake_home"
}

@test "passes when the resolved --repo target has no PR template of its own" {
    local fake_home target
    fake_home="$(mktemp -d)"
    target="$fake_home/github/no-template-repo"
    mkdir -p "$target"
    git init -q "$target"
    run env HOME="$fake_home" bash -c "payload 'gh pr create --repo someowner/no-template-repo --title x --body \"whatever\"' | '$GUARD'"
    [ "$status" -eq 0 ]
    rm -rf "$fake_home"
}
