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
| Remote branch was deleted, has unpushed commits | Warn and skip |
| Current branch is behind, working tree dirty | Warn and skip |

Local branches with no tracking upstream are always ignored.

## Safety guarantees

- Branches with any commit absent from every remote are never modified or deleted.
- The current checked-out branch is never force-updated — only pulled with `--ff-only` if the working tree is clean.
- Force-delete (`-D`) is used only when `git rev-list --count <branch> --not --remotes` returns zero — meaning every commit on that branch is reachable from some remote ref.

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
