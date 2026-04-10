---
name: s:py-migrate
description: Migrate Python code between versions or upgrade major dependencies. Trigger when asked to migrate, upgrade, update Python version, or upgrade a library.
effort: high
argument-hint: [source-file-or-directory] [from-version] [to-version]
---

Migrate the provided Python source code between Python versions or upgrade major
library dependencies. Apply changes to the source files and report what was modified.

## Required inputs

Before doing anything else, ask the user for the following if not already provided
in `$ARGUMENTS`:

1. **Source** — path to a `.py` file or a package directory.
2. **Migration type** — one of:
   - **Python version** — e.g., `3.9 -> 3.12`
   - **Library upgrade** — e.g., `pandas 1.x -> 2.x`, `sqlalchemy 1.4 -> 2.0`
3. **From version** — the current version.
4. **To version** — the target version.

Do not infer the source path. Wait for explicit confirmation before reading files.

## Python version migration

### Step 1: Detect current state

- Read `.python-version` and `pyproject.toml` for the declared target version.
- Verify the declared version matches the user's stated "from" version.
- If they conflict, ask the user which is correct before proceeding.

### Step 2: Identify deprecated features

Check for features removed or deprecated between the from-version and to-version:

| Removed in | Feature |
|-----------|---------|
| 3.10 | `collections.MutableMapping` (use `collections.abc`) |
| 3.10 | `typing.Optional` still works but `X \| None` is preferred |
| 3.11 | `asyncio.coroutine` decorator |
| 3.12 | `distutils` module |
| 3.12 | `imp` module |
| 3.12 | `pkgutil.ImpImporter` |
| 3.13 | `aifc`, `audioop`, `cgi`, `cgitb`, `chunk`, `crypt`, `imghdr`, `mailcap`, `msilib`, `nis`, `nntplib`, `ossaudiodev`, `pipes`, `sndhdr`, `spwd`, `sunau`, `telnetlib`, `uu`, `xdrlib` |

### Step 3: Identify new features available

Suggest adopting features available in the target version:

| Available from | Feature |
|---------------|---------|
| 3.10 | `match` / `case` (structural pattern matching) |
| 3.10 | `X \| None` instead of `Optional[X]` |
| 3.10 | `X \| Y` instead of `Union[X, Y]` |
| 3.10 | Parenthesised context managers |
| 3.11 | `ExceptionGroup` and `except*` |
| 3.11 | `tomllib` in stdlib |
| 3.12 | `type` statement for type aliases |
| 3.12 | `override` decorator in `typing` |
| 3.12 | Improved f-string parsing (nested quotes) |
| 3.13 | `typing.ReadOnly` for TypedDict fields |

### Step 4: Apply changes

- Update type hints (`Optional` to `X | None` if target >= 3.10).
- Replace deprecated imports with their modern equivalents.
- Update `pyproject.toml` `requires-python` and `target-version` in `ruff.toml`.
- Update `.python-version` if present.

## Library migration

### Step 1: Read current state

- Find the library version in `pyproject.toml`, `requirements*.txt`, or `setup.cfg`.
- Identify all import sites for the library across the source files.

### Step 2: Research breaking changes

- Check the library's changelog or migration guide for breaking changes between
  the from-version and to-version.
- List each breaking change with the affected API.

### Step 3: Apply changes

- Update import statements for renamed or moved APIs.
- Update function calls for changed signatures.
- Update configuration for changed settings.
- Update the version constraint in the dependency file.

## Output format

After migrating, report:

```
## Migration Report: <source> (<from> -> <to>)

### Changes applied (<count>)
- `file.py:12` — Updated `Optional[str]` to `str | None`
- `file.py:45` — Replaced `collections.MutableMapping` with `collections.abc.MutableMapping`
- `pyproject.toml:8` — Updated `requires-python` to `>=3.12`

### Manual review needed (<count>)
- `file.py:78` — Uses `distutils.version.LooseVersion`; consider `packaging.version.Version`

### Summary
<1-2 sentence migration assessment>
```

## Do Not

- Do not upgrade unrelated dependencies.
- Do not change behaviour beyond what the migration requires.
- Do not adopt new syntax features unless they replace deprecated patterns.
- Do not remove backwards-compatibility code without confirming the minimum
  supported version with the user.
- Do not run `pip install` or modify the virtual environment.
