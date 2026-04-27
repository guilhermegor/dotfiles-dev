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
test coverage checks, then produce a go/no-go report. Offer to open the PR
when the code passes all checks.

## Required inputs

Before doing anything else, ask the user for the following if not already
provided in `$ARGUMENTS`:

1. **Source** — path to a `.py` file or package directory to validate.

Do not infer the path. Wait for explicit confirmation.

---

## Pipeline

### Step 0: PR status check

Run in parallel:

```bash
git branch --show-current
gh pr list --head "$(git branch --show-current)" \
  --json number,title,url,state --limit 1
```

**If a PR already exists for this branch**, report it before proceeding:

```
Existing PR found: #<number> — <title>
State: <state>
URL:   <url>
```

Then ask:

> "A PR already exists. Run validation against it anyway? (yes/no)"

- **yes** → continue with the pipeline below; use the existing PR URL in the
  final report instead of offering to create a new one.
- **no** → stop.

**If no PR exists**, continue silently — the pipeline will offer to open one
after the READY verdict.

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

Generate the PR report description:

```
## Description  
**What**: Briefly summarize the changes (e.g., "Added user authentication module").  
**Why**: Explain the motivation (e.g., "To comply with new security policies").  
**How**: Link to implementation details (e.g., "Used OAuth2.0 via Auth0").  

---

## Changes Made
**Added**:
- New feature: [Description].  
- Dependency: [Package@version].  

**Updated**:
- Refactored [Component] for [Reason].  

**Fixed**:
- Issue #[Number]: [Brief description].  

---

## Testing
### Manual Testing
- **Test Case 1**:  
    - Steps: `1. Navigate to /login → 2. Submit credentials`  
    - Expected: Redirect to dashboard.  
    - Evidence: ![Screenshot](link).  
- **Test Case 2**:  
    - Steps: `Simulate network failure during API call`.  
    - Expected: Graceful error handling.  

### Automated Testing
- **Unit Tests**:  
    - File: `test_auth.py`  
    - Coverage: 95% (via `pytest --cov`).  
- **Integration Tests**:  
    - File: `tests.yaml`  
    - Status: `OK/NOK`.  

**Not Applicable**:  
- Explain (e.g., "Documentation-only change").  

---

## Documentation
- **Code**:
    - Updated docstrings in [files].  
- **Guides**:
    - Added [section] to README.  
- **Changelog**:
    - Entry under [Version].  

---

## Additional Notes  
**Dependencies**:  
- Blocks/Depends on #[PR Number].  

**Follow-up**:  
- Tech debt: [Brief note].  

**Reviewer Focus**:  
- Pay attention to [specific files/logic].  
```

### Blocking criteria

The verdict is **BLOCKED** if any of:
- s:py-review found **errors** (warnings and suggestions do not block)
- s:py-audit found **critical** or **high** severity findings
- Test coverage is below **80%** line coverage
- No tests exist for the module

Otherwise the verdict is **READY**.

### Step 5: Open PR (READY verdict only, no existing PR)

When the verdict is **READY** and no PR was found in Step 0, invoke:

```
/s:gh-create-pr
```

The skill handles the confirmation gate, template composition, user approval
loop, and `gh pr create` call. Do not duplicate any of that logic here.

If the verdict is **BLOCKED**, do not offer to open a PR — report blockers only.

## Memory

After each PR check, save a brief note about:
- Which module was checked
- The verdict (READY/BLOCKED)
- Recurring blockers across runs

## Do Not

- Do not modify any files — this is a read-only validation.
- Do not create or fix tests — only report coverage gaps.
- Do not auto-create the PR — wait for s:gh-create-pr confirmation gate.
- Do not lower the blocking thresholds without user approval.
- Do not offer to open a PR when the verdict is BLOCKED.
