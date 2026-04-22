---
name: a:gh-fix-ci
description: Fix GitHub Actions CI failures on a PR — fetches the latest
  failed run, analyses errors (user-chosen model), applies fixes
  (user-chosen model), commits, pushes to origin, and loops until CI is
  green or a hard stop is reached
model: sonnet
color: red
memory: true
effort: high
argument-hint: [<pr-number-or-url>] [--plan|--fix] [--help]
allowed-tools: Bash(rtk gh *) Bash(rtk git *) Bash(sqlite3 *) Agent Skill
---

Fix GitHub Actions CI failures on a pull request end-to-end: resolve the PR,
watch the latest run, extract errors, apply fixes, recommit, repush, and loop
until CI is green or a hard stop is reached.

## Required inputs

Parse from `$ARGUMENTS`:

1. **`--help` flag** — if `$ARGUMENTS` contains `--help` or `-h`, print the
   block below and stop immediately:

   ```
   Usage: a:gh-fix-ci [<pr>] [--plan|--fix] [--help]

   Arguments:
     <pr>       PR number or full URL.
                Auto-detects current branch if omitted.
     --plan     Propose each fix and wait for your approval (default).
                The implementation model is chosen after you see the
                proposed fixes, so you can judge their complexity first.
     --fix      Apply all fixes immediately without prompting.
                Both models are chosen before the loop starts.
     --help     Show this message

   Startup questions (in order):

     1. Mode — --plan or --fix (skipped if passed as a flag above)

     2. Planning model — which model analyses CI logs and proposes fixes
        · sonnet  Faster and cheaper. Best for straightforward failures:
                   unused imports, missing type annotations, a version pin,
                   a config key typo. Good choice on a Pro plan.
        · opus    Stronger multi-step reasoning. Best for complex failures:
                   a type error traced across 3+ files, a cryptic Docker
                   build failure, a Protocol mismatch introduced several
                   PRs ago, or a recurring error Sonnet failed to fix.
                   Better choice on a Max plan.
        Default: sonnet (press Enter)

     3. Implementation model — asked now only in --fix mode.
        In --plan mode this question comes after you see the proposed fixes.
        · sonnet  Best for mechanical fixes: adding an import, correcting a
                   version string, applying a clear diff hint.
        · opus    Best for structural changes: multi-file refactors,
                   signature changes with many callers, fixes without a hint.
        Default: sonnet (press Enter)

   State is stored in ~/.claude/gh-fix-ci/<project>.db (SQLite).
   After each approved iteration: commits staged files and pushes to origin.
   ```

2. **PR identifier** — a PR number (e.g. `42`), a full PR URL, or empty.
   If empty, auto-detect:
   ```bash
   rtk gh pr view --json number,title,headRefName,headRefOid
   ```
   If that fails (no open PR for current branch), report the error and stop.

3. **Mode flag** — ask first, before model questions.
   - `--plan`: propose each fix, wait for approval before applying.
   - `--fix`: apply fixes directly without asking.
   If absent, ask:
   > "Apply fixes directly (`--fix`) or propose first (`--plan`)?
   > [default: --plan]"

4. **Planning model** — ask after mode is set.
   > "Which model should analyse CI failures and propose fixes?
   >
   > · `sonnet` (default) — faster, cheaper. Good for simple failures:
   >   unused import, missing annotation, version pin, config typo.
   > · `opus` — stronger reasoning. Better for complex failures:
   >   type errors across multiple files, cryptic build output, recurring
   >   errors that Sonnet failed to resolve, Protocol mismatches.
   >
   > Press Enter for sonnet, or type `opus`:"
   Capture as `planning_model`. Default: `sonnet`.

5. **Implementation model** — ask only if `mode == fix`. In `--plan` mode
   this question is deferred to after Step 4.
   > "Which model should apply the fixes?
   >
   > · `sonnet` (default) — faster, cheaper. Good for mechanical edits:
   >   adding an import, correcting a version, applying a diff hint.
   > · `opus` — better for structural changes: multi-file refactors,
   >   signature changes with many callers, fixes without a diff hint.
   >
   > Press Enter for sonnet, or type `opus`:"
   Capture as `implementation_model`. Default: `sonnet`.
   In `--plan` mode, leave `implementation_model` unset for now.

