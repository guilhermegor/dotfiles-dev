---
name: c:restore-memory
allowed-tools: Bash(ls *), Bash(find *), Bash(mkdir *), Bash(cp *), Bash(rsync *), Bash(date *), Bash(echo *), Bash(cat *), Bash(tree *), Bash(stat *), Bash(readlink *), Bash(wc *), Read, Glob, AskUserQuestion
description: Restore Claude Code memory, commands, and settings from external backup
---

Restore the current user's Claude Code memory, slash commands, and settings from the backup directory defined in `$CLAUDE_BACKUP_DIR` (from `~/.claude/.env`).

## Steps

1. Verify `$CLAUDE_BACKUP_DIR` is set and the target is accessible (mounted). If not, print an error and stop.

2. List the **last 30 timestamped backup snapshots** found in `$CLAUDE_BACKUP_DIR/`, sorted newest-first. For each, show:
   - Snapshot name (e.g. `2026-04-08_153000`)
   - Number of project folders inside it
   - Total number of memory files
   - Total size

3. Present the list using `AskUserQuestion` with the **most recent snapshot as the first option (recommended)**. Show up to 4 options in the question (the 3 most recent + an "Other" for manual selection). If the user picks "Other", print the full list of up to 30 and ask them to specify the snapshot name.

4. Before restoring, **create a timestamped backup of the current `~/.claude/` state** to `$CLAUDE_BACKUP_DIR/` using the same format as `/export-memory` (prefix: `pre-restore_YYYY-MM-DD_HHMMSS`). This ensures the user can undo the restore.

5. Restore from the selected snapshot:

   The backup structure is:
   ```
   $CLAUDE_BACKUP_DIR/<snapshot>/
     commands/                      ← restore to ~/.claude/commands/
     settings/                      ← restore settings.json, CLAUDE.md to ~/.claude/
     projects/
       <project-name>/              ← restore to the matching ~/.claude/projects/*<project-name>/ directory
         memory/
         CLAUDE.md
   ```

   Restoration rules:
   - **commands/**: `rsync -a` the `*.md` files into `~/.claude/commands/`
   - **settings/settings.json**: merge with current `~/.claude/settings.json` (backup takes priority) using `jq '. * $backup'`. If `jq` is not available, overwrite with the backup copy.
   - **settings/CLAUDE.md**: copy to `~/.claude/CLAUDE.md`
   - **projects/**: For each `<project-name>/` in the backup:
     - Find the matching directory under `~/.claude/projects/` whose path ends with the project name
     - `rsync -a` the `memory/` folder into the matched project's `memory/`
     - Copy `CLAUDE.md` if present
     - If no matching project directory is found, print a warning and skip

6. Print a summary:
   - Pre-restore backup path
   - Snapshot restored from
   - Number of commands, settings, projects, and memory files restored
   - Any projects that were skipped (no match found)

## Important

- ALWAYS create the pre-restore backup before overwriting anything.
- Use `rsync -a` to preserve timestamps.
- When matching `<project-name>` to `~/.claude/projects/` directories, match on the last path segment (e.g. backup folder `stpstone` matches `~/.claude/projects/-home-guilhermegor-github-stpstone`).
- If `~/.claude/projects/` does not exist or has no subdirectories, still restore commands and settings.
- Do NOT delete files that exist locally but are absent from the backup — only overwrite/add.
