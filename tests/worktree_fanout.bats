#!/usr/bin/env bats
#
# Unit tests for ai_clients/claude/hooks/lib/worktree_fanout.sh's fanout_worktrees() —
# specifically the "pushed with NO PR" predicate (dotfiles-dev#457). "Pushed" must mean
# refs/remotes/origin/<branch> exists, never merely that `@{upstream}` resolves: a worktree
# created with `git worktree add -b <name> origin/master` tracks origin/master as its upstream
# from birth, with no remote ref of its own, and that used to read as "pushed".
#
# Builds a real local bare "origin" plus two real worktrees rather than stubbing `git`, because
# the predicate under test IS git ref plumbing (rev-parse --verify against refs/remotes/origin/*)
# — the same real-repo approach subagent_stop_sweep.sh's own oracle relies on. `gh` needs no stub
# here (unlike tests/free_surface.bats): fanout_worktrees() takes github_ok/json as already-
# resolved arguments, it never shells out to `gh` itself.

setup() {
    source "$BATS_TEST_DIRNAME/../ai_clients/claude/hooks/lib/worktree_fanout.sh"

    bare="$BATS_TEST_TMPDIR/origin.git"
    work="$BATS_TEST_TMPDIR/work"
    git init --quiet --bare -b master "$bare"
    git clone --quiet "$bare" "$work"

    git -C "$work" config user.email test@example.com
    git -C "$work" config user.name test
    echo one > "$work/file.txt"
    git -C "$work" add file.txt
    git -C "$work" commit --quiet -m 'chore: initial commit'
    git -C "$work" push --quiet origin master
    git -C "$work" remote set-head origin -a

    # branchA: created the way `git worktree add -b <name> origin/master` does — upstream
    # resolves (to origin/master), but the branch has no ref of its own on the remote.
    wtA="$BATS_TEST_TMPDIR/wtA"
    git -C "$work" worktree add --quiet -b branchA "$wtA" origin/master

    # branchB: genuinely pushed — origin/branchB exists as its own ref.
    wtB="$BATS_TEST_TMPDIR/wtB"
    git -C "$work" worktree add --quiet -b branchB "$wtB" origin/master
    git -C "$wtB" push --quiet -u origin branchB
}

@test "branch tracking origin/master with no remote ref of its own is not reported pushed" {
    run fanout_worktrees "$work" 1 '[]'
    [ "$status" -eq 0 ]
    [[ ! "$output" == *"branch branchA pushed with NO PR"* ]]
}

@test "branch with a genuine origin/<branch> ref and no PR is reported pushed" {
    run fanout_worktrees "$work" 1 '[]'
    [ "$status" -eq 0 ]
    [[ "$output" == *"branch branchB pushed with NO PR"* ]]
}