Save resolved values to memory:
- `pr_number` ← resolved PR number (integer)
- `mode` ← `plan` or `fix`
- `planning_model` ← `opus` or `sonnet`
- `implementation_model` ← `opus` or `sonnet` (`--fix` mode only for now;
  set after Step 4 in `--plan` mode)
- `iteration` ← 0
- `project_slug`, `db_path`, `session_id` ← set in Step 0

---

### Step 0 — Initialise SQLite session

**Guard — sqlite3 CLI must be present:**

```bash
command -v sqlite3 || {
  echo "sqlite3 not found — install with: sudo apt install sqlite3"
  exit 1
}
```

**Derive project slug from git remote:**

```bash
project_slug=$(
  rtk git remote get-url origin 2>/dev/null \
    | sed 's|.*[:/]\([^/]*/[^/]*\)\.git$|\1|;s|\.git$||' \
    | tr '/' '-' \
    | tr -cd 'a-zA-Z0-9-'
)
if [ -z "$project_slug" ]; then
  project_slug=$(basename "$(rtk git rev-parse --show-toplevel 2>/dev/null || pwd)")
fi
```

Save `project_slug` to memory. Set `db_path` and create the directory:

```bash
db_path="$HOME/.claude/gh-fix-ci/${project_slug}.db"
mkdir -p "$HOME/.claude/gh-fix-ci"
```

Save `db_path` to memory. Use it in every subsequent `sqlite3` call.

**Create schema and indexes (idempotent):**

```bash
sqlite3 "$db_path" "
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS sessions (
    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    project_slug          TEXT    NOT NULL,
    pr_number             INTEGER NOT NULL,
    mode                  TEXT    NOT NULL CHECK(mode IN ('plan','fix')),
    planning_model        TEXT    NOT NULL
                          CHECK(planning_model IN ('opus','sonnet')),
    implementation_model  TEXT    CHECK(implementation_model
                                       IN ('opus','sonnet')),
    started_at            TEXT    NOT NULL
                          DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    outcome               TEXT    CHECK(outcome IN ('green','stopped_by_user',
                                                   'max_iterations',
                                                   'recurring_error')),
    iterations            INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS ci_errors (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id  INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    iteration   INTEGER NOT NULL,
    fingerprint TEXT    NOT NULL,
    step        TEXT,
    message     TEXT,
    location    TEXT,
    exit_code   TEXT,
    created_at  TEXT    NOT NULL
                DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

CREATE TABLE IF NOT EXISTS proposed_fixes (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id  INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    iteration   INTEGER NOT NULL,
    fingerprint TEXT    NOT NULL,
    file_path   TEXT,
    line_number INTEGER,
    description TEXT    NOT NULL,
    diff_hint   TEXT,
    status      TEXT    NOT NULL DEFAULT 'pending'
                CHECK(status IN
                    ('pending','approved','skipped','applied','failed')),
    created_at  TEXT    NOT NULL
                DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    updated_at  TEXT    NOT NULL
                DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

CREATE INDEX IF NOT EXISTS idx_ci_errors_session
    ON ci_errors(session_id, fingerprint, iteration);

CREATE INDEX IF NOT EXISTS idx_proposed_fixes_lookup
    ON proposed_fixes(session_id, iteration, status);
"
```

**Insert session row and capture session_id:**

`--fix` mode (implementation_model known upfront):

```bash
sqlite3 "$db_path" \
  "INSERT INTO sessions
     (project_slug, pr_number, mode, planning_model, implementation_model)
   VALUES ('<project_slug>', <pr_number>, 'fix',
           '<planning_model>', '<implementation_model>');
   SELECT last_insert_rowid();"
```

`--plan` mode (implementation_model deferred — NULL until Step 4):

```bash
sqlite3 "$db_path" \
  "INSERT INTO sessions (project_slug, pr_number, mode, planning_model)
   VALUES ('<project_slug>', <pr_number>, 'plan', '<planning_model>');
   SELECT last_insert_rowid();"
```

Capture the integer printed to stdout as `session_id` and save to memory.

**Verify:**

```bash
sqlite3 "$db_path" "SELECT id FROM sessions WHERE id = <session_id>;"
```

If this returns nothing, report "SQLite session init failed" and stop.

---

## Loop

Repeat the following steps. Increment `iteration` by 1 at the start of each
cycle.

### Step 1 — Fetch latest run

