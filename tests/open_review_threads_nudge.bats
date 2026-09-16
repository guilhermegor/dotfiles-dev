#!/usr/bin/env bats
#
# Unit tests for ai_clients/claude/hooks/open_review_threads_nudge.sh (dotfiles-dev#397)
#
# Strategy:
#   - The hook is a stdin->exit-code filter: it reads a Stop-hook JSON payload and exits 0
#     (allow the stop) or 2 (block it), speaking only through stderr. Run it as a real
#     subprocess — `gh` is stubbed on PATH, `git`/`jq` are the real system binaries.
#   - The stub logs every `pr list` and `api graphql` call it serves, so a test can assert HOW
#     MANY calls were made (the short-circuit and cache tests), not just the final verdict.
#
# Run locally:  bats tests/            (install with: sudo apt-get install -y bats)

setup() {
    HOOK="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/ai_clients/claude/hooks/open_review_threads_nudge.sh"
    REPO="$(mktemp -d)"
    BIN="$REPO/bin"
    FIXTURE_DIR="$REPO/fixtures"
    mkdir -p "$BIN" "$FIXTURE_DIR"
    cd "$REPO" || return 1
    git init -q .
    git config user.email t@t.example
    git config user.name t

    export CLAUDE_CONFIG_DIR="$REPO/claude-home"
    export PRLIST_LOG="$REPO/prlist.log"
    export GRAPHQL_LOG="$REPO/graphql.log"
    export FIXTURE_DIR
    : >"$PRLIST_LOG"
    : >"$GRAPHQL_LOG"

    cat >"$BIN/gh" <<'STUB'
#!/bin/bash
case "$1 $2" in
"pr view")
    [ -n "${PR_VIEW_NUMBER:-}" ] && echo "$PR_VIEW_NUMBER"
    ;;
"repo view")
    echo "o/r"
    ;;
"pr list")
    echo call >>"$PRLIST_LOG"
    [ "${PR_LIST_FAIL:-0}" = 1 ] && exit 1
    printf '%s\n' "$PR_LIST"
    ;;
"api graphql")
    shift 2
    num=""
    while [ $# -gt 0 ]; do
        if [ "$1" = "-F" ]; then
            shift
            case "$1" in number=*) num="${1#number=}" ;; esac
            shift
        else
            shift
        fi
    done
    echo "$num" >>"$GRAPHQL_LOG"
    cat "$FIXTURE_DIR/$num.json" 2>/dev/null || echo '{}'
    ;;
esac
STUB
    chmod +x "$BIN/gh"
    export PATH="$BIN:$PATH"
    export -f payload
}

teardown() {
    rm -rf "$REPO"
}

# payload STOP_HOOK_ACTIVE SESSION_ID
payload() {
    jq -nc --argjson active "${1:-false}" --arg sid "${2:-}" \
        '{stop_hook_active: $active, session_id: $sid}'
}

clean_fixture() {
    jq -nc '{data: {repository: {pullRequest: {reviewThreads: {totalCount: 0, nodes: []}}}}}' \
        >"$FIXTURE_DIR/$1.json"
}

# A single bot-only thread — no roster file in the test repo, so the __NO_ROSTER__ fallback
# treats any Bot author as a reviewer whose own comment never counts as an answer -> "problems".
problem_fixture() {
    local body
    body="$(printf 'x%.0s' {1..150})"
    jq -nc --arg body "$body" '{data: {repository: {pullRequest: {reviewThreads: {
        totalCount: 1,
        nodes: [{isResolved: false, path: "a.sh", comments: {
            totalCount: 1,
            nodes: [{author: {login: "coderabbitai", __typename: "Bot"}, body: $body}]
        }}]
    }}}}}' >"$FIXTURE_DIR/$1.json"
}

# --- fast path: unchanged branch-scoped behaviour ------------------------------------------------

@test "fast path: a clean current-branch PR exits 0" {
    export PR_VIEW_NUMBER=42
    clean_fixture 42
    run bash -c "payload | '$HOOK'"
    [ "$status" -eq 0 ]
}

@test "fast path: a current-branch PR with problems blocks, referencing that PR only" {
    export PR_VIEW_NUMBER=42
    problem_fixture 42
    run bash -c "payload | '$HOOK'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"PR #42"* ]]
    [[ "$output" != *"repo-wide"* ]]
}

