# restore-env Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the `c:restore-env` slash command that restores a git-ignored `.env` file from a timestamped backup directory back to the project root, inverting the `c:backup-env` flow.

**Architecture:** Single markdown command file consumed by Claude Code. Mirrors `backup-env` source resolution; filters backups to the current project; defaults to the latest version per env type; asks before overwriting existing files.

**Tech Stack:** Bash (git, find, cp, mv, date, id), Claude Code slash-command markdown format.

---

### Task 1: Create the command file skeleton

**Files:**
- Create: `ai_clients/claude/commands/restore-env.md`

- [ ] **Step 1: Write the file with frontmatter and section headers only**

Create `ai_clients/claude/commands/restore-env.md` with this exact content:

```markdown
---
name: c:restore-env
allowed-tools: Bash(git rev-parse*), Bash(id *), Bash(find *), Bash(ls *), Bash(cat *), Bash(cp *), Bash(mv *), Bash(date *), Bash(echo *), Read, Glob
description: Restore a git-ignored .env file from a timestamped backup to the project root
argument-hint: "[source-path] — e.g. /mnt/usb/env_files (optional)"
---

You are restoring git-ignored `.env` files from a backup directory to this project root. Follow these steps exactly.

## 1. Parse arguments and resolve source path

## 2. Verify source

## 3. Get project name

## 4. Scan for backups

## 5. Select backup(s)

## 6. Handle existing files

## 7. Copy

## 8. Report
```

- [ ] **Step 2: Verify the file exists and frontmatter is valid**

```bash
head -10 ai_clients/claude/commands/restore-env.md
```

Expected: `---` frontmatter block with `name`, `allowed-tools`, `description`, `argument-hint`.

- [ ] **Step 3: Commit the skeleton**

```bash
git add ai_clients/claude/commands/restore-env.md
git commit -m "feat(commands): Scaffold restore-env command skeleton"
```

---

### Task 2: Implement step 1 — parse arguments and resolve source path

**Files:**
- Modify: `ai_clients/claude/commands/restore-env.md` (fill in `## 1.`)

- [ ] **Step 1: Replace the `## 1.` section with the full resolution logic**

Replace `## 1. Parse arguments and resolve source path` and everything up to `## 2.` with:

```markdown
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
```

- [ ] **Step 2: Confirm the section reads correctly**

```bash
grep -A 35 "## 1\. Parse" ai_clients/claude/commands/restore-env.md
```

Expected: the full resolution block with three-step fallback order, drive priority rules, and confirm/override prompt.

- [ ] **Step 3: Commit**

```bash
git add ai_clients/claude/commands/restore-env.md
git commit -m "feat(commands): Add source path resolution to restore-env"
```

---

### Task 3: Implement steps 2 & 3 — verify source and get project name

**Files:**
- Modify: `ai_clients/claude/commands/restore-env.md` (fill in `## 2.` and `## 3.`)

- [ ] **Step 1: Replace the `## 2.` section**

```markdown
## 2. Verify source

Run `ls "<source>"`. If it fails, print:
> "Cannot access `<source>`. Check that the drive is mounted." and stop.
```

- [ ] **Step 2: Replace the `## 3.` section**

```markdown
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
```

- [ ] **Step 3: Commit**

```bash
git add ai_clients/claude/commands/restore-env.md
git commit -m "feat(commands): Add source verification and project detection to restore-env"
```

---

### Task 4: Implement step 4 — scan for backups

**Files:**
- Modify: `ai_clients/claude/commands/restore-env.md` (fill in `## 4.`)

- [ ] **Step 1: Replace the `## 4.` section**

```markdown
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

Group files by `env_name`. Within each group, sort by timestamp descending.
```

- [ ] **Step 2: Confirm section**

```bash
grep -A 25 "## 4\. Scan" ai_clients/claude/commands/restore-env.md
```

- [ ] **Step 3: Commit**

```bash
git add ai_clients/claude/commands/restore-env.md
git commit -m "feat(commands): Add backup scanning step to restore-env"
```

---

### Task 5: Implement step 5 — select backup(s)

**Files:**
- Modify: `ai_clients/claude/commands/restore-env.md` (fill in `## 5.`)

- [ ] **Step 1: Replace the `## 5.` section**

```markdown
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

Wait for the user to pick a version number. Replace the default candidate for
that env type with the chosen version, then return to the main selection
prompt.

Store all final selected backup files as `<selected>`.
```

- [ ] **Step 2: Commit**

```bash
git add ai_clients/claude/commands/restore-env.md
git commit -m "feat(commands): Add backup selection step to restore-env"
```

---

### Task 6: Implement step 6 — handle existing files

**Files:**
- Modify: `ai_clients/claude/commands/restore-env.md` (fill in `## 6.`)

- [ ] **Step 1: Replace the `## 6.` section**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add ai_clients/claude/commands/restore-env.md
git commit -m "feat(commands): Add existing-file handling to restore-env"
```

---

### Task 7: Implement steps 7 & 8 — copy and report

**Files:**
- Modify: `ai_clients/claude/commands/restore-env.md` (fill in `## 7.` and `## 8.`)

- [ ] **Step 1: Replace the `## 7.` section**

```markdown
## 7. Copy

For each file in `<selected>` that was not skipped:

```bash
cp "<backup_file>" "<git_root>/.<env_name>"
```

Capture stderr from the `cp` tool call. If `cp` fails, print a per-file error:
> "Failed to restore `<backup_file>` → `.<env_name>`: <error>"
Continue with the remaining files — do not abort the whole operation.
```

- [ ] **Step 2: Replace the `## 8.` section**

```markdown
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
```

- [ ] **Step 3: Commit**

```bash
git add ai_clients/claude/commands/restore-env.md
git commit -m "feat(commands): Add copy and report steps to restore-env"
```

---

### Task 8: Smoke test

**Files:** none (verification only)

- [ ] **Step 1: Confirm the command is discoverable**

```bash
grep "name:" ai_clients/claude/commands/restore-env.md
```

Expected: `name: c:restore-env`

- [ ] **Step 2: Check the full file reads cleanly end-to-end**

```bash
cat ai_clients/claude/commands/restore-env.md
```

Verify all eight sections are present and none contain placeholder text (empty headings, "TBD", `...`).

- [ ] **Step 3: Cross-check allowed-tools covers every bash command used**

Commands used in the file body vs. `allowed-tools`:
- `id` → `Bash(id *)` ✓
- `cat` → `Bash(cat *)` ✓
- `ls` → `Bash(ls *)` ✓
- `find` → `Bash(find *)` ✓
- `git rev-parse` → `Bash(git rev-parse*)` ✓
- `cp` → `Bash(cp *)` ✓
- `mv` → `Bash(mv *)` ✓
- `date` → `Bash(date *)` ✓

Confirm all are present in the frontmatter `allowed-tools` line.

- [ ] **Step 4: Install and run a dry test**

From Claude Code, run `/restore-env` with no arguments in a project that has backups in the configured backup directory. Verify:
- Source dir is detected from `~/.claude/.env` or `/media/$USER/`
- Only backups for the current project name are shown
- Latest version is presented as default
- `history <n>` shows older versions
- Existing `.env` triggers the overwrite/backup/skip prompt
- Restored file appears at `<git_root>/.<env_name>`

- [ ] **Step 5: Final commit**

```bash
git add ai_clients/claude/commands/restore-env.md
git commit -m "feat(commands): Complete restore-env slash command"
```
