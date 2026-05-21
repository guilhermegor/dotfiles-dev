# ai_clients/CLAUDE.md

Context for creating or editing anything inside this directory.

## What this directory is

Source tree for AI client configurations. `make ai_clients` runs
`ai_clients/claude/main.sh`, which copies files from this tree into
`~/.claude/` via the lib scripts in `ai_clients/claude/lib/`.

Only `ai_clients/claude/` is wired up today. New clients follow the same
pattern: add `ai_clients/<name>/main.sh` and it is auto-discovered by
`ai_clients/main.sh`.

## The restore-`.env` prompt

`ai_clients/lib/restore_env_prompt.sh` defines `prompt_restore_env()`, which
asks `[y/N]` whether to restore git-ignored `.env` files from an external
backup drive. On yes it runs `~/.local/bin/restore-env.sh` if installed,
otherwise falls back to the in-repo `storage/restore_env.sh`.

It fires at the top of `ai_clients/main.sh`'s `main()`, and also as the
`make restore_env_prompt` target, which `make init` runs *first* so that
`install_programs` / `install_coding` can read restored `.env` values. The
`init` target exports `DOTFILES_INIT_IN_PROGRESS=1`; `main.sh` checks it and
skips its own prompt during an `init` run to avoid asking twice. This helper
is **not** a `claude/main.sh` STEPS-registry step — it is client-agnostic and
must run before client discovery.

## Three artifact types

### 1. Commands (slash commands)

| | |
|---|---|
| **Source** | `ai_clients/claude/commands/<name>.md` |
| **Installs to** | `~/.claude/commands/<name>.md` |
| **Lib script** | `lib/slash_commands.sh` → `install_slash_commands()` |
| **Invoked by user as** | `/name` (filename without `.md`) |

**Required frontmatter fields:**

```yaml
---
name: c:<kebab-name>          # c: namespace prefix is mandatory
allowed-tools: Bash(...), Read, Glob, Grep   # whitelist only what the command needs
description: <one-line, user-visible>
argument-hint: <hint shown in autocomplete>  # optional but recommended
---
```

**Writing conventions:**
- Open with `You are <doing X> for this repository. Follow these steps exactly.`
- Number steps sequentially (`## 1.`, `## 2.`, …); sub-steps use `## Na.`
- Reference user input as `$ARGUMENTS`; always handle the empty-arguments case
- Bash commands shown inline use backtick blocks; use `!cmd` notation for
  commands the model should run in the conversation
- `allowed-tools` must use glob patterns for Bash (`Bash(git diff*)`) —
  never `Bash(*)` (too broad)
- No trailing `Co-Authored-By` footers unless explicitly requested

### 2. Agents (subagent definitions)

| | |
|---|---|
| **Source** | `ai_clients/claude/agents/<name>.md` |
| **Installs to** | `~/.claude/agents/<name>.md` |
| **Lib script** | `lib/agents.sh` → `install_agents()` |
| **Invoked by user as** | `a:<name>` (via the `name` field) |

**Required frontmatter fields:**

```yaml
---
name: a:<kebab-name>          # a: namespace prefix is mandatory
description: <one-line trigger description>
model: sonnet                 # sonnet | opus | haiku
color: green                  # green | blue | yellow | red | purple
memory: true                  # persist memory across invocations
disable-model-invocation: true
effort: high                  # low | medium | high
argument-hint: [hint]
---
```

**Writing conventions:**
- Agents orchestrate skills (`/s:skill-name`) and other commands — they do
  not implement logic themselves
- Always start by asking for any required inputs not already in `$ARGUMENTS`
- Define explicit checkpoints (`### --- Checkpoint N ---`) where the agent
  pauses for user confirmation before continuing
- End with a structured `## Final summary` block
- Include a `## Do Not` section listing prohibited behaviors
- Use `## Memory` section when `memory: true` to define what to persist

### 3. Skills (mid-task reference guides)

| | |
|---|---|
| **Source** | `ai_clients/claude/skills/<name>.md` |
| **Installs to** | `~/.claude/skills/<name>.md` |
| **Lib script** | `lib/skills.sh` → `install_skills()` |
| **Invoked** | Loaded by Claude's Skill tool mid-task (not user-invoked) |

**Required frontmatter fields:**

```yaml
---
name: s:<kebab-name>          # s: namespace prefix is mandatory
description: Use when <specific triggering conditions — no workflow summary>
effort: high                  # low | medium | high
argument-hint: [hint]
allowed-tools: Read Glob Grep  # space-separated for skills (no commas)
---
```

**Writing conventions:**
- Description must start with "Use when…" and describe *when* to load the
  skill, never *what* the skill does — Claude reads the description to decide
  whether to load it; a workflow summary causes Claude to follow the
  description instead of reading the skill body
- Skills are read-only reference guides by default; add `allowed-tools` only
  if the skill legitimately needs to run commands
- Keep total token count low — skills load into every conversation that
  triggers them

## Namespace prefixes (summary)

| Prefix | Type | Invocation |
|--------|------|------------|
| `c:` | Command | `/c:name` by user |
| `a:` | Agent | `a:name` in task list |
| `s:` | Skill | Loaded by Skill tool |

## File naming standard

Filenames (without `.md`) follow the pattern **`<tool>-<action>`** or
**`<language>-<action>`**, where the prefix identifies the primary tool or
language the artifact targets:

