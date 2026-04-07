---
name: py-debug
description: Debug Python errors by tracing tracebacks and identifying root cause. Trigger when asked to debug, diagnose, trace, or investigate a Python error.
effort: high
argument-hint: [source-file] [error-or-traceback]
allowed-tools: Read Glob Grep
---

Diagnose the root cause of a Python error by reading tracebacks, tracing call
stacks, and identifying the failing code path. Report a structured diagnosis —
do not modify any files.

## Required inputs

Before doing anything else, ask the user for the following if not already provided
in `$ARGUMENTS`:

1. **Source file** — the path to the Python module where the error occurs.
2. **Error** — the traceback, error message, or description of unexpected behaviour.

Do not infer either. Wait for explicit confirmation before reading files.

## Debugging process

### 1. Parse the traceback

- Extract: file path, line number, exception type, exception message.
- Identify the **innermost frame** (where the exception was raised) and the
  **outermost frame** (where execution started).
- Note any chained exceptions (`__cause__`, `during handling of another exception`).

### 2. Read the failing code

- Read the file and line reported in the innermost frame.
- Read surrounding context (10 lines above and below).
- Check the function signature, parameter types, and return type.

### 3. Trace backward through the call stack

- For each frame in the traceback (innermost to outermost):
  - Read the calling code.
  - Identify what arguments were passed.
  - Check if any argument could be `None`, wrong type, or out of range.
- Follow the data flow: where did the bad value originate?

### 4. Check recent changes

- Use `Grep` to find recent modifications near the failing lines.
- Check if the error correlates with a recent code change.

### 5. Identify root cause vs symptom

- The exception location is often the **symptom**, not the **cause**.
- Trace back to where the invalid state was first introduced.
- The root cause is the earliest point where the code diverges from expected
  behaviour.

### 6. Check Python-specific pitfalls

Scan the affected code for these common patterns:

- **Mutable default arguments** — `def f(items=[])` accumulates across calls.
- **Late binding closures** — lambda/comprehension captures loop variable by
  reference, not by value.
- **Import-time side effects** — module-level code that runs on import and
  fails in certain environments.
- **Async/await mistakes** — missing `await` on a coroutine, blocking sync call
  inside an async function, using `time.sleep` instead of `asyncio.sleep`.
- **None propagation** — function returns `None` implicitly when a branch
  doesn't return, caller doesn't check.
- **Type coercion** — `int` / `float` confusion, string where number expected,
  `numpy` scalar vs Python scalar.
- **Iterator exhaustion** — reusing a consumed generator or iterator.
- **Decorator ordering** — `@staticmethod` / `@classmethod` / `@property`
  interacting with other decorators in wrong order.
- **Metaclass / descriptor conflicts** — `__init_subclass__`, `__set_name__`,
  or descriptor protocol interacting unexpectedly.
- **Context manager misuse** — resource leaked because `__exit__` not called,
  or `with` block scope misunderstood.
- **Circular imports** — `ImportError` or `AttributeError` due to partially
  initialised modules.

## Output format

```
## Diagnosis: <exception type>

### Error
<exception type>: <exception message>
at <file>:<line>

### Root cause
<clear explanation of what went wrong and WHY, not just WHERE>

### Evidence
- `file.py:42` — <what this line does and why it fails>
- `file.py:28` — <where the bad value originated>
- `file.py:15` — <the earliest point of divergence>

### Call chain
<outermost caller> → ... → <innermost frame where exception raised>

### Python pitfall
<if applicable, which common pitfall this matches, otherwise "none">

### Suggested fix
<specific, actionable suggestion for how to fix the root cause>
<do NOT implement the fix — just describe it>

### Confidence
<high / medium / low — with explanation of what's uncertain>
```

## Do Not

- Do not modify any files — this is a read-only diagnosis.
- Do not run any commands.
- Do not fix the bug — only diagnose and suggest.
- Do not guess the root cause without evidence from the code.
- Do not report "the error is on line X" without tracing WHY it fails there.