Get the PR's head SHA and the most recent workflow run:

```bash
rtk gh pr view <pr_number> --json headRefName,headRefOid,title
rtk gh run list --branch <headRefName> --limit 5 \
  --json databaseId,status,conclusion,headSha
```

Select the run whose `headSha` matches the PR's `headRefOid`. If no matching
run exists yet (new push just landed), wait 10 seconds and retry once. If
still no match, report and stop.

If the matching run exists but is already in progress (`status == "in_progress"`),
proceed directly to Step 2.

### Step 2 — Watch run

```bash
rtk gh run watch <run-id>
```

Report progress to the user before blocking:
> "Watching run #<run-id> for PR #<pr_number> (iteration <iteration>)…"

### Step 3 — Check result

```bash
rtk gh run view <run-id> --json conclusion
```

If `conclusion == "success"`:

```bash
sqlite3 "$db_path" \
  "UPDATE sessions SET outcome = 'green', iterations = <iteration>
   WHERE id = <session_id>;"
```

Print the final summary with `Outcome: green` and stop the loop.

### Step 4 — Extract errors (planning sub-agent)

Dispatch an Agent with `model: <planning_model>` and the prompt below.
Substitute `<run_id>`, `<session_id>`, `<db_path>`, and `<iteration>`.

**Prompt for planning sub-agent:**

> You are a CI error analyst. Do not apply any fixes. Follow these steps exactly.
>
> **A — Load skill and fetch logs**
>
> Load skill `s:gh-read-ci`, passing run ID `<run_id>`. The skill activates
> context-mode automatically, then returns a CI Error Report with an Errors
> table and a Fingerprints list.
>
> **B — Write ci_errors rows**
>
> For each row in the Errors table, INSERT one row. Escape single-quotes by
> doubling them (`''`). Use SQL NULL (not empty string) for absent fields:
>
> ```bash
> sqlite3 "<db_path>" \
>   "INSERT INTO ci_errors
>      (session_id, iteration, fingerprint, step, message, location, exit_code)
>    VALUES (<session_id>, <iteration>, '<fingerprint>',
>            '<step>', '<message>',
>            <'location' or NULL>, <'exit_code' or NULL>);"
> ```
>
> **C — Write proposed_fixes rows**
>
> For each fingerprint, reason about the most likely fix and INSERT one row.
> Set `diff_hint` to a minimal unified diff when the log gives enough context;
> use NULL only when it genuinely cannot be inferred:
>
> ```bash
> sqlite3 "<db_path>" \
>   "INSERT INTO proposed_fixes
>      (session_id, iteration, fingerprint,
>       file_path, line_number, description, diff_hint)
>    VALUES (<session_id>, <iteration>, '<fingerprint>',
>            <'file_path' or NULL>, <line_number or NULL>,
>            '<one-sentence fix description>',
>            <'--- a/f\n+++ b/f\n...' or NULL>);"
> ```
>
> **D — Return compact summary**
>
> ```
> ## Planning complete (iteration <iteration>)
> Errors written:    <N>
> Proposals written: <N>
> Fingerprints:      <comma-separated list>
> ```

After the sub-agent returns, verify rows were written:

```bash
sqlite3 "$db_path" \
  "SELECT fingerprint FROM ci_errors
   WHERE session_id = <session_id> AND iteration = <iteration>;"
```

If no rows are returned, report "Planning sub-agent wrote no ci_errors rows"
and stop.

**`--plan` mode only — recommend and confirm implementation model.**

Fetch proposed fixes to assess complexity:

```bash
sqlite3 -separator '|' "$db_path" \
  "SELECT fingerprint, file_path, line_number, description, diff_hint
   FROM proposed_fixes
   WHERE session_id = <session_id> AND iteration = <iteration>
   ORDER BY id;"
```

Evaluate using these heuristics:

- Recommend **Opus** if any of the following:
  - Any row has `diff_hint` = NULL
  - More than one distinct `file_path` (multi-file change)
  - Any `description` contains: "refactor", "signature", "rename",
    "callers", "Protocol", "move", "inheritance"
  - The same fingerprint appeared in a previous iteration (recurring)

- Recommend **Sonnet** when all of the following hold:
  - Every row has a non-NULL `diff_hint`
  - All fixes touch one file or are independent single-line changes
  - All descriptions are mechanical: "add import", "correct version",
    "fix assertion", "update pin", "remove unused"

