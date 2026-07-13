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
- [x] `issue-command-drives-kanban-lifecycle` → `hooks/kanban_lifecycle.sh` + `commands/issue.md` (#47, closed #46)
- [x] `github-project-workflows-off-and-unreadable` → `commands/issue.md` (enable-workflows step +
      duplicate-board guard) + `hooks/kanban_lifecycle.sh` (refuse on >1 same-titled board)
      (#49, closed #48 — the #47 fallout: merging #47 stranded #46's card because native Done
      workflows ship disabled)
- [x] `commit-body-autowrap-word-boundary-no-orphans` → `hooks/commit_body_wrap.sh` reflows per
      paragraph via Python `textwrap` (idempotent + widow control), replacing the per-line awk
      splitter that orphaned words (#51, closed #50 — cosmetic follow-up to #42)

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

## Session checkpoint — 2026-07-13

Every dotfiles-dev lesson in the store is implemented and merged. Session arc, in order:

| PR | State | What landed |
|---|---|---|
| #42 | merged | 5 lessons: dict-dispatch + ingestion rules; `commit_body_wrap`, `branch_requires_issue_guard`, `push_pr_head_guard` hooks |
| #43 | merged | tracker-agnostic branch guard (github + linear) |
| #45 | merged | `/release` skill + `release_dispatch_guard` (closed #44) |
| #47 | merged | `kanban_lifecycle` hook + `issue.md` hybrid (closed #46) |
| #49 | merged | board-workflow setup docs + duplicate-board guard (closed #48; the #47 fallout) |
| #51 | **OPEN** | per-paragraph commit-body reflow, no orphan words (closed #50) |

**Only open thread:** PR #51 awaits review/merge. On merge, sync master, delete the branch,
flip nothing else (its lesson is already tagged #51).

**Manual follow-ups the API cannot do (owner action):**
- Board `dotfiles-dev kanban` (#13): disable the **Pull request linked to issue** workflow — it
  races `kanban_lifecycle`'s PR→In review (see `github-project-workflows-off-and-unreadable`).
- Any *new* board `/issue` creates needs its **Item closed** + **Pull request merged** workflows
  enabled by hand (→ Done); `issue.md` now prints that instruction.

**Lessons captured this session:** `hook-config-outside-repo-and-no-mcp`,
`check-the-platform-before-building-the-hook`, `github-project-workflows-off-and-unreadable`.

No remaining backlog items. Session ends here.
