# Restore-`.env` Prompt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `[y/N]` prompt that offers to restore git-ignored `.env` files from an external backup drive before downstream installs run — firing at the start of both `make init` and `make ai_clients`.

**Architecture:** One sourced-or-executed bash helper (`ai_clients/lib/restore_env_prompt.sh`) defines `prompt_restore_env()`. `ai_clients/main.sh` sources it and calls it at the top of `main()`, gated by `$DOTFILES_INIT_IN_PROGRESS` so the `make init` chain doesn't double-ask. The `Makefile` exposes a `restore_env_prompt` target, makes `init` depend on it first, and exports the gate flag for the whole `init` dependency tree.

**Tech Stack:** Bash 5, GNU Make, `shellcheck 0.11.0`, `print_status` from `lib/common.sh`.

**Verification model:** This repo has **no unit-test framework** ("scripts are run directly" — CLAUDE.md). The red/green equivalent here is: (1) `shellcheck --severity=warning --exclude=SC1091 <file>` + `bash -n <file>` must pass, and (2) a non-interactive functional run with piped stdin must produce the expected observed output. Both are runnable commands with expected output, shown in every task.

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `ai_clients/lib/restore_env_prompt.sh` | Defines `prompt_restore_env()`; runs it when executed directly | **Create** |
| `ai_clients/main.sh` | Source helper; call it (gated) at top of `main()` | **Modify** (`~line 15`, `~line 100`) |
| `Makefile` | `restore_env_prompt` target; `init` dep + exported gate flag | **Modify** (`.PHONY` line 179, `init` line 18) |
| `ai_clients/CLAUDE.md` | One-paragraph note documenting the prompt | **Modify** |

**Boundary rationale:** The helper is self-contained — it knows how to find the repo root, how to resolve the restore command, and how to ask. `main.sh` owns only the *gating decision* (am I being run by `init`?). The `Makefile` owns only *flag propagation*. No responsibility is split across two files.

**Why not the `claude/main.sh` STEPS registry:** The prompt must run before client discovery and regardless of which client/steps are chosen, so it belongs at the `ai_clients/main.sh` top-level `main()`, not as a per-client step. The STEPS-registry docs in `ai_clients/CLAUDE.md` therefore do not apply here.

---

## Task 1: Create the `prompt_restore_env` helper

**Files:**
- Create: `ai_clients/lib/restore_env_prompt.sh`

- [ ] **Step 1: Write the helper**

Create `ai_clients/lib/restore_env_prompt.sh` with exactly this content:

```bash
#!/bin/bash
#
# ai_clients/lib/restore_env_prompt.sh
#
# Offers to restore git-ignored .env files from an external backup drive
# before downstream installs run. On a fresh Ubuntu install the per-project
# .env files do not exist (they are git-ignored), so installs that read .env
# values would otherwise run without them.
#
# Dual-mode: sourced by ai_clients/main.sh (which calls prompt_restore_env
# itself, gated by $DOTFILES_INIT_IN_PROGRESS) AND executed directly by
# `make restore_env_prompt` / `make init` (runs the prompt on execution).

_rep_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$_rep_dir/../.." && pwd)"
unset _rep_dir

# When executed standalone, print_status is not yet defined — pull it in.
# When sourced by ai_clients/main.sh (after utils.sh), it already exists,
# so this avoids a redundant second source of lib/common.sh.
if ! declare -F print_status >/dev/null 2>&1; then
    # shellcheck source=../../lib/common.sh
    source "$REPO_ROOT/lib/common.sh"
fi

# Ask whether to restore .env files; on yes, delegate to the installed
# restore-env.sh binary, falling back to the in-repo storage/restore_env.sh.
# Default is no (bare Enter skips). Never aborts the caller — returns instead.
prompt_restore_env() {
    local reply
    read -rp "Restore .env files from an external drive? [y/N]: " reply
    if [[ ! "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        print_status "info" "Skipping .env restore."
        return 0
    fi

    local installed="$HOME/.local/bin/restore-env.sh"
    local fallback="$REPO_ROOT/storage/restore_env.sh"

    if [[ -x "$installed" ]]; then
        print_status "info" "Running $installed"
        "$installed"
    elif [[ -f "$fallback" ]]; then
        print_status "warning" "$installed not found; running repo fallback"
        bash "$fallback"
    else
        print_status "error" "No restore-env script found. Skipping."
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    prompt_restore_env
fi
```

- [ ] **Step 2: Lint — verify shellcheck and parse both pass (the "green" gate)**

