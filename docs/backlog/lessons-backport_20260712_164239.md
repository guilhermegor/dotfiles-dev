# Lessons backport — work ledger

Ledger for backporting the dotfiles-dev lessons into the Claude toolchain. Source of truth for the
lessons themselves is the global store `~/.claude/memory/lessons-dotfiles/` (not in this repo).
This file is the per-branch work record: what is done, what remains. Kept as a record on
completion — never deleted.

## Done

- [x] `prefer-dict-dispatch-over-else-chain` → `rules/common.md` + `rules/python.md` (#42)
- [x] `ingestion-dataframe-url-updated-at-rule` → `rules/python.md` Data Engineering (#42)
- [x] `autowrap-commit-body-pretooluse-hook` → `hooks/commit_body_wrap.sh` (#42)
- [x] `no-implementation-without-a-tracked-issue` → `hooks/branch_requires_issue_guard.sh` (#42);
      commit-on-main half already in `protected_branch_guard.sh` (#41)
- [x] `verify-pr-head-after-push-not-lag` → `hooks/push_pr_head_guard.sh` (#42)
- [x] `permission-allowlist-cannot-see-past-the-first-token` → already in `destructive_command_guard.sh` (#41)
- [x] `hook-config-outside-repo-and-no-mcp` → made `branch_requires_issue_guard.sh` tracker-agnostic (#43)
- [x] `release-only-when-shipped-package-changes` → `skills/release.md` + `hooks/release_dispatch_guard.sh` (#44, this branch)

## Remaining

- [ ] `issue-command-drives-kanban-lifecycle` (extends `issue-authoring-command`)
  - **Branch:** `feat/issue-kanban-lifecycle` (open an issue first — the live branch guard requires it)
  - **Build:**
    - Extend `commands/issue.md` to emit the branch↔issue link and set the card **In progress** on branch open.
    - PostToolUse hooks: branch created → **In progress**; `gh pr create` → **In review** (piggyback on `pr_template_guard`); `gh pr merge` → **Done** + close issue.
    - Discover per-repo project id / Status field id / option ids via `gh project field-list` (or cache per-repo); never hard-code one board's ids.
    - Match the **verb**, then resolve issue/branch/card via `gh` — do not scrape a CLI flag from the raw command string (`hook-command-string-scraping-fragile`).

## Notes for whoever picks this up

- **`release_dispatch_guard.sh` deliberately blocks on only the offline-deterministic check**
  (shipped diff empty). The version/bump math needs `max(PyPI, Test PyPI)` (network), so it lives
  in the `s:release` skill; the guard adds only an advisory note for an obvious pre-1.0 over-bump.
- **Shipped paths** default to `src/` + `pyproject.toml`; a repo overrides via a committed
  `.claude/release.conf` (one path/glob per line). Committed on purpose — a repo's shipped layout
  is its own metadata, and you only release repos you control (contrast the tracker map in
  `~/.claude/issue-trackers.conf`, which is local/git-ignored because it selects behaviour for
  repos you may have restricted rights on).
- After a remaining item lands, tick its box here and flip its lesson file's `PR: pending` →
  the merged PR number.
