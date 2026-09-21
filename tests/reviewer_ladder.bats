#!/usr/bin/env bats
#
# Unit tests for ai_clients/claude/hooks/lib/reviewer_ladder.sh (dotfiles-dev#444).
# Fixture-driven only: no network, no real `codex`/`qwen` invocation. Every probe
# and every runtime/post call is stubbed via the lib's own override hooks
# (REVIEWER_LADDER_*_PROBE, REVIEWER_LADDER_RUN_CMD, REVIEWER_LADDER_POST_CMD).

setup() {
    source "$BATS_TEST_DIRNAME/../ai_clients/claude/hooks/lib/reviewer_ladder.sh"
    FIXTURES="$BATS_TEST_DIRNAME/fixtures/reviewer_ladder"
}

# --- codex resolver ----------------------------------------------------------

@test "resolves the review-specialized slug when present and invocable" {
    export REVIEWER_LADDER_CODEX_CACHE="$FIXTURES/codex_full.json"
    fake_probe() { [ "$1" = "codex-auto-review" ]; }
    export REVIEWER_LADDER_CODEX_PROBE=fake_probe

    local rc=0
    resolve_codex_model || rc=$?
    [ "$rc" -eq 0 ]
    [ "$CODEX_MODEL" = "codex-auto-review" ]
    [ "$CODEX_MODEL_SIGNAL" = "review-specialized-slug" ]
}

@test "codex: never selects by priority — reasoning richness wins regardless of priority value" {
    export REVIEWER_LADDER_CODEX_CACHE="$FIXTURES/codex_no_review.json"
    # Every candidate probes usable — priority=99 (gpt-5.5) and priority=3 (luna)
    # both lose to priority=7 (terra), which has the richest reasoning-level set.
    fake_probe() { return 0; }
    export REVIEWER_LADDER_CODEX_PROBE=fake_probe

    local rc=0
    resolve_codex_model || rc=$?
    [ "$rc" -eq 0 ]
    [ "$CODEX_MODEL" = "gpt-5.6-terra" ]
    [ "$CODEX_MODEL_SIGNAL" = "reasoning-levels-richness" ]
}

@test "codex: falls through to reasoning richness when the review slug is not invocable" {
    export REVIEWER_LADDER_CODEX_CACHE="$FIXTURES/codex_full.json"
    # codex-auto-review exists in the cache but the probe refuses it (entitlement
    # gap) — gpt-reserve (richest reasoning set) must win instead.
    fake_probe() { [ "$1" != "codex-auto-review" ]; }
    export REVIEWER_LADDER_CODEX_PROBE=fake_probe

    local rc=0
    resolve_codex_model || rc=$?
    [ "$rc" -eq 0 ]
    [ "$CODEX_MODEL" = "gpt-reserve" ]
    [ "$CODEX_MODEL_SIGNAL" = "reasoning-levels-richness" ]
}

@test "codex: no review model in the cache falls straight to reasoning richness" {
    export REVIEWER_LADDER_CODEX_CACHE="$FIXTURES/codex_no_review.json"
    fake_probe() { return 0; }
    export REVIEWER_LADDER_CODEX_PROBE=fake_probe

    local rc=0
    resolve_codex_model || rc=$?
    [ "$rc" -eq 0 ]
    [ "$CODEX_MODEL" = "gpt-5.6-terra" ]
}

@test "codex: fails closed when nothing probes usable — a rung that resolves nothing" {
    export REVIEWER_LADDER_CODEX_CACHE="$FIXTURES/codex_full.json"
    fake_probe() { return 1; }
    export REVIEWER_LADDER_CODEX_PROBE=fake_probe

    local rc=0
    resolve_codex_model || rc=$?
    [ "$rc" -eq 1 ]
    [ -z "$CODEX_MODEL" ]
    [ -z "$CODEX_MODEL_SIGNAL" ]
}

@test "codex: fails closed on a malformed cache (no models key), never guesses" {
    export REVIEWER_LADDER_CODEX_CACHE="$FIXTURES/codex_malformed.json"
    fake_probe() { return 0; }
    export REVIEWER_LADDER_CODEX_PROBE=fake_probe

    local rc=0
    resolve_codex_model || rc=$?
    [ "$rc" -eq 1 ]
    [ -z "$CODEX_MODEL" ]
}

