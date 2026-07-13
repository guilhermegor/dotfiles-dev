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
- [x] `release-only-when-shipped-package-changes` → `skills/release.md` + `hooks/release_dispatch_guard.sh` (#45, closed #44)
- [x] `issue-command-drives-kanban-lifecycle` → `hooks/kanban_lifecycle.sh` + `commands/issue.md` (#46)

## Remaining

- (none — all backlog items landed)

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
- **`kanban_lifecycle.sh` is a hybrid, not the literal lesson.** GitHub Projects' native
  workflows already do "PR merged / issue closed → Done", so the hook fills only the two
  transitions native workflows cannot trigger: branch open → **In progress**, PR open →
  **In review**. Done stays native. Building a hook for Done would race the native automation.
- Board ids are discovered live (`gh project field-list`) and cached per-repo in a **local,
  git-ignored** `~/.claude/kanban-boards/<owner>-<repo>.json` — same seam as the tracker map, so
  a repo needs zero in-repo board metadata. A repo with no `<repo> kanban` project no-ops (which
  also skips Linear/none repos). A stale cache self-heals: a failed move refreshes and retries.
- All backlog items are done — this ledger is kept as the permanent record (never deleted).
