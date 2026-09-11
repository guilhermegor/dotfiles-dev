#!/usr/bin/env bats
#
# Unit tests for ai_clients/claude/hooks/lib/review_thread_gate.sh
#
# Scope: `_gate_problems_filter`, the jq program that decides whether a review thread still
# needs a reply or a resolve. It is tested against fixtures rather than through
# gate_pr_thread_state(), which needs a live GitHub API.
#
# Why this file exists: the filter aborted with `jq: error: Cannot index array with string
# "author"` (exit 5) whenever a roster file was present AND the PR had at least one thread. The
# workflow runs the gate under `set -euo pipefail`, so the step died before printing any verdict
# -- a required check failing with no diagnostic. It stayed invisible because every PR gated
# until dotfiles-dev#325 had zero threads, and `nodes[]` over an empty list never evaluates the
# body. A fixture with one thread is all it takes to catch it, which is what these tests are.
#
# Run locally:  bats tests/            (install with: sudo apt-get install -y bats)

setup() {
    GATE="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/ai_clients/claude/hooks/lib/review_thread_gate.sh"
    # A body long enough to count as substantive (the filter's --argjson min is 100 chars).
    LONG_BODY="$(printf 'x%.0s' {1..150})"
}

# thread_fixture <isResolved> <human-reply-body>
# One review thread: a bot comment, then a human reply of the given body.
thread_fixture() {
    jq -nc --argjson resolved "$1" --arg bot "$LONG_BODY" --arg human "$2" '{
      data: { repository: { pullRequest: { reviewThreads: {
        totalCount: 1,
        nodes: [ { isResolved: $resolved, path: "a.sh", comments: {
          totalCount: 2,
          nodes: [
            { author: { login: "coderabbitai", __typename: "Bot"  }, body: $bot   },
            { author: { login: "guilhermegor", __typename: "User" }, body: $human }
          ] } } ] } } } }
    }'
}

# run_filter <fixture-json> <roster>
run_filter() {
    run bash -c "source '$GATE'; printf '%s' '$1' \
        | jq -r --argjson min 100 --arg roster '$2' \"\$(_gate_problems_filter)\""
}

# --- the regression: a roster + a thread used to abort the whole program ------------------------

@test "roster present, thread answered and resolved: silent, exit 0 (was jq exit 5)" {
    run_filter "$(thread_fixture true "$LONG_BODY")" "coderabbitai"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "roster present: does not abort with 'Cannot index array with string'" {
    # The precise failure mode. Asserted by name so a future rewrite that reintroduces
    # `$bots | index(.author.login)` fails here with an explanatory message.
    run_filter "$(thread_fixture false "$LONG_BODY")" "coderabbitai"
    [[ "$output" != *"Cannot index array"* ]]
    [ "$status" -eq 0 ]
}

# --- the verdicts themselves --------------------------------------------------------------------

@test "answered but unresolved: asks for a RESOLVE" {
    run_filter "$(thread_fixture false "$LONG_BODY")" "coderabbitai"
    [ "$status" -eq 0 ]
    [[ "$output" == *"a.sh"* ]]
    [[ "$output" == *"RESOLVING"* ]]
}

@test "no substantive human reply: asks for a REPLY" {
    # "ok" is under the 100-char floor, so it does not count as an answer.
    run_filter "$(thread_fixture true "ok")" "coderabbitai"
    [ "$status" -eq 0 ]
    [[ "$output" == *"needs a REPLY"* ]]
}

@test "a roster member's own comment never counts as the answer" {
    # Only the bot speaks, at length. Resolved or not, that is not somebody answering it.
    fixture="$(jq -nc --arg bot "$LONG_BODY" '{
      data: { repository: { pullRequest: { reviewThreads: {
        totalCount: 1,
        nodes: [ { isResolved: true, path: "a.sh", comments: {
          totalCount: 1,
          nodes: [ { author: { login: "coderabbitai", __typename: "Bot" }, body: $bot } ]
        } } ] } } } }
    }')"
    run_filter "$fixture" "coderabbitai"
    [ "$status" -eq 0 ]
    [[ "$output" == *"needs a REPLY"* ]]
}

# --- the no-roster fallback, which takes the other branch entirely -------------------------------

@test "__NO_ROSTER__ falls back to __typename and still exits 0" {
    run_filter "$(thread_fixture true "$LONG_BODY")" "__NO_ROSTER__"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "__NO_ROSTER__: a Bot comment does not count as the answer" {
    fixture="$(jq -nc --arg bot "$LONG_BODY" '{
      data: { repository: { pullRequest: { reviewThreads: {
        totalCount: 1,
        nodes: [ { isResolved: true, path: "a.sh", comments: {
          totalCount: 1,
          nodes: [ { author: { login: "somebot", __typename: "Bot" }, body: $bot } ]
        } } ] } } } }
    }')"
    run_filter "$fixture" "__NO_ROSTER__"
    [ "$status" -eq 0 ]
    [[ "$output" == *"needs a REPLY"* ]]
}

# --- no threads at all: the shape that hid the bug for its whole lifetime ------------------------

@test "zero threads: silent, exit 0 (this is why the bug went unseen)" {
    fixture='{"data":{"repository":{"pullRequest":{"reviewThreads":{"totalCount":0,"nodes":[]}}}}}'
    run_filter "$fixture" "coderabbitai"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
