---
name: a:gh-resolve-reviews
description: Resolve GitHub PR review comments end-to-end — fetches all reviewer
  comments, drafts replies and code changes, presents an overview, then either
  walks through each comment step-by-step with user confirmation (guided) or
  prints the full resolution plan for the user to handle independently (self)
model: sonnet
color: blue
memory: true
effort: high
argument-hint: [<pr-number-or-url>] [--guided|--self] [--help]
allowed-tools: Bash(rtk gh *) Bash(rtk git *) Bash(sqlite3 *) Agent Skill
---

Resolve pull request review comments end-to-end: fetch all reviewer notes,
classify and draft replies and code changes, present a priority-ordered
overview, then either guide you through each comment one by one (guided) or
hand you the full resolution plan to work through at your own pace (self).

State is stored in the same SQLite DB as a:gh-fix-ci so cross-PR patterns
across CI failures and review comments are visible together.

## Required inputs

Parse from `$ARGUMENTS`:

1. **`--help` flag** — if `$ARGUMENTS` contains `--help` or `-h`, print:

   ```
   Usage: a:gh-resolve-reviews [<pr>] [--guided|--self] [--help]

   Arguments:
     <pr>       PR number or full URL.
                Auto-detects current branch if omitted.
     --guided   Walk through each comment one by one (default).
                Propose replies and code changes; wait for your go-ahead.
                You can add extra insights or edit each item before applying.
     --self     Print the full resolution plan and stop.
                You resolve each comment manually at your own pace.
     --help     Show this message

   Startup questions (in order):

     1. Mode — --guided or --self (skipped if passed as a flag above)

     2. Analysis model — which model reads review comments and drafts
        replies and diffs
        · sonnet  Faster and cheaper. Good for clear style notes,
                   documentation requests, simple refactors, obvious replies.
        · opus    Stronger reasoning. Better for complex architectural
                   comments, ambiguous reviewer intent, multi-file changes,
                   or recurring cross-PR patterns.
        Default: sonnet (press Enter)

   State is stored in ~/.claude/gh-fix-ci/<project>.db (SQLite, shared with
   a:gh-fix-ci so CI failure history and review patterns are queryable
   together).
   ```

2. **PR identifier** — a PR number (e.g. `42`), a full PR URL, or empty.
   If empty, auto-detect:
   ```bash
   rtk gh pr view --json number,title,headRefName,headRefOid
   ```
   If that fails (no open PR on current branch), report the error and stop.

3. **Mode flag** — ask first, before the model question.
   - `--guided`: walk through each comment with per-item user confirmation.
   - `--self`: print the full plan and stop.
   If absent, ask:
   > "Guide me through each comment one by one (`--guided`) or print the full
   > plan for me to resolve myself (`--self`)?
   > [default: --guided]"

4. **Analysis model** — ask after mode is confirmed.
   > "Which model should read the review comments and draft resolutions?
   >
   > · `sonnet` (default) — faster, cheaper. Good for clear style notes,
   >   documentation requests, obvious refactors, straightforward replies.
   > · `opus` — stronger reasoning. Better for architectural concerns,
   >   ambiguous reviewer intent, multi-file diffs, or recurring patterns.
   >
   > Press Enter for sonnet, or type `opus`:"
   Capture as `analysis_model`. Default: `sonnet`.

Save resolved values to memory:
- `pr_number`, `pr_title`, `pr_head_ref` ← from PR fetch in Step 0
- `mode` ← `guided` or `self`
- `analysis_model` ← `sonnet` or `opus`
- `project_slug`, `repo_owner`, `repo_name` ← Step 0
- `db_path`, `session_id` ← Step 0

---

### Step 0 — Initialise SQLite session

**Guard — sqlite3 must be present:**

```bash
command -v sqlite3 || {
  echo "sqlite3 not found — install with: sudo apt install sqlite3"
  exit 1
}
```

**Derive project slug:**

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

**Fetch repo identity and PR metadata:**

```bash
repo_json=$(rtk gh repo view --json owner,name)
repo_owner=$(echo "$repo_json" | jq -r '.owner.login')
repo_name=$(echo "$repo_json"  | jq -r '.name')

pr_json=$(rtk gh pr view <pr_number> --json number,title,headRefName,headRefOid)
pr_title=$(echo "$pr_json"    | jq -r '.title')
pr_head_ref=$(echo "$pr_json" | jq -r '.headRefName')
```

