#!/bin/bash
# Installs user-level rule files into ~/.claude/rules/.
# Each file uses path-scoped frontmatter so it only loads for matching file types.
#
# To add a new language:
#   1. Write an install_<lang>_rules() function below.
#   2. Add a call to it inside install_rules().

# ── Python ────────────────────────────────────────────────────────────────────

install_python_rules() {
    local rules_dir="$1"

    cat > "$rules_dir/python.md" <<'PYTHON_EOF'
---
paths:
  - "**/*.py"
  - "**/pyproject.toml"
  - "**/conftest.py"
  - "**/ruff.toml"
---

# Python Preferences

> **Priority rule:** These are personal Python defaults. Whenever a project-level CLAUDE.md
> (or any instruction inside the active repository) conflicts with anything here, the project
> context takes precedence. Treat this file as a fallback, not a mandate.

## Toolchain

| Tool       | Role                                                         |
|------------|--------------------------------------------------------------|
| Ruff       | Linter + formatter (replaces Black, isort, flake8)           |
| mypy       | Static type checking (strict mode)                           |
| pytest     | Test runner                                                  |
| pre-commit | Hooks: ruff + mypy before every commit                       |

All project config and dependencies live in `pyproject.toml` or `ruff.toml`. No `setup.py`.
`requirements.txt` is allowed **only** to pin the package manager itself, e.g.:

```
poetry==2.1.2 ; python_full_version >= "3.9" and python_version < "3.14"
```

The package manager (Poetry, uv, etc.), its version, and the Python version constraints are
project-specific — never hardcode them; always follow what the project already uses.

## Ruff Configuration

- **Line length:** 99 characters.
- **Indent style:** tabs (not spaces).
- **Quote style:** double quotes.
- **Target version:** match the project's `pyproject.toml`; never hardcode it here.
- **Docstring convention:** NumPy style (`[lint.pydocstyle] convention = "numpy"`).
- **Docstring code blocks:** formatted to 79 chars for terminal readability.

Active lint rule sets: `UP` (pyupgrade), `E`/`F` (pycodestyle/flake8), `ANN` (annotations),
`B` (bugbear), `SIM` (simplify), `I` (isort), `AIR` (airflow), `ERA` (eradicate),
`S` (bandit), `PD` (pandas-vet), `D` (pydocstring).

Ignored: `D206` (tab-indented docstrings conflict with indent-style = tab).

### Annotations (flake8-annotations)

All four strict flags are on — no exceptions:
- `suppress-none-returning = false` — always annotate `-> None`.
- `suppress-dummy-args = false` — annotate `_` / dummy args.
- `ignore-fully-untyped = false` — flag completely unannotated functions.
- `allow-star-arg-any = false` — type `*args` and `**kwargs` explicitly.

### isort

- `combine-as-imports = true`
- `split-on-trailing-comma = true`
- `force-sort-within-sections = true`
- `lines-after-imports = 2`
- `force-single-line = false`

### Per-file ignores

- `tests/**/*.py` — `S101` (assert allowed in tests).

## Style

- `from __future__ import annotations` only when targeting Python < 3.10; not needed in newer versions since PEP 563 syntax is native.
- Type hints: always, including return types. `-> None` is not optional.
- Docstrings: NumPy style.
- Imports: absolute only; no relative imports except in `__init__.py`.
- f-strings over `.format()` or `%` formatting, with version-aware caveats:
  - **< 3.12:** f-string expressions cannot contain backslashes or reuse the outer quote
    character — extract complex expressions into a variable before the f-string.
  - **< 3.14:** template strings (`t"..."`, PEP 750) are not available; do not use them
    even if a linter suggests it.
  - **≥ 3.14:** prefer `t"..."` over f-strings for any string passed to an untrusted
    sink (HTML, SQL, shell) — they enable safe interpolation without manual escaping.
- Commented-out code is forbidden (`ERA` rule is active — Ruff will flag it).

## Composition Patterns

```python
# Prefer: Protocol + injection
from typing import Protocol

class Storage(Protocol):
    def save(self, record: dict) -> None: ...

class Scraper:
    def __init__(self, storage: Storage) -> None:
        self._storage = storage
```

- Use `dataclasses.dataclass` for simple value objects.
- Use Pydantic v2 `BaseModel` for any data that crosses a boundary (API, scraper, DB).
- Use `functools.singledispatch` or strategy pattern instead of `isinstance` chains.
- Never use multiple inheritance; use `Protocol` for structural typing.
- **Prefer module-level functions over utility classes:** if helpers share no state and need
  no lifecycle, write them as plain functions in a module — not as a class with `@staticmethod`
  methods. Reserve classes for when state or Protocol conformance is needed.

```python
# Avoid
class DateUtils:
    @staticmethod
    def to_br_format(dt: date) -> str:
        return dt.strftime("%d/%m/%Y")

# Prefer — just a function in utils/dates.py
def to_br_format(dt: date) -> str:
    return dt.strftime("%d/%m/%Y")
```

## Data Validation

- All external data (HTTP responses, scraped HTML, DB rows, file inputs) must pass through
  a Pydantic v2 model before any transformation.
- Use `model_validator` and `field_validator`; avoid ad-hoc sanitization scattered across
  business logic.
- Never use raw `dict` as a data contract — always define a model.

## Async

- Use `asyncio` throughout; `async/await` over threads for I/O-bound work.
- Browser automation: Playwright (`async_playwright`).
- HTTP: `httpx` async client.
- Never mix sync and async in the same layer without an explicit bridge.

## Testing

- Framework: `pytest` + `pytest-asyncio` for coroutines.
- Mock all external I/O at the boundary — this includes HTTP requests (`httpx`, `requests`),
  database calls (SQLAlchemy sessions, raw cursors), message brokers, file system writes,
  and any third-party API client. Use `unittest.mock.AsyncMock` for coroutines and
  `MagicMock` for synchronous boundaries. Never let a unit test touch a real network,
  real database, or real filesystem.
- One `conftest.py` per package; fixtures default to function scope.
- Naming: `test_<unit>_<scenario>_<expected_outcome>`.
- Target ≥ 90% coverage on business logic; exclude generated/migration files.

## Data Engineering (Python)

- Orchestration: Apache Airflow TaskFlow API.
- ETL sequence: extract → validate (Pydantic) → transform (pure functions) → load.
- DAG ids: `snake_case` with data-source prefix (e.g., `anbima_funds_daily`).
- Always persist raw responses before transforming.

## Numerical / Quant

- Use NumPy vectorized operations; avoid Python loops over arrays.
- Prefer `pd.DataFrame.pipe` chains over in-place mutation.
- Seed all RNG explicitly: `np.random.default_rng(seed=42)`.
- scikit-learn: always wrap in a `Pipeline`; never fit outside it.
PYTHON_EOF

    print_status "success" "Installed python.md → $rules_dir/python.md"
}

# ── Dispatcher ────────────────────────────────────────────────────────────────

install_rules() {
    print_status "section" "INSTALLING CLAUDE RULES"

    local rules_dir="$CLAUDE_DIR/rules"
    mkdir -p "$rules_dir"

    install_python_rules "$rules_dir"
    # install_typescript_rules "$rules_dir"  # future
    # install_go_rules "$rules_dir"          # future
}
