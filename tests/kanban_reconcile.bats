#!/usr/bin/env bats
#
# Unit tests for ai_clients/claude/hooks/lib/kanban_reconcile.sh (dotfiles-dev#448)
#
# Strategy (same shape as roadmap_unblock.bats / kanban_lifecycle.bats): a fake `gh` script is
# placed first on PATH so these tests never touch the network or a real project board. It logs
# every invocation to $GH_LOG and answers `project list`/`project field-list`/`pr list`/
# `project item-list`/`project item-edit`/`api graphql` from fixture files this test writes.
#
# Run locally:  bats tests/            (install with: sudo apt-get install -y bats)

setup() {
    LIB="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/ai_clients/claude/hooks/lib/kanban_reconcile.sh"
    TEST_TMP="$(mktemp -d)"
    FAKE_BIN="$TEST_TMP/bin"
    mkdir -p "$FAKE_BIN"
    PATH="$FAKE_BIN:$PATH"
    export GH_LOG="$TEST_TMP/gh.log"
    : > "$GH_LOG"

    # Isolate the board-id cache from any real ~/.claude/kanban-boards on a dev machine.
    export CLAUDE_CONFIG_DIR="$TEST_TMP/claude-home"

    # Default board: Backlog < In progress < In review < Done (order is what the reconcile ranks
    # against — never hardcoded in the lib itself).
    cat > "$TEST_TMP/fields.json" <<'JSON'
{"fields":[{"name":"Status","id":"FIELD_1","options":[
    {"name":"Backlog","id":"OPT_BACKLOG"},
    {"name":"In progress","id":"OPT_PROGRESS"},
    {"name":"In review","id":"OPT_REVIEW"},
    {"name":"Done","id":"OPT_DONE"}
]}]}
JSON
}

teardown() {
    rm -rf "$TEST_TMP"
}

# write_prs NUMBER...
# The bare numbers `gh pr list ... --jq '.[].number'` would print, one per line.
write_prs() {
    printf '%s\n' "$@" > "$TEST_TMP/prs.txt"
}

# item ID STATUS NUMBER
item() {
    jq -nc --arg id "$1" --arg status "$2" --argjson number "$3" \
        '{id: $id, status: $status, content: {type: "Issue", number: $number}}'
}

write_items() {
    printf '%s\n' "$@" | jq -sc '{items: .}' > "$TEST_TMP/items.json"
}

# write_closing PR_NUMBER ISSUE_NUMBER:STATE...
# Registers the closingIssuesReferences GraphQL response for one PR, or a bare "FAIL" to make
# that PR's read fail (simulating a 403/network error).
write_closing() {
    local pr="$1"; shift
    if [ "$1" = "FAIL" ]; then
        echo FAIL > "$TEST_TMP/closing-$pr.json"
        return
    fi
    local nodes="[]" pair number state
    for pair in "$@"; do
        number="${pair%%:*}"
        state="${pair##*:}"
        nodes="$(printf '%s' "$nodes" | jq -c --argjson n "$number" --arg s "$state" \
            '. + [{number: $n, state: $s}]')"
    done
    jq -nc --argjson nodes "$nodes" \
        '{data: {repository: {pullRequest: {closingIssuesReferences: {nodes: $nodes}}}}}' \
        > "$TEST_TMP/closing-$pr.json"
}

write_fake_gh() {
    cat > "$FAKE_BIN/gh" <<EOF
#!/bin/bash
echo "\$*" >> "$GH_LOG"
case "\$1 \$2" in
    "project list")
        echo '{"projects":[{"title":"repo kanban","number":1,"id":"PVT_1"}]}'
        ;;
    "project field-list")
        [ -f "$TEST_TMP/fail-field-list" ] && exit 1
        cat "$TEST_TMP/fields.json"
        ;;
    "pr list")
        [ -f "$TEST_TMP/fail-pr-list" ] && exit 1
        cat "$TEST_TMP/prs.txt" 2>/dev/null
        ;;
    "project item-list")
        [ -f "$TEST_TMP/fail-item-list" ] && exit 1
        cat "$TEST_TMP/items.json"
        ;;
    "project item-edit")
        [ -f "$TEST_TMP/fail-item-edit" ] && exit 1
        echo ok
        ;;
    "api graphql")
        full="\$*"
        num="\${full#*pullRequest(number:}"
        num="\${num%%)*}"
        f="$TEST_TMP/closing-\$num.json"
        if [ ! -f "\$f" ]; then
            echo '{"data":{"repository":{"pullRequest":{"closingIssuesReferences":{"nodes":[]}}}}}'
        elif [ "\$(cat "\$f")" = "FAIL" ]; then
            exit 1
        else
            cat "\$f"
        fi
        ;;
    *)
        exit 1
        ;;