@test "codex: fails closed on an empty models array" {
    export REVIEWER_LADDER_CODEX_CACHE="$FIXTURES/codex_empty.json"
    fake_probe() { return 0; }
    export REVIEWER_LADDER_CODEX_PROBE=fake_probe

    run resolve_codex_model
    [ "$status" -eq 1 ]
}

@test "codex: fails closed when the cache file is missing" {
    export REVIEWER_LADDER_CODEX_CACHE="$FIXTURES/does_not_exist.json"
    fake_probe() { return 0; }
    export REVIEWER_LADDER_CODEX_PROBE=fake_probe

    run resolve_codex_model
    [ "$status" -eq 1 ]
}

# --- qwen resolver -------------------------------------------------------

@test "qwen: resolves the account's configured default when it probes usable" {
    export REVIEWER_LADDER_QWEN_SETTINGS="$FIXTURES/qwen_settings.json"
    fake_probe() { [ "$1" = "qwen3.5-plus" ]; }
    export REVIEWER_LADDER_QWEN_PROBE=fake_probe

    local rc=0
    resolve_qwen_model || rc=$?
    [ "$rc" -eq 0 ]
    [ "$QWEN_MODEL" = "qwen3.5-plus" ]
    [ "$QWEN_MODEL_SIGNAL" = "configured-default" ]
}

@test "qwen: falls to the next candidate when the default fails entitlement, and fills fallbacks" {
    export REVIEWER_LADDER_QWEN_SETTINGS="$FIXTURES/qwen_settings.json"
    fake_probe() { [ "$1" != "qwen3.5-plus" ]; }
    export REVIEWER_LADDER_QWEN_PROBE=fake_probe

    local rc=0
    resolve_qwen_model || rc=$?
    [ "$rc" -eq 0 ]
    [ "$QWEN_MODEL" = "qwen3.6-plus" ]
    [ "$QWEN_MODEL_SIGNAL" = "reasoning-capable" ]
    # up to 2 runner-up candidates handed to qwen's native --fallback-model,
    # not probed individually
    [ -n "$QWEN_FALLBACK_MODELS" ]
}

@test "qwen: fails closed on malformed settings (no modelProviders key)" {
    export REVIEWER_LADDER_QWEN_SETTINGS="$FIXTURES/qwen_malformed.json"
    fake_probe() { return 0; }
    export REVIEWER_LADDER_QWEN_PROBE=fake_probe

    local rc=0
    resolve_qwen_model || rc=$?
    [ "$rc" -eq 1 ]
    [ -z "$QWEN_MODEL" ]
}

@test "qwen: fails closed when nothing probes usable" {
    export REVIEWER_LADDER_QWEN_SETTINGS="$FIXTURES/qwen_settings.json"
    fake_probe() { return 1; }
    export REVIEWER_LADDER_QWEN_PROBE=fake_probe

    local rc=0
    resolve_qwen_model || rc=$?
    [ "$rc" -eq 1 ]
}

# --- the ladder ------------------------------------------------------------

@test "ladder: qwen resolves first when both rungs are available" {
    export REVIEWER_LADDER_QWEN_SETTINGS="$FIXTURES/qwen_settings.json"
    export REVIEWER_LADDER_CODEX_CACHE="$FIXTURES/codex_full.json"
    fake_qwen_probe() { return 0; }
    fake_codex_probe() { return 0; }
    export REVIEWER_LADDER_QWEN_PROBE=fake_qwen_probe
    export REVIEWER_LADDER_CODEX_PROBE=fake_codex_probe

    local rc=0
    resolve_fallback_reviewer || rc=$?
    [ "$rc" -eq 0 ]
    [ "$LADDER_RUNTIME" = "qwen" ]
}

@test "ladder: falls through to codex when the qwen rung resolves nothing" {
    export REVIEWER_LADDER_QWEN_SETTINGS="$FIXTURES/qwen_malformed.json"
    export REVIEWER_LADDER_CODEX_CACHE="$FIXTURES/codex_full.json"
    fake_codex_probe() { [ "$1" = "codex-auto-review" ]; }
    export REVIEWER_LADDER_CODEX_PROBE=fake_codex_probe

    local rc=0
    resolve_fallback_reviewer || rc=$?
    [ "$rc" -eq 0 ]
    [ "$LADDER_RUNTIME" = "codex" ]
    [ "$LADDER_MODEL" = "codex-auto-review" ]
}

