# AI Clients Two-Level Menu Design

**Date:** 2026-04-03
**Status:** Approved

## Overview

Refactor `ai_clients/` to support a two-level interactive menu: first pick an AI client (Claude, others, all), then pick which setup steps to run within that client. A new top-level `ai_clients/main.sh` acts as a thin router; each client's `main.sh` remains fully self-contained and owns its own step menu.

## Architecture

### File Structure

```
ai_clients/
  lib/
    utils.sh            ← NEW: shared colors, print_status, LOG_FILE (moved from claude/lib/)
  main.sh               ← NEW: top-level router — discovers clients, delegates
  claude/
    main.sh             ← UPDATED: sources ../../lib/utils.sh; defines CLAUDE_DIR locally
    lib/
      utils.sh          ← DELETED: replaced by shared ai_clients/lib/utils.sh
      prerequisites.sh
      settings.sh
      marketplaces.sh
      plugins.sh
      slash_commands.sh
      claude_md.sh
      rules.sh
    settings.json
```

The Makefile `ai_clients` target changes from:
```bash
bash ai_clients/claude/main.sh all
```
to:
```bash
bash ai_clients/main.sh all
```

### Client Discovery

`ai_clients/main.sh` auto-discovers clients by globbing `ai_clients/*/main.sh`. The directory name is used as the client key (e.g. `claude`). Display names are derived by capitalising the directory name; a simple lookup map can override this (e.g. `claude` → `Claude Code`).

Adding a new client requires only dropping a new subdirectory with a `main.sh` — no changes to the router.

### Shared Utilities

`ai_clients/lib/utils.sh` contains:
- Color variables (`RED`, `GREEN`, `YELLOW`, `BLUE`, `CYAN`, `MAGENTA`, `NC`)
- `print_status` function
- `LOG_FILE` variable

`CLAUDE_DIR` is Claude-specific and moves from `claude/lib/utils.sh` into `claude/main.sh` directly.

## CLI Contract

| Invocation | Behaviour |
|---|---|
| `./main.sh` | Interactive client menu |
| `./main.sh all` | Run all discovered clients non-interactively (passes `all` to each) |
| `./main.sh claude` | Delegate to `claude/main.sh` with no args → Claude's interactive step menu |
| `./main.sh claude all` | Delegate to `claude/main.sh all` → all Claude steps |
| `./main.sh claude settings rules` | Delegate to `claude/main.sh settings rules` |

## Menu Flow

**Level 1 — client selection (interactive):**

```
========================================
 AI CLIENTS SETUP — Select client
========================================

  1) Claude Code
  a) All of the above
  q) Quit

Enter choice:
```

After selecting a client, delegates to `<client>/main.sh` with no args, which shows Level 2.

**Level 2 — step selection (owned by each client's `main.sh`):**

Claude's existing step menu is unchanged:
```
  1) Configure settings.json
  2) Install custom slash commands
  3) Install global CLAUDE.md
  4) Install language rules
  5) Register plugin marketplaces
  6) Promote plugins to user scope
  a) All of the above
  q) Quit
```

## Error Handling

- **No clients found** — print error, exit 1 (guards against running from wrong directory).
- **Unknown client arg** — print error listing valid clients, exit 1.
- **Client failure** — exit code propagates; `set -e` stops execution at first failure.
- **`all` with a failing client** — stops at first failing client (fail-fast).
- **Standalone client** — `claude/main.sh` works when called directly; shared utils path resolves correctly via relative `../../lib/utils.sh`.

## Out of Scope

- Per-client prerequisite checks at the router level (each client checks its own).
- A `--list-steps` introspection interface (not needed for this design).
- Parallel client execution.
