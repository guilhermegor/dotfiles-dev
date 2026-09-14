# Design: gh-fix-ci agent

**Date:** 2026-04-21
**Status:** Approved

## Summary

A Claude Code agent (`a:gh-fix-ci`) that connects to a GitHub PR, fetches the
latest failed Actions run, extracts errors via a companion skill, fixes them,
recommits and repushes, then loops — polling for the new run result and asking
the user whether to continue — until CI is green or a hard stop is hit.

---

## Artifacts

| File | Artifact | Invocation |
|------|----------|------------|
| `ai_clients/claude/agents/gh-fix-ci.md` | `a:gh-fix-ci` | User-invoked |
| `ai_clients/claude/skills/gh-read-ci.md` | `s:gh-read-ci` | Loaded by agent |

---

## Arguments

Parsed from `$ARGUMENTS`:

- **PR identifier** — a PR number (e.g. `42`), a PR URL, or empty.
  Empty → auto-detect from current branch via `gh pr view`.
- **Mode flag** — `--plan` (propose fixes, wait for approval) or `--fix`
  (apply directly). If absent, agent asks at startup.

---

## Agent memory schema

`memory: true` — persists across loop iterations within the session.

| Key | Type | Description |
|-----|------|-------------|
| `pr_number` | integer | Resolved PR number. Set once, reused each iteration. |
| `mode` | `plan` \| `fix` | Fix mode. Set once at startup. |
| `iteration` | integer | Increments each fix cycle. Starts at 1. |
| `seen_errors` | list of strings | Error fingerprints from all prior iterations. Used to detect recurring failures. |

---

## Loop flow

Each iteration:

```
1. Resolve PR    →  gh pr view (or $ARGUMENTS)
2. Fetch run     →  gh run list --limit 1 on PR's head SHA → get run ID
3. Watch run     →  gh run watch <run-id>  (blocks until complete)
4. Check result  →  if run succeeded → report "CI green" → stop
5. Fetch logs    →  gh run view <run-id> --log-failed
6. Load skill    →  s:gh-read-ci  (context-mode + error extraction)
7. Fix           →  apply fixes per mode (--plan proposes, --fix applies)
8. Commit+push   →  stage changed files, commit, push HEAD
9. Compare       →  diff new error fingerprints against seen_errors;
                    warn user if the same error recurs
10. Ask user     →  "CI is running again. Continue fixing? (yes/no)"
    yes → increment iteration, loop to step 2
    no  → stop, print summary
```

---

## Hard stop conditions

The agent stops without prompting when either condition is met:

- **Max iterations reached** — 5 iterations (hardcoded in the agent).
- **Recurring error** — the same error fingerprint appears 3 times in
  `seen_errors`. The agent reports which error is recurring and stops.

---

## `s:gh-read-ci` skill

**Purpose:** Parse raw `gh run view --log-failed` output into structured errors.

**Steps:**
1. Activate context-mode plugin to enrich CI log processing.
2. Extract failing step names, error messages, file:line references, and exit
   codes into a structured list.
3. Produce short error fingerprints (e.g. `mypy:src/foo.py:23`) for the agent
   to store in `seen_errors`.

**Output:** A structured error block consumed by the agent. Raw log text is not
surfaced to the user unless the agent decides to include it in a report.

**`allowed-tools`:** `Bash(gh run*)` only.

---

## Final summary format

After the loop ends (CI green, user stops, or hard stop), the agent prints:

```
## gh-fix-ci summary

PR:         #<number> — <title>
Iterations: <N>
Outcome:    green | stopped by user | max iterations | recurring error

### Fixed
- <file:line — description>

### Remaining errors
- <step — error — file:line>
```
