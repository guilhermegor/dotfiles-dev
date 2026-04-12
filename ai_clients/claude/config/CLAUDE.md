# Global Programming Preferences

> **Priority rule:** These are personal defaults. Whenever a project-level CLAUDE.md (or any
> instruction inside the active repository) conflicts with anything here, the project context
> takes precedence. Treat this file as a fallback, not a mandate.

## Core Philosophy

- **Composition over inheritance:** Inject collaborators; avoid deep class hierarchies.
- **Explicit over implicit:** no hidden side effects, no magic conventions.
- **Fail fast:** raise meaningful, descriptive errors early.
- **Reproducibility:** prefer automated, deterministic solutions over manual steps.
- Keep functions/methods small and single-purpose (SRP).
- Immutability by default; mutate only at well-defined boundaries.

## Code Style (All Languages)

- Meaningful names: variables, functions, and files must convey intent.
- No abbreviations unless they are universally known (`url`, `id`, `db`).
- Consistent indentation per language convention; never mix tabs and spaces.
- Max line length: 88–100 chars depending on language.
- Delete dead code — don't comment it out.
- No magic numbers; use named constants or enums.
- **Early returns / guard clauses:** validate preconditions and return (or raise) at the top
  of a function instead of nesting logic inside `if/elif/else` chains. Happy path last,
  edge cases first.

```
# Avoid
def process(data):
    if data is not None:
        if data.is_valid():
            if data.value > 0:
                return transform(data)

# Prefer
def process(data):
    if data is None:
        raise ValueError("data must not be None")
    if not data.is_valid():
        raise ValueError("data failed validation")
    if data.value <= 0:
        raise ValueError("value must be positive")
    return transform(data)
```

## Module Structure

### One Class Per File

Each source file must contain exactly **one public class**.

- Public classes: one per file, named after the file (`user_service.<extension_language>` → `UserService`).
- Private/shared base classes: allowed in their own file with a leading underscore prefix
  (`_base_ingestion.<extension_language>`). Must not appear in the same file as a public class.
- Utility functions with no shared state or lifecycle: write them as module-level functions,
  not wrapped in a utility class.

**Why:** Single-class files make `git blame` accurate, keep test files focused, and eliminate
the implicit coupling that arises when two classes share a module boundary.

## Design Patterns

### Prefer always

- Strategy pattern over long if/else or switch chains.
- Dependency injection over hard-coded instantiation.
- Interfaces / Protocols / Contracts over concrete coupling.
- Pipeline / chain-of-responsibility for data transformation.
- **Plain functions over utility classes:** if a group of helpers has no shared state and no
  lifecycle, write them as module-level functions, not as a class with `@staticmethod` or a
  single-instance object. A class is only warranted when state, dependency injection, or
  interface conformance is genuinely needed.

```
# Avoid — class adds nothing here
class StringUtils:
    @staticmethod
    def slugify(text: str) -> str: ...

# Prefer — just a function in utils/text.<extension_language>
def slugify(text: str) -> str: ...
```

### Avoid

- God objects / classes with more than one responsibility.
- Inheritance chains deeper than 2 levels.
- Global mutable state.
- Callback hell; prefer async/await or promise chains.
- Deeply nested `if/elif/else` — flatten with guard clauses and early returns.

## Architecture

- Separate I/O from business logic: pure functions in the core, side effects at the edges.
- Layer your data: raw → validated → transformed → stored (bronze/silver/gold).
- Configuration via environment variables or config files — never hard-coded credentials.
- Schema-validate all external inputs before processing.

## Testing

- Unit test pure functions; integration test I/O boundaries.
- Mock at the boundary (network, filesystem, DB), not inside business logic.
- Naming: `test_<unit>_<scenario>_<expected_outcome>`.
- Each test asserts one behavior.
- Tests must be deterministic: no random seeds without explicit fixtures.

## Version Control

- Conventional Commits: `feat:`, `fix:`, `chore:`, `test:`, `docs:`, `refactor:`.
- Atomic commits: one logical change per commit.
- Never commit secrets, credentials, or local config files.
- `.gitignore` before first commit.

## Documentation

- Docstrings/comments explain **why**, not **what** (the code shows what).
- Public APIs must have documented parameters, return types, and exceptions.
- Keep README up to date with: setup, run, test, and deploy instructions.

## What Claude Must Always Do

1. Show complete, runnable code — no `...` placeholders unless a snippet is explicitly requested.
2. Include type annotations / signatures on all public functions.
3. Use composition patterns; never propose deep inheritance as a solution.
4. Prefer `pyproject.toml` / lock files over ad-hoc dependency lists.
5. Validate external data at ingestion, before any transformation.
6. Use guard clauses / early returns to handle edge cases first; keep the happy path unindented.

## What Claude Must Never Do

- Use bare `catch` / `except` without re-raising or logging.
- Omit error handling for I/O operations.
- Use `print` / `console.log` for operational logging — use a proper logger.
- Suggest storing secrets in source code or environment variables committed to git.
- Write synchronous code where the language/framework supports async natively.
