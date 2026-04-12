# code_editors/CLAUDE.md

## Purpose

Scripts for setting up and restoring code editor configurations.

## Scripts

| File | What it does |
|------|-------------|
| `vscode.sh` | Install extensions, merge `settings.json`, configure keybindings |
| `vscode_restore.sh` | Restore VS Code config from a backup |
| `bash_profile_snippet.sh` | Append shell aliases/env vars to `~/.bash_profile` |
| `setup_starship_bash.sh` | Install and configure the Starship prompt |

## Conventions

- **Color vars** (`RED`, `GREEN`, `YELLOW`, `BLUE`, `CYAN`, `MAGENTA`, `NC`) declared at top.
- **`print_status <level> <msg>`** — levels: `success` `error` `warning` `info` `config` `section`.
- **`LOG_FILE`** timestamped with `$(date +%Y%m%d_%H%M%S)` and written alongside every action.
- **`set -e`** at the top of scripts where early-exit on error is safe.
- JSON manipulation goes through `jq`; always install it with `install_jq_if_needed` before use.
- Backup any file before overwriting: `cp "$file" "$file.backup_$(date +%Y%m%d_%H%M%S)"`.
- Settings merge strategy: `current * base` (base takes priority) via `jq '. * $critical'`.

## Adding a new editor

1. Create `code_editors/<editor>.sh` following the `print_status` / `LOG_FILE` pattern.
2. Wire it into the root `Makefile` under `editors_setup`.
