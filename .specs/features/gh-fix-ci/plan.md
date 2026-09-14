# gh-fix-ci Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a `a:gh-fix-ci` agent and `s:gh-read-ci` companion skill that watch a PR's GitHub Actions run, extract errors with context-mode, fix them, recommit+repush, and loop until CI is green.

**Architecture:** Two artifacts following the established `c:act` → `s:act-fix-py` pattern: an agent (`a:gh-fix-ci`) that owns the loop, commit, and user interaction, and a skill (`s:gh-read-ci`) that owns log parsing and fingerprint extraction. The agent loads the skill via the `Skill` tool at the error-extraction step.

**Tech Stack:** `gh` CLI (GitHub Actions API), git, Claude Code agent/skill system, context-mode plugin.

---

## File map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `ai_clients/claude/skills/gh-read-ci.md` | Parse CI logs, activate context-mode, emit error fingerprints |
| Create | `ai_clients/claude/agents/gh-fix-ci.md` | Orchestrate loop, memory, commit/push, user prompts |

---

## Task 1: Create `s:gh-read-ci` skill

**Files:**
- Create: `ai_clients/claude/skills/gh-read-ci.md`

- [ ] **Step 1: Create the skill file**

```markdown
---
name: s:gh-read-ci
description: Use when a:gh-fix-ci needs to parse raw GitHub Actions log output — extracts failing steps, error messages, file:line references, and produces fingerprints for seen_errors tracking
effort: high
argument-hint: [run-id] [--plan|--fix]
allowed-tools: Bash(gh run*)
---

You are parsing raw GitHub Actions log output to extract structured errors.
Follow these steps exactly.

## 0. Activate context-mode

Invoke context-mode to enrich processing of the CI log content before reading
any log lines.

## 1. Receive input

The caller provides:
- `run-id`: the GitHub Actions run ID
- Mode flag: `--plan` or `--fix`

## 2. Fetch failed logs

Run:
```bash
gh run view <run-id> --log-failed
```

## 3. Extract errors

Parse the output and produce a structured error list. For each failure extract:

| Field | Description | Example |
|-------|-------------|---------|
| `step` | Failing job/step name | `build / test` |
| `message` | Error text | `TypeError: unsupported operand` |
| `location` | file:line if present | `src/foo.py:42` |
| `exit_code` | Process exit code if shown | `1` |

## 4. Produce fingerprints

For each error, produce a short fingerprint.

Format: `<tool-or-step>:<file>:<line>` when location is available, or
`<tool-or-step>:<error-slug>` when not.

Examples:
- `mypy:src/foo.py:23`
- `pytest:tests/test_bar.py:88`
- `ruff:src/utils.py:12`
- `docker-build:no-such-file`

## 5. Return structured block

Output this block — the agent reads it directly:

```
## CI Error Report

Run: <run-id>
Failed steps: <N>

### Errors

| # | Step | Message | Location | Exit |
|---|------|---------|----------|------|
| 1 | <step> | <message> | <location or —> | <code or —> |
...

### Fingerprints

- <fingerprint-1>
- <fingerprint-2>
...
```

Do not surface the raw log output to the user.
```

- [ ] **Step 2: Verify required frontmatter fields are present**

Open `ai_clients/claude/skills/gh-read-ci.md` and confirm all mandatory fields
from `ai_clients/CLAUDE.md` are present:

```
name:          s:gh-read-ci          ← s: prefix ✓
description:   starts with "Use when" ✓
effort:        high ✓
allowed-tools: Bash(gh run*) ✓
```

If any field is missing or the description doesn't start with "Use when", fix
it before continuing.

- [ ] **Step 3: Install the skill and verify**

```bash
./ai_clients/claude/main.sh skills
```

Expected output contains:
```
✓ Installed s:gh-read-ci → ~/.claude/skills/gh-read-ci.md
```

Then confirm the file landed:
```bash
ls ~/.claude/skills/gh-read-ci.md
```

