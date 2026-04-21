---
name: c:act
description: Run a targeted GitHub Actions workflow locally with act, detect failures, and fix them iteratively (YAML first, then source code)
argument-hint: "<workflow.yml> [--plan|--fix]"
allowed-tools: Bash(act*), Read, Glob, Grep, Edit, Skill
---

You are running a GitHub Actions workflow locally with `act`, detecting failures, and fixing them for this repository. Follow these steps exactly.

## 1. Parse arguments

Extract from `$ARGUMENTS`:
- **Workflow path:** a `.yml` file path (e.g. `ci.yml` or `.github/workflows/ci.yml`)
- **Mode flag:** `--plan` (propose changes, ask before applying) or `--fix` (apply directly)

If the mode flag is absent, default to `--plan`.

If no workflow path is provided:
- Glob `.github/workflows/*.yml` and `.github/workflows/*.yaml`
- List the matches and ask the user which file to target

Normalise the path: if the user gave a bare filename (e.g. `ci.yml`), prepend `.github/workflows/`.

## 2. Pre-flight

**Docker socket discovery (Linux + Docker Desktop):**
Before running any `act` command, resolve the active Docker socket:
1. Check if `/var/run/docker.sock` exists → use it (standard Docker Engine).
2. Otherwise check `~/.docker/desktop/docker.sock` → set `DOCKER_HOST=unix://$HOME/.docker/desktop/docker.sock` and export it for all subsequent `act` calls.
3. If neither exists, report that Docker is not running and stop.

**Platform limitation:** `act` uses Linux Docker containers — it can only simulate `ubuntu-latest` jobs. For matrix workflows, always narrow the run with `--matrix os:ubuntu-latest` (and a single `python-version` if applicable) to avoid wasting time on runners `act` cannot emulate.

Run:
```
DOCKER_HOST=<resolved-socket> act --list -W <workflow-path>
```

- If `act` is not installed, report the error and stop — refer the user to `make install_programs` (the `install_act()` function handles installation).
- Report the job list to the user before continuing.
- Warn the user if the workflow has `windows-latest` or `macos-latest` matrix entries — these cannot be tested locally with `act`.

## 3. Pass 1 — YAML validation (dry-run)

Run:
```
DOCKER_HOST=<resolved-socket> act -W <workflow-path> -n --matrix os:ubuntu-latest
```

If the output contains errors, classify and fix:

| Error type | Example signal | Fix |
|---|---|---|
| Bad action version | `uses: actions/checkout@v1` | Bump to latest stable version |
| Missing env var | `${{ env.FOO }}` undefined | Add `env:` block or note it's missing |
| YAML syntax error | Parse failure, malformed `on:` | Fix indentation or key name |
| Unsupported event | `schedule:`, `workflow_dispatch` | Warn that `act` cannot simulate this trigger |
| Cross-platform shell quoting | Single-quoted arg in `run:` step fails on `windows-latest` with "path not found" or exit 255 | Replace `'...'` with `"..."` and escape any backslashes (`\.` → `\\.`). Single quotes are POSIX-only; Windows Git Bash mis-parses them as path globs. Always verify the change works on Linux bash and macOS zsh too — double-quoted args with escaped backslashes are safe on all three. |
| Windows `.exe` launcher broken | `poetry run <tool>` fails on `windows-latest` with "The system cannot find the path specified" (exit 255) even though the tool is installed | Use `poetry run python -m <tool>` instead. On Windows, `poetry install` creates `.exe` script wrappers in `.venv\Scripts\` that hardcode the Python path at install time. Cached venvs break when restored on a different runner. `python -m <tool>` bypasses the launcher and works on all platforms. |

Apply fixes based on mode:
- `--plan`: describe the proposed YAML change; wait for user confirmation before writing
- `--fix`: Edit the workflow file directly

Re-run the dry-run. If still failing after **2 attempts**, report the remaining error and stop.

If the dry-run passes, proceed to pass 2.

## 4. Pass 2 — Full run

Run (note: `act` full runs may take several minutes while Docker containers start):
```
DOCKER_HOST=<resolved-socket> act -W <workflow-path> --matrix os:ubuntu-latest
```

If exit code is 0, skip to step 5 with a success outcome.

On failure, identify the failing step name and error type:

**Python errors** — output contains any of:
`pytest`, `FAILED`, `AssertionError`, `ruff`, `flake8`, `pylint`, `mypy: error`,
`Incompatible types`, `ModuleNotFoundError`, `ImportError`,
`pip install`, `No matching distribution`, `coverage:` below threshold

→ Load `s:act-fix-py` via Skill tool, passing the full act output and current mode flag as context. Apply the fixes it returns.

**Non-Python errors** — classify inline:
- Missing binary → suggest adding an install step to the workflow
- Bad environment variable → propose adding it to the workflow `env:` block or a `.env` file
- Permission denied → check if the script needs `chmod +x` in the workflow
- Network error → note that `act` may need `--bind` or that external calls are unavailable offline

Apply fixes based on mode (`--plan` proposes, `--fix` edits).

Re-run `DOCKER_HOST=<resolved-socket> act -W <workflow-path> --matrix os:ubuntu-latest` after fixes. Repeat up to **3 total runs**. If still failing after 3 runs, report remaining errors and stop.

## 5. Final report

```
## act: <workflow-path>

Mode:    <--plan | --fix>
Outcome: <green (all jobs passed) | red (N jobs failed)>
Runs:    <N of 3>

### Fixed
- <file:line — description of what was changed and why>

### Remaining errors
- <step name — error summary — file:line if available>

### Learned patterns
- <new pattern saved to act-fix-patterns, if any>
```
