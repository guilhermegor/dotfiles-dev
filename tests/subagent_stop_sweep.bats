#!/usr/bin/env bats
#
# Unit tests for ai_clients/claude/hooks/subagent_stop_sweep.sh (dotfiles-dev#167, #195)
#
# Strategy:
#   - The script unconditionally runs `main "$@"` at the bottom, so `source`-ing it as-is would
#     fire a live sweep. `head -n -1` strips that trailing call before sourcing, leaving every
#     function defined and callable in isolation — the same functions the SubagentStop hook and
#     the versioned `s:dev-loop` step 2 call both rely on.
#   - `gh` is stubbed on PATH; `git` is the real `/usr/bin/git` (the script hardcodes that path,
#     never the rtk proxy) run against a throwaway local repo — no network required, since the
#     functions under test never depend on `origin` resolving to a real GitHub host.
#
# Run locally:  bats tests/            (install with: sudo apt-get install -y bats)

setup() {
    SWEEP_SRC="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/ai_clients/claude/hooks/subagent_stop_sweep.sh"
    REPO="$(mktemp -d)"
    BIN="$REPO/bin"
    mkdir -p "$BIN"
    export PATH="$BIN:$PATH"

    # Functions only — main() is never invoked by sourcing this. HOOK_DIR resolves relative to
    # wherever this gets sourced from, so its `source "$HOOK_DIR/lib/review_thread_gate.sh"` and
    # `source "$HOOK_DIR/lib/free_surface.sh"` lines each need a real copy sitting next to it.
    FUNCS="$REPO/sweep_funcs.sh"
    head -n -1 "$SWEEP_SRC" > "$FUNCS"
    mkdir -p "$REPO/lib"
    cp "$(dirname "$SWEEP_SRC")/lib/review_thread_gate.sh" "$REPO/lib/"
    cp "$(dirname "$SWEEP_SRC")/lib/free_surface.sh" "$REPO/lib/"
    source "$FUNCS"

    cd "$REPO" || return 1
    git init -q .
    git config user.email t@t.example
    git config user.name t
    git commit -q --allow-empty -m init

    # `ls-remote --heads origin` (used by free_dispatch_surface / sweep_orphan_branches) needs a
    # real "origin" remote — a local bare repo satisfies it with no network involved.
    git init -q --bare "$REPO/origin.git"
    git remote add origin "$REPO/origin.git"
    git push -q origin HEAD:refs/heads/main
}

teardown() {
    rm -rf "$REPO"
}

stub_gh() {
    # Env-driven stub for every call gate_free_surface makes. Where the library passes --jq, the
    # stub prints the post-jq value; where it pipes to jq itself, the stub prints raw JSON.
    #   $1 = open issue numbers (newline-separated)
    #   $2 = closingIssuesReferences numbers across ALL PRs, open and merged (space-separated)
    #   GH_FAIL=1 makes every call fail, to exercise the UNKNOWN path
    local refs="" n
    for n in $2; do refs="$refs{\"closingIssuesReferences\":{\"nodes\":[{\"number\":$n}]}},"; done
    refs="${refs%,}"
    cat > "$BIN/gh" <<STUB
#!/bin/bash
[ "\${GH_FAIL:-0}" = 1 ] && exit 1
case "\$*" in
"api repos/o/r --jq .default_branch") echo main ;;
"pr list"*) echo '[]' ;;
"api repos/o/r/branches"*) echo main ;;
"api graphql"*) printf '%s\n' '{"data":{"search":{"pageInfo":{"hasNextPage":false},"nodes":[$refs]}}}' ;;
"issue list"*) printf '%s\n' '$1' ;;
*) exit 1 ;;
esac
STUB
    chmod +x "$BIN/gh"
}

# --- free_dispatch_surface: exact claim via closingIssuesReferences, not a guess -----------------

@test "an issue no PR closes is free" {
    stub_gh '10
20
30' '20'
    run free_dispatch_surface "o/r"
    [ "$status" -eq 0 ]
    [[ "$output" == "#10 #30" ]]
}

