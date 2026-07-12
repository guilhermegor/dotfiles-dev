---
name: s:release
description: Use when the user asks to cut a release, bump the version, or publish a package to PyPI/Test PyPI — decides whether a release is warranted and what to bump from the shipped-artifact diff and Conventional Commit types since the last tag, then drives the Test PyPI → PyPI two-step with verification.
effort: high
argument-hint: [none — reads the repo state]
allowed-tools: Bash(git log*), Bash(git tag*), Bash(git describe*), Bash(git diff*), Bash(git rev-parse*), Bash(curl*), Bash(rtk git log*), Bash(rtk git diff*), Bash(gh workflow*), Bash(gh run*)
---

You are deciding and cutting a release for this repository. Follow these steps exactly.

The governing rule: **a version is a claim about the shipped artifact — only mint one when the
artifact changed.** A "minor-bump every merge" habit ships byte-identical wheels under new
numbers, filling the changelog with noise and draining the version of meaning. The release
trigger is a **diff in the shipped artifact**, never "a PR merged".

## 1. Resolve the shipped paths

The shipped paths are the files that actually end up in the distributed artifact. Read them, in
order:

1. A repo-committed `.claude/release.conf` — one path/glob per line, `#` comments ignored.
2. Otherwise the default for a Python package: `src/` and `pyproject.toml`.

**Not shipped** (never in the wheel): `.github/`, `bin/`, `tests/`, `docs/`, `SECURITY.md`,
`Makefile`, CI config. A change confined to these does **not** get a release.

## 2. Decide whether to release at all

```bash
git describe --tags --abbrev=0          # → <last-tag>; if this fails there are no tags yet
git diff --name-only <last-tag>..HEAD -- <shipped-paths...>
```

- **No tags yet** → this is the first release; proceed (propose the project's current
  `pyproject.toml` version, or `0.1.0`).
- **Shipped diff empty** → **STOP. No release.** Tell the user plainly: *"No shipped change since
  `<last-tag>` — ci/docs/chore/test do not get a release."* Do not publish anything, do not tag.
- **Shipped diff non-empty** → continue.

## 3. Compute the bump from Conventional Commit types

Scan `git log <last-tag>..HEAD` subjects and bodies. Take the **highest** signal present:

| Highest signal since the tag | Pre-1.0 (`0.x`) bump | `>=1.0` bump |
|---|---|---|
| breaking (`type!:` or `BREAKING CHANGE:`) | **MINOR** (0.24.x → 0.25.0) | MAJOR |
| `feat:` | **PATCH** (0.24.0 → 0.24.1) | MINOR |
| `fix:` / hotfix | **PATCH** | PATCH |

**Honour 0.x semantics while `<1.0`** — a library still stabilising its API: breaking → MINOR,
feat/fix → PATCH. Cut `1.0.0` deliberately when the API is stable, then switch to full
major/minor/patch. Do not leave this to recall — apply the table.

## 4. Compute the next version across BOTH indices

The next version must be **greater than the max of what is already published on PyPI AND on Test
PyPI** — not just PyPI:

```bash
curl -s https://pypi.org/pypi/<pkg>/json            | jq -r '.info.version'   # or 404 if none
curl -s https://test.pypi.org/pypi/<pkg>/json       | jq -r '.info.version'
```

**Why both:** a Test PyPI rehearsal permanently raises that index's floor. If `0.25.0` was pushed
to Test PyPI but never released to PyPI, PyPI sits at `0.24.0` and Test PyPI at `0.25.0` — so the
next correct version `0.24.1` passes the PyPI gate but **fails the Test PyPI gate**. Compute
`next = bump(max(pypi_version, testpypi_version))`. State out loud that **PyPI will show gaps —
that is expected**; version numbers are free, correctness is not.

## 5. Propose, and wait for confirmation

Present:

> **Release proposal**
> - Shipped change since `<last-tag>`: `<n>` files (`<list>`)
> - Highest commit signal: `<breaking|feat|fix>`
> - Current max across indices: PyPI `<x>`, Test PyPI `<y>`
> - **Proposed version: `<next>`** (`<bump>`, pre-1.0 rules)
>
> Publish this? (yes / a different version / no)

Wait for an explicit answer. This human gate is the point — the automation removes the *wrong*
releases, not the oversight.

## 6. Publish — Test PyPI first, then PyPI, each verified

```bash
gh workflow run release-test-pypi.yaml -f version=<next>
```

Then **verify by install** before promoting — do not trust a single index read:

- Poll the run to green (`gh run list --workflow=release-test-pypi.yaml --limit 1`).
- `pip install -i https://test.pypi.org/simple/ <pkg>==<next>` in a throwaway venv; **retry on
  failure** — both `/simple/` and the file host lag a fresh upload, so a first-attempt failure
  then success is normal. A missing version means **unknown**, not absent; ground truth is the
  workflow's publish log showing twine's `200 OK` plus a successful install on retry.

Only once Test PyPI is verified:

```bash
gh workflow run release-pypi.yaml -f version=<next>
```

Verify the same way (green run + `pip install <pkg>==<next>` with retry).

## 7. Report

> Released `<pkg>` `<next>`:
> - Test PyPI: published + install-verified
> - PyPI: published + install-verified
> - Skipped: `<none | the index-floor gap, if any>`

## Do Not

- Do not release for a change that does not alter the shipped artifact (ci/docs/chore/test).
- Do not compute the next version from PyPI alone — always `max(PyPI, Test PyPI)`.
- Do not declare a release broken on a single negative index read — retry; a missing version is
  unknown, not absent.
- Do not minor-bump a `fix:` (pre-1.0 it is PATCH) — inflating the minor axis drains its meaning.
- Do not publish without the explicit user confirmation in step 5.
- Do not keep stacking release dispatches; one version per shipped change.
