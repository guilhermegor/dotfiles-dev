---
name: py-fix
description: Fix a Python bug using test-driven development — diagnose, write failing test, fix, verify, review.
model: opus
color: red
memory: true
disable-model-invocation: true
effort: high
argument-hint: [source-file] [error-or-traceback]
---

Fix a Python bug end-to-end: diagnose the root cause, write a failing test,
apply the fix, verify it passes, and review the result.

## Required inputs

Before doing anything else, ask the user for the following if not already provided
in `$ARGUMENTS`:

1. **Source file** — the path to the Python module with the bug.
2. **Error** — the traceback, error message, or description of unexpected behaviour.

Do not infer either. Wait for explicit confirmation.

---

## Pipeline

### Step 1: Diagnose

Invoke `/py-debug` with the source file and error.

Collect the diagnosis: root cause, evidence, call chain, suggested fix.

### --- Checkpoint 1 ---

**Pause and present the diagnosis to the user.**

```
## Checkpoint: Diagnosis Complete

### Root cause
<from py-debug output>

### Suggested fix
<from py-debug output>

### Confidence
<from py-debug output>

Proceed with test-driven fix?
```

Wait for user confirmation. If the user disagrees with the diagnosis or wants
to investigate further, respect that.

### Step 2: Write failing test

Write a **single, targeted test** that reproduces the bug. This is NOT a full
test suite — it is one test function that:

- Sets up the conditions that trigger the bug.
- Calls the failing code path.
- Asserts the expected (correct) behaviour.
- **Currently fails** because the bug is still present.

Place the test in the appropriate test file:
- `src/module.py` → `tests/test_module.py`
- `package/module.py` → `tests/package/test_module.py`

If the test file already exists, append the new test. If not, create it.

Name the test: `test_<function_name>_<bug_description>`.

### Step 3: Verify test fails

Run the new test via `pytest <test_file>::<test_name> -v`.

Confirm it **fails** with the expected error. If it passes, the test doesn't
reproduce the bug — revise it before continuing.

### Step 4: Fix the bug

Apply the minimal fix to the source file:

- Fix the **root cause**, not the symptom.
- Change as few lines as possible.
- Do not refactor surrounding code — this is a targeted fix.
- Do not add features or change unrelated behaviour.

### Step 5: Verify test passes

Run the new test again: `pytest <test_file>::<test_name> -v`.

Confirm it **passes** now.

### Step 6: Run full test suite

Run `pytest` on the full test suite (or at minimum the test file for the
affected module) to verify no regressions.

### --- Checkpoint 2 ---

**Pause and present the test results to the user.**

```
## Checkpoint: Fix Verified

### New test
<test name> — <PASS/FAIL>

### Regression check
<count> tests passed, <count> failed, <count> skipped

### Changes made
- `source.py:42` — <what was changed>

Proceed to review?
```

Wait for user confirmation. If there are regressions, investigate before
continuing.

### Step 7: Review

Invoke `/py-review` on the modified source file.

Report any findings. If errors are found, fix them before completing.

---

## Final summary

```
## Bug Fix Complete

### Bug
<original error description>

### Root cause
<one-sentence explanation>

### Fix applied
- `source.py:42` — <change description>

### Test added
- `test_file.py::test_name` — reproduces and verifies the fix

### Review
- Errors: <count>
- Warnings: <count>
```

## Memory

After each bug fix, save a brief note about:
- The module and function affected
- The root cause category (e.g., None propagation, mutable default, async mistake)
- Whether the diagnosis was correct on first attempt

## Do Not

- Do not skip the failing test step — TDD is mandatory.
- Do not apply the fix before the test is written and confirmed failing.
- Do not refactor surrounding code — fix only the bug.
- Do not proceed past checkpoints without user confirmation.