@test "a branch name ending in -<issue> no longer claims it (heuristic disqualified, #340)" {
    stub_gh '10
20' ''
    git push -q origin HEAD:refs/heads/feat/widget-10
    run free_dispatch_surface "o/r"
    [ "$status" -eq 0 ]
    [[ "$output" == "#10 #20" ]]
}

@test "every issue claimed leaves no output at all" {
    # Exit status 1 here is the function's own last-command status (an empty free_list makes its
    # trailing `[ ... -gt 0 ] && printf` false) — harmless, since main() only ever reads stdout.
    stub_gh '10' '10'
    run free_dispatch_surface "o/r"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "a gh API failure reports UNKNOWN, never an empty surface" {
    stub_gh '10' ''
    GH_FAIL=1 run free_dispatch_surface "o/r"
    [ "$status" -eq 1 ]
    [[ "$output" == "UNKNOWN" ]]
}

# --- sweep_worktrees: every linked worktree is residue, whatever it is named ---------------------

@test "a clean worktree reports none" {
    run sweep_worktrees "$REPO"
    [ "$status" -eq 0 ]
    [[ "$output" == "    none" ]]
}

@test "a worktree not named agent-* is residue too" {
    # A resumed agent's worktree was created by hand as `worktrees/issue-356`; the old
    # `*worktrees/agent-*` filter skipped it and the step printed "none" while it held two
    # uncommitted files.
    WT="$REPO/worktrees/issue-356"
    mkdir -p "$(dirname "$WT")"
    git worktree add -q -b issuebranch "$WT" >/dev/null
    echo dirty > "$WT/f.txt"
    run sweep_worktrees "$REPO"
    [[ "$output" == *"issuebranch: 1 uncommitted"* ]]
}

@test "the main checkout is not reported as residue" {
    echo dirty > "$REPO/mainfile.txt"
    run sweep_worktrees "$REPO"
    [ "$status" -eq 0 ]
    [[ "$output" == "    none" ]]
}

@test "uncommitted changes in a linked worktree are reported" {
    WT="$REPO/worktrees/agent-test"
    mkdir -p "$(dirname "$WT")"
    git worktree add -q -b wtbranch "$WT" >/dev/null
    echo dirty > "$WT/f.txt"
    run sweep_worktrees "$REPO"
    # Status 1 is the function's own last-command status when residue is found (the trailing
    # `[ "$any" = "0" ] && echo none` is false) — harmless, since main() only reads stdout.
    [ "$status" -eq 1 ]
    [[ "$output" == *"uncommitted"* ]]
}

# --- sweep_orphan_branches: a pushed stash reads as a snapshot, never a missing-PR branch --------
# dotfiles-dev#399: `subagent_stop_sweep.sh`'s [3] check used to print every branch with no PR the
# same way, so a pushed `git stash` (tip titled `WIP on <branch>: ...` by git stash itself) read
# as unfinished work missing a PR, round after round, on blueprintx's `rescue/pep8-naming-422-wip`.

stub_gh_orphan() {
    # ORPHAN_PR_HEADS      = head labels ("<owner>:<branch>") the head-listing query returns
    # ORPHAN_PR_NUMS       = PR numbers the state=all query returns (space/newline separated)
    # ORPHAN_PR_FILES_<n>  = space-separated filenames PR <n> touches
    # ORPHAN_FAIL_HEADS=1     = the head-listing call fails (exit 1)
    # ORPHAN_FAIL_PULLS_ALL=1 = the state=all PR-listing call fails (exit 1)
    # ORPHAN_FAIL_FILES=1     = every per-PR files call fails (exit 1)
    # Clauses discriminate on the --jq expression, never on the query string: both
    # callers now hit `pulls?state=all`, and matching the query alone sent the
    # head-listing call to `*) exit 1` — which reads as UNKNOWN, not as a stub gap.
    cat > "$BIN/gh" <<'STUB'
#!/bin/bash
case "$*" in
*"head.label"*)
    [ "${ORPHAN_FAIL_HEADS:-0}" = 1 ] && exit 1
    printf '%s\n' "${ORPHAN_PR_HEADS:-}"
    ;;
*"/files"*)
    [ "${ORPHAN_FAIL_FILES:-0}" = 1 ] && exit 1
    n="$(printf '%s' "$*" | sed -n 's#.*pulls/\([0-9]\{1,\}\)/files.*#\1#p')"
    var="ORPHAN_PR_FILES_$n"
    printf '%s\n' "${!var:-}" | tr ' ' '\n'
    ;;
