# AI Clients Two-Level Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `ai_clients/` to add a thin top-level router (`ai_clients/main.sh`) that auto-discovers clients and presents a two-level menu (client → steps), backed by shared utilities in `ai_clients/lib/utils.sh`.

**Architecture:** A new `ai_clients/main.sh` globs `*/main.sh` to discover clients, shows a numbered client menu, and delegates to the chosen client's `main.sh` passing args through unchanged. Shared colors/logging move to `ai_clients/lib/utils.sh`; each client sources it via a relative path. `claude/main.sh` gains a one-line `CLAUDE_DIR` definition to replace what was in its now-deleted `lib/utils.sh`.

**Tech Stack:** Bash 5, `jq`, standard POSIX tools (`find`, `glob`, `basename`).

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| CREATE | `ai_clients/lib/utils.sh` | Shared colors, `print_status`, `LOG_FILE` |
| CREATE | `ai_clients/main.sh` | Top-level router: discovery, menu, delegation |
| MODIFY | `ai_clients/claude/main.sh` | Source shared utils; define `CLAUDE_DIR` locally |
| DELETE | `ai_clients/claude/lib/utils.sh` | Replaced by shared utils |
| MODIFY | `Makefile` | Point `ai_clients` target at `ai_clients/main.sh all` |

---

### Task 1: Create shared `ai_clients/lib/utils.sh`

**Files:**
- Create: `ai_clients/lib/utils.sh`

- [ ] **Step 1: Create the directory and file**

```bash
mkdir -p ai_clients/lib
```

Write `ai_clients/lib/utils.sh`:

```bash
#!/bin/bash
# Shared variables and print_status used by all ai_clients setup modules.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

LOG_FILE="$HOME/ai_clients_setup_$(date +%Y%m%d_%H%M%S).log"

print_status() {
    local status="$1"
    local message="$2"
    case "$status" in
        "success") echo -e "${GREEN}[✓]${NC} ${message}" ;;
        "error")   echo -e "${RED}[✗]${NC} ${message}" >&2 ;;
        "warning") echo -e "${YELLOW}[!]${NC} ${message}" ;;
        "info")    echo -e "${BLUE}[i]${NC} ${message}" ;;
        "config")  echo -e "${CYAN}[→]${NC} ${message}" ;;
        "section")
            echo -e "\n${MAGENTA}========================================${NC}"
            echo -e "${MAGENTA} $message${NC}"
            echo -e "${MAGENTA}========================================${NC}\n"
            ;;
        *) echo -e "[ ] ${message}" ;;
    esac
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$status] $message" >> "$LOG_FILE"
}
```

- [ ] **Step 2: Syntax check**

Run: `bash -n ai_clients/lib/utils.sh`
Expected: no output, exit 0.

- [ ] **Step 3: Commit**

```bash
git add ai_clients/lib/utils.sh
git commit -m "feat(ai_clients): add shared utils.sh with colors and print_status"
```

---

### Task 2: Update `ai_clients/claude/main.sh` to use shared utils

**Files:**
- Modify: `ai_clients/claude/main.sh`

- [ ] **Step 1: Replace the utils source line and add CLAUDE_DIR**

In `ai_clients/claude/main.sh`, replace:

```bash
source "$SCRIPT_DIR/lib/utils.sh"
```

with:

```bash
source "$SCRIPT_DIR/../lib/utils.sh"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
```

- [ ] **Step 2: Syntax check**

Run: `bash -n ai_clients/claude/main.sh`
Expected: no output, exit 0.

- [ ] **Step 3: Smoke-test standalone invocation**

Run: `bash ai_clients/claude/main.sh settings 2>&1 | head -5`
Expected: lines containing `CHECKING PREREQUISITES` and `CONFIGURING CLAUDE SETTINGS` — confirms shared utils load correctly and `CLAUDE_DIR` is available to all sourced libs.

- [ ] **Step 4: Commit**

```bash
git add ai_clients/claude/main.sh
git commit -m "refactor(claude): source shared ai_clients/lib/utils.sh; define CLAUDE_DIR locally"
```

---

### Task 3: Delete `ai_clients/claude/lib/utils.sh`

**Files:**
- Delete: `ai_clients/claude/lib/utils.sh`

- [ ] **Step 1: Remove the file**

```bash
git rm ai_clients/claude/lib/utils.sh
```

- [ ] **Step 2: Verify claude still works without it**

Run: `bash ai_clients/claude/main.sh settings 2>&1 | head -5`
Expected: same output as Task 2 Step 3 — no "file not found" errors.

- [ ] **Step 3: Commit**

```bash
git commit -m "refactor(claude): remove lib/utils.sh superseded by ai_clients/lib/utils.sh"
```

---

### Task 4: Create `ai_clients/main.sh` — the top-level router

**Files:**
- Create: `ai_clients/main.sh`

- [ ] **Step 1: Write the router**

Write `ai_clients/main.sh`:

