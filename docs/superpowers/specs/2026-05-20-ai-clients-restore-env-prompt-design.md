# Restore-`.env` prompt for `make init` and `make ai_clients`

**Date:** 2026-05-20
**Author:** brainstorming session with Claude Opus 4.7
**Status:** approved by user

## Problem

On a fresh Ubuntu install, the repo's `.env` files (one per project) do not
exist — `.gitignore` excludes them by design. The user keeps timestamped
backups on an external drive and has a working restore flow already wired
to `Super+Alt+E` (`$HOME/.local/bin/restore-env.sh`, sourced from
`storage/restore_env.sh`).

But `make init` runs `setup_env → install_programs → install_coding →
ai_clients`. Several `install_*` functions read `.env` values
(license keys, API credentials, paid-app activation tokens). If `.env`
is absent at that point, those installs silently skip or fail. The user
wants a prompt at the *start* of the run that asks whether to restore
from the external drive first.

The user explicitly framed this as part of `make ai_clients`, but also
agreed that running it earlier in `make init` is the right call — the
prompt should fire in both flows, gated by a one-shot idempotency env var
so chained `init → ai_clients` runs don't double-ask.

## Design

### Files touched

| File | Change |
|---|---|
| `ai_clients/lib/restore_env_prompt.sh` | **NEW** — defines `prompt_restore_env()` |
| `ai_clients/main.sh` | sources the helper and calls `prompt_restore_env` at the top of `main()` |
| `Makefile` | new phony target `restore_env_prompt`; `init` depends on it before any other step |

### Helper contract

`prompt_restore_env()` is a single bash function with these responsibilities:

1. **Prompt.** Read a `[y/N]` answer. Default is "no" — bare Enter skips.
2. **Dispatch on yes.** Resolve the restore command in this priority:
   - If `$HOME/.local/bin/restore-env.sh` is executable → run it directly.
   - Else if `<repo_root>/storage/restore_env.sh` is a regular file →
     `bash <repo_root>/storage/restore_env.sh`.
   - Else → print an error via `print_status "error"` and return non-zero
     **without** aborting the larger make flow.
3. **Repo-root discovery.** The helper derives `<repo_root>` from
   `$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)` so it works whether
   sourced from `ai_clients/main.sh` or invoked via `bash ai_clients/lib/restore_env_prompt.sh`.

The helper itself is unconditional. Idempotency lives at the *call sites*,
not inside the function — see the next section.

### Idempotency across `make init`

Each `make` recipe spawns a fresh sub-shell. An env var exported inside the
helper would not survive from the `restore_env_prompt` recipe to the later
`ai_clients` recipe. So we declare the flag on the `init` target itself:

```makefile
init: export DOTFILES_INIT_IN_PROGRESS=1
init: restore_env_prompt permissions setup_env install_programs install_coding ai_clients …
```

Make injects `DOTFILES_INIT_IN_PROGRESS=1` into every recipe `init` depends on.
`ai_clients/main.sh` then gates its own call:

```bash
main() {
    [[ -z "$DOTFILES_INIT_IN_PROGRESS" ]] && prompt_restore_env
    local clients=()
    …
}
```

| Invocation | `DOTFILES_INIT_IN_PROGRESS` | Behaviour |
|---|---|---|
| `make ai_clients` | unset | `ai_clients/main.sh` prompts |
| `bash ai_clients/main.sh` | unset | prompts |
| `make init` → `restore_env_prompt` recipe | `1` (set by `init`) | helper still prompts — that's the whole point of this recipe |
| `make init` → `ai_clients` recipe | `1` | `main.sh` skips the prompt; `restore_env_prompt` already asked earlier |
| `make restore_env_prompt` standalone | unset | helper prompts (re-ask after plugging in a drive) |

### Wiring

**`ai_clients/main.sh`:**
```bash
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/restore_env_prompt.sh"   # NEW
…
main() {
    [[ -z "$DOTFILES_INIT_IN_PROGRESS" ]] && prompt_restore_env  # NEW
    local clients=()
    mapfile -t clients < <(discover_clients)
    …
}
```

**`Makefile`:**
```makefile
.PHONY: restore_env_prompt
restore_env_prompt:  ## Ask whether to restore .env files from external backup drive
	@bash ai_clients/lib/restore_env_prompt.sh

init: export DOTFILES_INIT_IN_PROGRESS=1
init: restore_env_prompt permissions setup_env install_programs install_coding ai_clients …
```

`ai_clients/lib/restore_env_prompt.sh` becomes invokable two ways:

| Caller | Path used |
|---|---|
| `make restore_env_prompt` and `make init` | `bash ai_clients/lib/restore_env_prompt.sh` — file is also the script entry point; runs `prompt_restore_env` when executed directly |
| `ai_clients/main.sh` (sourced) | Calls `prompt_restore_env` after sourcing |

To support both modes, the file ends with:
```bash
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    prompt_restore_env
fi
```

### Failure modes

| Condition | Behaviour |
|---|---|
| User answers no (default) | Print "Skipping .env restore." and return 0. |
| `~/.local/bin/restore-env.sh` exists, runs, exits non-zero | The helper returns that exit code. `make` continues — Makefile recipe does **not** prefix with `-` to suppress, but the function returns rather than aborting the larger flow. |
| Neither path exists | Print error and return 1. `make init` continues (the prompt step is best-effort). |
| Run twice in same `make init` (chained recipes) | `ai_clients/main.sh` sees `$DOTFILES_INIT_IN_PROGRESS=1` exported by the `init` target and skips its own prompt. The `restore_env_prompt` recipe still runs once — that's where the question is asked. |

### Out of scope

- **Backup prompt.** The mirror `c:backup-env` flow is *not* added here.
  This spec is restore-only.
- **External-drive auto-detection.** Already handled inside `storage/restore_env.sh`
  and `c:restore-env`; the prompt just delegates.
- **Schema validation of restored `.env`.** Not this PR's problem.
- **Adding a second prompt later in the flow** for projects added after
  the initial restore — `make ai_clients` standalone already covers that
  case via the same helper.

## Acceptance criteria

1. Running `make init` on a fresh checkout asks once: `Restore .env files
   from an external drive? [y/N]:`.
2. Pressing Enter (or typing `n`) skips and continues with `permissions`.
3. Typing `y` runs the installed binary if present, else the repo fallback.
4. Running `make ai_clients` standalone asks the same question.
5. Running `make init` does **not** ask twice when it later invokes `ai_clients`.
6. Running `make restore_env_prompt` standalone is also valid (re-ask after
   plugging in a drive that wasn't mounted earlier).

## Notes from session

- The user's first phrasing was "backup the .env files from an external
  hard drive", but in context they meant *restore from* — confirmed during
  brainstorming.
- The keybinding was given as `Super+Alt+W`; the actual binding in
  `distro_config/set_custom_shortcuts.sh:475` is `Super+Alt+E`. Treated as
  a typo and confirmed with the user.
