---
name: py-refactor
description: Refactor Python source code to comply with project style, typing, and linting standards. Trigger when asked to refactor, reformat, clean up, or standardise a Python file.
---

Refactor the provided Python module according to the rules below. Return only the
refactored code — no explanations, no commentary. Use `True` / `False` instead
of `OK` / `NOK`.

**Guiding principle — preserve behaviour.** The refactored module must be a
drop-in replacement for the original. Do not alter return values, side effects,
public API signatures, or observable behaviour. Every existing feature, example,
and reference must survive the refactor unchanged.

## Required inputs

Before doing anything else, ask the user for the following if not already provided
in `$ARGUMENTS`:

1. **Source file** — the path to the Python module to refactor.

Do not infer the path. Wait for explicit confirmation before reading the file.

## Coding standards

Before writing any code, read the shared standards document:

    Read ~/.claude/skills/py-standards.md

Apply every rule in that document to the refactored code.

## Do Not

- Do not add features or change behaviour — refactor only.
- Do not remove functionality, imports, or logic.
- Do not use `@pytest.mark.skip`, placeholders, or `...` stubs in output.
- Do not return `OK` / `NOK` — use `True` / `False` instead.
- Do not comment out code — delete it.
- Do not use `typing.Dict`, `typing.List`, `typing.Tuple` — use `dict`, `list`, `tuple`.

## Output format

- Return **only** the refactored Python source — nothing else.
- Preserve exact file structure and all original imports (add missing ones as needed).
- Preserve all functionality unchanged.
- Follow the reference implementation in `py-standards.md` as a model for style.
