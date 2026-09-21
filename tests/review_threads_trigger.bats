#!/usr/bin/env bats
#
# Contract tests for .github/workflows/review_threads.yml's "Check review-thread
# state" step (dotfiles-dev#431). CodeRabbit posts no pull_request_review and no
# pull_request_review_comment when it finds nothing, so those two triggers alone
# never fire for a clean review and the required check never posts (measured on
# #412: `pulls/412/reviews` length 0, mergeStateStatus BLOCKED forever). The fix
# adds an issue_comment trigger guarded to CodeRabbit's own completion marker,
# but the step itself is the real unit under test here, not the `on:` block —
# actionlint/yamllint already prove the YAML parses; this proves the step's
# bash decides correctly for every event shape it can now receive.
#
# The step's script lives inline in the workflow (`run: |`), not in a sourced
# lib, per dotfiles-dev#431's file scope (workflow + test only — the shared
# ai_clients/claude/hooks/lib/review_thread_gate.sh gate stays untouched). It is
# extracted here with PyYAML instead of parsed with a fragile sed/awk slice, so
# a reformat of the surrounding YAML can't silently desync the test from the
# step it's meant to cover.
#
# Run locally: bats tests/          (install with: sudo apt-get install -y bats)

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORKFLOW="$REPO_ROOT/.github/workflows/review_threads.yml"
    SCRIPT="$(mktemp)"
    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    doc = yaml.safe_load(f)
steps = doc['jobs']['gate']['steps']
step = next(s for s in steps if s.get('name') == 'Check review-thread state')
print(step['run'], end='')
" > "$SCRIPT"
}

teardown() {
    rm -f "$SCRIPT"
}

# run_step EVENT_NAME COMMENT_AUTHOR COMMENT_BODY REVIEW_COUNT THREADS_JSON [ASSOCIATION]
# Stubs `gh` for both calls the step makes (`pr view --json files`,
# `pr view --json reviews`) plus the GraphQL call review_thread_gate.sh makes,
# then runs the extracted script from the repo root so its relative `source`
# resolves.
run_step() {
    local event="$1" author="$2" body="$3" review_count="$4" threads_json="$5"
    local association="${6:-}"
    run env \
        GH_TOKEN=x OWNER=o REPO=r PR_NUMBER=5 \
        EVENT_NAME="$event" COMMENT_AUTHOR="$author" COMMENT_BODY="$body" \
        COMMENT_AUTHOR_ASSOCIATION="$association" \
        REVIEW_COUNT="$review_count" THREADS_JSON="$threads_json" \
        REPO_ROOT="$REPO_ROOT" SCRIPT="$SCRIPT" \
        bash -c '
            cd "$REPO_ROOT" || exit 1
            gh() {
                case "$*" in
                    *"--json files"*)   echo "ai_clients/claude/hooks/lib/foo.sh" ;;
                    *"--json reviews"*) printf "%s\n" "$REVIEW_COUNT" ;;
                    "api graphql"*)     printf "%s" "$THREADS_JSON" ;;
                    *) return 1 ;;
                esac
            }
            export -f gh
            bash "$SCRIPT"
        '
}

# --- the currently-unrepresented case (dotfiles-dev#431's own test ask) -----
# zero submitted reviews, zero review comments, and this run was NOT fired by
# CodeRabbit's completion marker: must reach a DECIDED (failing) state, never
# an absent one — the gate step must itself exit non-zero with a diagnostic.

@test "zero reviews, zero comments, non-marker trigger: fails decided, not absent" {
    run_step "pull_request_review" "" "" 0 '{"data":{"repository":{"pullRequest":{"reviewThreads":{"totalCount":0,"nodes":[]},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"totalCount":0,"nodes":[]}}}}]}}}}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"no reviewer has reported"* ]]
}

# --- blueprintx#213: a rate-limit refusal must not count as a review --------

@test "issue_comment rate-limit refusal: still fails, never a false pass" {
    run_step "issue_comment" "coderabbitai[bot]" \
        "your next included review will be available in 34 minutes" \
        0 '{"data":{"repository":{"pullRequest":{"reviewThreads":{"totalCount":0,"nodes":[]},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"totalCount":0,"nodes":[]}}}}]}}}}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"no reviewer has reported"* ]]
}

# --- blueprintx#213: a random human comment must not count as a review ------

@test "issue_comment from a human, unrelated text: still fails" {
    run_step "issue_comment" "guilhermegor" "LGTM, nice work" \
        0 '{"data":{"repository":{"pullRequest":{"reviewThreads":{"totalCount":0,"nodes":[]},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"totalCount":0,"nodes":[]}}}}]}}}}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"no reviewer has reported"* ]]
}