```bash
#!/bin/bash
# Top-level AI clients router.
# Auto-discovers clients via ai_clients/*/main.sh.
# Usage:
#   ./main.sh                        — interactive client menu
#   ./main.sh all                    — run all clients (all steps each)
#   ./main.sh claude                 — interactive step menu for claude
#   ./main.sh claude all             — all steps for claude
#   ./main.sh claude settings rules  — specific steps for claude

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/utils.sh"

# Display name overrides: directory key → human label
declare -A CLIENT_NAMES=(
    ["claude"]="Claude Code"
)

# ── Discovery ──────────────────────────────────────────────────────────────────

discover_clients() {
    local clients=()
    for path in "$SCRIPT_DIR"/*/main.sh; do
        [[ -f "$path" ]] || continue
        clients+=("$(basename "$(dirname "$path")")")
    done
    echo "${clients[@]}"
}

get_display_name() {
    local key="$1"
    echo "${CLIENT_NAMES[$key]:-${key^}}"
}

# ── Delegation ─────────────────────────────────────────────────────────────────

run_client() {
    local key="$1"; shift
    local client_main="$SCRIPT_DIR/$key/main.sh"

    if [[ ! -f "$client_main" ]]; then
        print_status "error" "Unknown client: $key"
        print_status "info"  "Valid clients: $(discover_clients | tr ' ' ',')"
        exit 1
    fi

    bash "$client_main" "$@"
}

# ── Interactive menu ───────────────────────────────────────────────────────────

show_menu() {
    local clients=("$@")
    echo ""
    echo -e "${MAGENTA}========================================${NC}"
    echo -e "${MAGENTA} AI CLIENTS SETUP — Select client${NC}"
    echo -e "${MAGENTA}========================================${NC}"
    echo ""
    local i=1
    for key in "${clients[@]}"; do
        echo "  $i) $(get_display_name "$key")"
        (( i++ ))
    done
    echo ""
    echo "  a) All of the above"
    echo "  q) Quit"
    echo ""
}

interactive_menu() {
    local clients
    read -ra clients <<< "$(discover_clients)"

    while true; do
        show_menu "${clients[@]}"
        read -rp "Enter choice: " input

        case "$input" in
            q|Q) print_status "info" "Aborted."; exit 0 ;;
            a|A)
                for key in "${clients[@]}"; do run_client "$key" all; done
                break
                ;;
            *)
                if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= ${#clients[@]} )); then
                    run_client "${clients[$((input-1))]}"
                    break
                else
                    print_status "error" "Invalid choice: $input"
                fi
                ;;
        esac
    done
}

# ── Entry point ────────────────────────────────────────────────────────────────

main() {
    local clients
    read -ra clients <<< "$(discover_clients)"

    if [[ ${#clients[@]} -eq 0 ]]; then
        print_status "error" "No AI clients found under $SCRIPT_DIR"
        print_status "info"  "Each client needs a main.sh at ai_clients/<name>/main.sh"
        exit 1
    fi

    if [[ $# -eq 0 ]]; then
        interactive_menu
    elif [[ "$1" == "all" ]]; then
        for key in "${clients[@]}"; do run_client "$key" all; done
    else
        local client="$1"; shift
        run_client "$client" "$@"
    fi
}

main "$@"
```

- [ ] **Step 2: Make executable and syntax check**

```bash
chmod +x ai_clients/main.sh
bash -n ai_clients/main.sh
```

Expected: no output, exit 0.

- [ ] **Step 3: Verify client discovery**

Run: `bash -c 'SCRIPT_DIR=$(pwd)/ai_clients; for p in "$SCRIPT_DIR"/*/main.sh; do [[ -f "$p" ]] && basename "$(dirname "$p")"; done'`
Expected: `claude`

- [ ] **Step 4: Test non-interactive delegation — all steps for claude**

Run: `bash ai_clients/main.sh claude all 2>&1 | head -10`
Expected: output containing `CLAUDE CODE CONFIGURATION SCRIPT` and `CHECKING PREREQUISITES`.

- [ ] **Step 5: Test non-interactive delegation — specific step**

Run: `bash ai_clients/main.sh claude settings 2>&1 | grep -E "(CONFIGURING CLAUDE SETTINGS|Settings written)"`
Expected: both lines appear.

- [ ] **Step 6: Test unknown client error handling**

Run: `bash ai_clients/main.sh foobar 2>&1; echo "exit: $?"`
Expected: output contains `Unknown client: foobar` and `exit: 1`.

- [ ] **Step 7: Commit**

```bash
git add ai_clients/main.sh
git commit -m "feat(ai_clients): add top-level router with auto-discovery and two-level menu"
```

---

### Task 5: Update Makefile `ai_clients` target

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Update the target**

In `Makefile`, replace:

```makefile
ai_clients:
	@echo "Configuring all AI clients (Claude, ...)..."
	@bash ai_clients/claude/main.sh all
```

with:

```makefile
ai_clients:
	@echo "Configuring all AI clients (Claude, ...)..."
	@bash ai_clients/main.sh all
```

- [ ] **Step 2: Verify via make**

Run: `make ai_clients 2>&1 | grep -E "(✓|✗|Configuring)"`
Expected: lines with `✓` for each completed step, no `✗` errors.

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "chore: point ai_clients Makefile target at top-level router"
```

---

### Task 6: End-to-end verification

- [ ] **Step 1: Full make run**

Run: `make ai_clients 2>&1 | tail -10`
Expected: `✓ Claude Code configuration applied` and no error lines.

- [ ] **Step 2: Verify standalone claude still works**

Run: `bash ai_clients/claude/main.sh settings 2>&1 | grep "Settings written"`
Expected: `→ Settings written to: /home/<user>/.claude/settings.json`

- [ ] **Step 3: Verify no orphan reference to deleted utils**

Run: `grep -r "claude/lib/utils" ai_clients/`
Expected: no output (zero matches).

- [ ] **Step 4: Push**

```bash
git push origin HEAD
```
