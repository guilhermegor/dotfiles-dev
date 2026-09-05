---
paths:
  - "**/*.py"
  - "**/*.pyi"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.mjs"
  - "**/*.cjs"
  - "**/*.sh"
  - "**/*.bash"
  - "**/*.go"
  - "**/*.rs"
  - "**/*.java"
  - "**/*.kt"
  - "**/*.rb"
  - "**/*.php"
  - "**/*.c"
  - "**/*.h"
  - "**/*.cpp"
  - "**/*.hpp"
  - "**/*.cc"
  - "**/*.cs"
  - "**/*.swift"
  - "**/*.scala"
  - "**/*.sql"
---

# Language-Common Coding Rules

> **Priority rule:** These are personal, language-agnostic coding defaults. They auto-load
> when editing any source file (via the `paths:` frontmatter above), so they stay out of the
> always-on context. Whenever a project-level CLAUDE.md (or any instruction inside the active
> repository) conflicts with anything here, the project context takes precedence — treat this
> file as a fallback, not a mandate. Language-specific rules (`python.md`, `bash.md`, …) layer
> on top of this file.

## Core Philosophy

- **Simplicity first:** make every change as small and targeted as possible —
  touch the minimum code needed to achieve the goal. Complexity is a debt paid
  by every future reader.
- **Separation of concerns:** each module, class, or function owns exactly one
  responsibility. I/O, business logic, and presentation must not be tangled.
- **Don't repeat yourself (DRY):** every piece of knowledge has a single,
  authoritative representation. Duplication is a bug waiting to diverge.
- **Composition over inheritance:** Inject collaborators; avoid deep class hierarchies.
- **Explicit over implicit:** no hidden side effects, no magic conventions.
- **Fail fast:** raise meaningful, descriptive errors early.
- **Root cause over symptom — even when it is more work:** always default to the
  fix that resolves the problem at its source (the tool, the config, the data, the
  design), and present that as the primary recommendation, regardless of how much
  more total labour it is than a workaround, suppression, or exemption. Never nudge
  toward the lighter option, and never editorialise thoroughness as a "tax",
  "busywork", or "churn". Effort is not the decision criterion — correctness and
  durability are. Assume "do it properly and completely" unless told otherwise.
  (This does not license scope creep: keep the *change* minimal per *Simplicity
  first*, but make it a real fix, not a patch over the symptom.)
  ⚠️ **A failing test is a finding, not an obstacle.** When a test fails, the
  default is to fix the code, never the expectation. Changing an assertion to
  match current behaviour is legitimate *only* when the expectation itself is
  provably wrong — and then it is a change that must be stated and justified,
  never made silently in the same commit that touches the code under test. The
  same applies to deleting a test, marking it `skip`/`xfail`, broadening a
  `pytest.raises`, or weakening an operator (`==` → `in`, `assertEqual` →
  `assertTrue`). Editing an assertion is indistinguishable from correcting one
  by diff shape alone — that is exactly why it needs a stated reason, not a
  silent edit.
- **Reproducibility:** prefer automated, deterministic solutions over manual steps.
- Keep functions/methods small and single-purpose (SRP).
- Immutability by default; mutate only at well-defined boundaries.

## Code Style (All Languages)

- Meaningful names: variables, functions, and files must convey intent.
- No abbreviations unless they are universally known (`url`, `id`, `db`).
- Consistent indentation per language convention; never mix tabs and spaces.
- Max line length: 88–100 chars depending on language.
- Delete dead code — don't comment it out.
- Never import unused libraries or modules — remove any import that is not
  referenced in the file.
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

- Strategy pattern over if/else or switch chains — **including short 2–3 way ones**. When a
  branch's only job is to *select a value* by a key, replace it with a **dict dispatch**, and
  derive the set of valid keys from that same dict so the two cannot drift.

  ```python
  # Avoid — an else block, plus a second copy of the valid names living elsewhere
  if strategy == "linear":
      wait = base * attempt
  elif strategy == "constant":
      wait = base
  else:                       # exponential
      wait = base * factor ** (attempt - 1)

  # Prefer — the dict IS the branch, and the key-set is derived from it
  _STRATEGY_WAITS = {
      "exponential": lambda base, factor, attempt: base * factor ** (attempt - 1),
      "linear":      lambda base, factor, attempt: base * attempt,
      "constant":    lambda base, factor, attempt: base,
  }
  _STRATEGIES = frozenset(_STRATEGY_WAITS)   # single source of the valid names
  wait = _STRATEGY_WAITS[strategy](base, factor, attempt)
  ```

  Adding a behaviour is then adding a key, not a branch. Where a branch only picks between
  "compute" and "return early", use a guard clause instead of an `else:` block.