# --- the bug's own shape: #412 — CodeRabbit reviewed, found nothing ---------
# reviews API length 0 (no formal review object), zero threads, but the
# triggering comment IS CodeRabbit's completion marker: must reach a DECIDED
# (passing) state now, where before #431 the workflow never ran at all.

@test "issue_comment with CodeRabbit's completion marker: clean review passes" {
    run_step "issue_comment" "coderabbitai[bot]" \
        "✅ Action performed — Full review finished." \
        0 '{"data":{"repository":{"pullRequest":{"reviewThreads":{"totalCount":0,"nodes":[]},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"totalCount":0,"nodes":[]}}}}]}}}}}'
    [ "$status" -eq 0 ]
    [[ "$output" != *"no reviewer has reported"* ]]
}

# --- the marker must not paper over a real open thread -----------------------
# Guards against a version of the fix that treats "CodeRabbit commented" as
# "everything is fine" instead of "a reviewer has reported, now check threads".

@test "completion marker present but a thread is still unanswered: fails" {
    run_step "issue_comment" "coderabbitai[bot]" \
        "✅ Action performed — Full review finished." \
        0 '{"data":{"repository":{"pullRequest":{"reviewThreads":{"totalCount":1,"nodes":[{"isResolved":false,"path":"a.sh","comments":{"totalCount":0,"nodes":[]}}]},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"totalCount":0,"nodes":[]}}}}]}}}}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"review gate status=problems"* ]]
}

# --- an ordinary review still works unchanged --------------------------------

@test "a real submitted review (review_count > 0): proceeds past the reported check" {
    run_step "pull_request_review" "" "" 1 '{"data":{"repository":{"pullRequest":{"reviewThreads":{"totalCount":0,"nodes":[]},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"totalCount":0,"nodes":[]}}}}]}}}}}'
    [ "$status" -eq 0 ]
    [[ "$output" != *"no reviewer has reported"* ]]
}

# --- dotfiles-dev#451: the reviewer ladder's fallback review is a report ----
# The ladder (#444/#446/#449) posts its fallback review as an issue_comment
# from the operator's own account — never a review object — so review_count
# stays 0 and only the marker + author_association can tell "reviewed via
# the ladder" apart from "nobody has reported yet".

LADDER_BODY="Fallback review — runtime: codex, model: codex-auto-review (selected by: review-specialized-slug)

No findings."
ZERO_THREADS='{"data":{"repository":{"pullRequest":{"reviewThreads":{"totalCount":0,"nodes":[]},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"totalCount":0,"nodes":[]}}}}]}}}}}'
ONE_OPEN_THREAD='{"data":{"repository":{"pullRequest":{"reviewThreads":{"totalCount":1,"nodes":[{"isResolved":false,"path":"a.sh","comments":{"totalCount":0,"nodes":[]}}]},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"totalCount":0,"nodes":[]}}}}]}}}}}'

@test "ladder marker from OWNER, zero reviews, zero threads: passes" {
    run_step "issue_comment" "guilhermegor" "$LADDER_BODY" 0 "$ZERO_THREADS" "OWNER"
    [ "$status" -eq 0 ]
    [[ "$output" != *"no reviewer has reported"* ]]
}

@test "ladder marker from author_association=NONE: fails" {
    run_step "issue_comment" "guilhermegor" "$LADDER_BODY" 0 "$ZERO_THREADS" "NONE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"no reviewer has reported"* ]]
}

@test "ladder marker from author_association=CONTRIBUTOR: fails" {
    run_step "issue_comment" "guilhermegor" "$LADDER_BODY" 0 "$ZERO_THREADS" "CONTRIBUTOR"
    [ "$status" -ne 0 ]
    [[ "$output" == *"no reviewer has reported"* ]]
}

@test "ladder marker quoted on a non-first line: fails" {
    local quoted="Re-posting for visibility:

$LADDER_BODY"
    run_step "issue_comment" "guilhermegor" "$quoted" 0 "$ZERO_THREADS" "OWNER"
    [ "$status" -ne 0 ]
    [[ "$output" == *"no reviewer has reported"* ]]
}

@test "ladder marker present but a thread is still open: fails" {
    run_step "issue_comment" "guilhermegor" "$LADDER_BODY" 0 "$ONE_OPEN_THREAD" "OWNER"
    [ "$status" -ne 0 ]
    [[ "$output" == *"review gate status=problems"* ]]
}
