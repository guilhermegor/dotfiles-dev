# ai_clients/CLAUDE.md

Context for creating or editing anything inside this directory.

## What this directory is

Source tree for AI client configurations. `make ai_clients` runs
`ai_clients/claude/main.sh`, which copies files from this tree into
`~/.claude/` via the lib scripts in `ai_clients/claude/lib/`.

Only `ai_clients/claude/` is wired up today. New clients follow the same
pattern: add `ai_clients/<name>/main.sh` and it is auto-discovered by
`ai_clients/main.sh`.

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
