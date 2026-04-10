---
name: c:export-memory
allowed-tools: Bash(ls *), Bash(find *), Bash(mkdir *), Bash(cp *), Bash(rsync *), Bash(date *), Bash(echo *), Bash(cat *), Bash(tree *), Read, Glob
description: Export Claude Code memory, commands, and settings to external backup
---

Export the current user's Claude Code memory, slash commands, and settings to the backup directory defined in `$CLAUDE_BACKUP_DIR` (from `~/.claude/.env`).

## Steps

1. Verify `$CLAUDE_BACKUP_DIR` is set and the target is accessible (mounted). If not, print an error and stop.

2. Create a timestamped export under `$CLAUDE_BACKUP_DIR/` with this structure:

```
$CLAUDE_BACKUP_DIR/
  latest/                          ← always-current symlink (overwritten each run)
  YYYY-MM-DD_HHMMSS/              ← timestamped snapshot
    commands/                      ← ~/.claude/commands/*.md
    settings/                      ← ~/.claude/settings.json, CLAUDE.md
    projects/
      <project-name>/              ← human-readable name extracted from directory path
        memory/                    ← all memory/*.md files for that project
        CLAUDE.md                  ← project-level CLAUDE.md if it exists
```

3. For each project directory under `~/.claude/projects/`:
   - Extract a human-readable name from the directory name (e.g. `-home-guilhermegor-github-stpstone` becomes `stpstone`)
   - Copy `memory/` contents and project `CLAUDE.md` if they exist

4. Copy user-level files:
   - `~/.claude/commands/*.md` to `commands/`
   - `~/.claude/settings.json` to `settings/` (if it exists)
   - `~/.claude/CLAUDE.md` to `settings/` (if it exists)

5. Update the `latest` symlink to point to the new timestamped folder.

6. Print a summary: number of projects exported, number of memory files, total size, and the export path.

## Important

- Use `rsync -a` for copying to preserve timestamps.
- Skip projects that have no memory directory and no CLAUDE.md.
- The human-readable project name should be the LAST segment of the path after removing the prefix (e.g. `-home-guilhermegor-github-` prefix → use the repo/folder name).
- Do NOT delete old backups — keep all timestamped snapshots.