- Dependency injection over hard-coded instantiation.
- Interfaces / Protocols / Contracts over concrete coupling.
- Pipeline / chain-of-responsibility for data transformation.
- **Class vs function — the three triggers:** reach for a function by default.
  A class is only warranted when **at least one** of these holds:
  1. **State + lifecycle** — instance fields, `init/dispose`, scoped lifetime.
  2. **Interface conformance** — concrete implementation of a domain port.
  3. **Dependency injection** — collaborators wired at construction.

  A class that satisfies none of the three is a module in disguise — collapse
  it to a module of functions or a frozen object of functions.

  | Pattern | Shape |
  |---|---|
  | Pure transformation (`formatSecondsToMinutes`) | function |
  | Pure reducer (`(state, action) => state`) | function |
  | Stateless facade over a vendor API (`showMessage = { success, error }`) | frozen object of functions |
  | Top-level use case with no dependencies | function |
  | Worker / connection / session manager (owns a resource + lifecycle) | class |
  | Adapter implementing a domain port | class |
  | Service / use case needing injected collaborators | class |

  **Anti-patterns (always collapse):**
  - **Class as namespace** — every method `static`, no instance state → module of functions.
  - **Anemic class** — only getters/setters, no behavior → `type` / `interface` / dataclass.
  - **Singleton wrapping a stateless function** (`Slugifier.getInstance().slugify(x)`) → `slugify(x)`.

  ```python
  # Avoid — no state, no port, no DI → class adds nothing
  class StringUtils:
      @staticmethod
      def slugify(text: str) -> str: ...

  # Prefer — just a function in utils/text.py
  def slugify(text: str) -> str: ...
  ```

  ```typescript
  // Correct use of a class — implements a port and owns a Worker instance
  class TimerWorkerManager implements ITimerWorker {
    private worker: Worker;
    constructor() { this.worker = new Worker(...); }
    postMessage(input: TimerWorkerInput): void { this.worker.postMessage(input); }
    terminate(): void { this.worker.terminate(); }
  }
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

## Numeric Precision

- **Never use `float` for values where precision matters** (money, measurements,
  aggregations, comparisons). IEEE 754 binary floats cannot represent most decimal
  fractions exactly — errors accumulate silently.
- **Use the language-native decimal library instead:**
  - Python → `from decimal import Decimal`
  - JavaScript/TypeScript → [`decimal.js`](https://github.com/MikeMcl/decimal.js)
    or [`big.js`](https://github.com/MikeMcl/big.js)
  - Java/Kotlin → `java.math.BigDecimal`
  - Go → `github.com/shopspring/decimal`
  - Rust → `rust_decimal` crate
- Initialise `Decimal` from **strings**, not floats: `Decimal("0.1")` not
  `Decimal(0.1)` — constructing from a float inherits the float's imprecision.
- **Prefer truncation (`ROUND_DOWN`) over rounding up or down** when discarding
  excess digits. Truncation is deterministic and never inflates a value —
  rounding introduces a directional bias that compounds across bulk operations
  (e.g. summing thousands of prices). Only use `ROUND_HALF_UP` / `ROUND_HALF_EVEN`
  when the domain explicitly demands it (e.g. tax, regulatory reporting).
- **Always ask the developer for the required precision of each `Decimal` field**
  before writing the code. Propose a sensible default based on the domain first,
  then wait for explicit confirmation:
  - Money / prices → suggest 2 decimal places (`0.01`)
  - Exchange rates / unit prices → suggest 4 decimal places (`0.0001`)
  - Percentages / ratios → suggest 4 decimal places (`0.0001`)
  - Quantities / weights → suggest 3 decimal places (`0.001`)
  - Scientific measurements → suggest 10 decimal places (`0.0000000001`)

  Example prompt to the developer:
  > "I'll use `Decimal` with **2 decimal places, truncation** for `price`.
  > Does that match your requirements, or do you need a different precision
  > or rounding mode?"

  Never assume; never hardcode a precision without this confirmation step.

## What Claude Must Never Do

- Use bare `catch` / `except` without re-raising or logging.
- Omit error handling for I/O operations.
- Use `print` / `console.log` for operational logging — use a proper logger.
- Suggest storing secrets in source code or environment variables committed to git.
- Write synchronous code where the language/framework supports async natively.
- Use `float` for monetary values, precise measurements, or any calculation
  where cumulative rounding errors are unacceptable — use `Decimal` instead.
