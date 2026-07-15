---
name: s:wrap-up
description: Use when ending or wrapping up a work session — before /exit or /clear, or when the user asks "did I capture everything?", "safe to end?", "wrap up", "anything I forgot?". Runs the deterministic capture audit and FIXES the gaps (writes the missing lesson, indexes and mirrors it, files the missing issue, updates the checkpoint) while the session is still live — the SessionEnd hook can only report a gap forward, it cannot fix one.
effort: high
argument-hint: [none]
allowed-tools: Bash Read Glob Grep Write Edit
---

You are closing out a work session. The question *"did I capture every lesson / issue /
checkpoint?"* is **deterministic and checkable** — do not answer it from memory, because memory
is exactly what is under audit. Run the audit, then **act on every finding while the session is
still live**. This is the fixer; the `SessionEnd` hook is only a safety net that reports gaps
forward to the next session.

## 1. Run the audit

```bash
bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/session_capture_audit.sh"
```

It prints two blocks: **mechanical gaps** (git / lesson-index / mirror — already decided for you)
and a **judgment checklist** (superseded rules / issues-PRs / checkpoint / lesson routing — the
script cannot decide these; you must). Work every line of both.

## 2. Fix the mechanical gaps

- **`[git] uncommitted changes` / `unpushed commits`** — surface them and ask the user whether to
  commit/push. **Never commit or push without an explicit request** (global rule) — report and let
  them decide.
- **`[git] on branch '…' (not default)`** — remind the user the branch is unmerged; offer to open
  a PR (`s:gh-create-pr`) if the work is done.
- **`[lessons] '<file>' is not in the <store> README index`** — a lesson file exists but is
  unindexed = a lost lesson. Add its one-line index entry to that store's `README.md`.
- **`[lessons] '<file>' … not in docs/<mirror>.md`** — add the lesson to this repo's git-ignored
  mirror (`docs/blueprintx-lessons.md` or `docs/dotfiles-dev-lessons.md`).
- **`[lessons] '<file>' has no **Tier:** line`** — add a `- **Tier:**` line. Tier is an **open
  field**: pick the best fit (`python-common`, `language-common`, `language-specific (<lang>)`, or a
  layout/archetype like `mvc-*`, `ddd-*`, `library`) — and a **new/unknown tier is fine**, never
  reject one against a hardcoded list.

## 3. Work the judgment checklist

- **Superseded rules — the highest-value check, and the one nobody remembers.** If this session
  **changed a standing rule**, the new rule got written (memory, lesson) but the **old rule keeps
  living** in whatever tracked doc / README / backlog ledger first stated it — and a tracked doc
  outranks your memory for the *next* session. `grep` the tracked docs for the old rule and delete
  or rewrite it. (A real audit found a revoked "minor-bump every merge" release rule still sitting
  in a tracked ledger; a future session would have read and obeyed it.)
- **Issues / PRs** — every issue created this session is on the repo's board and its card is in the
  right column; open PRs are accounted for. Fix stragglers via `/issue` / `s:gh-create-pr`.
- **Checkpoint** — does the project memory hold a resume point covering this session's work? If not,
  write one so the next session can pick up.
- **Lessons routing** — did any work yield a *generalizable* toolchain/scaffold improvement not yet
  captured? Load `s:capturing-lessons` and route it by **where the fix lands**: a scaffolding
  template → BlueprintX store (`~/.claude/memory/lessons/` + `docs/blueprintx-lessons.md`); the
  Claude/dotfiles toolchain → dotfiles-dev store (`~/.claude/memory/lessons-dotfiles/` +
  `docs/dotfiles-dev-lessons.md`). Every lesson must exist in **all three** places: file, README
  index, repo mirror.

## 4. Re-run and report

Re-run the audit from step 1. Report, concisely:
- What you **fixed** (lessons indexed/mirrored, checkpoint written, stale rule removed, …).
- What remains and **needs the user** (uncommitted/unpushed work, an unmerged branch).
- Confirm whether the mechanical block is now clean. Only then is it safe to end.
