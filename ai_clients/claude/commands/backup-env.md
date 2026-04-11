---
name: c:backup-env
allowed-tools: Bash(git check-ignore*), Bash(git rev-parse*), Bash(find *), Bash(ls *), Bash(cat *), Bash(cp *), Bash(mkdir *), Bash(date *), Bash(echo *), Read, Glob
description: Copy git-ignored .env files from the project root to a timestamped backup
argument-hint: "[target-path] — e.g. /mnt/usb/env_files (optional)"
---

You are backing up git-ignored `.env` files from this project. Follow these steps exactly.

## 1. Resolve target path

If `$ARGUMENTS` is non-empty, use it directly as the target path and skip to step 2.

Otherwise, resolve the default in this order:

1. Run `cat ~/.claude/.env 2>/dev/null` and look for a line matching
   `CLAUDE_BACKUP_DIR=<path>`. If found, set target to `<path>/env_files`.
2. If not found, run `ls /media/$USER/ 2>/dev/null` to list mounted drives.
   Select the first drive whose name contains "BKP" or "backup"
   (case-insensitive) or that already contains an `env_files/` subdirectory.
   Set target to `/media/$USER/<drive>/env_files`.
3. If no drive matches, leave the target blank.

Present the resolved default (or a blank prompt if nothing was found):

> "Target backup directory: `<resolved-path>` — press Enter to confirm or
> type a new path:"

Wait for the user's response. If they type a new path, use that. If they
press Enter (empty response), use the resolved default. If the default was
blank and the user also gives an empty response, print an error and stop:
> "No backup directory specified. Please provide a path as an argument or
> set CLAUDE_BACKUP_DIR in ~/.claude/.env."

## 2. Verify target

Run:

```bash
mkdir -p "<target>"
```

If the command fails (non-zero exit), print:
> "Cannot create or access `<target>`. Check that the drive is mounted and
> you have write permission." and stop.

## 3. Discover candidates

Run:

```bash
git rev-parse --show-toplevel
```

Store the result as `<git-root>`. If this fails, print:
> "Not inside a git repository. Aborting." and stop.

Then run:

```bash
find "<git-root>" -maxdepth 1 -name ".env*" ! -name "*.md"
```

For each file in the result, run:

```bash
git check-ignore --quiet "<file>"
```

Keep only files where the exit code is `0` (git-ignored). Collect them as
`<candidates>`.

If `<candidates>` is empty, print:
> "No git-ignored .env files found in the project root. Nothing to back up."
and stop.

## 4. Select files

If `<candidates>` contains exactly one file, display it and ask:
> "Found 1 git-ignored env file: `<file>`. Back it up? (yes/no)"
If the user answers no, stop.

If `<candidates>` contains two or more files, display a numbered list:

```
Git-ignored .env files found:
  1) .env
  2) .env.prd
  3) .env.dev
Which would you like to back up? Enter numbers separated by spaces or
commas (e.g. 1 3), or "all" to select everything:
```

Wait for the user's response. Parse their input:
- `"all"` → select every candidate
- Numbers → select only the files at those positions (1-indexed)
- Invalid input → ask again

Store the selected files as `<selected>`.

## 5. Copy

Run once to capture shared values:

```bash
project_name=$(basename "$(git rev-parse --show-toplevel)")
timestamp=$(date +%Y%m%d_%H%M%S)
```

For each file in `<selected>`:

1. Derive `env_name` by stripping the leading dot from the filename:
   - `.env`     → `env`
   - `.env.prd` → `env.prd`
   - `.env.dev` → `env.dev`

2. Build the destination path:
   `<target>/<project_name>.<env_name>_<timestamp>`

3. Run:
   ```bash
   cp "<file>" "<destination>"
   ```
   If `cp` fails, print a per-file error:
   > "Failed to copy `<file>` → `<destination>`: <error>"
   Continue with the remaining files — do not abort the whole operation.

## 6. Report

Print a summary of every file that was successfully copied:

```
Backed up:
  .env      → /media/guilhermegor/BKP_GOR/env_files/myproject.env_20260411_080312
  .env.prd  → /media/guilhermegor/BKP_GOR/env_files/myproject.env.prd_20260411_080312
```

If any files failed to copy, list them separately:

```
Failed:
  .env.dev  → /media/.../myproject.env.dev_20260411_080312 (Permission denied)
```
