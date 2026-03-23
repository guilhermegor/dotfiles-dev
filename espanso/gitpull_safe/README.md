# gitpull_safe espanso package

Safely update your local `main` branch from `origin/main` and optionally create a new feature branch.

## Triggers

- `:gitpull`: Runs safe sync flow and prints output.
- `:gitpullb`: Prompts for a branch name, then runs safe sync and creates that branch.

## Terminal wrappers

`setup.sh` creates wrappers in `$HOME/bin`:

- `gitpull-safe`
- `:gitpull`

## Safety checks

The script stops when:

- You are not inside a git repository.
- There are uncommitted or untracked changes.
- A merge, rebase, or cherry-pick is in progress.

Then it runs:

- `git fetch origin --prune`
- `git switch main`
- `git pull --ff-only origin main`

If a branch name is provided, it also runs:

- `git switch -c <branch-name>`

## Files

- `gitpull_safe.sh`: Core safe git sync script.
- `package.yml`: Espanso triggers.
- `setup.sh`: Makes script executable and creates terminal wrapper `:gitpull` in `$HOME/bin`.
	It also creates `gitpull-safe` in `$HOME/bin`.

## Install

From repository root:

```bash
make install_espanso_packages
```

## Manual usage

After setup, terminal wrapper supports:

```bash
gitpull-safe
gitpull-safe feature/my-new-branch

:gitpull
:gitpull feature/my-new-branch
```
