# backup-env Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the `c:backup-env` slash command that copies git-ignored `.env` files from a project root to a backup directory using the `<project>.<env_name>_YYYYMMDD_HHMMSS` naming convention.

**Architecture:** Single markdown command file consumed by Claude Code. The command drives Claude through a structured interactive flow: resolve target path → discover git-ignored `.env*` files → prompt user to select → copy with timestamped names → report.

**Tech Stack:** Bash (git, find, cp, date), Claude Code slash-command markdown format.

---

### Task 1: Create the command file skeleton

**Files:**
- Create: `ai_clients/claude/commands/backup-env.md`

- [ ] **Step 1: Write the file with frontmatter and section headers only**

```markdown
---
name: c:backup-env
allowed-tools: Bash(git check-ignore*), Bash(git rev-parse*), Bash(find *), Bash(ls *), Bash(cat *), Bash(cp *), Bash(mkdir *), Bash(date *), Bash(echo *), Read, Glob
description: Copy git-ignored .env files from the project root to a timestamped backup
argument-hint: "[target-path] — e.g. /mnt/usb/env_files (optional)"
---

You are backing up git-ignored `.env` files from this project. Follow these steps exactly.

## 1. Resolve target path

## 2. Verify target

## 3. Discover candidates

## 4. Select files

## 5. Copy

## 6. Report
```

- [ ] **Step 2: Verify the file exists and frontmatter is valid**

```bash
head -10 ai_clients/claude/commands/backup-env.md
```

Expected output: the `---` frontmatter block with `name`, `allowed-tools`, `description`, `argument-hint`.

- [ ] **Step 3: Commit the skeleton**

```bash
git add ai_clients/claude/commands/backup-env.md
git commit -m "feat(commands): Scaffold backup-env command skeleton"
```

---

### Task 2: Implement step 1 — resolve target path

**Files:**
- Modify: `ai_clients/claude/commands/backup-env.md` (fill in `## 1. Resolve target path`)

- [ ] **Step 1: Replace the `## 1` section with the full resolution logic**

Replace the `## 1. Resolve target path` heading and everything until `## 2` with:

```markdown
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
```

- [ ] **Step 2: Confirm the section reads correctly**

```bash
grep -A 30 "## 1. Resolve" ai_clients/claude/commands/backup-env.md
```

Expected: the full resolution block with the three-step fallback order.

- [ ] **Step 3: Commit**

```bash
git add ai_clients/claude/commands/backup-env.md
git commit -m "feat(commands): Add target path resolution to backup-env"
```

---

### Task 3: Implement step 2 — verify target

**Files:**
- Modify: `ai_clients/claude/commands/backup-env.md` (fill in `## 2. Verify target`)

- [ ] **Step 1: Replace the `## 2` section**

```markdown
## 2. Verify target

Run:

```bash
mkdir -p "<target>"
```

If the command fails (non-zero exit), print:
> "Cannot create or access `<target>`. Check that the drive is mounted and
> you have write permission." and stop.
```

- [ ] **Step 2: Commit**

```bash
git add ai_clients/claude/commands/backup-env.md
git commit -m "feat(commands): Add target verification to backup-env"
```

---

### Task 4: Implement step 3 — discover git-ignored candidates

**Files:**
- Modify: `ai_clients/claude/commands/backup-env.md` (fill in `## 3. Discover candidates`)

- [ ] **Step 1: Replace the `## 3` section**

```markdown
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
```

- [ ] **Step 2: Confirm section**

```bash
grep -A 25 "## 3. Discover" ai_clients/claude/commands/backup-env.md
```

- [ ] **Step 3: Commit**

```bash
git add ai_clients/claude/commands/backup-env.md
git commit -m "feat(commands): Add candidate discovery to backup-env"
```

---

### Task 5: Implement step 4 — select files

**Files:**
- Modify: `ai_clients/claude/commands/backup-env.md` (fill in `## 4. Select files`)

- [ ] **Step 1: Replace the `## 4` section**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add ai_clients/claude/commands/backup-env.md
git commit -m "feat(commands): Add file selection step to backup-env"
```

---

### Task 6: Implement step 5 — copy with timestamped names

**Files:**
- Modify: `ai_clients/claude/commands/backup-env.md` (fill in `## 5. Copy`)

- [ ] **Step 1: Replace the `## 5` section**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add ai_clients/claude/commands/backup-env.md
git commit -m "feat(commands): Add copy logic to backup-env"
```

---

### Task 7: Implement step 6 — report

**Files:**
- Modify: `ai_clients/claude/commands/backup-env.md` (fill in `## 6. Report`)

- [ ] **Step 1: Replace the `## 6` section**

```markdown
## 6. Report

Print a summary of every file that was successfully copied:

```
Backed up:
  .env      → /media/<user>/<BKP_DIR>/env_files/myproject.env_20260411_080312
  .env.prd  → /media/<user>/<BKP_DIR>/env_files/myproject.env.prd_20260411_080312
```

If any files failed to copy, list them separately:

```
Failed:
  .env.dev  → /media/.../myproject.env.dev_20260411_080312 (Permission denied)
```
```

- [ ] **Step 2: Commit**

```bash
git add ai_clients/claude/commands/backup-env.md
git commit -m "feat(commands): Add report step to backup-env"
```

---

### Task 8: Manual smoke test

**Files:** none (verification only)

- [ ] **Step 1: Confirm the command is discoverable**

```bash
grep "name:" ai_clients/claude/commands/backup-env.md
```

Expected: `name: c:backup-env`

- [ ] **Step 2: Check the full file reads cleanly end-to-end**

```bash
cat ai_clients/claude/commands/backup-env.md
```

Verify all six sections are present and none contain placeholder text like "TBD" or empty headings.

- [ ] **Step 3: Install the command and run a dry test**

From Claude Code, run `/backup-env` with no arguments in a project that has a git-ignored `.env` file. Verify:
- The command detects the default backup path from `~/.claude/.env` or `/media/$USER/`
- It presents the numbered list of `.env*` candidates
- After selection, files appear in the target directory with the correct naming convention

- [ ] **Step 4: Final commit**

```bash
git add ai_clients/claude/commands/backup-env.md
git commit -m "feat(commands): Complete backup-env slash command"
```
