---
name: a:py-pr
description: Validate Python code is PR-ready — review, audit, test coverage, and summary report. Trigger before creating a pull request.
model: sonnet
color: blue
memory: true
disable-model-invocation: true
effort: high
argument-hint: [source-file-or-directory]
---

Validate that Python code is ready for a pull request. Run review, audit, and
test coverage checks, then produce a go/no-go report.

## Required inputs

Before doing anything else, ask the user for the following if not already provided
in `$ARGUMENTS`:

1. **Source** — path to a `.py` file or package directory to validate.

Do not infer the path. Wait for explicit confirmation.

---

## Pipeline

### Step 1: Code review

Invoke `/s:py-review` on the source.

Collect: error count, warning count, suggestion count, and all findings.

### Step 2: Security audit

Invoke `/s:py-audit` on the source.

Collect: findings by severity (critical, high, medium, low, informational).

### Step 3: Test coverage

Run the test suite with coverage measurement:

```bash
pytest --cov=<module> --cov-branch --cov-report=term-missing
```

Derive the module name from the source path. Collect:
- Line coverage percentage
- Branch coverage percentage
- Uncovered lines

If no tests exist for the module, report "No tests found" as a blocker.

### Step 4: Produce report

Generate the final PR readiness report:

```
## PR Readiness Report: <source>

### Code Review
- Errors: <count>
- Warnings: <count>
- Suggestions: <count>

### Security Audit
- Critical: <count>
- High: <count>
- Medium: <count>
- Low: <count>

### Test Coverage
- Line: <percentage>%
- Branch: <percentage>%
- Uncovered: <list of file:line ranges>

---

### Verdict: <READY or BLOCKED>

<if BLOCKED, list each blocker:>
- [ ] <review error description>
- [ ] <critical audit finding>
- [ ] <coverage below threshold>

<if READY:>
All checks passed. Code is ready for pull request.
```

### Blocking criteria

The verdict is **BLOCKED** if any of:
- s:py-review found **errors** (warnings and suggestions do not block)
- s:py-audit found **critical** or **high** severity findings
- Test coverage is below **80%** line coverage
- No tests exist for the module

Otherwise the verdict is **READY**.

## Memory

After each PR check, save a brief note about:
- Which module was checked
- The verdict (READY/BLOCKED)
- Recurring blockers across runs

## Do Not

- Do not modify any files — this is a read-only validation.
- Do not create or fix tests — only report coverage gaps.
- Do not auto-create the PR — only produce the readiness report.
- Do not lower the blocking thresholds without user approval.