Run:
```bash
shellcheck --severity=warning --exclude=SC1091 ai_clients/lib/restore_env_prompt.sh && \
bash -n ai_clients/lib/restore_env_prompt.sh && echo "LINT OK"
```
Expected: `LINT OK` with no warnings above it.

- [ ] **Step 3: Functional test — default-no path**

Run (pipe an empty line = bare Enter):
```bash
printf '\n' | bash ai_clients/lib/restore_env_prompt.sh
```
Expected: output contains `Skipping .env restore.` and the command exits 0.

- [ ] **Step 4: Functional test — yes path resolves a script**

Run (pipe `y`):
```bash
printf 'y\n' | bash ai_clients/lib/restore_env_prompt.sh ; echo "exit=$?"
```
Expected: it does **not** print `No restore-env script found` — instead it
prints either `Running .../restore-env.sh` (if the binary is installed) or
`... not found; running repo fallback` followed by `storage/restore_env.sh`'s
own prompts. `storage/restore_env.sh` exists in-repo, so the fallback branch
is always reachable. (You may Ctrl-C out of the restore script's own prompts;
the point is the dispatch branch was taken, not completing a restore.)

- [ ] **Step 5: Commit**

```bash
git add ai_clients/lib/restore_env_prompt.sh
git commit -m "feat(ai_clients): add restore-env prompt helper"
```

---

## Task 2: Wire the helper into `ai_clients/main.sh`

**Files:**
- Modify: `ai_clients/main.sh:15` (add source line)
- Modify: `ai_clients/main.sh:100` (add gated call inside `main()`)

- [ ] **Step 1: Source the helper next to utils.sh**

In `ai_clients/main.sh`, find line 15:
```bash
source "$SCRIPT_DIR/lib/utils.sh"
```
Change it to:
```bash
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/restore_env_prompt.sh"
```

- [ ] **Step 2: Add the gated call at the top of `main()`**

In `ai_clients/main.sh`, find the start of `main()` (line 99-101):
```bash
main() {
    local clients=()
    mapfile -t clients < <(discover_clients)
```
Change it to:
```bash
main() {
    # Skip when make init already asked via the restore_env_prompt target.
    [[ -z "$DOTFILES_INIT_IN_PROGRESS" ]] && prompt_restore_env

    local clients=()
    mapfile -t clients < <(discover_clients)
```

- [ ] **Step 3: Lint — verify the modified file passes the gate**

Run:
```bash
shellcheck --severity=warning --exclude=SC1091 ai_clients/main.sh && \
bash -n ai_clients/main.sh && echo "LINT OK"
```
Expected: `LINT OK`.

- [ ] **Step 4: Functional test — prompt fires when flag is UNSET**

Run (answer `n` to restore, then `q` to quit the client menu):
```bash
printf 'n\nq\n' | bash ai_clients/main.sh
```
Expected: output contains both `Restore .env files from an external drive?`
and `Skipping .env restore.`, then the `AI CLIENTS SETUP` menu, then `Aborted.`

- [ ] **Step 5: Functional test — prompt is SKIPPED when flag is SET**

Run (only `q` needed — no restore prompt should appear):
```bash
printf 'q\n' | DOTFILES_INIT_IN_PROGRESS=1 bash ai_clients/main.sh
```
Expected: output does **not** contain `Restore .env files from an external
drive?`. It goes straight to the `AI CLIENTS SETUP` menu, then `Aborted.`

- [ ] **Step 6: Commit**

```bash
git add ai_clients/main.sh
git commit -m "feat(ai_clients): fire restore-env prompt unless run by init"
```

---

## Task 3: Wire the `restore_env_prompt` target into the Makefile

**Files:**
- Modify: `Makefile:18` (`init` target — add dep + exported flag)
- Modify: `Makefile:179` (`.PHONY` line — add `restore_env_prompt`)
- Modify: `Makefile` (`##@ Batch Operations` section — add the target recipe)

- [ ] **Step 1: Add `restore_env_prompt` to the Batch Operations `.PHONY` line**

In `Makefile`, find line 179:
```makefile
.PHONY: full_setup install_espanso_packages hardware_setup storage_setup vm_setup permissions ai_clients
```
Change it to:
```makefile
.PHONY: full_setup install_espanso_packages hardware_setup storage_setup vm_setup permissions ai_clients restore_env_prompt
```

- [ ] **Step 2: Add the target recipe next to `ai_clients`**

In `Makefile`, find the `ai_clients` target (lines 245-247):
```makefile
ai_clients:  ## Configure all AI clients (interactive menu: Claude Code, ...)
	@echo "Configuring all AI clients (Claude, ...)..."
	@bash ai_clients/main.sh
```
Immediately **after** it, add:
```makefile
restore_env_prompt:  ## Ask whether to restore .env files from external backup
	@bash ai_clients/lib/restore_env_prompt.sh
```

