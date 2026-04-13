# Design: `c:backup-env` command

**Date:** 2026-04-11
**Status:** Approved

## Summary

A Claude Code slash command that copies git-ignored `.env` files from a project root to a designated backup directory, using the naming convention `<project_name>.<env_name>_YYYYMMDD_HHMMSS`.

---

## Structure & Naming

**File:** `ai_clients/claude/commands/backup-env.md`
**Command name:** `c:backup-env`
**Argument hint:** `[target-path]` — optional destination directory

### Output filename format

```
<project_name>.<env_name>_YYYYMMDD_HHMMSS
```

- `project_name` — basename of `git rev-parse --show-toplevel`
- `env_name` — filename with leading dot stripped (`.env` → `env`, `.env.prd` → `env.prd`)
- `timestamp` — `date +%Y%m%d_%H%M%S`

**Examples:**
- `.env` → `stpstone.env_20260411_080312`
- `.env.prd` → `stpstone.env.prd_20260411_080312`

---

## Allowed Tools

```
Bash(git check-ignore*),  Bash(git rev-parse*),
Bash(find *),             Bash(ls *),
Bash(cat *),              Bash(cp *),
Bash(mkdir *),            Bash(date *),
Bash(echo *),             Read, Glob
```

---

## Command Flow

### Step 1 — Parse arguments

Extract optional target path from `$ARGUMENTS`. If present, skip to step 3.

### Step 2 — Resolve target path

Resolution order:
1. `$ARGUMENTS` → use directly
2. Read `~/.claude/.env` for `CLAUDE_BACKUP_DIR` → use `$CLAUDE_BACKUP_DIR/env_files`
3. Scan `/media/$USER/` for drives that contain an `env_files/` directory or have "BKP" / "backup" (case-insensitive) in their name → append `/env_files`
4. If nothing is detected, present an empty prompt asking the user to enter a path

In all cases (except when `$ARGUMENTS` provided), show the resolved default and ask the user to confirm or override before continuing.

### Step 3 — Verify target

Run `mkdir -p <target>` to ensure the directory exists. If the target path is on a removable drive and is not mounted, report an error and stop.

### Step 4 — Discover candidates

```bash
find <git-root> -maxdepth 1 -name ".env*" ! -name "*.md"
```

For each candidate, run:

```bash
git check-ignore --quiet <file>
```

Keep only files that are git-ignored. If zero files pass this filter, report "no git-ignored .env files found in project root" and stop.

### Step 5 — Select files

- **1 file found:** display it and ask yes/no before proceeding
- **2+ files found:** display a numbered list, user enters space- or comma-separated numbers to select

### Step 6 — Copy

For each selected file:

```bash
project_name=$(basename "$(git rev-parse --show-toplevel)")
timestamp=$(date +%Y%m%d_%H%M%S)
env_name="${filename#.}"          # strip leading dot
cp <file> <target>/<project_name>.<env_name>_<timestamp>
```

### Step 7 — Report

List each source file alongside its full destination path. Example:

```
Copied:
  .env       → /media/<user>/<BKP_DIR>/env_files/stpstone.env_20260411_080312
  .env.prd   → /media/<user>/<BKP_DIR>/env_files/stpstone.env.prd_20260411_080312
```

---

## Error Handling

| Condition | Behaviour |
|-----------|-----------|
| Target drive not mounted | Print error, stop |
| No git-ignored `.env*` files found | Print info message, stop |
| `cp` fails for a file | Print per-file error, continue with remaining files |
| `git rev-parse` fails (not a git repo) | Print error, stop |

---

## Non-Goals

- Does not decrypt or inspect the contents of `.env` files
- Does not rotate or delete old backups
- Does not handle `.env` files in subdirectories (maxdepth 1 only)