*"pulls?state=all"*)
    [ "${ORPHAN_FAIL_PULLS_ALL:-0}" = 1 ] && exit 1
    printf '%s\n' "${ORPHAN_PR_NUMS:-}"
    ;;
*)
    exit 1
    ;;
esac
STUB
    chmod +x "$BIN/gh"
}

@test "an ordinary branch with no PR is reported as a branch, not a snapshot" {
    stub_gh_orphan
    git checkout -q -b feature/real-work
    echo work > realfile.txt
    git add realfile.txt
    git commit -q -m "add real feature work"
    git push -q origin HEAD:refs/heads/feature/real-work

    run sweep_orphan_branches "$REPO" "o/r" "o" "main"
    [[ "$output" == *"- feature/real-work"* ]]
    [[ "$output" != *"STASH SNAPSHOT"* ]]
}

@test "a pushed stash snapshot is reported with base/diff/overlap context" {
    stub_gh_orphan
    echo original > tracked.txt
    git add tracked.txt
    git commit -q -m "add tracked file"
    git push -q origin HEAD:refs/heads/main
    base="$(git rev-parse --short HEAD)"

    git checkout -q -b rescue/wip-branch
    echo changed > tracked.txt
    git commit -q -am "WIP on feat/foo: $base add tracked file"
    git push -q origin HEAD:refs/heads/rescue/wip-branch

    git checkout -q main
    echo more > other.txt
    git add other.txt
    git commit -q -m "advance main"
    git push -q origin HEAD:refs/heads/main

    run sweep_orphan_branches "$REPO" "o/r" "o" "main"
    [[ "$output" == *"rescue/wip-branch: STASH SNAPSHOT"* ]]
    [[ "$output" == *"main gained 1 commit(s) since this snapshot's base"* ]]
    [[ "$output" == *"tracked.txt: +1/-1"* ]]
    [[ "$output" == *"no open or merged PR touches these files"* ]]
}

@test "a stash snapshot whose files a merged PR already touches names that PR" {
    export ORPHAN_PR_NUMS="7"
    export ORPHAN_PR_FILES_7="tracked.txt"
    stub_gh_orphan

    echo original > tracked.txt
    git add tracked.txt
    git commit -q -m "add tracked file"
    git push -q origin HEAD:refs/heads/main
    base="$(git rev-parse --short HEAD)"

    git checkout -q -b rescue/wip-branch2
    echo changed > tracked.txt
    git commit -q -am "WIP on feat/foo: $base add tracked file"
    git push -q origin HEAD:refs/heads/rescue/wip-branch2

    run sweep_orphan_branches "$REPO" "o/r" "o" "main"
    [[ "$output" == *"same files touched by: #7"* ]]
}

@test "an index-on-<branch> stash title is also recognised" {
    stub_gh_orphan
    git checkout -q -b rescue/index-branch
    echo x > untracked.txt
    git add untracked.txt
    git commit -q -m "index on feat/foo: 0000000 add file"
    git push -q origin HEAD:refs/heads/rescue/index-branch

    run sweep_orphan_branches "$REPO" "o/r" "o" "main"
    [[ "$output" == *"rescue/index-branch: STASH SNAPSHOT"* ]]
}

