---
name: py-review
description: Review Python code for standards compliance, design issues, and bugs. Trigger when asked to review, check, or critique a Python file.
effort: high
argument-hint: [source-file]
allowed-tools: Read Glob Grep
---

Review the provided Python source code against the project's coding standards.
Report findings as a structured list — do not modify any files.

## Required inputs

Before doing anything else, ask the user for the following if not already provided
in `$ARGUMENTS`:

1. **Source file** — the path to the Python module to review.

Do not infer the path. Wait for explicit confirmation before reading the file.

## Coding standards

Before reviewing, read the shared standards document:

    Read ~/.claude/skills/py-standards.md

Use every rule in that document as a checklist item for the review.

## Review checklist

### Style and formatting
- **Ruff compliance** — check against the project's `ruff.toml` (or `pyproject.toml`
  `[tool.ruff]` section). If absent, check against the fallback rule sets in
  py-standards.md.
- **Line length** — 99 characters maximum.
- **Indentation** — tabs (4 spaces equivalent), no mixing.
- **Strings** — double quotes in code; single quotes inside docstring body text.
- **Imports** — isort order (stdlib, third-party, local); no unused imports.

### Type annotations
- Every function/method signature has parameter and return type annotations.
- No implicit `Any` — every container element is typed.
- `Optional[X]` / `Union[X, Y]` for Python < 3.10; `X | None` allowed on 3.10+.
- `NDArray[np.float64]` instead of `np.ndarray`.
- Return dicts typed as `class Return<MethodName>(TypedDict)`.
- No `typing.Dict`, `typing.List`, `typing.Tuple` — use primitives.

### Docstrings
- Numpy style, 79-character line limit inside body.
- First line: imperative mood, ends with a period, on the same line as `"""`.
- Sections: `Parameters`, `Returns`, `Raises`, `Notes`, `References` — only where
  applicable.
- Single quotes inside docstring body; double quotes nowhere.
- Module docstring: two paragraphs (summary + description).

### Validation and error handling
- Guard clauses at the top of functions (early returns/raises).
- `_validate_<name>` methods at the top of classes for reusable checks.
- `as err` and `from err` on all re-raised exceptions (Ruff B904).
- Descriptive error messages including the variable name and violated constraint.
- Sanity checks for 0-1 range, positive/negative numbers, arrays (empty, shape,
  finite, numeric).

### Design
- Composition over inheritance — no deep class hierarchies.
- Single Responsibility — each class/function does one thing.
- No god objects or classes with mixed concerns.
- Plain functions over utility classes when no shared state.
- Strategy pattern or dict dispatch over long if/else chains.
- No magic numbers — named constants with domain meaning.

### Dead code
- No unused imports, variables, or functions.
- No commented-out code.
- No unreachable branches.

## Severity levels

Classify each finding as one of:

- **Error** — must fix; violates a hard rule, introduces a bug, or breaks type safety.
- **Warning** — should fix; violates a convention, harms readability, or risks maintenance debt.
- **Suggestion** — nice to have; a style improvement or minor optimisation.

## Output format

```
## Review: <filename>

### Errors (<count>)
- `file.py:42` — <description of the issue>
- `file.py:87` — <description of the issue>

### Warnings (<count>)
- `file.py:15` — <description of the issue>

### Suggestions (<count>)
- `file.py:3` — <description of the issue>

### Summary
<1-2 sentence overall assessment>
```

## Do Not

- Do not modify any files — this is a read-only review.
- Do not run any commands.
- Do not report issues in test files unless explicitly asked.
- Do not flag style preferences that contradict py-standards.md.
- Do not report more than 20 findings — prioritise by severity.
