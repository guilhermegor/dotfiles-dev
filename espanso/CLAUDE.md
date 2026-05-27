# espanso/CLAUDE.md

## Purpose

Espanso text-expander packages. Each subdirectory is one self-contained package.

## Package structure

```
espanso/<package-name>/
    package.yml       ← required: triggers and replacements
    setup.sh          ← optional: runs after the copy step in make install_espanso_packages
```

## Current packages

**Keep this table in sync with `:shortcuts` output whenever a package is added, removed, or its triggers change.**

| Package | Trigger(s) | Purpose |
|---------|-----------|---------|
| `datetime` | `:today`, `:time`, `:now` | Insert current date/time |
| `gitpull_safe` | `:git_sync_main`, `:git_sync_main_create_branch`, `:git_reset_current_branch_to_main` | Safe git pull, optional branch creation, or reset to main |
| `git_reset` | `:gitreset` | Reset git repo hard, clean, reopen VS Code |
| `gpg_apt_generate` | `:gpgaptgen` | Generate passphrase-free Ed25519 GPG key and display APT_GPG_* secrets |
| `hostname_catcher` | `:hostname_catcher` | Get hostname info (short name, FQDN, domain) |
| `ipv4_catcher` | `:ipv4_catcher` | Get local and public IPv4 addresses |
| `kill_port` | `:killport`, `:kp` | Kill processes running on specific ports |
| `shortcuts` | `:shortcuts` | List all package triggers and descriptions |
| `ssh_generate` | `:sshgen` | Interactive SSH key generator with GUI prompts |
| `ssh_list` | `:sshlist` | List SSH public keys and copy selected to clipboard |
| `gh_protect_branch` | `:gh_protect_branch` | Apply standard GitHub branch protection to default branch |
| `git_sync_origin` | `:git_sync_origin` | Sync all local tracking branches to match origin (fast-forward only; warns and skips branches with unpushed commits) |

## `package.yml` conventions

```yaml
name: <package-name>
description: One-line description

matches:
  - trigger: ":<short-keyword>"
    replace: "replacement text"

  # Shell command output:
  - trigger: ":<keyword>"
    replace: false
    action:
      type: shell
      cmd: "bash -lc '<command>'"
```

- Triggers must start with `:` to avoid accidental expansion.
- Use `bash -lc` for shell commands so `~/.bash_profile` is sourced.
- Keep each package focused on a single domain.

## Deployment

```bash
make install_espanso_packages   # copies packages → ~/.config/espanso/packages/
```

Packages are copied verbatim; `setup.sh` runs post-copy if present.
