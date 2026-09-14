#!/usr/bin/env bats
#
# Unit tests for ai_clients/claude/hooks/lib/roadmap_unblock.sh (dotfiles-dev#369)
#
# Strategy (same shape as kanban_lifecycle.bats): a fake `gh` script is placed first on PATH so
# these tests never touch the network or a real project board. It logs every invocation to
# $GH_LOG (for asserting which mutations did or did not happen) and answers `project item-list`
# from a fixture file, and `api .../dependencies/blocked_by` from a per-test map keyed by issue
# number (FAKE_BLOCKERS_<n>), so one item-list fixture can carry several Blocked items at once.
#
# Run locally:  bats tests/            (install with: sudo apt-get install -y bats)

setup() {
    LIB="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/ai_clients/claude/hooks/lib/roadmap_unblock.sh"
    TEST_TMP="$(mktemp -d)"
    FAKE_BIN="$TEST_TMP/bin"
    mkdir -p "$FAKE_BIN"
    PATH="$FAKE_BIN:$PATH"
    export GH_LOG="$TEST_TMP/gh.log"
    : > "$GH_LOG"
}

teardown() {
    rm -rf "$TEST_TMP"
}

# item OWNER/REPO NUMBER STATUS BLOCKED_BY_TEXT BODY
# Emits one project-item JSON object. BLOCKED_BY_TEXT may be "" (field absent, matching the real
# API which only emits the "blocked by" key when the field is non-empty).
item() {
    local repo="$1" number="$2" status="$3" blocked_by="$4" body="$5"
    jq -nc --arg repo "$repo" --argjson number "$number" --arg status "$status" \
        --arg blocked_by "$blocked_by" --arg body "$body" '
        {status: $status, content: {type: "Issue", number: $number, repository: $repo,
         url: ("https://github.com/" + $repo + "/issues/" + ($number|tostring)), body: $body}}
        | if $blocked_by == "" then . else . + {"blocked by": $blocked_by} end
    '
}

# write_items ITEM_JSON...
# Writes {"items":[...]} to the fixture file the fake gh's `project item-list` reads.
write_items() {
    printf '%s\n' "$@" | jq -sc '{items: .}' > "$TEST_TMP/items.json"
}

# blocker NUMBER STATE REPO
blocker() {
    jq -nc --argjson number "$1" --arg state "$2" --arg repo "$3" \
        '{number: $number, state: $state, repository: {full_name: $repo}}'
}

# write_blockers ISSUE_NUMBER BLOCKER_JSON...
# Registers the dependencies/blocked_by fixture for one issue number, or a bare "FAIL" sentinel
# file to make that read fail (simulating an API error).
write_blockers() {
    local number="$1"; shift
    if [ "$1" = "FAIL" ]; then
        echo FAIL > "$TEST_TMP/blockers-$number.json"
    else
        printf '%s\n' "$@" | jq -sc '.' > "$TEST_TMP/blockers-$number.json"
    fi
}

write_fake_gh() {
    cat > "$FAKE_BIN/gh" <<EOF
#!/bin/bash
echo "\$*" >> "$GH_LOG"
case "\$1 \$2" in
    "project item-list")
        cat "$TEST_TMP/items.json"
        ;;
    "api "*)
        path="\$2"
        n="\${path##*/issues/}"
        n="\${n%%/dependencies*}"
        f="$TEST_TMP/blockers-\$n.json"
        [ -f "\$f" ] || { echo '[]'; exit 0; }
        if [ "\$(cat "\$f")" = "FAIL" ]; then
            exit 1
        fi
        cat "\$f"
        ;;
    "issue edit")
        [ -f "$TEST_TMP/fail-issue-edit" ] && exit 1
        echo ok
        ;;
    "project item-edit")
        [ -f "$TEST_TMP/fail-item-edit" ] && exit 1
        echo ok
        ;;
    "issue comment")
        [ -f "$TEST_TMP/fail-comment" ] && exit 1
        echo ok
        ;;
    *)
        exit 1
        ;;
esac
EOF
    chmod +x "$FAKE_BIN/gh"
}

run_reconcile() {
    run bash -c "source '$LIB'; reconcile_roadmap_unblock owner 17; \
        echo \"STATUS=\$RECONCILE_STATUS\"; echo \"REPORT_START\"; \
        printf '%s\n' \"\$RECONCILE_REPORT\"; echo \"REPORT_END\""
}

# --- one closed blocker: unblocked + commented ---------------------------------------------------

@test "one closed native blocker: item is unblocked, labeled, and commented" {
    write_items "$(item "owner/repo" 3 "Blocked" "" "**Blocked by:** owner/repo#2")"
    write_blockers 3 "$(blocker 2 closed "owner/repo")"
    write_fake_gh
    run_reconcile
    [[ "$output" == *"STATUS=ok"* ]]
    [[ "$output" == *"unblocked owner/repo#3"* ]]
    [[ "$output" == *"owner/repo#2"* ]]
    grep -q 'issue edit 3 --repo owner/repo --add-label state:ready --remove-label state:blocked' "$GH_LOG"
    grep -q 'project item-edit 17 --owner owner --url .*--field Status --value Ready' "$GH_LOG"
    grep -q 'project item-edit 17 --owner owner --url .*--field Blocked by --clear' "$GH_LOG"
    grep -q 'issue comment 3 --repo owner/repo' "$GH_LOG"
}

# --- one open of two: untouched ------------------------------------------------------------------

