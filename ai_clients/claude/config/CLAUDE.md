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

## Author Claude artifacts in dotfiles-dev, never only in live `~/.claude/`

Durable Claude artifacts (commands, skills, agents, rules, hooks, global
`CLAUDE.md`, settings) must be authored in the version-controlled source under
`~/github/dotfiles-dev/ai_clients/claude/`, then deployed with `make ai_clients`
(or `cp` into place). Never write them only to `~/.claude/` — it is machine-local
and non-symlinked, so direct edits are lost on the next OS/distro install.

Enforced by the `claude_artifact_source_guard.sh` PreToolUse hook: a direct
Write/Edit into `~/.claude/{commands,skills,agents,rules,hooks}/` or `CLAUDE.md`
is blocked and redirected to its source. Exempt (written live on purpose):
project-scoped `.claude/`, project memory, `tasks/`, `plans/`, `settings*.json`.
Full source-path table: `ai_clients/CLAUDE.md`.

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

## Version Control

- Conventional Commits: `feat:`, `fix:`, `chore:`, `test:`, `docs:`, `refactor:`.
- Atomic commits: one logical change per commit.
- Never commit secrets, credentials, or local config files.
- `.gitignore` before first commit.
- **Never `git commit` or `git push` without an explicit user request** — this applies universally, not just after spec/plan docs. Staging (`git add`) is fine, but always stop and confirm before committing or pushing. Pre-commit hooks are slow and pushes are irreversible from the user's perspective.

## Tutoring — resume before replacing

When the user asks Claude to "resume tutoring", "continue tutoring",
"pick up where we left off", or anything semantically equivalent —
**including in plain natural language, not only via `/tutoring on`** —
Claude MUST treat in-progress work as the source of truth and look for
it before generating any new curriculum.

Mandatory discovery sequence, in order:

1. **Project memory file.** Compute the encoded project memory path:
   `pwd | sed 's|/|-|g'` → `~/.claude/projects/<encoded>/memory/`.
   If `tutoring_session.md` exists there, read it and resume from the
   step marked `[>]`. Do not rewrite it from scratch and do not invent
   a new step list.
2. **Active plan file.** If `tutoring_session.md` is missing or empty,
   scan `~/.claude/plans/*.md` for any plan whose body references the
   current working directory, the repo name, or the project's
   `CLAUDE.md` topic. If a match is found, use **its** task/step list as
   the curriculum and resume from the first unchecked item. Linking back
   to that plan in `tutoring_session.md` is fine; replacing its content
   with an invented parallel list is not.
3. **Only if both checks fail** may a fresh curriculum be generated, and
   only after explicit user confirmation ("yes, start from scratch").

This rule overrides any default tendency to begin with a clean slate.
It applies regardless of which slash command (or none) triggered the
session, and regardless of the model handling the conversation.

**Why:** prior tutoring sessions encode the user's chosen step
ordering, completed work, accumulated feedback, and recurring-issue
notes. Inventing a new step list silently throws all of that away and
forces re-work. The `/tutoring on` command's step 2b implements this
check too; this section makes the same discipline mandatory for the
natural-language path.

## Self-Improvement Loop

### Session start

At the start of every session, read `~/.claude/tasks/lessons.md` (if it
exists) and surface any entries whose **Scope** matches the current working
directory or is `global`. Apply those rules immediately — do not wait to be
reminded.

### After a user correction

Whenever the user corrects a mistake (wrong approach, wrong assumption, style
violation, misunderstood requirement, etc.), immediately append an entry to
`~/.claude/tasks/lessons.md` using the template below. Create the file and
its parent directory if they do not exist.

**Entry template:**

```markdown
## YYYY-MM-DD — <short description of the mistake>

- **Project:** <absolute path of current working directory, or "global" if
  the user says it applies across all projects>
- **Mistake:** <one sentence — what I did wrong>
- **Correction:** <what the user said or did to fix it>
- **Rule:** <an imperative rule that prevents this mistake — "Never…" or
  "Always…">
- **Why:** <one sentence explaining the underlying reason>
```

**Scope decision:**
- Default scope is the current project (use its absolute path).
- Escalate to `global` only when the user explicitly says the lesson applies
  everywhere (e.g. "don't do that in any project").

### Iteration discipline

- After writing a lesson, re-read the last five entries for the current
  project and check whether any of them have now been violated again. If so,
  add a `**Recurrence:** <date> — still happening` line to the original entry
  and tighten the rule wording.