Expected: file exists, no error.

- [ ] **Step 4: Commit**

```bash
git add ai_clients/claude/skills/gh-read-ci.md
git commit -m "feat(claude): add s:gh-read-ci skill for CI log parsing"
```

Verify title length ≤ 72 chars:
```bash
echo -n "feat(claude): add s:gh-read-ci skill for CI log parsing" | wc -c
```

Expected: ≤ 72.

---

## Task 2: Create `a:gh-fix-ci` agent

**Files:**
- Create: `ai_clients/claude/agents/gh-fix-ci.md`

- [ ] **Step 1: Create the agent file**

```markdown
---
name: a:gh-fix-ci
description: Fix GitHub Actions CI failures on a PR — fetches the latest failed run, extracts errors, applies fixes, recommits and repushes, then loops until CI is green or a hard stop is reached
model: sonnet
color: red
memory: true
disable-model-invocation: true
effort: high
argument-hint: [<pr-number-or-url>] [--plan|--fix]
---

Fix GitHub Actions CI failures on a pull request end-to-end: resolve the PR,
watch the latest run, extract errors, apply fixes, recommit, repush, and loop
until CI is green or a hard stop is reached.

## Required inputs

Parse from `$ARGUMENTS`:

1. **PR identifier** — a PR number (e.g. `42`), a full PR URL, or empty.
   If empty, auto-detect:
   ```bash
   gh pr view --json number,title,headRefName,headRefOid
   ```
   If that fails (no open PR for current branch), report the error and stop.

2. **Mode flag** — `--plan` or `--fix`.
   - `--plan`: propose each fix, wait for approval before applying.
   - `--fix`: apply fixes directly without asking.
   If absent, ask:
   > "Apply fixes directly (`--fix`) or propose first (`--plan`)?
   > [default: --plan]"

Save resolved values to memory:
- `pr_number` ← resolved PR number (integer)
- `mode` ← `plan` or `fix`
- `iteration` ← 0
- `seen_errors` ← []

---

## Loop

Repeat the following steps. Increment `iteration` by 1 at the start of each
cycle.

### Step 1 — Fetch latest run

Get the PR's head SHA and the most recent workflow run:

```bash
gh pr view <pr_number> --json headRefName,headRefOid,title
gh run list --branch <headRefName> --limit 5 \
  --json databaseId,status,conclusion,headSha
```

Select the run whose `headSha` matches the PR's `headRefOid`. If no matching
run exists yet (new push just landed), wait 10 seconds and retry once. If
still no match, report and stop.

### Step 2 — Watch run

```bash
gh run watch <run-id>
```

Report progress to the user before blocking:
> "Watching run #<run-id> for PR #<pr_number> (iteration <iteration>)…"

### Step 3 — Check result

```bash
gh run view <run-id> --json conclusion
```

If `conclusion == "success"`: print the final summary with
`Outcome: green` and stop the loop.

### Step 4 — Extract errors

Load `s:gh-read-ci` via the Skill tool, passing the run ID and mode flag as
context. Collect the structured CI Error Report and fingerprint list it
returns.

### Step 5 — Check hard stop conditions

**Max iterations:** If `iteration >= 5`, print the final summary with
`Outcome: max iterations` and stop.

**Recurring error:** For each new fingerprint, count occurrences in
`seen_errors`. If any fingerprint has appeared **3 or more times**, report:
> "Error `<fingerprint>` has recurred 3 times without being resolved —
> stopping to avoid a fix loop."

Print the final summary with `Outcome: recurring error` and stop.

Append all new fingerprints from this iteration to `seen_errors` in memory.

### Step 6 — Apply fixes

Based on the CI Error Report:

**`--plan` mode** — for each error, show:
> "Proposed fix for `<fingerprint>`:
> File: `<path:line>`
> Change: <description>
> Apply? (yes/no/skip)"
Wait for the user's answer before editing.

**`--fix` mode** — apply all fixes directly and report each one:
> "Fixed `<fingerprint>` → `<file:line>`: <one-line description>"

### Step 7 — Commit and push

Stage only the files modified during this iteration — never `git add -A`:

```bash
git add <file1> <file2> ...
```

Compose the commit message. Verify line lengths before committing:
```bash
# Title must be ≤ 72 chars
echo -n "fix(ci): resolve CI failures — iteration <N>" | wc -c