Present recommendation with reasoning, then ask for confirmation:

> "Based on the proposed fixes (iteration <iteration>):
>
> ### Proposed fixes
> - <fingerprint> → <file_path>:<line_number>: <description>
>   Diff hint: <diff_hint or 'none'>
> ...
>
> **Recommendation: `<opus|sonnet>`**
> Reason: <one sentence>
>
> Press Enter to use `<recommendation>`, or type `sonnet`/`opus` to override:"

Capture as `implementation_model`. Default: the recommendation.
Save to memory and update the sessions row:

```bash
sqlite3 "$db_path" \
  "UPDATE sessions SET implementation_model = '<implementation_model>'
   WHERE id = <session_id>;"
```

### Step 5 — Check hard stop conditions

**Max iterations:** If `iteration >= 5`, record and stop:

```bash
sqlite3 "$db_path" \
  "UPDATE sessions
   SET outcome = 'max_iterations', iterations = <iteration>
   WHERE id = <session_id>;"
```

Print final summary with `Outcome: max iterations` and stop.

**Recurring error check** (within this session):

```bash
sqlite3 "$db_path" \
  "SELECT fingerprint, COUNT(DISTINCT iteration) AS occurrences
   FROM ci_errors
   WHERE session_id = <session_id>
   GROUP BY fingerprint
   HAVING occurrences >= 3;"
```

If any rows are returned, for each matching fingerprint report:
> "Error `<fingerprint>` has recurred `<occurrences>` times without being
> resolved — stopping to avoid a fix loop."

```bash
sqlite3 "$db_path" \
  "UPDATE sessions
   SET outcome = 'recurring_error', iterations = <iteration>
   WHERE id = <session_id>;"
```

Print final summary with `Outcome: recurring error` and stop.

**Cross-PR pattern note** (informational — never a hard stop):

```bash
sqlite3 "$db_path" \
  "SELECT e.fingerprint, COUNT(DISTINCT s.pr_number) AS pr_count
   FROM ci_errors e
   JOIN sessions s ON s.id = e.session_id
   WHERE s.project_slug = '<project_slug>'
   GROUP BY e.fingerprint
   HAVING pr_count >= 2
   ORDER BY pr_count DESC
   LIMIT 5;"
```

If any rows are returned, print as an advisory and continue:
> "Project-level recurring errors (seen in multiple PRs):
> - `<fingerprint>` — appeared in `<pr_count>` different PRs
> ...
> Consider fixing the root cause permanently rather than patching each PR."

### Step 6 — Apply fixes (implementation sub-agent)

Dispatch an Agent with `model: <implementation_model>` and the prompt below.
Substitute `<session_id>`, `<db_path>`, `<iteration>`, and `<mode>`.

**Prompt for implementation sub-agent:**

> You are a CI fix implementer. Follow these steps exactly.
>
> **A — Read proposals**
>
> ```bash
> sqlite3 -separator '|' "<db_path>" \
>   "SELECT id, fingerprint, file_path, line_number, description, diff_hint
>    FROM proposed_fixes
>    WHERE session_id = <session_id>
>      AND iteration  = <iteration>
>      AND status     = 'pending'
>    ORDER BY id;"
> ```
>
> Each line: `id|fingerprint|file_path|line_number|description|diff_hint`
>
> **B — Apply (mode: `<mode>`)**
>
> For each pending row:
>
> *`plan` mode* — show and wait:
> > "Proposed fix for `<fingerprint>`:
> > File:   `<file_path>:<line_number>`
> > Change: `<description>`
> > Hint:   `<diff_hint, or 'none — infer from description'>`
> > Apply? (yes / no / skip)"
>
> - `yes` → mark `approved`, apply the edit
> - `no` → stop processing remaining fixes
> - `skip` → mark `skipped`, continue to next fix
>
> *`fix` mode* — apply immediately:
> > "Fixed `<fingerprint>` → `<file_path>:<line_number>`: `<description>`"
>
> **C — Update status after each action**
>
> After a successful edit:
>
> ```bash
> sqlite3 "<db_path>" \
>   "UPDATE proposed_fixes
>    SET status = 'applied',
>        updated_at = strftime('%Y-%m-%dT%H:%M:%SZ','now')
>    WHERE id = <fix_id>;"
> ```
>
> On failure:
>
> ```bash
> sqlite3 "<db_path>" \
>   "UPDATE proposed_fixes
>    SET status = 'failed',
>        updated_at = strftime('%Y-%m-%dT%H:%M:%SZ','now')
>    WHERE id = <fix_id>;"
> ```
>
> **D — Return compact summary**
>
> ```
> ## Implementation complete (iteration <iteration>)
> Applied: <N>  Skipped: <N>  Failed: <N>
>
> ### Changes made
> - <fingerprint> → <file_path>:<line_number>: <description>
> ```