# --- stop_hook_active is honoured, and short-circuits before any gh call -------------------------

@test "stop_hook_active exits 0 without ever calling gh" {
    export PR_VIEW_NUMBER=42
    problem_fixture 42
    run bash -c "payload true | '$HOOK'"
    [ "$status" -eq 0 ]
    [ ! -s "$PRLIST_LOG" ]
    [ ! -s "$GRAPHQL_LOG" ]
}

# --- the regression: no PR for this branch/HEAD is exactly the silent case #397 reports ----------

@test "no PR for the current branch: a problem PR elsewhere in the repo now blocks the stop" {
    # PR_VIEW_NUMBER unset == detached HEAD / branch with no PR, exactly the orchestrator-session
    # shape #397 describes. The OLD branch-scoped code exits 0 here without ever looking further
    # -- this is the case that must now fall back to a repo-wide scan instead.
    export PR_LIST=$'10\n20'
    clean_fixture 10
    problem_fixture 20
    run bash -c "payload | '$HOOK'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"repo-wide scan"* ]]
    [[ "$output" == *"PR #20"* ]]
}

@test "no PR for the current branch, every open PR clean: exits 0" {
    export PR_LIST=$'10\n20'
    clean_fixture 10
    clean_fixture 20
    run bash -c "payload | '$HOOK'"
    [ "$status" -eq 0 ]
}

@test "no PR for the current branch, no open PRs at all: exits 0" {
    export PR_LIST=""
    run bash -c "payload | '$HOOK'"
    [ "$status" -eq 0 ]
}

@test "a gh pr list failure fails open" {
    export PR_LIST=""
    export PR_LIST_FAIL=1
    run bash -c "payload | '$HOOK'"
    [ "$status" -eq 0 ]
}

# --- bound the cost: short-circuit and cache ------------------------------------------------------

@test "the repo-wide scan stops at the first non-clean PR, never querying the rest" {
    export PR_LIST=$'10\n20\n30'
    problem_fixture 10
    clean_fixture 20
    clean_fixture 30
    run bash -c "payload | '$HOOK'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"PR #10"* ]]
    run grep -qx 10 "$GRAPHQL_LOG"
    [ "$status" -eq 0 ]
    run grep -qx 20 "$GRAPHQL_LOG"
    [ "$status" -ne 0 ]
    run grep -qx 30 "$GRAPHQL_LOG"
    [ "$status" -ne 0 ]
}

@test "a repeat scan within the cache TTL reuses the cached verdict, no second pr-list call" {
    export PR_LIST=$'10\n20'
    export OPEN_THREADS_NUDGE_CACHE_TTL=600
    clean_fixture 10
    problem_fixture 20
    run bash -c "payload false sess-1 | '$HOOK'"
    [ "$status" -eq 2 ]
    [ "$(wc -l <"$PRLIST_LOG")" -eq 1 ]

    run bash -c "payload false sess-1 | '$HOOK'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"PR #20"* ]]
    [ "$(wc -l <"$PRLIST_LOG")" -eq 1 ]
}

@test "an expired cache entry triggers a fresh scan" {
    export PR_LIST=$'10\n20'
    export OPEN_THREADS_NUDGE_CACHE_TTL=600
    clean_fixture 10
    problem_fixture 20
    run bash -c "payload false sess-2 | '$HOOK'"
    [ "$status" -eq 2 ]
    [ "$(wc -l <"$PRLIST_LOG")" -eq 1 ]

    # Force the cached entry to look ten thousand seconds old.
    cache_file="$CLAUDE_CONFIG_DIR/open-threads-nudge/sess-2-o_r"
    [ -f "$cache_file" ]
    old_ts=$(( $(date +%s) - 10000 ))
    jq --argjson ts "$old_ts" '.ts = $ts' "$cache_file" >"$cache_file.tmp"
    mv "$cache_file.tmp" "$cache_file"

    run bash -c "payload false sess-2 | '$HOOK'"
    [ "$status" -eq 2 ]
    [ "$(wc -l <"$PRLIST_LOG")" -eq 2 ]
}