# Each bullet must be ≤ 80 chars
echo -n "  - <fingerprint> → <file:line>" | wc -c
```

Commit only when all lines pass:
```bash
git commit -m "$(cat <<'EOF'
fix(ci): resolve CI failures — iteration <N>

  - <fingerprint-1> → <file:line>
  - <fingerprint-2> → <file:line>
EOF
)"
git push origin HEAD
```

### Step 8 — Ask to continue

> "Push complete. CI is running again (iteration <iteration> of 5).
> Continue watching? (yes/no)"

- **yes** → loop back to Step 1
- **no** → print final summary with `Outcome: stopped by user` and stop

---

## Final summary

```
## gh-fix-ci summary

PR:         #<pr_number> — <title>
Iterations: <iteration>
Outcome:    green | stopped by user | max iterations | recurring error

### Fixed
- <file:line — description>

### Remaining errors
- <step — error — file:line>
```

---

## Memory

After each completed session, save:
- PR number and title
- Final outcome (green / stopped / max iterations / recurring error)
- Any fingerprints that recurred across iterations

---

## Do Not

- Do not stage files with `git add -A` or `git add .` — stage by name only.
- Do not skip the `gh run watch` step — never assume a run has completed.
- Do not proceed past hard stop conditions.
- Do not commit with `--no-verify` unless the user explicitly requests it.
- Do not push without committing first.
- Do not start a new iteration if `iteration >= 5`.
```

- [ ] **Step 2: Verify required frontmatter fields are present**

Open `ai_clients/claude/agents/gh-fix-ci.md` and confirm all mandatory fields
from `ai_clients/CLAUDE.md` are present:

```
name:          a:gh-fix-ci           ← a: prefix ✓
description:   one-line trigger ✓
model:         sonnet ✓
color:         red ✓
memory:        true ✓
disable-model-invocation: true ✓
effort:        high ✓
argument-hint: present ✓
```

- [ ] **Step 3: Install the agent and verify**

```bash
./ai_clients/claude/main.sh agents
```

Expected output contains:
```
✓ Installed a:gh-fix-ci → ~/.claude/agents/gh-fix-ci.md
```

Confirm the file landed:
```bash
ls ~/.claude/agents/gh-fix-ci.md
```

Expected: file exists, no error.

- [ ] **Step 4: Commit**

```bash
git add ai_clients/claude/agents/gh-fix-ci.md
git commit -m "feat(claude): add a:gh-fix-ci agent for PR CI fix loop"
```

Verify title length ≤ 72 chars:
```bash
echo -n "feat(claude): add a:gh-fix-ci agent for PR CI fix loop" | wc -c
```

Expected: ≤ 72.

---

## Task 3: Smoke-test installation

**Files:** none created — verification only.

- [ ] **Step 1: Verify both artifacts are installed**

```bash
ls ~/.claude/skills/gh-read-ci.md ~/.claude/agents/gh-fix-ci.md
```

Expected: both paths exist.

- [ ] **Step 2: Verify agent frontmatter is readable**

```bash
head -15 ~/.claude/agents/gh-fix-ci.md
```

Expected: shows the full frontmatter block ending with `---`.

- [ ] **Step 3: Verify skill frontmatter is readable**

```bash
head -8 ~/.claude/skills/gh-read-ci.md
```

Expected: shows the full frontmatter block ending with `---`.

- [ ] **Step 4: Confirm `gh` CLI is available (runtime dependency)**

```bash
gh --version
```

Expected: prints a version string. If not found, note that `gh` must be
installed before `a:gh-fix-ci` can run.