@test "one open blocker of two: left blocked, no mutation" {
    write_items "$(item "owner/repo" 4 "Blocked" "" "**Blocked by:** owner/repo#2, owner/repo#5")"
    write_blockers 4 "$(blocker 2 closed "owner/repo")" "$(blocker 5 open "owner/repo")"
    write_fake_gh
    run_reconcile
    [[ "$output" == *"STATUS=ok"* ]]
    [[ "$output" == *"still blocked owner/repo#4"* ]]
    [[ "$output" == *"owner/repo#5"* ]]
    ! grep -q 'issue edit' "$GH_LOG"
    ! grep -q 'item-edit' "$GH_LOG"
    ! grep -q 'issue comment' "$GH_LOG"
}

# --- a cross-repo blocker, all closed: still unblocks -------------------------------------------

@test "cross-repo native blocker, closed: unblocked" {
    write_items "$(item "owner/greenfield" 12 "Blocked" "" "**Blocked by:** owner/blueprintx#482")"
    write_blockers 12 "$(blocker 482 closed "owner/blueprintx")"
    write_fake_gh
    run_reconcile
    [[ "$output" == *"unblocked owner/greenfield#12"* ]]
    [[ "$output" == *"owner/blueprintx#482"* ]]
}

# --- decision blocker: never auto-cleared, even alone with no native blocker ---------------------

@test "decision: blocker present (in the Blocked-by field): left untouched" {
    write_items "$(item "owner/repo" 7 "Blocked" "decision: find and read the terms of use" "")"
    write_blockers 7
    write_fake_gh
    run_reconcile
    [[ "$output" == *"STATUS=ok"* ]]
    [[ "$output" == *"decision blocker owner/repo#7"* ]]
    [[ "$output" == *"decision: find and read the terms of use"* ]]
    ! grep -q 'issue edit' "$GH_LOG"
    ! grep -q 'item-edit' "$GH_LOG"
    ! grep -q 'issue comment' "$GH_LOG"
}

@test "decision: blocker present only in the body line: still left untouched" {
    write_items "$(item "owner/repo" 7 "Blocked" "" "**Blocked by:** decision: pick a vendor")"
    write_blockers 7
    write_fake_gh
    run_reconcile
    [[ "$output" == *"decision blocker owner/repo#7"* ]]
    ! grep -q 'issue edit' "$GH_LOG"
}

# --- blocked by nothing: reported, untouched ------------------------------------------------------

@test "blocked by nothing: Status=Blocked with no blocker recorded anywhere is reported, not moved" {
    write_items "$(item "owner/repo" 13 "Blocked" "" "no blocker line here")"
    write_blockers 13
    write_fake_gh
    run_reconcile
    [[ "$output" == *"STATUS=ok"* ]]
    [[ "$output" == *"blocked by nothing owner/repo#13"* ]]
    ! grep -q 'issue edit' "$GH_LOG"
    ! grep -q 'item-edit' "$GH_LOG"
}

# --- API failure: UNKNOWN, untouched --------------------------------------------------------------

@test "dependencies API failure: reported UNKNOWN, left untouched (fail closed)" {
    write_items "$(item "owner/repo" 16 "Blocked" "" "**Blocked by:** owner/repo#9")"
    write_blockers 16 FAIL
    write_fake_gh
    run_reconcile
    [[ "$output" == *"STATUS=ok"* ]]
    [[ "$output" == *"UNKNOWN owner/repo#16"* ]]
    ! grep -q 'issue edit' "$GH_LOG"
    ! grep -q 'item-edit' "$GH_LOG"
    ! grep -q 'issue comment' "$GH_LOG"
}

@test "the board itself unreadable: global UNKNOWN, non-zero return, nothing touched" {
    write_fake_gh
    rm -f "$TEST_TMP/items.json"   # item-list now fails: no such fixture file for `cat`
    run bash -c "source '$LIB'; reconcile_roadmap_unblock owner 17; echo \"rc=\$?\"; \
        echo \"STATUS=\$RECONCILE_STATUS\"; echo \"REPORT=\$RECONCILE_REPORT\""
    [[ "$output" == *"rc=1"* ]]
    [[ "$output" == *"STATUS=unknown"* ]]
    [[ "$output" == *"UNKNOWN"* ]]
    ! grep -q 'issue edit' "$GH_LOG"
}

# --- idempotent: re-running after an unblock changes nothing -------------------------------------

@test "idempotent: an already-Ready item (no longer Blocked) triggers no mutation on re-run" {
    # Round 1: unblock it.
    write_items "$(item "owner/repo" 3 "Blocked" "" "**Blocked by:** owner/repo#2")"
    write_blockers 3 "$(blocker 2 closed "owner/repo")"
    write_fake_gh
    run_reconcile
    [[ "$output" == *"unblocked owner/repo#3"* ]]

    # Round 2: the board now reflects Ready (as the real board would after round 1's writes) —
    # the item no longer matches the Status=="Blocked" filter, so nothing fires again.
    : > "$GH_LOG"
    write_items "$(item "owner/repo" 3 "Ready" "" "")"
    run_reconcile
    [[ "$output" == *"STATUS=ok"* ]]
    [[ "$output" != *"owner/repo#3"* ]]
    ! grep -q 'issue edit' "$GH_LOG"
    ! grep -q 'item-edit' "$GH_LOG"
    ! grep -q 'issue comment' "$GH_LOG"
}

# --- a partial write failure is surfaced, never silently swallowed -------------------------------

@test "a gh write failing partway is reported as FAILED, not silently as unblocked" {
    write_items "$(item "owner/repo" 3 "Blocked" "" "**Blocked by:** owner/repo#2")"
    write_blockers 3 "$(blocker 2 closed "owner/repo")"
    write_fake_gh
    touch "$TEST_TMP/fail-item-edit"
    run_reconcile
    [[ "$output" == *"FAILED to unblock owner/repo#3"* ]]
    [[ "$output" != *"unblocked owner/repo#3"* ]]
}
