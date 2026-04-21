---
name: s:act-fix-py
description: Use when act/CI output contains Python failures — pytest errors, import errors, ruff/flake8 lint, mypy type errors, or pip install failures from a GitHub Actions run
effort: high
argument-hint: [act-output] [--plan|--fix]
allowed-tools: Read Glob Grep Edit
---

Classify Python CI failures from `act` output and delegate to the appropriate `s:py-*` sub-skill. The caller (`/c:act`) passes the raw act output and mode flag as context.

## 1. Load learned patterns

Read `~/.claude/tasks/act-fix-patterns.md` if it exists. Merge any table rows from that file into the built-in classification table below before scanning the output.

## 2. Classify the error

### Built-in patterns

| act output contains | Sub-skill |
|---|---|
| `FAILED` / `AssertionError` / `pytest` | `s:py-debug` |
| `ruff` / `flake8` / `pylint` violation | `s:py-review` |
| `mypy: error` / `Incompatible types` | `s:py-standards` |
| `ModuleNotFoundError` / `ImportError` | `s:py-debug` |
| `pip install` / `No matching distribution` | `s:py-audit` |
| `coverage:` below threshold | `s:py-unit-test` |

Scan the act output for the first matching pattern. Extract:
- **Failing file path(s)** — from traceback frames or lint output
- **Error message** — the specific exception or violation text
- **Line numbers** — from traceback or lint output

## 3. Delegate to sub-skill

Invoke the matched sub-skill via Skill tool, passing:
- Failing file path(s)
- Error message and line numbers
- Mode flag (`--plan` or `--fix`) so the sub-skill honours the caller's mode

If multiple error categories are present, process one at a time in table order above.

## 4. Handle unrecognised patterns

If no pattern matches:

1. Apply a best-effort fix based on context clues in the act output and the failing file.

2. Append the new pattern to `~/.claude/tasks/act-fix-patterns.md`:
   - If the file does not exist, create it with this header first:
     ```
     # act-fix-py learned patterns
     <!-- Appended automatically when /c:act encounters an unrecognised Python CI error. -->
     | act output pattern | sub-skill | notes |
     |---|---|---|
     ```
   - Append one row: `| <pattern fragment> | <sub-skill or "inline"> | <brief notes> |`

3. Append a lesson to `~/.claude/tasks/lessons.md` using the project-scoped template:
   ```
   ## YYYY-MM-DD — act: unrecognised Python CI error

   - **Project:** <current repo absolute path>
   - **Mistake:** Encountered a Python CI failure with no built-in pattern match
   - **Correction:** <fix applied>
   - **Rule:** When act output contains "<pattern fragment>", apply <fix description>
   - **Why:** <one sentence on why this fix resolves the error>
   ```

## 5. Report back to /c:act

- List of files changed with file:line references
- Summary of fixes applied per category
- Any new patterns appended to `act-fix-patterns.md`
