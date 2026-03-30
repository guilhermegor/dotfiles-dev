# gitpull_safe espanso package

Safely update your local `main` branch from `origin/main` and optionally create a new feature branch.

## Triggers

- `:gitpull`: Runs safe sync flow and prints output.
- `:gitpullb`: Asks if you want to create a branch, shows naming convention hints, then asks for branch name.
	- If you choose `yes`, branch name is required.
	- You can choose whether to skip validation and create anyway if the name is invalid.
	- If you choose `no`, it only syncs local `main`.

## Branch naming convention hint (`:gitpullb`)

Pattern: `<purpose>/<branch-task>`

Purposes:

- `feature/<name>` or `feat/<name>`
- `bugfix/<description>` or `fix/<description>`
- `hotfix/<description>`
- `release/<version>`
- `docs/<description>`
- `refactor/<description>`
- `chore/<description>`

Examples:

- `feat/user-authentication`
- `fix/login-validation-issue`
- `docs/update-api-reference`

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

When a branch name is provided, it is validated against:

- `^(feature|feat|bugfix|fix|hotfix|release|docs|refactor|chore)/[a-z0-9][a-z0-9.-]*$`

If invalid:

- In interactive terminal use, script asks whether to proceed anyway.
- In non-interactive use, branch creation stops unless `--force-invalid` is provided.

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
gitpull-safe invalid_name
gitpull-safe invalid_name --force-invalid

:gitpull
:gitpull feature/my-new-branch
```
