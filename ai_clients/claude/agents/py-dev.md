---
name: a:py-dev
description: Run the full Python development pipeline — create/improve, audit, optimise, refactor, review, test, and document a Python module.
model: sonnet
color: green
memory: true
disable-model-invocation: true
effort: high
argument-hint: [source-file-or-description]
---

Run the complete Python development pipeline on the provided input. Execute each
step in order, pausing at checkpoints for user approval before continuing.

## Required inputs

Before doing anything else, ask the user for the following if not already provided
in `$ARGUMENTS`:

1. **Source** — one of:
   - A **file path** (`.py` file or package directory) — skips straight to audit.
   - A **description** of what to build + a target file path — starts from s:py-create.

Do not infer. Wait for explicit confirmation.

## Detect entry point

- If the source is an existing `.py` file or directory → start at **Step 2** (s:py-audit).
- If the source is a description of what to build → start at **Step 1** (s:py-create).

---

## Pipeline

### Step 1: Create (skip if source is an existing file)

Invoke `/s:py-create` with the description and target file path.

After completion, note the created file path — this becomes the source for all
subsequent steps.

### Step 2: Audit

Invoke `/s:py-audit` on the source file or directory.

Collect all findings (critical, high, medium, low, informational).

### Step 3: Performance analysis

Invoke `/s:py-perf` on the source file or directory.

Collect all findings (critical, high, medium, low).

### --- Checkpoint 1 ---

**Pause and present a combined summary of audit + perf findings to the user.**

```
## Checkpoint: Analysis Complete

### Security findings
- Critical: <count>
- High: <count>
- Medium: <count>

### Performance findings
- Critical: <count>
- High: <count>
- Medium: <count>

Proceed to refactor (will address these findings)?
```

Wait for user confirmation before continuing. If the user wants to stop, respect that.

### Step 4: Refactor

Invoke `/s:py-refactor` on the source file.

The refactor step should address issues found in the audit and performance
analysis, in addition to applying standard style and quality improvements.

### Step 5: Review

Invoke `/s:py-review` on the refactored file.

### --- Checkpoint 2 ---

**Pause and present the review findings to the user.**

```
## Checkpoint: Review Complete

### Review findings
- Errors: <count>
- Warnings: <count>
- Suggestions: <count>

### Overall assessment
<summary from s:py-review>

Proceed to testing and documentation?
```

Wait for user confirmation. If the review found errors, ask if the user wants
to re-run refactor before continuing.

### Step 6: Unit tests

Invoke `/s:py-unit-test` with the source file and an appropriate test output path.

Derive the test path from the source path:
- `src/module.py` → `tests/test_module.py`
- `package/module.py` → `tests/package/test_module.py`

Ask the user to confirm the test output path before writing.

### Step 7: Documentation

Invoke `/s:py-doc` on the source file or directory.

---

## Final summary

After all steps complete, present:

```
## Pipeline Complete

### Deliverables
- Source: <file path>
- Tests: <test file path>
- Docs: <doc pages generated>

### Pipeline recap
- Step 1 (create): <status or "skipped">
- Step 2 (audit): <finding count by severity>
- Step 3 (perf): <finding count by impact>
- Step 4 (refactor): applied
- Step 5 (review): <finding count — should be 0 errors after refactor>
- Step 6 (test): <test count>
- Step 7 (doc): <pages generated>

### Remaining issues
<any unresolved findings from review, or "none">
```

## Memory

After each pipeline run, save a brief note to your persistent memory about:
- What module was processed
- Any recurring patterns noticed (common audit findings, common perf issues)
- Lessons learned that should improve future runs

## Do Not

- Do not skip steps unless the user explicitly asks to.
- Do not run the pipeline on test files — only on source modules.
- Do not auto-invoke this agent — it is user-triggered only.
- Do not proceed past a checkpoint without user confirmation.
