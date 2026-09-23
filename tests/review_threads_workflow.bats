#!/usr/bin/env bats
#
# Invariants for .github/workflows/review_threads.yml (dotfiles-dev#481).
#
# The defect this pins down is not a logic bug inside the gate — the gate was correct. It is
# that the verdict was published to the WRONG COMMIT: for an issue_comment event GitHub runs
# the workflow in the default branch's context, so Actions attached the check-run to master's
# SHA and the required context was absent from every PR head. Nothing went red; 22 PRs simply
# could not merge.
#
# These are structural assertions over the YAML rather than a live run, because the failure is
# a property of WHERE the job reports, which no local execution can exercise.

setup() {
    WORKFLOW="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/.github/workflows/review_threads.yml"
    RUN_SCRIPT="$BATS_TEST_TMPDIR/run.sh"
    python3 - "$WORKFLOW" "$RUN_SCRIPT" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
step = next(s for s in doc["jobs"]["gate"]["steps"] if "run" in s)
open(sys.argv[2], "w").write(step["run"])
PY
}

@test "the job may write checks — without it every publish 403s" {
    run python3 -c "
import yaml,sys
d = yaml.safe_load(open(sys.argv[1]))
print((d.get('permissions') or {}).get('checks',''))
" "$WORKFLOW"
    [ "$status" -eq 0 ]
    [ "$output" = "write" ]
}

@test "the check-run targets the PR head, never the event's own SHA" {
    grep -q 'HEAD_SHA=.*pulls/\$PR_NUMBER' "$RUN_SCRIPT"
    grep -q 'head_sha:\$s' "$RUN_SCRIPT"
    # github.sha is master for issue_comment — the whole defect. It must not be the source.
    run grep -c 'github\.sha' "$RUN_SCRIPT"
    [ "$output" -eq 0 ]
}

@test "no success path terminates without publishing a verdict" {
    # Strip the report() helper, whose own `exit 0` is the single legitimate one. Anything
    # left that exits 0 is a path that ends with no check-run on the PR head — which is the
    # selective-skip regression: "not required" still leaves the PR blocked.
    python3 - "$RUN_SCRIPT" "$BATS_TEST_TMPDIR/stripped.sh" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
stripped = re.sub(r"\n\s*report\(\) \{.*?\n\s*\}\n", "\n", src, flags=re.S)
assert "report() {" not in stripped, "report() helper was not stripped"
open(sys.argv[2], "w").write(stripped)
PY
    run grep -c 'exit 0' "$BATS_TEST_TMPDIR/stripped.sh"
    [ "$output" -eq 0 ]
}

@test "the only non-zero exit is an unpublishable verdict, not a failing one" {
    # A failing gate must still report `failure` and exit 0: the check-run carries the verdict.
    # Exiting non-zero to mirror it would leave the run red with nothing on the PR.
    grep -q 'could not publish the check-run' "$RUN_SCRIPT"
    run grep -c 'exit 1' "$RUN_SCRIPT"
    [ "$output" -eq 1 ]
}

@test "all four outcomes publish: two success, two failure" {
    run grep -c 'report success' "$RUN_SCRIPT"
    [ "$output" -eq 2 ]
    run grep -c 'report failure' "$RUN_SCRIPT"
    [ "$output" -eq 2 ]
}

@test "issue_comment is still a trigger — #431's fix is not undone by this one" {
    run python3 -c "
import yaml,sys
print(sorted((yaml.safe_load(open(sys.argv[1])).get(True) or {}).keys()))
" "$WORKFLOW"
    [[ "$output" == *"issue_comment"* ]]
    [[ "$output" == *"pull_request_review"* ]]
    [[ "$output" == *"pull_request_review_comment"* ]]
}

@test "checkout is pinned to the default branch, never the event's ref" {
    # The privileged half of #481: `checks: write` makes the sourced gate library worth
    # attacking. For pull_request_review/pull_request_review_comment GITHUB_REF is the PR
    # MERGE REF, so a bare checkout would run PR-controlled code with a token that can
    # publish a passing required check without consulting gate_pr_thread_state at all.
    run python3 -c "
import yaml,sys
d = yaml.safe_load(open(sys.argv[1]))
step = next(s for s in d['jobs']['gate']['steps'] if 'checkout' in str(s.get('uses','')))
print((step.get('with') or {}).get('ref',''))
" "$WORKFLOW"
    [ "$status" -eq 0 ]
    [[ "$output" == *"default_branch"* ]]
}
