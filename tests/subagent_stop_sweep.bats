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

# --- sweep_worktrees: residue is scoped to worktrees/agent-*, exactly the #162 pattern -----------

@test "a clean worktree reports none" {
    run sweep_worktrees "$REPO"
    [ "$status" -eq 0 ]
    [[ "$output" == "    none" ]]
}

@test "uncommitted changes in the current tree are reported" {
    # git worktree list always includes the main tree itself; give it a name that matches the
    # residue filter (case "$wt" in *worktrees/agent-*) so this test exercises the report line,
    # not just the "no matching path" skip.
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