@test "an untracked-files-on-<branch> stash title (git stash -u) is also recognised" {
    stub_gh_orphan
    git checkout -q -b rescue/untracked-branch
    echo x > newfile.txt
    git add newfile.txt
    git commit -q -m "untracked files on feat/foo: 0000000 add file"
    git push -q origin HEAD:refs/heads/rescue/untracked-branch

    run sweep_orphan_branches "$REPO" "o/r" "o" "main"
    [[ "$output" == *"rescue/untracked-branch: STASH SNAPSHOT"* ]]
}

@test "a branch whose head a PR already carries is not reported at all" {
    export ORPHAN_PR_HEADS="o:feature/has-a-pr"
    stub_gh_orphan
    git checkout -q -b feature/has-a-pr
    echo work > realfile.txt
    git add realfile.txt
    git commit -q -m "work behind an open PR"
    git push -q origin HEAD:refs/heads/feature/has-a-pr

    run sweep_orphan_branches "$REPO" "o/r" "o" "main"
    [[ "$output" != *"feature/has-a-pr"* ]]
}

@test "a fork PR sharing our branch name does not claim our branch" {
    # head.label is "<owner>:<branch>"; matching the bare branch name would read
    # the fork's PR as covering ours and hide a real orphan.
    export ORPHAN_PR_HEADS="someforker:feature/shared-name"
    stub_gh_orphan
    git checkout -q -b feature/shared-name
    echo work > realfile.txt
    git add realfile.txt
    git commit -q -m "our own unclaimed work"
    git push -q origin HEAD:refs/heads/feature/shared-name

    run sweep_orphan_branches "$REPO" "o/r" "o" "main"
    [[ "$output" == *"- feature/shared-name"* ]]
}

@test "a gh API failure listing PR heads reports UNKNOWN, never 'none'" {
    export ORPHAN_FAIL_HEADS=1
    stub_gh_orphan
    git checkout -q -b feature/unclaimed
    echo work > realfile.txt
    git add realfile.txt
    git commit -q -m "work with no PR"
    git push -q origin HEAD:refs/heads/feature/unclaimed

    run sweep_orphan_branches "$REPO" "o/r" "o" "main"
    [[ "$output" == *"UNKNOWN"* ]]
    [[ "$output" != *"none"* ]]
    [[ "$output" != *"- feature/unclaimed"* ]]
}

@test "a gh API failure listing PRs reports UNKNOWN, never a clean overlap" {
    export ORPHAN_FAIL_PULLS_ALL=1
    stub_gh_orphan

    echo original > tracked.txt
    git add tracked.txt
    git commit -q -m "add tracked file"
    git push -q origin HEAD:refs/heads/main
    base="$(git rev-parse --short HEAD)"

    git checkout -q -b rescue/wip-branch3
    echo changed > tracked.txt
    git commit -q -am "WIP on feat/foo: $base add tracked file"
    git push -q origin HEAD:refs/heads/rescue/wip-branch3

    run sweep_orphan_branches "$REPO" "o/r" "o" "main"
    [[ "$output" == *"UNKNOWN — could not list open/merged PRs"* ]]
    [[ "$output" != *"no open or merged PR touches these files"* ]]
}

@test "a gh API failure listing one PR's files reports UNKNOWN, never a clean overlap" {
    export ORPHAN_PR_NUMS="9"
    export ORPHAN_FAIL_FILES=1
    stub_gh_orphan

    echo original > tracked.txt
    git add tracked.txt
    git commit -q -m "add tracked file"
    git push -q origin HEAD:refs/heads/main
    base="$(git rev-parse --short HEAD)"

    git checkout -q -b rescue/wip-branch4
    echo changed > tracked.txt
    git commit -q -am "WIP on feat/foo: $base add tracked file"
    git push -q origin HEAD:refs/heads/rescue/wip-branch4

    run sweep_orphan_branches "$REPO" "o/r" "o" "main"
    [[ "$output" == *"UNKNOWN — could not list files for PR #9"* ]]
    [[ "$output" != *"no open or merged PR touches these files"* ]]
}
