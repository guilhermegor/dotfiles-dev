# Design: Env & Memory Backup/Restore Bash Scripts

**Date:** 2026-04-12
**Status:** Approved

## Overview

Four standalone zenity-based bash scripts in `storage/` that implement the logic
from the `backup-env`, `restore-env`, `export-memory`, and `restore-memory` Claude
Code commands — but run as GUI shortcuts without a terminal.

## File Layout

```
storage/
  backup_env.sh       → ~/.local/bin/backup-env.sh
  export_memory.sh    → ~/.local/bin/export-memory.sh
  restore_env.sh      → ~/.local/bin/restore-env.sh
  restore_memory.sh   → ~/.local/bin/restore-memory.sh
```

The Makefile gains a `install_backup_tools` target that:
1. Copies all 4 scripts to `~/.local/bin/` and `chmod +x`s them.
2. Registers 4 GNOME custom shortcuts via `gsettings`.

## Keyboard Shortcuts

| Script | Binding | Semantic |
|---|---|---|
| `backup-env.sh` | `<Super><Shift>e` | **E**nv write |
| `export-memory.sh` | `<Super><Shift>m` | **M**emory write |
| `restore-env.sh` | `<Super><Alt>e` | **E**nv read back |
| `restore-memory.sh` | `<Super><Alt>m` | **M**emory read back |

No collision with existing custom shortcuts (`<Super>b/c/e/j/k/r/t`, `<Super><Ctrl>s`,
`<Ctrl><Shift>c/v/Escape`) or common GNOME system bindings.

## Shared Conventions (all 4 scripts)

- Read `CLAUDE_BACKUP_DIR` from `~/.claude/.env` (`grep CLAUDE_BACKUP_DIR`).
- If `CLAUDE_BACKUP_DIR` is unset or the path is inaccessible, show a zenity error and exit.
- Use `notify-send` for non-blocking start notifications (low urgency).
- Use `zenity --info` / `zenity --error` for final summaries (blocking).
- Use `zenity --progress --pulsate` during long operations (rsync, multi-repo scan).
- Follow the `backup_external_ssd.sh` pattern: no terminal, no `print_status`, pure zenity.

## Script: backup_env.sh

**Trigger:** `<Super><Shift>e`

**Flow:**
1. Read `CLAUDE_BACKUP_DIR` → set `TARGET=$CLAUDE_BACKUP_DIR/env_files`.
2. `mkdir -p "$TARGET"` — error + exit on failure.
3. Find all git repos under `~/github` (dirs containing `.git/`), up to 2 levels deep.
4. For each repo: run `find <repo> -maxdepth 1 -name ".env*" ! -name "*.md"`, then
   `git -C <repo> check-ignore --quiet <file>` to keep only git-ignored files.
5. Build a zenity checklist: columns `Repo | File | Path`. Pre-check all rows.
6. User picks subset (or cancels → exit).
7. For each selected file:
   - `project_name=$(basename <repo>)`
   - `env_name` = filename with leading dot stripped (`.env.prd` → `env.prd`)
   - `timestamp=$(date +%Y%m%d_%H%M%S)`
   - destination: `$TARGET/<project_name>.<env_name>_<timestamp>`
   - `cp <file> <destination>`; record success/failure per file.
8. `notify-send` summary + zenity --info with backed-up and failed lists.

## Script: export_memory.sh

**Trigger:** `<Super><Shift>m`

**Flow:**
1. Read `CLAUDE_BACKUP_DIR` — error + exit if unset/inaccessible.
2. `SNAPSHOT=$CLAUDE_BACKUP_DIR/$(date +%Y-%m-%d_%H%M%S)`.
3. Spawn zenity --progress --pulsate (background).
4. `mkdir -p "$SNAPSHOT/commands" "$SNAPSHOT/settings"`.
5. `rsync -a ~/.claude/commands/*.md "$SNAPSHOT/commands/"` (if any exist).
6. Copy `~/.claude/settings.json` and `~/.claude/CLAUDE.md` to `$SNAPSHOT/settings/`
   (skip silently if absent).
