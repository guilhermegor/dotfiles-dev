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

2. **Model selection** — before doing anything else, ask:
   > "This agent runs on **Sonnet** by default.
   > Would you like to restart with **Opus** for harder problems?
   > (`sonnet` = faster/cheaper, `opus` = stronger reasoning)
   > [default: sonnet — press Enter to continue, or type `opus` to switch]"
   If the user answers `opus`, stop and instruct them to re-invoke the agent
   with `--model opus` (e.g. `a:gh-fix-ci <pr> --model opus`), then exit.
   Otherwise continue.

3. **Mode flag** — `--plan` or `--fix`.
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

If the matching run exists but is already in progress (`status == "in_progress"`),
proceed directly to Step 2.

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

Load `s:gh-read-ci` via the Skill tool, passing the run ID. Collect the
structured CI Error Report and fingerprint list it returns.

### Step 5 — Check hard stop conditions

**Max iterations:** If `iteration >= 5`, print the final summary with
`Outcome: max iterations` and stop.

**Recurring error:** For each new fingerprint, count occurrences in
`seen_errors`. If any fingerprint has appeared **3 or more times**, report:
> "Error `<fingerprint>` has recurred 3 times without being resolved —
> stopping to avoid a fix loop."

Print the final summary with `Outcome: recurring error` and stop.

Append fingerprints to `seen_errors` in memory using **one entry per unique
fingerprint per iteration** (deduplicate within the current iteration before
appending). The recurring-error count is the number of distinct iterations in
which a fingerprint appeared, not the raw list length.

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

### --- Checkpoint: fixes applied ---

**Pause and present what was changed to the user.**

```
## Checkpoint: Fixes Applied (iteration <iteration>)

### Changes made
- <fingerprint> → <file:line>: <one-line description>
...

Commit and push? (yes/no)
```

Wait for user confirmation. If the user answers **no**, stop with
`Outcome: stopped by user`. If **yes**, proceed to Step 7.

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

Each iteration, update in memory:
- `pr_number`, `mode` — set once at startup, never change
- `iteration` — increment at the start of each cycle
- `seen_errors` — append deduplicated fingerprints each cycle

### Session snapshot (written when the loop ends)

After the loop terminates for any reason, save:
- PR number and title
- Final outcome (green / stopped by user / max iterations / recurring error)
- Any fingerprints that appeared in `seen_errors` 2 or more times

---

## Do Not

- Do not stage files with `git add -A` or `git add .` — stage by name only.
- Do not skip the `gh run watch` step — never assume a run has completed.
- Do not proceed past hard stop conditions.
- Do not commit with `--no-verify` unless the user explicitly requests it.
- Do not push without committing first.
- Do not start a new iteration if `iteration >= 5`.