esac
EOF
    chmod +x "$FAKE_BIN/gh"
}

refute_gh() {
    run grep -q -- "$1" "$GH_LOG"
    [ "$status" -ne 0 ]
}

run_reconcile() {
    run bash -c "source '$LIB'; reconcile_kanban owner repo; \
        echo \"rc=\$?\"; echo \"STATUS=\$RECONCILE_KANBAN_STATUS\"; \
        echo \"REPORT_START\"; printf '%s\n' \"\$RECONCILE_KANBAN_REPORT\"; echo \"REPORT_END\""
}

# --- (a) Backlog issue with an open closing PR: one item-edit to In review ----------------------

@test "issue in Backlog with an open closing PR is moved to In review" {
    write_prs 10
    write_closing 10 "42:OPEN"
    write_items "$(item ITEM_42 Backlog 42)"
    write_fake_gh
    run_reconcile
    [[ "$output" == *"rc=0"* ]]
    [[ "$output" == *"STATUS=ok"* ]]
    [[ "$output" == *"moved issue #42 to In review"* ]]
    grep -q -- '--id ITEM_42 --field-id FIELD_1 --single-select-option-id OPT_REVIEW' "$GH_LOG"
}

# --- (b) already In review: no call --------------------------------------------------------------

@test "issue already In review triggers no item-edit call" {
    write_prs 10
    write_closing 10 "42:OPEN"
    write_items "$(item ITEM_42 "In review" 42)"
    write_fake_gh
    run_reconcile
    [[ "$output" == *"STATUS=ok"* ]]
    [[ "$output" != *"moved issue"* ]]
    refute_gh 'item-edit'
}

# --- (c) Done with an open referencing PR: never moved backwards --------------------------------

@test "issue in Done with an open referencing PR is left alone (never backwards)" {
    write_prs 10
    write_closing 10 "42:OPEN"
    write_items "$(item ITEM_42 Done 42)"
    write_fake_gh
    run_reconcile
    [[ "$output" == *"STATUS=ok"* ]]
    [[ "$output" != *"moved issue"* ]]
    refute_gh 'item-edit'
}

# --- (d) gh 403 on the PR list / board read: UNKNOWN, zero item-edit calls -----------------------

@test "gh failure listing open PRs: UNKNOWN, nothing touched" {
    touch "$TEST_TMP/fail-pr-list"
    write_items "$(item ITEM_42 Backlog 42)"
    write_fake_gh
    run_reconcile
    [[ "$output" == *"rc=1"* ]]
    [[ "$output" == *"STATUS=unknown"* ]]
    [[ "$output" == *"UNKNOWN"* ]]
    refute_gh 'item-edit'
}

@test "gh 403 resolving one PR's closing issues: reported UNKNOWN for that PR, round continues" {
    write_prs 10 11
    write_closing 10 FAIL
    write_closing 11 "42:OPEN"
    write_items "$(item ITEM_42 Backlog 42)"
    write_fake_gh
    run_reconcile
    [[ "$output" == *"STATUS=ok"* ]]
    [[ "$output" == *"UNKNOWN PR #10"* ]]
    [[ "$output" == *"moved issue #42 to In review"* ]]
}

# --- an unclaimed board / unreadable items: UNKNOWN, fails closed --------------------------------

@test "board items unreadable: STATUS=unknown, non-zero return, nothing touched" {
    write_prs 10
    write_closing 10 "42:OPEN"
    write_fake_gh
    touch "$TEST_TMP/fail-item-list"
    run_reconcile
    [[ "$output" == *"rc=1"* ]]
    [[ "$output" == *"STATUS=unknown"* ]]
    refute_gh 'item-edit'
}

# --- idempotent: an already-moved card produces an empty report on the next round ----------------

@test "idempotent: no cards changed on a re-run once the board reflects In review" {
    write_prs 10
    write_closing 10 "42:OPEN"
    write_items "$(item ITEM_42 "In review" 42)"
    write_fake_gh
    run_reconcile
    [[ "$output" == *"STATUS=ok"* ]]
    # REPORT_START/REPORT_END with nothing meaningful in between (printf on an empty string still
    # emits one blank line).
    [[ "$output" != *"moved issue"* ]]
    refute_gh 'item-edit'
}

# --- two open PRs closing the same issue: moved once, not twice ---------------------------------

@test "two open PRs closing the same issue move its card exactly once" {
    write_prs 10 11
    write_closing 10 "42:OPEN"
    write_closing 11 "42:OPEN"
    write_items "$(item ITEM_42 Backlog 42)"
    write_fake_gh
    run_reconcile
    [[ "$output" == *"moved issue #42 to In review"* ]]
    local edits
    edits="$(grep -c -- '--single-select-option-id OPT_REVIEW' "$GH_LOG")"
    [ "$edits" -eq 1 ]
}
