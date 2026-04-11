# Design: `c:restore-env` command

**Date:** 2026-04-11
**Status:** Approved

## Summary

A Claude Code slash command that restores a git-ignored `.env` file from a backup directory back to the project root, inverting the `c:backup-env` flow. Source directory is resolved the same way as `backup-env`; backups are filtered to the current project and presented with the latest version as the default.

---

## Structure & Naming

**File:** `ai_clients/claude/commands/restore-env.md`
**Command name:** `c:restore-env`
**Argument hint:** `[source-path]` — optional source directory (same resolution logic as `backup-env`)

### Destination filename derivation

Backup filenames are reversed to produce the destination:

| Backup filename | Destination |
|----------------|-------------|
| `stpstone.env_20260411_080312` | `<git-root>/.env` |
| `stpstone.env.prd_20260411_080312` | `<git-root>/.env.prd` |
| `stpstone.env.dev_20260411_080312` | `<git-root>/.env.dev` |

Rule: strip `<project_name>.` prefix and `_YYYYMMDD_HHMMSS` suffix, then prepend a dot.

---

## Allowed Tools

```
Bash(git rev-parse*), Bash(id *),
Bash(find *),         Bash(ls *),
Bash(cat *),          Bash(cp *),
Bash(mv *),           Bash(date *),
Bash(echo *),         Read, Glob
```

`Bash(mv *)` is needed to rename existing files before overwriting (back-it-up option).

---

## Command Flow

### Step 1 — Parse arguments

Trim leading/trailing whitespace from `$ARGUMENTS`. If non-empty, use it directly as the source path and skip to step 3.

### Step 2 — Resolve source path

Resolution order (mirrors `backup-env`):

1. Read `~/.claude/.env` for `CLAUDE_BACKUP_DIR` — append `/env_files` to get the source path (mirrors where `backup-env` writes).
2. If not found, run `current_user=$(id -un)` then `ls /media/$current_user/` and select a drive using this priority:
   a. Drives that already contain an `env_files/` subdirectory
   b. Drives whose name contains "BKP" or "backup" (case-insensitive)
   c. If multiple drives match the same priority, show a numbered list and ask the user to choose
   Set source to `/media/$current_user/<drive>/env_files`.
3. If nothing is found, leave the source blank.

Present the resolved default and ask to confirm or override:
> "Source backup directory: `<resolved-path>` — press Enter to confirm or type a new path:"

If the default is blank and the user gives an empty response, print an error and stop:
> "No source directory specified. Please provide a path as an argument or set CLAUDE_BACKUP_DIR in ~/.claude/.env."

### Step 3 — Verify source

Run `ls "<source>"`. If it fails, print:
> "Cannot access `<source>`. Check that the drive is mounted." and stop.

### Step 4 — Get project name

Run:

```bash
git rev-parse --show-toplevel
```

If this fails, print: "Not inside a git repository. Aborting." and stop.

Store `git_root` and `project_name=$(basename "$git_root")`.

### Step 5 — Scan for backups

Run:

```bash
find "<source>" -maxdepth 1 -name "<project_name>.*_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]"
```

If no files match, print:
> "No backups found for `<project_name>` in `<source>`." and stop.

### Step 6 — Select backup(s)

Group files by `env_name` (the part between `<project_name>.` and `_YYYYMMDD_HHMMSS`). Within each group, sort by timestamp descending and take the most recent as the default.

**1 env type found:**
Show the latest backup and ask:
> "Latest backup: `<filename>` (YYYY-MM-DD HH:MM:SS). Restore it? (yes/no)"
If no, stop.

**2+ env types found:**
Show a numbered list of the latest backup per type:
```
Available backups for <project_name>:
  1) .env       — 2026-04-11 08:03:12  (stpstone.env_20260411_080312)
  2) .env.prd   — 2026-04-10 21:34:00  (stpstone.env.prd_20260410_213400)
Which would you like to restore? Enter numbers (space/comma separated) or "all":
```

**Viewing history:**
At any point the user may type `history <n>` to list all versions of env type `n`. Show them as a numbered sub-list and ask the user to pick one. Then continue with that version selected.

**Invalid input:** Numbers outside the valid range or non-numeric input → ask again.

Store selected backup files as `<selected>`.

### Step 7 — Handle existing files

For each file in `<selected>`, check if `<git_root>/.<env_name>` exists.

If it does, ask:
```
`.<env_name>` already exists. What would you like to do?
  a) Overwrite it
  b) Back it up first, then restore
  c) Skip this file
```

- **a)** Proceed directly to copy.
- **b)** Run:
  ```bash
  mv "<git_root>/.<env_name>" "<git_root>/.<env_name>.bak_$(date +%Y%m%d_%H%M%S)"
  ```
  Then proceed to copy.
- **c)** Skip this file; continue with the next.

If the file does not exist, proceed directly to copy.

### Step 8 — Copy

```bash
cp "<backup_file>" "<git_root>/.<env_name>"
```

If `cp` fails, capture stderr and print a per-file error:
> "Failed to restore `<backup_file>` → `<destination>`: <error>"
Continue with remaining files — do not abort the whole operation.

### Step 9 — Report

Print a summary:

```
Restored:
  stpstone.env_20260411_080312  →  .env
  stpstone.env.prd_20260410_213400  →  .env.prd

Skipped:
  .env.dev  (user skipped)

Failed:
  stpstone.env.local_...  →  .env.local  (Permission denied)
```

---

## Error Handling

| Condition | Behaviour |
|-----------|-----------|
| Source drive not mounted / inaccessible | Print error, stop |
| Not inside a git repository | Print error, stop |
| No backups for current project | Print info message, stop |
| Existing file at destination | Ask: overwrite / back up / skip |
| `cp` fails | Print per-file error, continue |
| `mv` (backup rename) fails | Print error, skip overwrite for that file |

---

## Non-Goals

- Does not decrypt or inspect `.env` contents
- Does not delete old backups after restoring
- Does not restore to a path other than the project git root
- Does not handle backups in subdirectories of the source (maxdepth 1)
