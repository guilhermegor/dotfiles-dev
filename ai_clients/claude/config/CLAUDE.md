@RTK.md

## CLI Commands — Always Use RTK Proxy

For any command RTK supports (`git`, `gh`, `find`, `grep`, `ls`, `curl`,
`docker`, `pytest`, `cargo`, etc.), write the `rtk` prefix explicitly in
agents, skills, and commands — never the bare binary. See RTK.md for the
full list.

Why: the `PreToolUse` hook rewrites at execution time, but the approval
prompt shows the pre-hook command, so "don't ask again" creates a wrong
allowlist entry (`Bash(git *)` instead of `Bash(rtk git *)`).

Commands RTK does not wrap run bare as normal (`sqlite3`, `jq`, `make`,
`python3`, `node`, etc.).

Exceptions where bare binary is always correct:
- `command -v <tool>` availability checks
- Install instructions (`sudo apt install ...`)
- Prohibition examples in "Do Not" sections

### Never infer existence from rtk-proxied `ls`/`find` output

The rtk proxy can collapse real `ls`/`find`/`grep` results to `(empty)` to save
tokens — so an empty-looking result is **"unknown", never "absent"**. Acting on a
false negative silently skips real files (PR templates, populated stores, lessons
files) and has repeatedly produced wrong "this is empty / does not exist" claims.

- To check whether a path exists, use the **Read** or **Glob** tool — never
  rtk-proxied `ls`/`find`.
