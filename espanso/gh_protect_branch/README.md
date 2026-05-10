# gh_protect_branch

Espanso package that applies standard GitHub branch protection to the default branch (`main`, `master`, or whatever `origin/HEAD` points to) of the current git repository.

## Trigger

```
:gh_protect_branch
```

## What it does

1. Shows a confirmation form (defaults to **no**).
2. Detects `owner/repo` from the `origin` remote URL (supports both HTTPS and SSH).
3. Detects the default branch via `git symbolic-ref refs/remotes/origin/HEAD`.
4. Calls `gh api PUT /repos/{owner}/{repo}/branches/{branch}/protection` with:
   - Required PR reviews: 1 approving reviewer, dismiss stale reviews
   - Enforce admins: yes
   - Force pushes: blocked
   - Deletions: blocked
   - Linear history required: yes

## Requirements

- [`gh`](https://cli.github.com/) authenticated with admin rights on the target repository.
- Must be run from inside the target git repository's working tree.

## Install

```bash
make install_espanso_packages
```
