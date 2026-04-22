# distro_config/CLAUDE.md

## Purpose

Distribution-level setup: package installation, toolchains, environment, and GNOME keybindings.

## Scripts

| File | What it does |
|------|-------------|
| `install_programs.sh` | Multi-distro package installer (apt / dnf / pacman / zypper) |
| `install_toolchains.sh` | Dev toolchains (Node, Python, Rust, Go, …) |
| `setup_env.sh` | Shell environment (PATH, env vars, dotfiles symlinks) |
| `ubuntu_workspace.sh` | GNOME workspace count and layout |
| `set_custom_shortcuts.sh` | GNOME custom keybindings via gsettings |
| `irpf_download.sh` | Download the Brazilian IRPF tax program |

## Conventions

- **`print_status <level> <msg>`** with the standard color vars.
- Distro detection via `/etc/os-release` (`$ID`); branch on `apt-get`, `dnf`, `pacman`, `zypper`.
- Use `command -v <tool>` to guard installs; never assume a package is absent.

## Checklist for Every New Install Function

When asked to install any program, complete **all three steps** before reporting the task as done:

1. **Write `install_<name>()`** in `install_programs.sh` — guard with `command_exists`, use `install_package` for multi-distro names.
2. **Add to the menu** — append `"install_<name>:Display Name"` to the `components` array at the bottom of `install_programs.sh`, in the logical position relative to similar tools.
3. **GNOME placement** — if the app has a GUI/frontend, ask the user which folder it belongs in (see table below) and add its `.desktop` entry to `ubuntu_workspace.sh`. If it is CLI-only or a background service, document that explicitly in the function comment.

Never declare the task complete if any of these three steps is missing.

## App Installation Preference Order

When adding a new application, choose the installation method using this priority:

1. **Official `.deb` from vendor** — prefer when the software vendor provides an official `.deb` (e.g. download page or GitHub releases). Follow the `install_fastfetch` pattern: `wget`/`curl` to a `mktemp` dir, `apt-get install -y <file>.deb`, then clean up. Always guard with `command_exists` before downloading.
2. **Flatpak** — use when no official `.deb` exists; sandboxed, distro-agnostic, available on all supported distros.
3. **Homebrew** — use when the app has an official Homebrew formula and no `.deb` or Flatpak; works everywhere but adds PATH complexity.
4. **Snap** — acceptable fallback when `.deb` and Flatpak are unavailable; note that snap confinement can cause issues on some systems.
5. **PWA (Chrome `--app=<url>`)** — use for Google/web-first apps with no native Linux package (e.g. Google Calendar, Google Tasks). Requires Chrome; creates a `.desktop` entry under `~/.local/share/applications/`.
6. **AppImage** — last resort for portable binaries with no managed package; download to `$DOWNLOADS_DIR`, `chmod +x`, and symlink into `/usr/local/bin/`.

Each install function must guard against re-installation with `command_exists` or an equivalent check before attempting any download or package operation.

## GNOME App Placement (`ubuntu_workspace.sh`)

**When adding a new `install_*` function, always ask: should this app be placed in a GNOME folder or pinned to the dock?**

- If it belongs in a **folder**: add its `.desktop` filename to the appropriate `*_app_names` array inside `organize_app_folders()` in `ubuntu_workspace.sh`. Existing folders and their purpose:

  | dconf key | Display name | Typical contents |
  |-----------|--------------|-----------------|
  | `Sistema` | Sistema | System tools, settings, file manager |
  | `Seguranca` | Segurança | Security, antivirus, backup |
  | `Utilitarios` | Utilitários | General utilities (screenshots, image editors…) |
  | `Media` | Media | Video players, audio players, media tools |
  | `Sharing` | Sharing | File-sharing and remote-desktop apps |
  | `IRPF` | IRPF | Brazilian tax program |
  | `DEV` | DEV | IDEs, terminals, DB clients, Docker |
  | `Ereader` | Ereader | E-book readers |
  | `Office` | Office | LibreOffice suite |
  | `OrgPessoal` | Organização Pessoal | Calendars, tasks, email, productivity |
  | `AmbienteVirtual` | Ambiente Virtual | VMs and virtualisation |

- If it belongs on the **dock**: add its `.desktop` filename to the `favorite-apps` gsettings key in the relevant configure function.
- If neither (background service, CLI-only tool): no placement change needed — document this explicitly in the install function comment.

The `.desktop` filename for a PWA created by `install_programs.sh` is always the value passed to `desktop_file` (e.g. `google-tasks.desktop`). For Flatpak apps it is the app ID with `.desktop` suffix (e.g. `com.slack.Slack.desktop`).

## GNOME Custom Keybindings (`set_custom_shortcuts.sh`)

Bindings are managed through three layers:

1. **`set_keybindings_array`** — declares the indexed list of active custom binding paths in
   dconf. The array size must match the number of `set_individual_keybinding` calls exactly.
2. **`set_individual_keybinding <index> <name> <command> <binding>`** — writes `name`,
   `command`, and `binding` for `custom<index>`.
3. **`verify_keybindings`** — checks for conflicts before applying.

### Adding a new shortcut

1. Add the binding string (e.g. `"<Super>b"`) to the `bindings` array in `set_all_keybindings`.
2. Append `'/org/.../custom<N>/'` to `set_keybindings_array` (increment `N`).
3. Call `set_individual_keybinding <N> "<label>" "<command>" "<binding>"`.
4. If the command needs a helper script, create it in `$HOME/.local/bin/` and call it from
   a `create_<name>_script` function, following the `create_copy_path_script` pattern.
5. Update the summary block at the bottom of `set_all_keybindings`.

Binding syntax (GDK format): `<Super>`, `<Ctrl>`, `<Shift>`, `<Alt>` + key.