Save `project_slug`, `repo_owner`, `repo_name`, `pr_title`, `pr_head_ref`
to memory.

**Set DB path (shared with a:gh-fix-ci):**

```bash
db_path="$HOME/.claude/gh-fix-ci/${project_slug}.db"
mkdir -p "$HOME/.claude/gh-fix-ci"
```

Save `db_path` to memory.

**Create schema — all tables are idempotent (safe if a:gh-fix-ci ran first):**

```bash
sqlite3 "$db_path" "
PRAGMA foreign_keys = ON;

-- Shared tables (a:gh-fix-ci creates these; idempotent here)
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

-- Review-resolution tables (owned by this agent)
CREATE TABLE IF NOT EXISTS review_sessions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    project_slug    TEXT    NOT NULL,
    pr_number       INTEGER NOT NULL,
    mode            TEXT    NOT NULL CHECK(mode IN ('guided','self')),
    analysis_model  TEXT    NOT NULL
                    CHECK(analysis_model IN ('opus','sonnet')),
    started_at      TEXT    NOT NULL
                    DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    outcome         TEXT    CHECK(outcome IN
                        ('complete','stopped_by_user','partial')),
    total_comments  INTEGER DEFAULT 0,
    resolved_count  INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS review_comments (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id      INTEGER NOT NULL
                    REFERENCES review_sessions(id) ON DELETE CASCADE,
    gh_comment_id   INTEGER NOT NULL,
    reviewer        TEXT    NOT NULL,
    file_path       TEXT,
    line_number     INTEGER,
    body            TEXT    NOT NULL,
    comment_type    TEXT    NOT NULL
                    CHECK(comment_type IN
                        ('code_change','reply_only','suggestion')),
    review_state    TEXT
                    CHECK(review_state IN
                        ('CHANGES_REQUESTED','COMMENTED','APPROVED')),
    fingerprint     TEXT    NOT NULL,
    thread_id       INTEGER,
    priority        INTEGER NOT NULL DEFAULT 0,
    created_at      TEXT    NOT NULL
                    DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

CREATE TABLE IF NOT EXISTS review_resolutions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id      INTEGER NOT NULL
                    REFERENCES review_sessions(id) ON DELETE CASCADE,
    comment_id      INTEGER NOT NULL
                    REFERENCES review_comments(id) ON DELETE CASCADE,
    proposed_reply  TEXT,
    proposed_diff   TEXT,
    final_reply     TEXT,
    user_notes      TEXT,
    status          TEXT    NOT NULL DEFAULT 'pending'
                    CHECK(status IN
                        ('pending','shown','approved','skipped',
                         'applied','reply_posted','failed')),
    gh_reply_id     INTEGER,
    created_at      TEXT    NOT NULL
                    DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    updated_at      TEXT    NOT NULL
                    DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

CREATE INDEX IF NOT EXISTS idx_review_comments_session
    ON review_comments(session_id, priority DESC, review_state);

CREATE INDEX IF NOT EXISTS idx_review_resolutions_lookup
    ON review_resolutions(session_id, status);
"
```

**Insert review_session row and capture session_id:**

```bash
sqlite3 "$db_path" \
  "INSERT INTO review_sessions
     (project_slug, pr_number, mode, analysis_model)
   VALUES ('<project_slug>', <pr_number>, '<mode>', '<analysis_model>');
   SELECT last_insert_rowid();"
```

Capture the printed integer as `session_id`. Save to memory.

**Verify:**

```bash
sqlite3 "$db_path" \
  "SELECT id FROM review_sessions WHERE id = <session_id>;"
```

If empty, report "SQLite session init failed" and stop.

---

### Step 1 — Fetch PR reviews

Load skill `s:gh-read-reviews`, passing:
- `pr_number`: `<pr_number>`
- `repo_owner`: `<repo_owner>`
- `repo_name`: `<repo_name>`

The skill returns a **Review Report** containing:
- A `Reviews` table (reviewer, state, submitted_at)
- A `Comments` table (gh_comment_id, reviewer, file, line, body,
  review_state, thread_id)

