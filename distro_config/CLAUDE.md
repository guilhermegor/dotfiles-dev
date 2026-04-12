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