After the sub-agent returns, read applied rows to build the Checkpoint display:

```bash
sqlite3 -separator '|' "$db_path" \
  "SELECT fingerprint, file_path, line_number, description
   FROM proposed_fixes
   WHERE session_id = <session_id>
     AND iteration  = <iteration>
     AND status     = 'applied'
   ORDER BY id;"
```

### --- Checkpoint: fixes applied ---

**Pause and present what was changed to the user.**
Use the SQLite query from the end of Step 6 to populate the changes list.

```
## Checkpoint: Fixes Applied (iteration <iteration>)

### Changes made
- <fingerprint> → <file_path>:<line_number>: <description>
...

Commit staged changes locally and push to origin? (yes/no)
```

Wait for user confirmation. If **no**:

```bash
sqlite3 "$db_path" \
  "UPDATE sessions
   SET outcome = 'stopped_by_user', iterations = <iteration>
   WHERE id = <session_id>;"
```

Print final summary with `Outcome: stopped by user` and stop.
If **yes**, proceed to Step 7.

### Step 7 — Commit locally and push to origin

Stage only the files modified during this iteration — never `git add -A`.
After committing, push the branch to `origin` so CI picks up the new commit.

```bash
rtk git add <file1> <file2> ...
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
rtk git commit -m "$(cat <<'EOF'
fix(ci): resolve CI failures — iteration <N>

  - <fingerprint-1> → <file:line>
  - <fingerprint-2> → <file:line>
EOF
)"
rtk git push origin HEAD
```

### Step 8 — Ask to continue

> "Push complete. CI is running again (iteration <iteration> of 5).
> Continue watching? (yes/no)"

- **yes** → loop back to Step 1
- **no** →
  ```bash
  sqlite3 "$db_path" \
    "UPDATE sessions
     SET outcome = 'stopped_by_user', iterations = <iteration>
     WHERE id = <session_id>;"
  ```
  Print final summary with `Outcome: stopped by user` and stop

---

## Final summary

```text
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

### Live state (updated each iteration)

- `pr_number`, `mode` — set once at startup, never change
- `planning_model` — set once at startup, never changes
- `implementation_model` — set at startup (`--fix`) or after Step 4 (`--plan`)
- `project_slug` — derived in Step 0, never changes
- `db_path` — full path to this project's SQLite DB, set in Step 0
- `session_id` — integer set in Step 0, never changes
- `iteration` — increment at the start of each cycle

### Session snapshot

`sessions.outcome` is written to SQLite at every termination path.
No additional memory snapshot is needed.

---

## Do Not

- Do not stage files with `git add -A` or `git add .` — stage by name only.
- Do not skip `rtk gh run watch` — never assume a run has completed.
- Do not proceed past hard stop conditions.
- Do not commit with `--no-verify` unless the user explicitly requests it.
- Do not push without committing first.
- Do not start a new iteration if `iteration >= 5`.
- Do not read or write `seen_errors` in memory — recurring errors live in
  the `ci_errors` SQLite table.
- Do not call `rtk gh run view` directly in Steps 4 or 6 — sub-agents handle it.
- Do not dispatch sub-agents without substituting all `<placeholder>` values.
- Do not skip SQLite status updates when a fix is applied, skipped, or failed.
- Do not abbreviate `implementation_model` to `impl_model` in prompts or SQL.
- Do not default either model to `opus` — both default to `sonnet`.
- Do not ask for `implementation_model` upfront in `--plan` mode — defer it
  to after Step 4 so the user can judge complexity from the proposed fixes.
- Do not hardcode `~/.claude/gh-fix-ci.db` — always use `$db_path` (the
  project-scoped path derived in Step 0).
- Do not skip `project_slug` derivation — without it all projects share one DB.
