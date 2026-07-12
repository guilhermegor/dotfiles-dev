# Lessons backport — remaining work

Tracks the dotfiles-dev lessons still to implement, in order, with the branch and
PR to open for each. Source of truth for the lessons themselves is the global store
`~/.claude/memory/lessons-dotfiles/` (not in this repo). This file exists only
because there is no native cross-session to-do list.

## Done (PR `feat/lessons-backport`)

| Lesson | Landed as |
|---|---|
| `prefer-dict-dispatch-over-else-chain` | `rules/common.md` + `rules/python.md` |
| `ingestion-dataframe-url-updated-at-rule` | `rules/python.md` (Data Engineering) |
| `autowrap-commit-body-pretooluse-hook` | `hooks/commit_body_wrap.sh` |
| `no-implementation-without-a-tracked-issue` | `hooks/branch_requires_issue_guard.sh` (commit-on-main half already shipped in `protected_branch_guard.sh`, #41) |
| `verify-pr-head-after-push-not-lag` | `hooks/push_pr_head_guard.sh` |
| `permission-allowlist-cannot-see-past-the-first-token` | already shipped in #41 (`destructive_command_guard.sh`) — no work left |

## Remaining — each is its own branch + PR

### 1. `/release` skill + release-dispatch guard

- **Branch:** `feat/release-skill`
- **Lesson:** `release-only-when-shipped-package-changes`
- **Build:**
  - `skills/release.md` (`s:release`) — decide *whether* to release and *what to bump*
    from the Conventional Commit types since the last tag **and** the paths they touched:
    - `feat:`/`fix:` touching the shipped package → **PATCH** pre-1.0 (MINOR/PATCH at ≥1.0)
    - breaking (`!` / `BREAKING CHANGE:`) → **MINOR** pre-1.0 (MAJOR at ≥1.0)
    - `ci:`/`docs:`/`chore:`/`test:`/`style:`/`refactor:` with **no** shipped-package diff
      → **no release at all**
    - Trigger is a diff in the SHIPPED artifact, not a merge: `git diff --name-only
      <last-tag>..HEAD -- <shipped-paths>` empty ⇒ skip entirely.
    - Next version must be greater than the max of **both** PyPI and Test PyPI (a Test PyPI
      rehearsal permanently raises that index's floor).
    - Keep the Test PyPI → verify-by-install → PyPI → verify two-step and the human confirm gate.
  - `hooks/release_dispatch_guard.sh` — **PreToolUse** guard on `gh workflow run
    release-{test-,}pypi.yaml -f version=X.Y.Z` (and the `rtk gh` form). Block when: the
    shipped diff is empty; the `-f version=` does not match the computed bump; or the version
    is not greater than the max of both indices. **A hook cannot fire on "PR merged"** (a
    GitHub event, not a tool call) — the dispatch is the binding interception point.
  - Optional PostToolUse nudge on `git pull --ff-only` / `git checkout main`: inject one line
    (`RELEASE DUE: 0.24.1 (feat)` / `NO RELEASE NEEDED (ci/docs only)`).
  - A one-line rule in `rules/` or global `CLAUDE.md`: releases are driven by the shipped diff
    + commit type, never by "a PR merged".
- **Config seam:** shipped-paths must be a **per-project** list (a Python lib is `src/` +
  `pyproject.toml`; a service differs). The skill and the guard must read the *same* list or
  they will disagree — default to the language template's package root.

### 2. `/issue` kanban lifecycle hooks

- **Branch:** `feat/issue-kanban-lifecycle`
- **Lessons:** `issue-command-drives-kanban-lifecycle` (extends `issue-authoring-command`)
- **Build:**
  - Extend `commands/issue.md` to emit the branch↔issue link and set the card to **In
    progress** when it opens the branch.
  - PostToolUse hooks moving the card automatically:
    - branch created → **In progress**
    - `gh pr create` → **In review** (piggyback on `pr_template_guard`, which already
      intercepts PR creation)
    - `gh pr merge` → **Done** + close the issue
  - Discover the per-repo project id, Status field id, and option ids via
    `gh project field-list` (or cache them per-repo); never hard-code one board's ids.
  - Match the **verb**, then resolve issue/branch/card via `gh` — do not scrape a CLI flag out
    of the raw command string (`hook-command-string-scraping-fragile`).

## After each lands

Update the lesson file's `PR:` field in `~/.claude/memory/lessons-dotfiles/<name>.md`
from `pending` to the merged PR number, and move its row up to the Done table here.