7. For each dir under `~/.claude/projects/`:
   - Extract readable name = last `_`-separated segment after stripping the
     `-home-<user>-github-` prefix.
   - Skip if no `memory/` dir and no `CLAUDE.md`.
   - `mkdir -p "$SNAPSHOT/projects/<name>/memory"`.
   - `rsync -a <project>/memory/ "$SNAPSHOT/projects/<name>/memory/"`.
   - Copy `<project>/CLAUDE.md` if present.
8. `ln -sfn "$SNAPSHOT" "$CLAUDE_BACKUP_DIR/latest"`.
9. Kill progress dialog; `notify-send` + zenity --info with project count, memory
   file count, total size, and snapshot path.

## Script: restore_env.sh

**Trigger:** `<Super><Alt>e`

**Flow:**
1. Read `CLAUDE_BACKUP_DIR` → set `SOURCE=$CLAUDE_BACKUP_DIR/env_files`.
2. `ls "$SOURCE"` — error + exit if inaccessible.
3. Find all files matching `<project>.<env>_<YYYYMMDD_HHMMSS>` pattern.
4. Group by project, then by env type; keep latest per env type as default candidate.
5. Build zenity checklist: columns `Project | Env file | Date`. Pre-check all rows.
6. User picks subset (or cancels → exit).
7. **Confirmation dialog:** "Restore N env file(s)? This will modify your project roots."
8. For each selected backup:
   - Derive git root: `~/github/<project>`.
   - Destination: `<git_root>/.<env_name>`.
   - If destination exists → zenity --list conflict dialog:
     `Overwrite | Back up first (rename to .<env>.bak_<ts>) | Skip`.
   - Handle choice, then `cp <backup> <destination>`.
9. zenity --info summary (Restored / Skipped / Failed sections).

## Script: restore_memory.sh

**Trigger:** `<Super><Alt>m`

**Flow:**
1. Read `CLAUDE_BACKUP_DIR` — error + exit if unset/inaccessible.
2. List last 10 timestamped snapshots (exclude `latest` symlink and `pre-restore_*`
   prefixed dirs), newest-first. For each compute: project count, memory file count,
   total size.
3. zenity --list: user picks one snapshot (or cancels → exit).
4. **Confirmation dialog:** "Restore snapshot <name>? Current ~/.claude/ will be
   backed up first as pre-restore_<ts>."
5. Create safety backup: `rsync -a ~/.claude/ "$CLAUDE_BACKUP_DIR/pre-restore_<ts>/"`.
6. Spawn zenity --progress --pulsate.
7. Restore:
   - `rsync -a <snapshot>/commands/ ~/.claude/commands/`
   - `cp <snapshot>/settings/settings.json ~/.claude/settings.json` (if exists)
   - `cp <snapshot>/settings/CLAUDE.md ~/.claude/CLAUDE.md` (if exists)
   - For each `<snapshot>/projects/<name>/`: find matching
     `~/.claude/projects/*<name>` dir; rsync `memory/`; copy `CLAUDE.md`.
     Warn (non-fatal) if no match found.
8. Kill progress; notify-send + zenity --info summary.

## Makefile Target

```makefile
install_backup_tools: permissions
	@echo "Installing backup/restore scripts..."
	cp storage/backup_env.sh    ~/.local/bin/backup-env.sh
	cp storage/export_memory.sh ~/.local/bin/export-memory.sh
	cp storage/restore_env.sh   ~/.local/bin/restore-env.sh
	cp storage/restore_memory.sh ~/.local/bin/restore-memory.sh
	chmod +x ~/.local/bin/backup-env.sh \
	         ~/.local/bin/export-memory.sh \
	         ~/.local/bin/restore-env.sh \
	         ~/.local/bin/restore-memory.sh
	@# Register GNOME shortcuts (appends to existing custom list)
	@bash storage/register_shortcuts.sh
	@echo "Done. Shortcuts: Super+Shift+E/M and Super+Alt+E/M"
```

Shortcut registration is extracted to `storage/register_shortcuts.sh` to keep the
Makefile readable and to allow re-running independently.
