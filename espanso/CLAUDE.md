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

| Package | Trigger | Purpose |
|---------|---------|---------|
| `datetime` | `:date`, `:time`, … | Insert current date/time |
| `gitpull_safe` | `:gitpull` | Safe git pull snippet |
| `git_reset` | `:gitreset` | Git reset snippet |
| `hostname_catcher` | `:hostname` | Insert machine hostname |
| `ipv4_catcher` | `:ipv4` | Insert local IPv4 |
| `kill_port` | `:killport` | fuser / kill command snippet |
| `shortcuts` | `:shortcuts` | List all package triggers |
| `gpg_apt_generate` | `:gpgaptgen` | Generate Ed25519 GPG key and display APT_GPG_* secrets |
| `ssh_generate` | `:sshgen` | SSH keygen command |
| `ssh_list` | `:sshlist` | List SSH keys |

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