@test "ladder: neither rung resolves — LADDER_RUNTIME stays none, returns 1" {
    export REVIEWER_LADDER_QWEN_SETTINGS="$FIXTURES/qwen_malformed.json"
    export REVIEWER_LADDER_CODEX_CACHE="$FIXTURES/codex_malformed.json"

    local rc=0
    resolve_fallback_reviewer || rc=$?
    [ "$rc" -eq 1 ]
    [ "$LADDER_RUNTIME" = "none" ]
}

# --- attribution, blast radius --------------------------------------------

@test "attribution line names the runtime, model, and selection signal" {
    run ladder_attribution_line "codex" "codex-auto-review" "review-specialized-slug"
    [[ "$output" == "Fallback review — runtime: codex, model: codex-auto-review (selected by: review-specialized-slug)" ]]
}

@test "already-covered: a higher rung's attribution line blocks a re-review" {
    run ladder_already_covered "some comment
Fallback review — runtime: codex, model: codex-auto-review (selected by: review-specialized-slug)
another comment"
    [ "$status" -eq 0 ]
}

@test "already-covered: no attribution line present is not covered" {
    run ladder_already_covered "just a normal comment, no ladder marker"
    [ "$status" -eq 1 ]
}

@test "candidate gate: a DIRTY PR is never a candidate" {
    run ladder_candidate_ok "DIRTY" "" 1000
    [ "$status" -eq 1 ]
}

@test "candidate gate: pushed 2 minutes ago is skipped (inside the ~10 minute window)" {
    run ladder_candidate_ok "BLOCKED" 1000 1120
    [ "$status" -eq 1 ]
}

@test "candidate gate: pushed 20 minutes ago, not DIRTY, is a valid candidate" {
    run ladder_candidate_ok "BLOCKED" 1000 2200
    [ "$status" -eq 0 ]
}

# --- run_fallback_review orchestration + dry-run ----------------------------

@test "dry-run resolves and reports, but posts nothing and runs no review" {
    export REVIEWER_LADDER_QWEN_SETTINGS="$FIXTURES/qwen_settings.json"
    fake_probe() { return 0; }
    export REVIEWER_LADDER_QWEN_PROBE=fake_probe
    _run_runtime_review() { echo "SHOULD NOT BE CALLED" >&2; return 1; }
    _post_pr_comment() { echo "SHOULD NOT BE CALLED" >&2; return 1; }
    export -f _run_runtime_review _post_pr_comment

    run run_fallback_review o r 42 BLOCKED "" 5000 "" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY RUN"* ]]
    [[ "$output" != *"SHOULD NOT BE CALLED"* ]]
}

@test "already-covered PR is skipped before the resolver ever runs" {
    resolve_fallback_reviewer() { echo "SHOULD NOT RESOLVE" >&2; return 1; }
    export -f resolve_fallback_reviewer

    run run_fallback_review o r 42 BLOCKED "" 5000 \
        "Fallback review — runtime: codex, model: codex-auto-review (selected by: review-specialized-slug)"
    [ "$status" -eq 0 ]
    [[ "$output" != *"SHOULD NOT RESOLVE"* ]]
}

@test "a DIRTY PR is refused before the resolver ever runs" {
    resolve_fallback_reviewer() { echo "SHOULD NOT RESOLVE" >&2; return 1; }
    export -f resolve_fallback_reviewer

    run run_fallback_review o r 42 DIRTY "" 5000 ""
    [ "$status" -eq 1 ]
    [[ "$output" != *"SHOULD NOT RESOLVE"* ]]
}

@test "no rung resolves — run_fallback_review fails closed, posts nothing" {
    export REVIEWER_LADDER_QWEN_SETTINGS="$FIXTURES/qwen_malformed.json"
    export REVIEWER_LADDER_CODEX_CACHE="$FIXTURES/codex_malformed.json"
    _post_pr_comment() { echo "SHOULD NOT BE CALLED" >&2; return 1; }
    export -f _post_pr_comment

    run run_fallback_review o r 42 BLOCKED "" 5000 ""
    [ "$status" -eq 1 ]
    [[ "$output" != *"SHOULD NOT BE CALLED"* ]]
}
