---
name: s:py-create
description: Write a new Python module from scratch. Trigger when asked to create, write, implement, or build a new Python file, module, class, or function.
effort: high
argument-hint: [description] [target-file]
---

Write a complete, production-ready Python module according to the rules below.
Return only the code — no explanations, no commentary.

**Guiding principles:**

- **Composition over inheritance** — use `Protocol` and dependency injection, not
  deep class hierarchies.
- **Single Responsibility** — each module, class, and function does one thing.
- **Explicit over implicit** — no hidden state, no magic; make dependencies and
  data flow visible.
- **Fail fast** — validate inputs at the boundary; raise clear exceptions immediately.

## Required inputs

Before doing anything else, ask the user for both of the following if they have not
already been provided in `$ARGUMENTS`:

1. **What to build** — a description of the module, function, or class to create.
2. **Target file** — the exact path where the new file should be written.

Do not infer either. Wait for explicit confirmation before writing any code.

## Coding standards

Before writing any code, read the shared standards document:

    Read ~/.claude/skills/py-standards.md

Apply every rule in that document to the code you produce.

## Architecture guidance

- **Composition over inheritance.** Use `Protocol` to define contracts; inject
  collaborators through `__init__`. Never use multiple inheritance.
- **Dependency injection.** Accept dependencies as constructor parameters typed
  against `Protocol` interfaces, not concrete classes.
- **Separate I/O from business logic.** Pure functions for transformations;
  thin adapter classes for HTTP, DB, filesystem. Business logic never imports
  `requests`, `httpx`, or ORM sessions directly.
- **Plain functions over utility classes** when there is no shared state.
  A module of functions is simpler than a class of `@staticmethod` methods.
- **Guard clauses and early returns.** Validate inputs at the top and return/raise
  immediately. Avoid deep nesting.
- **Strategy pattern over long if/else chains.** When behaviour varies by a
  mode/type parameter, use a dict dispatch or `functools.singledispatch` instead
  of cascading conditionals.
- **Constants, not magic numbers.** Every literal with domain meaning gets a
  named constant at module level with a comment explaining the value.

## Do Not

- Do not leave placeholder comments like `# TODO`, `# implement later`, or `pass` stubs.
- Do not use magic numbers or string literals without a named constant.
- Do not use bare `except:` or `except Exception:` without re-raising.
- Do not use `typing.Dict`, `typing.List`, `typing.Tuple` — use `dict`, `list`, `tuple`.
- Do not use multiple inheritance.
- Do not mix I/O and business logic in the same function.

## Output format

- Return a **complete, runnable Python module** — not a fragment or skeleton.
- The module must start with a two-paragraph module docstring.
- All public functions and classes must have full Numpy-style docstrings.
- All functions and methods must have complete type annotations.
- Include all necessary imports; do not assume the user will add them.
- Follow the reference implementation in `py-standards.md` as a model for style.
