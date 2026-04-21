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