- If the same mistake recurs three or more times, promote it to a top-level
  rule in the project's `CLAUDE.md` (or the global one if scoped globally) and
  mark the lessons.md entry `**Promoted:** YYYY-MM-DD`.
- Never delete or archive lessons — accumulate them so pattern trends are
  visible over time.

## Scaffolding lessons — capture before moving on (standing instruction)

When work in **any BlueprintX-scaffolded repo** (`mvc-*`, `ddd-*`, `react-*`, and any
future tier) yields a **generalizable** change — a reusable seam, tooling, convention,
or guardrail, *not* a project-specific business rule — capture it **before moving on**:

1. Save it in the global store `~/.claude/memory/lessons/` as **one file per lesson**
   (kebab-case), in the format `# Title` then `Tier / Lesson / Why / Scaffold into /
   Origin`, and add it to that store's `README.md` index. Tier is one of
   `language-common`, `python-common`, `language-specific (<lang>)`, or a scaffolding
   tier (`mvc-*`, `ddd-*`, `react-*`, …).
2. Mirror it in the originating repo's `docs/blueprintx-lessons.md`, kept
   **git-ignored** and **excluded from the docs site** (untracked whenever the repo has
   a remote, so the internal note never ships).

Later, apply the captured lessons to the BlueprintX templates at
`~/github/blueprintx/templates/` so future scaffolds inherit them instead of
rediscovering them. Full convention: `~/.claude/memory/lessons/README.md`. This is
**global — it applies to every project**, not one repo.

## dotfiles-dev toolchain lessons — capture before moving on (standing instruction)

When work in **any project** yields a generalizable improvement to the **Claude / dotfiles
toolchain** — a reusable slash command, skill, agent, rule, hook, global `CLAUDE.md` rule, or
installer change, *not* a project-specific business rule — capture it **before moving on**:

1. Save it in the global store `~/.claude/memory/lessons-dotfiles/` as **one file per lesson**
   (kebab-case), in the format `# Title` then `Area / Lesson / Why / Apply to (dotfiles-dev) /
   PR / Origin`, and add it to that store's `README.md` index.
2. Mirror it in the originating repo's `docs/dotfiles-dev-lessons.md`, kept **git-ignored** and
   **excluded from the docs site** (never ships).

Later, apply the captured lessons to the dotfiles-dev source at
`~/github/dotfiles-dev/ai_clients/claude/` (per the "Author Claude artifacts in dotfiles-dev"
rule above), each landing via its own dotfiles-dev PR. This is the toolchain analogue of the
BlueprintX "Scaffolding lessons" instruction — that one feeds templates, this one feeds the
dotfiles-dev toolchain. Full convention: `~/.claude/memory/lessons-dotfiles/README.md`.
**Global — it applies to every project**, not one repo.

### Which store? Route by where the fix lands, not by the topic

The two "capture before moving on" instructions above feed **different** backport
targets with **different** inheritance mechanisms. Pick the store by the **artifact
the fix ultimately edits**, never by what the lesson is *about*:

- Fix edits a **scaffolding template** under `~/github/blueprintx/templates/` (changes
  what a *generated project* contains — source seams, `pyproject.toml`, `.gitignore`,
  CI, `Makefile`, `.pre-commit-config.yaml`, `mkdocs.yml`, docs, a baked-in convention)
  → **BlueprintX store** `~/.claude/memory/lessons/`.
- Fix edits the **Claude/dotfiles toolchain** under
  `~/github/dotfiles-dev/ai_clients/claude/` (a slash command, skill, agent, rule,
  hook, global `CLAUDE.md` rule, `settings*.json`, or installer — changes how *Claude
  itself* behaves across every project) → **dotfiles-dev store**
  `~/.claude/memory/lessons-dotfiles/`.

**Decision test** — ask *"how does a fresh environment inherit this fix?"*: via
**scaffolding a new project** → BlueprintX; via **reinstalling the Claude toolchain
(`make ai_clients`)**, surviving across all projects → dotfiles-dev.

**Route by landing site, not subject.** A lesson *about* the dotfiles toolchain whose
fix lands in a **template** (e.g. "scaffold ships a git-ignored lessons mirror") is a
**BlueprintX** lesson; a hook that helps *capture* scaffold lessons is a **dotfiles-dev**
lesson — it lands in `ai_clients/claude/`. If one finding genuinely requires changes in
**both** a template and the toolchain, write **two** lessons, one per store,
cross-referencing. Misrouting parks a fix in a queue that never applies it.

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
