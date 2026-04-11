---
name: c:restore-env
allowed-tools: Bash(git rev-parse*), Bash(id *), Bash(find *), Bash(ls *), Bash(cat *), Bash(cp *), Bash(mv *), Bash(date *), Bash(echo *), Read, Glob
description: Restore a git-ignored .env file from a timestamped backup to the project root
argument-hint: "[source-path] — e.g. /mnt/usb/env_files (optional)"
---

You are restoring git-ignored `.env` files from a backup directory to this project root. Follow these steps exactly.

## 1. Parse arguments and resolve source path

Trim leading and trailing whitespace from `$ARGUMENTS`. If non-empty, use it
directly as the source path and skip to step 2.

Otherwise, resolve the default in this order:

1. Run `cat ~/.claude/.env 2>/dev/null` and look for a line matching
   `CLAUDE_BACKUP_DIR=<path>`. If found, set source to `<path>/env_files`.
2. If not found, run `current_user=$(id -un)` then
   `ls /media/$current_user/ 2>/dev/null` to list mounted drives.
   Use this priority to select the drive:
   a. First, prefer drives that already contain an `env_files/` subdirectory.
   b. If none, prefer drives whose name contains "BKP" or "backup"
      (case-insensitive).
   c. If multiple drives match the same priority level, show a numbered list
      and ask the user to choose.
   Set source to `/media/$current_user/<drive>/env_files`.
3. If no drive matches, leave source blank.

Present the resolved default (or a blank prompt if nothing was found):

> "Source backup directory: `<resolved-path>` — press Enter to confirm or
> type a new path:"

Wait for the user's response. If they type a new path, use that. If they
press Enter (empty response), use the resolved default. If the default was
blank and the user also gives an empty response, print an error and stop:
> "No source directory specified. Please provide a path as an argument or
> set CLAUDE_BACKUP_DIR in ~/.claude/.env."

## 2. Verify source

Run `ls "<source>"`. If it fails, print:
> "Cannot access `<source>`. Check that the drive is mounted." and stop.

## 3. Get project name

Run:

```bash
git rev-parse --show-toplevel
```

If this fails, print: "Not inside a git repository. Aborting." and stop.

Store the result as `<git_root>` and derive:

```bash
project_name=$(basename "<git_root>")
```

## 4. Scan for backups

Run:

```bash
find "<source>" -maxdepth 1 \
  -name "<project_name>.*_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]"
```

If no files match, print:
> "No backups found for `<project_name>` in `<source>`." and stop.

For each matched filename, parse out:
- `env_name`: the part between `<project_name>.` and the final
  `_YYYYMMDD_HHMMSS` suffix.
  Example: `stpstone.env.prd_20260411_080312` → `env_name = env.prd`
- `timestamp`: the final `_YYYYMMDD_HHMMSS` portion, formatted as a
  human-readable date for display (e.g. `2026-04-11 08:03:12`).

Note: treat `<project_name>.` as a **literal prefix** — not a glob — when
parsing `env_name`. Use the full project name as a string anchor to avoid
false matches from projects whose names share a common prefix.

Group files by `env_name`. Within each group, sort by timestamp descending.

## 5. Select backup(s)

Take the most recent file (by timestamp) from each `env_name` group as the
default candidate.

**1 env type found:**
Display the latest backup and ask:
> "Latest backup: `<filename>` (YYYY-MM-DD HH:MM:SS). Restore it? (yes/no)"
If no, stop.

**2+ env types found:**
Display a numbered list of the latest backup per type:

```
Available backups for <project_name>:
  1) .env      — 2026-04-11 08:03:12  (stpstone.env_20260411_080312)
  2) .env.prd  — 2026-04-10 21:34:00  (stpstone.env.prd_20260410_213400)
Which would you like to restore? Enter numbers (space/comma separated) or "all":
```

Wait for the user's response. Parse their input:
- `"all"` → select every latest candidate
- Numbers → select only the files at those positions (1-indexed)
- Numbers outside the valid range or non-numeric input → ask again

**Viewing history:**
If the user types `history <n>` (e.g. `history 2`), list all versions of env
type `n` as a numbered sub-list with timestamps, oldest to newest:

```
All backups for .env.prd:
  1) stpstone.env.prd_20260409_120000  (2026-04-09 12:00:00)
  2) stpstone.env.prd_20260410_213400  (2026-04-10 21:34:00)  ← latest
Pick a version (number):
```

Wait for the user to pick a version number. If the user enters a number
outside the valid range or non-numeric input, re-display the sub-list and
ask again. Replace the default candidate for that env type with the chosen
version, then re-display the updated numbered list (with the chosen version
shown for that env type) and wait for the user's selection.

Store all final selected backup files as `<selected>`.

## 6. Handle existing files

For each file in `<selected>`:

Derive the destination path:
- Restore destination: `<git_root>/.<env_name>`
  Example: `env_name = env.prd` → destination = `<git_root>/.env.prd`

Check if the destination file already exists.

If it **does not exist**, proceed directly to step 7 (copy).

If it **does exist**, ask:

```
`.<env_name>` already exists at `<git_root>`. What would you like to do?
  a) Overwrite it
  b) Back it up first, then restore
  c) Skip this file
```

- **a) Overwrite:** proceed to step 7 (copy).
- **b) Back it up first:** run:
  ```bash
  mv "<git_root>/.<env_name>" "<git_root>/.<env_name>.bak_$(date +%Y%m%d_%H%M%S)"
  ```
  If `mv` fails, capture stderr, print:
  > "Could not back up existing `.<env_name>`: <error>. Skipping."
  and skip this file. Otherwise proceed to step 7 (copy).
- **c) Skip:** record this file as skipped and move on to the next.

## 7. Copy

For each file in `<selected>` that was not skipped:

```bash
cp "<backup_file>" "<git_root>/.<env_name>"
```

Capture stderr from the `cp` tool call. If `cp` fails, print a per-file error:
> "Failed to restore `<backup_file>` → `.<env_name>`: <error>"
Continue with the remaining files — do not abort the whole operation.

## 8. Report

Print a summary of every file processed:

```
Restored:
  stpstone.env_20260411_080312        →  .env
  stpstone.env.prd_20260410_213400    →  .env.prd

Skipped:
  .env.dev  (user chose to skip)

Failed:
  stpstone.env.local_20260411_080312  →  .env.local  (Permission denied)
```

Omit any section (Restored / Skipped / Failed) that has no entries.

Files skipped due to a failed backup `mv` (step 6) are reported under
**Failed** with the note "(could not back up existing file — original
untouched)".
