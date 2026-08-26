#!/usr/bin/env bats
#
# Unit tests for ai_clients/claude/hooks/pr_merge_threads_guard.sh
#
# Strategy:
#   - The hook is a stdin->exit-code filter: it reads a PreToolUse JSON payload and exits 0 (allow)
#     or 2 (block), speaking only through stderr.
#   - `gh` is stubbed on PATH. `gh pr view` echoes a PR whose number is the first positional it was
#     given (999 when it got none, i.e. "the current branch"), so a test can assert WHICH PR the
#     guard decided to vet. `gh api graphql` replays a fixture written by the test.
#   - jq is the real one — the completion predicate under test lives in a jq filter.
#
# Run locally:  bats tests/            (install with: sudo apt-get install -y bats)

setup() {
    GUARD="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/ai_clients/claude/hooks/pr_merge_threads_guard.sh"
    REPO="$(mktemp -d)"
    BIN="$REPO/bin"
    mkdir -p "$BIN"
    cd "$REPO"
    export FIXTURE="$REPO/threads.json"

    cat > "$BIN/gh" <<'STUB'
#!/bin/bash
case "$1 $2" in
"pr view")
    shift 2
    num=999
    while [ $# -gt 0 ]; do
        case "$1" in
            --json | -q | --repo) shift 2 ;;
            -*) shift ;;
            *) num="$1"; shift ;;
        esac
    done
    [[ "$num" =~ ^[0-9]+$ ]] || num=555
    printf '{"number":%s,"url":"https://github.com/o/r/pull/%s"}' "$num" "$num"
    ;;
"api graphql")
    cat "$FIXTURE"
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

payload() {
    jq -nc --arg cmd "$1" '{tool_name: "Bash", tool_input: {command: $cmd}}'
}

# $1 = author login, $2 = author __typename, $3 = isResolved, $4 = body
threads_fixture() {
    jq -n --arg login "$1" --arg type "$2" --argjson resolved "$3" --arg body "$4" '
    {data: {repository: {pullRequest: {reviewThreads: {
        totalCount: 1,
        nodes: [{
            isResolved: $resolved,
            path: "hooks/thing.sh",
            comments: {totalCount: 1, nodes: [{author: {login: $login, __typename: $type}, body: $body}]}
        }]
    }}}}}' > "$FIXTURE"
}

LONG_REPLY="Rewrote the predicate to key off author.__typename instead of the login suffix, because \
GraphQL strips the [bot] marker and the suffix test therefore matched nothing at all."

# --- the merge TARGET, not the current branch --------------------------------------------------

@test "resolves the PR number when it follows a flag" {
    threads_fixture "coderabbitai" "Bot" false "finding"
    run bash -c "payload 'gh pr merge --squash 42' | '$GUARD'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"PR #42"* ]]
}

@test "resolves the PR number when it follows the subcommand" {
    threads_fixture "coderabbitai" "Bot" false "finding"
    run bash -c "payload 'gh pr merge 42 --squash' | '$GUARD'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"PR #42"* ]]
}

@test "falls back to the current branch when no target is given" {
    threads_fixture "coderabbitai" "Bot" false "finding"
    run bash -c "payload 'gh pr merge --squash' | '$GUARD'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"PR #999"* ]]
}

@test "a word inside --body is not mistaken for the target" {
    threads_fixture "coderabbitai" "Bot" false "finding"
    run bash -c "payload 'gh pr merge --squash --body 77' | '$GUARD'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"PR #999"* ]]
}

# --- a bot comment is never an answer ----------------------------------------------------------

@test "bot-only thread is not an answer even without a roster file" {
    # GraphQL returns `coderabbitai`, never `coderabbitai[bot]`, so the old login-suffix test
    # counted every bot as a human and reported unanswered findings as replied.
    threads_fixture "coderabbitai" "Bot" true "$LONG_REPLY"
    run bash -c "payload 'gh pr merge 42' | '$GUARD'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"no reply from anyone outside the reviewer roster"* ]]
}

@test "a substantive human reply on a resolved thread passes" {
    threads_fixture "guilhermegor" "User" true "$LONG_REPLY"
    run bash -c "payload 'gh pr merge 42' | '$GUARD'"
    [ "$status" -eq 0 ]
}

@test "a human reply on an unresolved thread still blocks" {
    threads_fixture "guilhermegor" "User" false "$LONG_REPLY"
    run bash -c "payload 'gh pr merge 42' | '$GUARD'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"still OPEN"* ]]
}

# --- a short page is not a clean PR ------------------------------------------------------------

@test "blocks when more review threads exist than one page can hold" {
    threads_fixture "guilhermegor" "User" true "$LONG_REPLY"
    jq '.data.repository.pullRequest.reviewThreads.totalCount = 143' "$FIXTURE" > "$FIXTURE.tmp"
    mv "$FIXTURE.tmp" "$FIXTURE"
    run bash -c "payload 'gh pr merge 42' | '$GUARD'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"UNREADABLE"* ]]
    [[ "$output" == *"143 review threads"* ]]
}

@test "blocks when a thread holds more comments than one page can hold" {
    threads_fixture "guilhermegor" "User" true "$LONG_REPLY"
    jq '.data.repository.pullRequest.reviewThreads.nodes[0].comments.totalCount = 80' "$FIXTURE" \
        > "$FIXTURE.tmp"
    mv "$FIXTURE.tmp" "$FIXTURE"
    run bash -c "payload 'gh pr merge 42' | '$GUARD'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"80 comments, only 1 read"* ]]
}

# --- fails open, never on its own blindness ----------------------------------------------------

@test "ignores a command that is not gh pr merge" {
    threads_fixture "coderabbitai" "Bot" false "finding"
    run bash -c "payload 'gh pr view 42' | '$GUARD'"
    [ "$status" -eq 0 ]
}

@test "stands aside for the documented escape hatch" {
    threads_fixture "coderabbitai" "Bot" false "finding"
    run bash -c "payload 'ALLOW_UNRESOLVED_THREADS=1 gh pr merge 42' | '$GUARD'"
    [ "$status" -eq 0 ]
}