| Prefix | Targets | Examples |
|--------|---------|---------|
| `py-` | Python language | `py-audit`, `py-create`, `py-unit-test` |
| `bash-` | Bash scripts | `bash-create` |
| `gh-` | GitHub CLI (`gh`) | `gh-create-pr` |
| `git-` | Git commands | `git-rebase` (hypothetical) |
| `design-` | Cross-tier design-family primitives (tokens, interview, exports) shared across the three design tiers | `design-color-system`, `design-token-export`, `design-write-language` |
| `brand-` | Brand-tier–specific concerns (identity, voice, logo, brand book assembly) | `brand-identity`, `brand-logo-imagery`, `brand-write-book` |

**Rules:**
- Use the tool/CLI name as prefix when the skill wraps a specific external
  tool (e.g. `gh`, `git`, `docker`).
- Use the language name as prefix when the skill targets a programming
  language workflow (e.g. `py`, `bash`).
- The action segment is a short imperative verb phrase: `create`, `audit`,
  `unit-test`, `create-pr`.
- Never use a bare action without a prefix (e.g. `create-pr.md` is wrong;
  `gh-create-pr.md` is correct).
- The `name` field in frontmatter follows the same pattern with the
  namespace prefix: `s:gh-create-pr`, `s:py-audit`, `c:commit-code`.

## Design family (3-tier agent architecture)

The repo ships **three independent agents** that mirror the three deliverables
of a professional design org. They share a foundation library of `design-*`
skills and compose through on-disk artifacts — never through agent-to-agent
calls.

### Tiers

| Tier | Agent | Output | Machine export |
|---|---|---|---|
| Brand | `a:brand-design` | `design/brand/brand-book.md` (prose-first identity manual + 5-colour identity palette + 1–3 typefaces) | none |
| Language | `a:design-language` | `design/language/<purpose>.md` (foundation tokens + Overview/Colors/Type/Layout/Elevation/Motion/Responsive prose) | `tokens.*.json` + `theme.css` |
| System | `a:design-system` | `design/system/<purpose>.md` (foundations + components-with-`states:` + themes + accessibility audit + governance/changelog) | `tokens.*.json` + `theme.css` |

Tiers conceptually nest (system ⊃ language ⊃ brand), but agents stay
independent. Each higher tier's `s:design-interview` checks disk for a
lower tier's artifact and offers to reuse it; if absent, it gathers
what it needs itself.

### Skill split

- **`design-*` skills** — tier-neutral primitives reused across language
  and system tiers (and lightly by brand): `design-interview`,
  `design-color-system`, `design-type-system`, `design-layout-system`,
  `design-motion-system`, `design-component-system`,
  `design-accessibility-audit`, `design-theming`, `design-governance`,
  `design-token-export`. Plus per-tier writers `design-write-language`
  and `design-write-system`.
- **`brand-*` skills** — brand-tier–specific: `brand-identity`,
  `brand-logo-imagery`, `brand-write-book`. The brand tier owns its own
  palette + typeface picks at identity level; the full token scale
  lives in design-language.

### Runtime choices

Format/behavior decisions are deferred to the *runtime user*, not baked in:

- `s:design-token-export` asks **which JSON shape(s)** to emit (W3C DTCG /
  flat namespaced / Style Dictionary) and **which CSS naming** to use
  (dot-flattened / path-preserved / Tailwind v4 `@theme`).
- `s:design-color-system` asks **WCAG verification mode** (flag-only /
  auto-suggest replacements / skip).
- `s:design-theming` asks **which theme variants** to generate (dark /
  high-contrast / compact / none).

### Output directory layout

```
design/
├── brand/
│   └── brand-book.md
├── language/
│   ├── <purpose>.md
│   ├── tokens.dtcg.json        (per export selection)
│   ├── tokens.flat.json
│   ├── tokens.style-dictionary.json
│   └── theme.css
└── system/
    ├── <purpose>.md
    ├── tokens.*.json
    └── theme.css
```

`<purpose>` is the kebab-case surface slug (e.g. `web-app`, `app-cellphone`,
`dashboard`, `ecommerce`). The brand book is per-brand (one file, no
purpose suffix); language and system docs are per-purpose.

### Do-not list (architecture invariants)

- Agents never invoke each other. Reuse is always via on-disk artifacts
  read by `s:design-interview`.
- The brand tier never produces a full token scale or component spec —
  those belong to language and system respectively.
- The language tier never produces a `components:` block — components
  are the system tier's concern.
- The markdown frontmatter is the canonical source of truth for tokens.
  JSON / CSS exports are pure derivations emitted by `s:design-token-export`.

## Deployment

```bash
make ai_clients        # interactive menu (choose steps individually)
# or via main.sh directly:
./ai_clients/claude/main.sh slash_commands   # install only commands
./ai_clients/claude/main.sh skills           # install only skills
./ai_clients/claude/main.sh agents           # install only agents
./ai_clients/claude/main.sh all              # install everything
```

## Adding a new step to the orchestrator

1. Create the lib function in `ai_clients/claude/lib/<step>.sh`
2. Source it in `ai_clients/claude/main.sh`
3. Add `"key|Label"` to the `STEPS` array
4. Add a `case` branch in `dispatch_step()`

## Commit message constraints (gitlint)

This repo enforces gitlint. Commits must satisfy:

- Title line: ≤ **72 characters** (including `type(scope): `)
- Body lines: ≤ **80 characters** each (including `  - ` prefix and ` → file` suffix)
- Measure with `echo -n "..." | wc -c` before committing; never estimate