- [ ] **Step 3: Make `init` depend on it first and export the gate flag**

In `Makefile`, find the `init` target (lines 17-18):
```makefile
.PHONY: init
init: permissions setup_env install_programs install_espanso_packages install_coding ai_clients bash_profile starship_setup editors_setup irpf_download set_shortcuts ubuntu_workspace  ## Complete initial setup (RECOMMENDED first-time entry point)
```
Change to (add the export line, and `restore_env_prompt` as the first prereq):
```makefile
.PHONY: init
init: export DOTFILES_INIT_IN_PROGRESS=1
init: restore_env_prompt permissions setup_env install_programs install_espanso_packages install_coding ai_clients bash_profile starship_setup editors_setup irpf_download set_shortcuts ubuntu_workspace  ## Complete initial setup (RECOMMENDED first-time entry point)
```

- [ ] **Step 4: Verify the target exists and help renders**

Run:
```bash
make help | grep -A0 restore_env_prompt
```
Expected: a line showing `restore_env_prompt   Ask whether to restore .env files from external backup`.

- [ ] **Step 5: Verify init ordering and flag export with a dry run**

Run:
```bash
make -n init 2>&1 | head -5
```
Expected: the **first** recipe line shown is `bash ai_clients/lib/restore_env_prompt.sh` (the `restore_env_prompt` prereq runs before `permissions`). No restore actually happens — `-n` only prints.

- [ ] **Step 6: Verify the exported flag reaches the ai_clients recipe**

Run (confirms `init`'s target-export flows to its `ai_clients` prereq — so
`main.sh` will skip its own prompt; pipe `q` so the menu it would reach exits):
```bash
make -n init 2>&1 | grep -c "ai_clients/main.sh"
```
Expected: `1` (the `ai_clients` recipe is still scheduled; the gate only
suppresses the *duplicate prompt* inside it, not the recipe itself).

- [ ] **Step 7: Commit**

```bash
git add Makefile
git commit -m "feat(install): run restore-env prompt first in make init"
```

---

## Task 4: Document the prompt in `ai_clients/CLAUDE.md`

**Files:**
- Modify: `ai_clients/CLAUDE.md` (append a short subsection under "What this directory is")

- [ ] **Step 1: Add the documentation paragraph**

In `ai_clients/CLAUDE.md`, find the end of the "What this directory is"
section (immediately before the `## Three artifact types` heading). Insert
this subsection just before that heading:

```markdown
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
```

- [ ] **Step 2: Verify the insertion reads correctly**

Run:
```bash
grep -n "restore-\`.env\` prompt\|DOTFILES_INIT_IN_PROGRESS" ai_clients/CLAUDE.md
```
Expected: two line-number matches (the heading and the flag mention).

- [ ] **Step 3: Commit**

```bash
git add ai_clients/CLAUDE.md
git commit -m "docs(ai_clients): document the restore-env prompt"
```

---

## Acceptance Criteria (run after all tasks)

These map 1:1 to the spec's acceptance criteria.

1. **Fresh `make init` asks once** — `make -n init 2>&1 | head -1` shows
   `bash ai_clients/lib/restore_env_prompt.sh` first.
2. **Enter / `n` skips** — `printf '\n' | bash ai_clients/lib/restore_env_prompt.sh`
   prints `Skipping .env restore.` and exits 0.
3. **`y` dispatches** — `printf 'y\n' | bash ai_clients/lib/restore_env_prompt.sh`
   does not print `No restore-env script found`.
4. **Standalone `make ai_clients` asks** —
   `printf 'n\nq\n' | bash ai_clients/main.sh` shows the restore prompt.
5. **`make init` does not double-ask** —
   `printf 'q\n' | DOTFILES_INIT_IN_PROGRESS=1 bash ai_clients/main.sh`
   shows no restore prompt.
6. **`make restore_env_prompt` standalone is valid** —
   `make help | grep restore_env_prompt` shows the target.

---

## Notes

- **No `git push`** anywhere in this plan — per the user's global rule, pushing
  waits for an explicit request. Each task commits locally only.
- **Branch:** work continues on the current feature branch unless the user asks
  to branch. Confirm before pushing or opening a PR.
- **`storage/restore_env.sh` is assumed to exist** (it is the source of the
  installed `~/.local/bin/restore-env.sh`). The fallback branch depends on it;
  if it is ever removed, Task 1 Step 4's fallback assertion changes to the
  error branch.
