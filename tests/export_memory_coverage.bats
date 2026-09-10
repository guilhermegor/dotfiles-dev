#!/usr/bin/env bats
#
# The ~/.claude snapshot must be driven by a DENYLIST, not an allowlist.
#
# The bug this pins: export_memory.sh used to name the seven things worth
# keeping, so every artifact type added afterwards was silently absent from
# every snapshot — skills/, agents/, hooks/, rules/, specs/, kanban-boards/,
# teams/, settings.local.json, and memory/, which holds lessons stores that
# exist nowhere else. Nothing failed. The snapshot just stopped being a backup.
#
# So the assertion that matters is not "does it copy X" for a fixed X — that is
# the allowlist thinking that caused the bug. It is: an artifact nobody
# enumerated is copied anyway.
#
# Strategy: build a fake ~/.claude, run the real exclusion list against it with
# rsync, and assert on what lands. No test touches the real home directory.
#
# Run locally: bats tests/

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    FAKE_HOME="$(mktemp -d)"
    SNAP="$(mktemp -d)"

    # Pull the exclusion list out of the script itself, so this test cannot
    # drift from the list it is testing.
    mapfile -t EXCLUDES < <(
        sed -n '/readonly -a EXCLUDES/,/^)/p' "$REPO_ROOT/storage/export_memory.sh" \
            | grep -oE "\-\-exclude='[^']*'" | sed "s/'//g"
    )

    mkdir -p "$FAKE_HOME"/{memory,skills/foo,agents,hooks,rules,specs,kanban-boards,teams}
    mkdir -p "$FAKE_HOME"/{plugins/big,projects/p1,cache,security/agent-sdk-venv/lib}
    echo x > "$FAKE_HOME/memory/a-lesson.md"
    echo x > "$FAKE_HOME/skills/foo/SKILL.md"
    echo x > "$FAKE_HOME/agents/an-agent.md"
    echo x > "$FAKE_HOME/hooks/a-guard.sh"
    echo x > "$FAKE_HOME/settings.local.json"
    echo x > "$FAKE_HOME/.credentials.json"
    echo x > "$FAKE_HOME/plugins/big/blob.bin"
    echo x > "$FAKE_HOME/projects/p1/transcript.jsonl"
    echo x > "$FAKE_HOME/cache/junk"
    echo x > "$FAKE_HOME/security/agent-sdk-venv/lib/pkg.py"
    echo x > "$FAKE_HOME/settings.json.backup_20260101_010101"

    run_export() { rsync -a "${EXCLUDES[@]}" "$FAKE_HOME/" "$SNAP/"; }
}

teardown() {
    rm -rf "$FAKE_HOME" "$SNAP"
}

# --- the regression guard: unenumerated artifacts survive ----------------------

@test "an artifact type nobody enumerated is copied anyway" {
    # This file matches no rule in the exclusion list and no rule anywhere else.
    mkdir -p "$FAKE_HOME/some-future-artifact-type"
    echo x > "$FAKE_HOME/some-future-artifact-type/thing.md"

    run_export
    [ -f "$SNAP/some-future-artifact-type/thing.md" ]
}

@test "the artifact types the old allowlist missed are all present" {
    run_export
    [ -f "$SNAP/memory/a-lesson.md" ]
    [ -f "$SNAP/skills/foo/SKILL.md" ]
    [ -f "$SNAP/agents/an-agent.md" ]
    [ -f "$SNAP/hooks/a-guard.sh" ]
    [ -f "$SNAP/settings.local.json" ]
    [ -d "$SNAP/specs" ]
    [ -d "$SNAP/kanban-boards" ]
    [ -d "$SNAP/teams" ]
}

# --- credentials must never reach the drive -----------------------------------

@test "credentials are never snapshotted" {
    run_export
    [ ! -f "$SNAP/.credentials.json" ]
    run find "$SNAP" -name '.credentials.json'
    [ -z "$output" ]
}

# --- the bulk exclusions still hold -------------------------------------------

@test "regenerable bulk is excluded" {
    run_export
    [ ! -d "$SNAP/plugins" ]
    [ ! -d "$SNAP/projects" ]
    [ ! -d "$SNAP/cache" ]
}

@test "the python virtualenv under security/ is excluded, security/ itself is not" {
    echo x > "$FAKE_HOME/security/a-real-file.json"
    run_export
    [ ! -d "$SNAP/security/agent-sdk-venv" ]
    [ -f "$SNAP/security/a-real-file.json" ]
}

@test "rotated backup copies are excluded" {
    run_export
    run find "$SNAP" -name '*.backup_*'
    [ -z "$output" ]
}

# --- restore must understand what export writes -------------------------------
# A snapshot that cannot be restored is worse than no snapshot: it reports
# success on both ends and loses the data anyway. The export writes under
# claude/, so the restore has to read that path.

@test "restore reads the layout the export writes" {
    run grep -c 'selected_snapshot/claude' "$REPO_ROOT/storage/restore_memory.sh"
    [ "$status" -eq 0 ]
    [ "$output" -gt 0 ]
}

@test "restore still understands pre-existing snapshots in the old layout" {
    run grep -c 'selected_snapshot/commands' "$REPO_ROOT/storage/restore_memory.sh"
    [ "$status" -eq 0 ]
    [ "$output" -gt 0 ]
}