- To list a directory reliably, use **Glob** (`dir/**`) or the raw escape hatch
  **`rtk proxy ls <dir>`** / **`rtk proxy find <dir>`** (RTK.md: "execute raw
  command without filtering").
- If a result looks empty but anything (a memory, an index, prior knowledge) says
  the path should exist, verify with `Read`/`Glob` before concluding absence. A
  negative from a lossy channel is not evidence.

### Git writes run under the sandbox — verify HEAD, never `| tail` a commit

A `git commit`/`push`/`tag`/`branch -d/-D` run through the Bash tool executes in the
**default sandbox** overlay. It can print full success — every pre-commit hook `Passed`,
`[branch abc123] N files changed` — while **the ref update is discarded on teardown and HEAD
never moves**. A push then ships a branch missing the "committed" work. The rtk proxy is
orthogonal here: it only rewrites `git …` → `rtk git …`; the sandbox overlay, a Claude Code
harness behaviour, is what drops the write. So **leaving git writes unproxied is not the fix**
(evaluated for dotfiles-dev#79 — cosmetic, the proxy is not the persistence culprit).

One symptom, **two** independent causes — check for both:

1. **Sandbox overlay non-persistence** → run every git write with
   `dangerouslyDisableSandbox: true`.
2. **A pre-commit hook rejected the commit and `| tail`/`| grep` hid the failure line.** The
   hook list is long, so a tailed commit shows only trailing `Passed` lines while the rejection
   (`codespell`, `gitlint`, `ruff E501`) scrolled off — HEAD is unchanged because the commit
   really failed.

Robust practice:

- Run git writes with `dangerouslyDisableSandbox: true`.
- **Never pipe `git commit` through `tail`/`head`/`grep`.** Use full output, then in the same
  call: `echo "===EXIT=$?===" ; git log --oneline -1`. A non-zero exit or an unmoved HEAD means
  it did **not** land. If output must be trimmed, `grep -nE 'Failed|error|rejected'`, never `tail`.
- **Ground truth when unsure:** `Read` `.git/refs/heads/<branch>` (or `.git/logs/HEAD`) directly
  — a proxied `git log`/`rev-parse` can read the same overlay and lie.

## Author Claude artifacts in dotfiles-dev, never only in live `~/.claude/`

Durable Claude artifacts (commands, skills, agents, rules, hooks, global
`CLAUDE.md`, settings) must be authored in the version-controlled source under
`~/github/dotfiles-dev/ai_clients/claude/`, then deployed with `make ai_clients`
(or `cp` into place). Never write them only to `~/.claude/` — it is machine-local
and non-symlinked, so direct edits are lost on the next OS/distro install.

Enforced by the `claude_artifact_source_guard.sh` PreToolUse hook: a direct
Write/Edit into `~/.claude/{commands,skills,agents,rules,hooks}/` or `CLAUDE.md`
is blocked and redirected to its source. Not blocked by the hook:
project-scoped `.claude/`, project memory, `tasks/`, `plans/`, `settings*.json`.
⚠️ **Not-blocked ≠ write-it-live.** `settings*.json` is unblocked only because it
also carries machine-local keys — **durable** settings (permissions `allow`/`deny`/
`ask`, model, hooks, plugins) are still authored in
`ai_clients/claude/settings.json` and deployed; `configure_settings` deep-merges
(`jq '. * $base'`), so source wins and live-only keys survive. Full source-path
table: `ai_clients/CLAUDE.md`.

# Global Programming Preferences

> **Priority rule:** These are personal defaults. Whenever a project-level CLAUDE.md (or any
> instruction inside the active repository) conflicts with anything here, the project context
> takes precedence. Treat this file as a fallback, not a mandate.

Language-agnostic coding conventions — Core Philosophy, Code Style, Module
Structure, Design Patterns, Architecture, Testing, Documentation, the
always/never-do checklists, and Numeric Precision — live in
`ai_clients/claude/rules/common.md`. It auto-loads (via `paths:` frontmatter)
whenever a source file is touched, so it stays out of the always-on context.
Per-language rules (`python.md`, `bash.md`, …) layer on top. Only genuinely
cross-cutting, non-file-scoped rules remain below.

## Dispatching subagents — brief them to commit early

When a task handed to a subagent (or a worktree-isolated agent) is expected to touch
multiple files or take more than a couple of tool calls, its brief must say to commit
at the first coherent point and keep committing — not to save committing for the end.
Measured cost of the opposite (dotfiles-dev#167): three subagents were killed on the
session limit in one afternoon holding 662, 694, and 256 lines of *uncommitted* work
each, rescued only because a human happened to notice before the worktree was torn
down. The loss was never caused by running out of budget — a kill halfway through
costs the same whether it lands at 50% or 90% of the window — it was caused by work
sitting in the worktree, undurable, until the very end.

This prose rule is the probabilistic half of the fix, and prose alone is not enough
(see the `Compaction`/"rule that must fire every cycle" framing below); the
deterministic half is `uncommitted_worktree_guard.sh`, a `Stop` hook that refuses to
end a turn while `git status --porcelain` is non-empty. A **pre-dispatch** "is there
room to finish what I'm about to start?" budget check was considered and deliberately
NOT built: there is no remaining-context-window signal readable from the hook
environment, and a wall-clock/token-percentage alarm was evaluated and rejected — a
90%-alarm narrows the window in which the damage happens without shrinking the damage
itself, and it fires exactly when there is least room left to act.

## Version Control

- Conventional Commits: `feat:`, `fix:`, `chore:`, `test:`, `docs:`, `refactor:`.
- Atomic commits: one logical change per commit.
- Never commit secrets, credentials, or local config files.
- `.gitignore` before first commit.

## Tutoring — resume before replacing

When the user asks to resume/continue tutoring or "pick up where we left off"
(in plain language, not only via `/tutoring on`), find in-progress work before
generating any new curriculum. The `s:tutoring-resume` skill holds the mandatory
discovery sequence (project memory file → active plan → fresh only after explicit
confirmation).

## Lessons — capture and apply

Two lesson systems, both with detailed how-to in the `s:capturing-lessons` skill
(load it the moment you decide something is worth capturing):

- **Corrections log** (`~/.claude/tasks/lessons.md`) — when the user corrects a
  mistake, append an entry before moving on. Surfaced each session by the
  `session_start_context.sh` hook; read and apply entries scoped to the cwd or `global`.
- **Generalizable improvements** — when work yields a reusable seam/tooling/convention/
  guardrail (not a project-specific rule), **capture it before moving on** into the right
  backport store, routed by *where the fix lands*: a scaffolding template →
  BlueprintX store `~/.claude/memory/lessons/`; the Claude/dotfiles toolchain →
  dotfiles-dev store `~/.claude/memory/lessons-dotfiles/`.

Before ending a session, run **`/wrap-up`** (skill `s:wrap-up`). It runs the deterministic
capture audit (`session_capture_audit.sh`) and **fixes** what it finds — the missing lesson,
its index/mirror entries, the unfiled issue, the checkpoint — while the session is still live.
The `SessionEnd` hook runs the same audit but can only **report forward**: it writes unresolved
gaps to a handoff file that `session_start_context.sh` surfaces next session. It never blocks the
exit. The highest-value check is the one nobody remembers: when a session **changes a standing
rule**, grep the tracked docs for the OLD rule — a tracked doc outranks memory next session.

## Compaction

When the context window is compacted, apply this priority order:

**Always keep**
- The current task description and its acceptance criteria
- File paths that have been read, created, or modified in this session
- Test results (pass/fail counts, assertion errors, failing test names)
- The current plan or step list and which steps are done vs. pending
- Any explicit user instructions or corrections given during the session
- Final state of any code written or edited (not intermediate drafts)

**Summarise (keep the conclusion, drop the detail)**
- Exploration trails: keep the finding, drop the path taken to reach it
- Tool call chains that produced a single result — keep only the result
- Repeated grep/glob searches — keep the final match, drop earlier misses

**Drop entirely**
- Error messages that have already been resolved
- Superseded approaches, rejected designs, or abandoned file reads
- Intermediate reasoning steps that led to a decision already recorded
- Duplicate information (e.g. the same file path mentioned three times)
- Any raw tool output that was only used to derive a now-recorded fact
