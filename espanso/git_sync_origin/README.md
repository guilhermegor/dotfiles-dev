# git_sync_origin espanso package

Sync all local tracking branches to match the state of origin.

## Trigger

- `:git_sync_origin`: Shows a confirmation form, then runs the full sync.

## What it does

For each local branch that has a configured upstream tracking branch:

| Situation | Action |
|---|---|
| Branch is up to date with origin | Skip (already in sync) |
| Branch is behind origin (no unpushed commits) | Fast-forward to origin |
| Branch is ahead of origin (unpushed commits) | Warn and skip |
| Remote branch was deleted, no unpushed commits | Delete local branch |
| Remote branch was deleted, but its diff is already in the default branch (squash/rebase merge) | Delete local branch |
| Remote branch was deleted, has genuinely unmerged commits | Warn and skip |
| Current branch is behind, working tree dirty | Warn and skip |

Local branches whose remote is gone *and* have no tracking upstream are handled the same way: deleted if fully merged (directly or squashed), otherwise reported.

## Safety guarantees

- A branch is deleted only when its work is provably already on a remote — either every commit is reachable from some remote ref, **or** its entire diff is already contained in the default branch (`origin/master` / `origin/main`). Branches that still carry unmerged work are never modified or deleted.
- The current checked-out branch is never force-updated — only pulled with `--ff-only` if the working tree is clean.
- Squash- and rebase-merges rewrite commits to new SHAs, so `git rev-list --count <branch> --not --remotes` (which compares by commit identity) reports them as unpushed. To avoid leaving these branches behind as phantom "unpushed" cruft, the script also checks patch equivalence: it synthesises a commit holding the branch's whole diff on top of its merge-base and asks `git cherry` whether the default branch already contains that patch.

## Output

```
Fetching origin...

========================================
Sync summary
========================================

Updated (2):
  + feat/user-auth
  + fix/login-bug

Deleted — remote removed (1):
  - chore/old-cleanup

Deleted — squash-merged into master (1):
  - feat/old-squashed-pr

Already in sync (1):
  = master

Skipped — action required (1):
  ! docs/draft (3 unpushed commit(s), remote deleted)
```

## Terminal wrappers

`setup.sh` creates wrappers in `$HOME/bin`:

- `git-sync-origin`
- `:git_sync_origin`

## Install

From repository root:

```bash
make install_espanso_packages
```

## Manual usage

```bash
git-sync-origin
:git_sync_origin
```