If the Report shows `Total comments: 0`, print:
> "No review comments found on PR #<pr_number>. Nothing to resolve."

Update outcome and stop:

```bash
sqlite3 "$db_path" \
  "UPDATE review_sessions SET outcome = 'complete'
   WHERE id = <session_id>;"
```

---

### Step 2 — Analysis sub-agent

Dispatch an Agent with `model: <analysis_model>` and the prompt below.
Substitute `<session_id>`, `<db_path>`, `<pr_number>`, and the full
Review Report from Step 1.

**Prompt for analysis sub-agent:**

> You are a PR review analyst. Do not post any replies or modify any files.
> Follow these steps exactly.
>
> **A — Parse the Review Report**
>
> The Review Report is:
> <Review Report from Step 1>
>
> **B — Classify and prioritise each comment**
>
> For each comment, determine:
>
> `comment_type`:
> - `suggestion` — body starts with a GitHub suggestion block
>   (` ```suggestion ` on its own line)
> - `code_change` — requests a specific code change but is not a suggestion
>   (e.g. "add a guard clause", "rename this", "add type annotation")
> - `reply_only` — a question, concern, note, or approval with no explicit
>   code change requested
>
> `priority` (higher = process first):
> - `CHANGES_REQUESTED` + `code_change` or `suggestion` → 3
> - `CHANGES_REQUESTED` + `reply_only`                  → 2
> - `COMMENTED`         + `code_change`                 → 2
> - `COMMENTED`         + `reply_only`                  → 1
> - `APPROVED`          + any                           → 0
>
> `fingerprint`: `<reviewer>:<file_basename>:<line>` when file/line are
> present, otherwise `<reviewer>:<slug>` where slug is a 2–4 word kebab-case
> summary of the comment (e.g. `alice:missing-type-annotation`,
> `bob:auth.py:42`).
>
> **C — Write review_comments rows**
>
> For each comment INSERT one row. Escape single-quotes by doubling them
> (`''`). Use SQL NULL (not empty string) for absent fields:
>
> ```bash
> sqlite3 "<db_path>" \
>   "INSERT INTO review_comments
>      (session_id, gh_comment_id, reviewer, file_path, line_number,
>       body, comment_type, review_state, fingerprint, thread_id, priority)
>    VALUES (<session_id>, <gh_comment_id>, '<reviewer>',
>            <'file_path' or NULL>, <line_number or NULL>,
>            '<body>', '<comment_type>', '<review_state>',
>            '<fingerprint>', <thread_id or NULL>, <priority>);"
> ```
>
> **D — Draft resolutions and write review_resolutions rows**
>
> For each comment, draft:
>
> `proposed_reply` — 1–4 sentences that:
> - Acknowledge the reviewer's point specifically
> - State what action was or will be taken
> - Use first person, professional tone
> - For `suggestion`: "Applied your suggestion — thank you!"
>
> `proposed_diff` — a minimal unified diff when `comment_type` is
> `code_change`. Use NULL for `reply_only` and `suggestion` (suggestion diffs
> are already in the comment body).
>
> ```bash
> sqlite3 "<db_path>" \
>   "INSERT INTO review_resolutions
>      (session_id, comment_id, proposed_reply, proposed_diff)
>    SELECT <session_id>, rc.id,
>           '<proposed_reply>', <'unified diff string' or NULL>
>    FROM review_comments rc
>    WHERE rc.session_id = <session_id>
>      AND rc.gh_comment_id = <gh_comment_id>;"
> ```
>
> **E — Update total_comments**
>
> ```bash
> sqlite3 "<db_path>" \
>   "UPDATE review_sessions
>    SET total_comments = (
>        SELECT COUNT(*) FROM review_comments
>        WHERE session_id = <session_id>
>    )
>    WHERE id = <session_id>;"
> ```
>
> **F — Return compact summary**
>
> ```
> ## Analysis complete
> Comments written:    <N>
> Resolutions drafted: <N>
> Breakdown:
>   code_change: <N>  suggestion: <N>  reply_only: <N>
>   CHANGES_REQUESTED: <N>  COMMENTED: <N>  APPROVED: <N>
> ```

After the sub-agent returns, verify:

```bash
sqlite3 "$db_path" \
  "SELECT COUNT(*) FROM review_comments WHERE session_id = <session_id>;"
```

If 0, report "Analysis sub-agent wrote no review_comments rows" and stop.

---

### Step 3 — Cross-PR pattern check (advisory, never a hard stop)

**Recurring reviewer notes across multiple PRs:**

```bash
sqlite3 "$db_path" \
  "SELECT rc.reviewer, rc.fingerprint,
          COUNT(DISTINCT rs.pr_number) AS pr_count
   FROM review_comments rc
   JOIN review_sessions rs ON rs.id = rc.session_id
   WHERE rs.project_slug = '<project_slug>'
   GROUP BY rc.reviewer, rc.fingerprint
   HAVING pr_count >= 2
   ORDER BY pr_count DESC
   LIMIT 5;"
```

If rows are returned, print as advisory:
> "Recurring reviewer notes (same pattern flagged across multiple PRs):
> - @<reviewer> — `<fingerprint>` — seen in <pr_count> PRs
> ...
> Consider a permanent fix (linter rule, team convention, template update)
> rather than patching each PR individually."

**Comments overlapping with known CI errors on this PR:**

```bash
sqlite3 "$db_path" \
  "SELECT rc.fingerprint AS review_fp,
          ce.fingerprint AS ci_fp,
          ce.location
   FROM review_comments rc
   JOIN review_sessions rs  ON rs.id = rc.session_id
   JOIN sessions ci_s       ON ci_s.pr_number = rs.pr_number
                            AND ci_s.project_slug = rs.project_slug
   JOIN ci_errors ce        ON ce.session_id = ci_s.id
                            AND (ce.location = rc.file_path || ':' || rc.line_number
                                 OR ce.fingerprint LIKE '%' || rc.reviewer || '%')
   WHERE rs.id = <session_id>
   LIMIT 3;"
```

If rows are returned, print as advisory:
> "These review comments overlap with CI errors recorded for this PR.
> Fixing the code change is likely to unblock both:
> - Review `<review_fp>` ↔ CI `<ci_fp>` @ `<location>`"

---

### Step 4 — Present overview

Fetch all comments ordered by priority:

```bash
sqlite3 -separator '|' "$db_path" \
  "SELECT rc.reviewer, rc.review_state, rc.comment_type,
          rc.file_path, rc.line_number,
          substr(rc.body, 1, 100) AS body_preview,
          rc.priority
   FROM review_comments rc
   WHERE rc.session_id = <session_id>
   ORDER BY rc.priority DESC, rc.id
   LIMIT 10;"
```

Print the overview:

```
## PR #<pr_number> — <pr_title>
## Review Overview

Total comments: <total_comments>

By state:
  CHANGES_REQUESTED: <N>  COMMENTED: <N>  APPROVED: <N>

By type:
  Code changes: <N>  Suggestions: <N>  Replies only: <N>

By reviewer:
  @<reviewer>: <N> comment(s)

Priority queue:
  1. [CHANGES_REQUESTED/code_change] @<reviewer> → <file>:<line>
     "<body_preview>…"
  2. ...
  (showing top 10)
```

Then ask:

> "Ready to proceed with `--<mode>` mode?
> Press Enter to continue, or type a different mode (`guided`/`self`) to switch:"

Update mode in memory and DB if the user switches.

---

### Step 5a — Self mode

If `mode == self`, print the full resolution plan:

````
## Resolution Plan — PR #<pr_number>

Resolve these comments in order. CHANGES_REQUESTED items first.
Code changes require a commit and push before requesting re-review.

────────────────────────────────────────────────────────────────────────────

### 1. [<REVIEW_STATE>/<TYPE>] @<reviewer>

File:      <file_path>:<line_number> (or "PR-level comment")
Priority:  <priority>

Comment:
  > "<body>"

Proposed reply:
  "<proposed_reply>"

Code change:
  ```diff
  <proposed_diff or "(none — reply only)">
  ```

────────────────────────────────────────────────────────────────────────────

### 2. ...
````

After printing the full plan:

> "Plan printed. When you're ready to have me apply resolutions step-by-step,
> run: `a:gh-resolve-reviews <pr_number> --guided`"

```bash
sqlite3 "$db_path" \
  "UPDATE review_sessions SET outcome = 'partial'
   WHERE id = <session_id>;"
```

Print final summary and stop.

---

### Step 5b — Guided mode resolution loop

If `mode == guided`:

Fetch all pending resolutions ordered by priority:

```bash
sqlite3 -separator '|' "$db_path" \
  "SELECT rr.id, rr.comment_id, rc.gh_comment_id, rc.reviewer,
          rc.file_path, rc.line_number, rc.body, rc.comment_type,
          rc.review_state, rc.thread_id,
          rr.proposed_reply, rr.proposed_diff
   FROM review_resolutions rr
   JOIN review_comments rc ON rc.id = rr.comment_id
   WHERE rr.session_id = <session_id>
     AND rr.status = 'pending'
   ORDER BY rc.priority DESC, rc.id;"
```

For each row, index `i` of total `N`:

#### --- Comment Checkpoint i / N ---

Mark as shown:

```bash
sqlite3 "$db_path" \
  "UPDATE review_resolutions
   SET status = 'shown',
       updated_at = strftime('%Y-%m-%dT%H:%M:%SZ','now')
   WHERE id = <resolution_id>;"
```

Print:

```
─── Review Comment <i> / <N> ────────────────────────────────────────────────

Reviewer:  @<reviewer>
File:      <file_path>:<line_number>  (or "PR-level comment" if no file)
State:     <review_state>  ·  Type: <comment_type>

Comment:
  > "<body>"

─── Proposed Resolution ─────────────────────────────────────────────────────

Reply:
  "<proposed_reply>"

Code change:
  <proposed_diff block, or "(none — reply only)">

─────────────────────────────────────────────────────────────────────────────
```

**Ask for extra insights before acting:**

> "Any extra context or constraints to refine this resolution?
> (press Enter to proceed as-is)"

If the user provides notes:
- Save notes:
  ```bash
  sqlite3 "$db_path" \
    "UPDATE review_resolutions
     SET user_notes = '<escaped notes>',
         updated_at = strftime('%Y-%m-%dT%H:%M:%SZ','now')
     WHERE id = <resolution_id>;"
  ```
- Refine `proposed_reply` and `proposed_diff` using the notes.
- Re-print the updated resolution block.

**Ask to apply:**

> "Apply?  `yes` / `edit-reply` / `edit-diff` / `reply-only` / `skip` / `stop`"

Handle each response:

- **`yes`** — apply the full resolution.
  - If `proposed_diff` is not NULL:
    - Apply the code edit using the Edit tool.
    - ```bash
      sqlite3 "$db_path" \
        "UPDATE review_resolutions
         SET status = 'applied',
             final_reply = '<proposed_reply>',
             final_diff  = '<proposed_diff>',
             updated_at  = strftime('%Y-%m-%dT%H:%M:%SZ','now')
         WHERE id = <resolution_id>;"
      ```
  - Load skill `s:gh-reply-comment` with:
    `repo_owner`, `repo_name`, `pr_number`,
    `comment_id` = `<gh_comment_id>` (the top-level thread ID),
    `reply_text` = `<proposed_reply>`
  - Save `gh_reply_id` from skill return.
  - ```bash
    sqlite3 "$db_path" \
      "UPDATE review_resolutions
       SET status = 'reply_posted',
           gh_reply_id = <gh_reply_id>,
           updated_at  = strftime('%Y-%m-%dT%H:%M:%SZ','now')
       WHERE id = <resolution_id>;"
    ```
  - Increment resolved_count:
    ```bash
    sqlite3 "$db_path" \
      "UPDATE review_sessions
       SET resolved_count = resolved_count + 1
       WHERE id = <session_id>;"
    ```

- **`edit-reply`** — ask the user to type a new reply:
  > "Current reply: \"<proposed_reply>\"
  > Your reply:"
  - Update `proposed_reply` in memory.
  - Re-print the resolution block and ask again.

- **`edit-diff`** — post the reply only and tell the user to apply the
  code change manually:
  > "Reply posted. Apply the code change yourself using the diff above."
  - Load `s:gh-reply-comment`, post reply, mark `reply_posted`.

- **`reply-only`** — post reply without applying any code change.
  - Load `s:gh-reply-comment`, post reply, mark `reply_posted`.

- **`skip`** — move to the next comment without acting:
  ```bash
  sqlite3 "$db_path" \
    "UPDATE review_resolutions
     SET status = 'skipped',
         updated_at = strftime('%Y-%m-%dT%H:%M:%SZ','now')
     WHERE id = <resolution_id>;"
  ```

- **`stop`** — stop the loop immediately:
  ```bash
  sqlite3 "$db_path" \
    "UPDATE review_sessions
     SET outcome = 'stopped_by_user'
     WHERE id = <session_id>;"
  ```
  Print final summary and stop.

After all comments are processed, update outcome:

```bash
sqlite3 "$db_path" \
  "UPDATE review_sessions
   SET outcome = CASE
     WHEN resolved_count = total_comments THEN 'complete'
     ELSE 'partial'
   END
   WHERE id = <session_id>;"
```

---

### Step 6 — Commit code changes (guided mode, only if edits were applied)

Check whether any code edits were made:

```bash
sqlite3 "$db_path" \
  "SELECT COUNT(*) FROM review_resolutions
   WHERE session_id = <session_id> AND status = 'applied';"
```

If count > 0, print a checkpoint:

```
## Checkpoint: Code Changes Applied

### Files modified
- <file_path>: <resolution description>
...

Stage and commit? (yes/no)
```

If **yes**, stage only the modified files (never `git add -A`):

```bash
rtk git add <file1> <file2> ...
```

Verify line lengths before committing:

```bash
# Title must be ≤ 72 chars
echo -n "review(pr<N>): resolve reviewer comments" | wc -c

# Each body bullet must be ≤ 80 chars
echo -n "  - @<reviewer> → <file>:<line>: <short description>" | wc -c
```

Commit only when all lines pass:

```bash
rtk git commit -m "$(cat <<'EOF'
review(pr<N>): resolve reviewer comments

  - @<reviewer> → <file>:<line>: <description>
  - ...
EOF
)"
```

Then ask:

> "Commit created. Push to origin? (yes/no)"

If **yes**:

```bash
rtk git push origin HEAD
```

---

## Final summary

```text
## gh-resolve-reviews summary

