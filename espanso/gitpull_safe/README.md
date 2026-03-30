# gitpull_safe espanso package

Safely update your local `main` branch from `origin/main`, optionally create a new feature branch, or reset the current branch to match `main` without deleting the branch.

## Triggers

- `:git_sync_main`: Runs safe sync flow and prints output.
- `:git_sync_main_create_branch`: Asks if you want to create a branch, shows naming convention hints, then asks for branch name.
	- If you choose `yes`, branch name is required.
	- You can choose whether to skip validation and create anyway if the name is invalid.
	- If you choose `no`, it only syncs local `main`.
- `:git_reset_current_branch_to_main`: Confirms a destructive reset and then makes the current local branch match `main` exactly, without deleting the branch locally or remotely.

## Branch naming convention hint (`:git_sync_main_create_branch`)

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
- `:git_sync_main`
- `:git_sync_main_create_branch`
- `:git_reset_current_branch_to_main`

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

If reset mode is used, it also runs:

- `git switch <current-branch>`
- `git reset --hard main`

When a branch name is provided, it is validated against:

- `^(feature|feat|bugfix|fix|hotfix|release|docs|refactor|chore)/[a-z0-9][a-z0-9.-]*$`

If invalid:

- In interactive terminal use, script asks whether to proceed anyway.
- In non-interactive use, branch creation stops unless `--force-invalid` is provided.

## Files

- `gitpull_safe.sh`: Core safe git sync script.
- `gitpull_safe.sh` also defines the reset-to-main flow used by `:git_reset_current_branch_to_main` and `gitpull-safe --reset-current-branch-to-main`.
- `package.yml`: Espanso triggers.
- `setup.sh`: Makes script executable and creates terminal wrappers in `$HOME/bin`.
	It also creates `gitpull-safe` in `$HOME/bin`.
	It also creates `:git_sync_main`, `:git_sync_main_create_branch`, and `:git_reset_current_branch_to_main` in `$HOME/bin`.

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
gitpull-safe --reset-current-branch-to-main
gitpull-safe invalid_name
gitpull-safe invalid_name --force-invalid

:git_sync_main
:git_sync_main feature/my-new-branch
:git_sync_main_create_branch
:git_reset_current_branch_to_main
```
