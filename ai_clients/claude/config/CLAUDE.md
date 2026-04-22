@RTK.md

## CLI Commands — Always Use RTK Proxy

For any command RTK supports (`git`, `gh`, `find`, `grep`, `ls`, `curl`,
`docker`, `pytest`, `cargo`, etc.), write the `rtk` prefix explicitly in
agents, skills, and commands — never the bare binary. See RTK.md for the
full list.

Why: the `PreToolUse` hook rewrites at execution time, but the approval
prompt shows the pre-hook command, so "don't ask again" creates a wrong
allowlist entry (`Bash(git *)` instead of `Bash(rtk git *)`).

Commands RTK does not wrap run bare as normal (`sqlite3`, `jq`, `make`,
`python3`, `node`, etc.).

Exceptions where bare binary is always correct:
- `command -v <tool>` availability checks
- Install instructions (`sudo apt install ...`)
- Prohibition examples in "Do Not" sections

# Global Programming Preferences

> **Priority rule:** These are personal defaults. Whenever a project-level CLAUDE.md (or any
> instruction inside the active repository) conflicts with anything here, the project context
> takes precedence. Treat this file as a fallback, not a mandate.

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
- **Never stage or commit automatically after creating spec/plan docs** (e.g. after a superpowers skill invocation). Pre-commit hooks are slow; let the user run the final commit when the full feature is ready.

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

## Self-Improvement Loop

### Session start

At the start of every session, read `~/.claude/tasks/lessons.md` (if it
exists) and surface any entries whose **Scope** matches the current working
directory or is `global`. Apply those rules immediately — do not wait to be
reminded.

### After a user correction

Whenever the user corrects a mistake (wrong approach, wrong assumption, style
violation, misunderstood requirement, etc.), immediately append an entry to
`~/.claude/tasks/lessons.md` using the template below. Create the file and
its parent directory if they do not exist.

**Entry template:**

```markdown
## YYYY-MM-DD — <short description of the mistake>

- **Project:** <absolute path of current working directory, or "global" if
  the user says it applies across all projects>
- **Mistake:** <one sentence — what I did wrong>
- **Correction:** <what the user said or did to fix it>
- **Rule:** <an imperative rule that prevents this mistake — "Never…" or
  "Always…">
- **Why:** <one sentence explaining the underlying reason>
```

**Scope decision:**
- Default scope is the current project (use its absolute path).
- Escalate to `global` only when the user explicitly says the lesson applies
  everywhere (e.g. "don't do that in any project").

### Iteration discipline

- After writing a lesson, re-read the last five entries for the current
  project and check whether any of them have now been violated again. If so,
  add a `**Recurrence:** <date> — still happening` line to the original entry
  and tighten the rule wording.
- If the same mistake recurs three or more times, promote it to a top-level
  rule in the project's `CLAUDE.md` (or the global one if scoped globally) and
  mark the lessons.md entry `**Promoted:** YYYY-MM-DD`.
- Never delete or archive lessons — accumulate them so pattern trends are
  visible over time.

## Compaction

When the context window is compacted, apply this priority order:

**Always keep**
- The current task description and its acceptance criteria
- File paths that have been read, created, or modified in this session
- Test results (pass/fail counts, assertion errors, failing test names)
- The current plan or step list and which steps are done vs. pending
- Any explicit user instructions or corrections given during the session
- Final state of any code written or edited (not intermediate drafts)

**Summarise (keep the conclusion, drop the detail)**
- Exploration trails: keep the finding, drop the path taken to reach it
- Tool call chains that produced a single result — keep only the result
- Repeated grep/glob searches — keep the final match, drop earlier misses

**Drop entirely**
- Error messages that have already been resolved
- Superseded approaches, rejected designs, or abandoned file reads
- Intermediate reasoning steps that led to a decision already recorded
- Duplicate information (e.g. the same file path mentioned three times)
- Any raw tool output that was only used to derive a now-recorded fact