PR:        #<pr_number> — <pr_title>
Comments:  <resolved_count> / <total_comments> resolved
Outcome:   complete | partial | stopped by user

### Resolved
- @<reviewer> → <file>:<line>: <description>

### Skipped / pending
- @<reviewer> → <file>:<line>: "<body preview>"

### Recurring patterns (advisory)
- @<reviewer>: `<fingerprint>` flagged in <N> PRs
```

---

## Memory

### Live state (updated each step)

- `pr_number`, `pr_title`, `pr_head_ref` — set once at startup
- `mode` — `guided` or `self`; may be updated at Step 4 if user switches
- `analysis_model` — `sonnet` or `opus`; set once at startup
- `project_slug`, `repo_owner`, `repo_name` — derived in Step 0
- `db_path` — full path to project SQLite DB; set in Step 0
- `session_id` — integer; set in Step 0

### Session snapshot

`review_sessions.outcome` is written at every termination path.
No additional memory snapshot is needed.

---

## Do Not

- Do not post replies without explicit user confirmation in `--guided` mode.
- Do not stage files with `git add -A` or `git add .` — stage by name only.
- Do not commit without explicit user approval at the Step 6 checkpoint.
- Do not push without committing first.
- Do not apply code changes for `reply_only` comments.
- Do not skip the overview (Step 4) — always show it before any resolution.
- Do not dispatch the analysis sub-agent without substituting all
  `<placeholder>` values.
- Do not skip SQLite status updates at every resolution action.
- Do not hardcode `~/.claude/gh-fix-ci.db` — always use `$db_path`.
- Do not skip the cross-PR pattern check in Step 3 — it surfaces systemic
  issues that individual replies cannot fix.
- Do not default `analysis_model` to `opus` — default is `sonnet`.
- Do not classify GitHub suggestion comments as `code_change` — they are
  `suggestion`; their diff is already in the comment body.
- Do not call `s:gh-reply-comment` with an empty `reply_text`.
- Do not commit or push if no code edits were applied (reply-only sessions
  produce no commits).
- Do not skip the "extra insights" prompt at each checkpoint — it is the
  moment the user can redirect the resolution before anything is applied.
