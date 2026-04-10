---
name: c:dep-py
allowed-tools: Bash(poetry*), Bash(uv*), Bash(pip*), Bash(pip-audit*), Bash(python -m*), Bash(cat pyproject.toml*), Read, Glob, Grep, WebSearch
description: Add, remove, bump, or audit a Python dependency with compatibility reasoning
argument-hint: "<add|remove|bump|audit> [package] [version] — e.g. dep add httpx | dep bump pydantic 2.0 | dep audit"
---

You are managing Python dependencies for this project. Follow these steps exactly.

## 1. Parse arguments

Extract from `$ARGUMENTS`:
- **Operation:** one of `add`, `remove`, `bump`, `audit`
- **Package name:** required for add/remove/bump, ignored for audit
- **Version constraint:** optional for add/bump (e.g. `>=2.0`, `~=1.5`, or exact `2.0.1`)

If the operation is missing or invalid, ask the user to specify one.

## 2. Detect project environment

Read `pyproject.toml` to determine:
- **Package manager:** Poetry (`[tool.poetry]`), uv (`[tool.uv]`), or plain pip (`[project]` with no Poetry/uv markers)
- **Python version constraint:** from `requires-python` or `[tool.poetry.dependencies].python`
- **Current dependencies:** list from `[project.dependencies]` or `[tool.poetry.dependencies]`

If no `pyproject.toml` exists, warn the user and ask how to proceed.

## 3. Execute the operation

### For `add`:
1. **Check quality:** Web search for `<package> snyk advisor` to find the Snyk Advisor score. If the score is below 80, warn the user and ask for confirmation before proceeding.
2. **Check compatibility:** Verify the package supports the project's Python version.
3. **Check conflicts:** Scan current dependencies for known incompatibilities with the new package.
4. **Install:** Run the appropriate command:
   - Poetry: `poetry add <package>[<version>]`
   - uv: `uv add <package>[<version>]`
   - pip: `pip install <package>[<version>]` and update `pyproject.toml` manually
5. **Verify:** Confirm the lock file updated cleanly and the package is importable (`python -c "import <package>"`).

### For `remove`:
1. **Check usage:** Grep the entire codebase for imports of the package (`import <pkg>`, `from <pkg>`).
2. **Warn if used:** If the package is still imported anywhere, list the files and ask the user for confirmation.
3. **Remove:** Run the appropriate command:
   - Poetry: `poetry remove <package>`
   - uv: `uv remove <package>`
   - pip: `pip uninstall <package>` and update `pyproject.toml` manually
4. **Verify:** Confirm the lock file updated and no broken imports remain.

### For `bump`:
1. **Identify current version:** From the lock file or installed packages (`pip show <package>`).
2. **Check changelog:** Web search for `<package> changelog` or `<package> release notes` to find breaking changes between the current and target versions.
3. **Warn about breaking changes:** If major version changes or known breaking changes exist, list them and ask the user for confirmation.
4. **Update:** Run the appropriate command:
   - Poetry: `poetry update <package>` or `poetry add <package>@<version>`
   - uv: `uv add <package>>=<version>` or `uv lock --upgrade-package <package>`
   - pip: `pip install --upgrade <package>[<version>]`
5. **Suggest testing:** Recommend running the test suite, especially tests that import the bumped package.

### For `audit`:
1. **Run audit tool:** Try in order: `pip-audit`, `safety check`, or `python -m pip_audit`.
2. **Check outdated:** Run `pip list --outdated` or equivalent.
3. **Report:** For each finding, provide: package name, current version, issue (vulnerability CVE or available upgrade), severity, and recommended action.

## 4. Report

Output a structured report:

```
## Dependency: <operation> <package>

**Package manager:** <Poetry|uv|pip>
**Python version:** <constraint>

### What happened
<1-2 sentence summary of the action taken>

### Details
- <specific changes made>
- <versions: before → after>
- <lock file status>

### Warnings
- <any compatibility concerns, breaking changes, or low Snyk scores>

### Next steps
- <run tests, update imports, check CI, etc.>
```
