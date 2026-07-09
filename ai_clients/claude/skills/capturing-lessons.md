---
name: s:capturing-lessons
description: Use when capturing or writing a lesson — logging a user correction to the project lessons log, or saving a generalizable scaffold/toolchain improvement to a lessons store and deciding which store (BlueprintX vs dotfiles-dev) it belongs in. Load it the moment you decide "this is worth capturing", before writing the lesson.
effort: medium
argument-hint: [none]
allowed-tools: Read Glob Grep Write Edit
---

Two distinct lesson systems live here. Pick by what you are capturing.

---

## System 1 — Corrections log (`~/.claude/tasks/lessons.md`)

**When:** the user corrects a mistake — wrong approach, wrong assumption, style violation,
misunderstood requirement, etc. Append an entry **immediately**, before moving on. Create the
file and its parent directory if they do not exist.

**Entry template:**

```markdown
## YYYY-MM-DD — <short description of the mistake>

- **Project:** <absolute path of current working directory, or "global" if the user says it
  applies across all projects>
- **Mistake:** <one sentence — what I did wrong>
- **Correction:** <what the user said or did to fix it>
- **Rule:** <an imperative rule that prevents this mistake — "Never…" or "Always…">
- **Why:** <one sentence explaining the underlying reason>
```

**Scope:** default to the current project (absolute path). Escalate to `global` only when the
user explicitly says it applies everywhere.

**Iteration discipline:**
- After writing a lesson, re-read the last five entries for the current project; if any is now
  violated again, add a `**Recurrence:** <date> — still happening` line and tighten the rule.
- If the same mistake recurs **three or more times**, promote it to a top-level rule in the
  project's `CLAUDE.md` (or the global one if scoped globally) and mark the entry
  `**Promoted:** YYYY-MM-DD`.
- Never delete or archive lessons — accumulate them so trends stay visible.

*(Session-start surfacing of this file is emitted by the `session_start_context.sh` hook, not
this skill.)*

---

## System 2 — Generalizable backport stores (capture before moving on)

**When:** work in **any project** yields a *generalizable* improvement — a reusable seam,
tooling, convention, guardrail, command/skill/agent/rule/hook/config/installer change — **not**
a project-specific business rule. Capture it **before moving on**.

There are two stores with different backport targets. **Route by where the fix ultimately
lands, never by what the lesson is about.**

### Which store?

- Fix edits a **scaffolding template** under `~/github/blueprintx/templates/` (changes what a
  *generated project* contains — source seams, `pyproject.toml`, `.gitignore`, CI, `Makefile`,
  `.pre-commit-config.yaml`, `mkdocs.yml`, docs, a baked-in convention)
  → **BlueprintX store** `~/.claude/memory/lessons/`.
  Format: `# Title` then `Tier / Lesson / Why / Scaffold into / Origin`. Tier ∈
  `language-common`, `python-common`, `language-specific (<lang>)`, or a scaffolding tier
  (`mvc-*`, `ddd-*`, `react-*`, …). Backport target: `~/github/blueprintx/templates/`.

- Fix edits the **Claude/dotfiles toolchain** under `~/github/dotfiles-dev/ai_clients/claude/`
  (a slash command, skill, agent, rule, hook, global `CLAUDE.md` rule, `settings*.json`, or
  installer — changes how *Claude itself* behaves across every project)
  → **dotfiles-dev store** `~/.claude/memory/lessons-dotfiles/`.
  Format: `# Title` then `Area / Lesson / Why / Apply to (dotfiles-dev) / PR / Origin`.
  Backport target: `~/github/dotfiles-dev/ai_clients/claude/`, each landing via its own PR.

**Decision test** — ask *"how does a fresh environment inherit this fix?"*: via **scaffolding a
new project** → BlueprintX; via **reinstalling the Claude toolchain (`make ai_clients`)**,
surviving across all projects → dotfiles-dev.

A lesson *about* the dotfiles toolchain whose fix lands in a **template** is a **BlueprintX**
lesson; a hook that helps *capture* scaffold lessons is a **dotfiles-dev** lesson. If one
finding needs changes in **both** a template and the toolchain, write **two** lessons, one per
store, cross-referencing. Misrouting parks a fix in a queue that never applies it.

### Steps for either store

1. Save it as **one file per lesson** (kebab-case) in the store, using that store's format.
2. Add it to the store's `README.md` index.
3. Mirror it in the originating repo as a **git-ignored**, docs-site-excluded note
   (`docs/blueprintx-lessons.md` or `docs/dotfiles-dev-lessons.md`) — *unless* the origin repo
   **is** the backport target repo, where the same-repo mirror is redundant (skip it).
4. Later, apply the captured lessons to the backport target so future work inherits them.

Full conventions: `~/.claude/memory/lessons/README.md` and
`~/.claude/memory/lessons-dotfiles/README.md`.
