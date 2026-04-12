---
name: s:bash-create
description: Use when writing a new Bash script or module — applies project conventions for structure, banners, color output, logging, and caller/callee file splits.
effort: high
argument-hint: [description] [target-file]
allowed-tools: Read, Glob, Grep
---

Write a complete, production-ready Bash script following the conventions below.

## Required inputs

Before doing anything else, ask the user for both of the following if not
already provided in `$ARGUMENTS`:

1. **What to build** — what the script should do.
2. **Target file** — exact path for the main script (e.g. `scripts/setup.sh`).

Do not infer either. Wait for explicit confirmation before writing any code.

## File structure (single-file)

Every standalone script follows this top-to-bottom order:

```bash
#!/bin/bash
# <one-line description of what this script does>
# Usage: ./<script>.sh [args]

set -e

# ============================================================================
# CONSTANTS
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

LOG_FILE="$HOME/<script>_$(date +%Y%m%d_%H%M%S).log"

readonly RED GREEN YELLOW BLUE CYAN MAGENTA NC LOG_FILE

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

print_status() { ... }   # always present — see canonical implementation below

# ============================================================================
# <DOMAIN A> FUNCTIONS
# ============================================================================

do_something() { ... }
validate_something() { ... }

# ============================================================================
# <DOMAIN B> FUNCTIONS
# ============================================================================

configure_thing() { ... }

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() { ... }

main "$@"
```

## Canonical `print_status`

Always include this exact implementation — never simplify or abbreviate it:

```bash
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

## Section banner format

The banner is exactly this — two `# ===` lines enclosing the label:

```bash
# ============================================================================
# SECTION LABEL IN UPPER CASE
# ============================================================================
```

- The `=` line is 76 characters wide (counting `# `).
- One blank line before the banner, one blank line after it.
- Group every function with the same domain concern under one banner.
- A banner with only one function underneath is acceptable when the domain
  is distinct — do not merge unrelated functions to avoid a banner.

## Function conventions

- Names: `snake_case`, verb-first (`install_deps`, `validate_path`,
  `restore_backup`).
- All parameters captured into `local` variables at the top of the function:
  ```bash
  my_func() {
      local target="$1"
      local mode="${2:-default}"
      ...
  }
  ```
- Announce major operations with `print_status "section" "LABEL"`.
- Return `0` on success, non-zero on failure. Use `return 1` — never `exit`
  from inside a library function.
- Use `print_status "error"` before returning non-zero; this ensures the
  message lands in the log.
- Never use global mutable variables inside functions — pass values as
  arguments or capture them with `local`.

## `main()` and entry point

Always define a `main()` function and call it as the last line:

```bash
main() {
    print_status "section" "SCRIPT NAME — BRIEF PURPOSE"
    print_status "info" "Log: $LOG_FILE"

    # steps in order
    step_one
    step_two || { print_status "error" "step_two failed"; exit 1; }

    print_status "success" "Done."
}

main "$@"
```

## When to split into caller + callee files

Split when **any** of these is true:

| Condition | Action |
|-----------|--------|
| Script exceeds ~200 lines | Split by domain into `lib/<concern>.sh` |
| Two or more logically distinct domains | One lib file per domain |
| `print_status` / colors reused by multiple scripts | Extract to `lib/utils.sh` |
| A function is called from more than one entry-point script | Move to a lib |

**Do not** split for the sake of it — a 150-line self-contained script is
better as one file than three trivial libs.

## Caller/callee layout

```
scripts/
  main.sh          ← caller: sources libs, defines entry point
  lib/
    utils.sh       ← colors, LOG_FILE, print_status (no main())
    <concern_a>.sh ← all functions for concern A (no main())
    <concern_b>.sh ← all functions for concern B (no main())
```

**Caller (`main.sh`) pattern:**

```bash
#!/bin/bash
# <description>
# Usage: ./main.sh [all | step1 step2 ...]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/concern_a.sh"
source "$SCRIPT_DIR/lib/concern_b.sh"

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    print_status "section" "SETUP SCRIPT"
    concern_a_function
    concern_b_function
}

main "$@"
```

**Callee (`lib/<concern>.sh`) pattern:**

```bash
#!/bin/bash
# <one-line description of this module's concern>

concern_a_function() {
    print_status "section" "CONCERN A"
    local target="$1"
    ...
}
```

- Callee files do **not** define colors, `LOG_FILE`, or `print_status` — they
  inherit these from `utils.sh` sourced by the caller.
- Callee files do **not** call `main` or include an entry point.
- Use `SCRIPT_DIR` in the caller for all path resolution; pass paths as
  arguments to callee functions rather than re-resolving them.

## Strict mode (optional but recommended)

For scripts that handle critical operations, prefer:

```bash
set -euo pipefail
```

- `-e` — exit on error
- `-u` — treat unset variables as errors
- `-o pipefail` — catch failures in pipelines

If using `-u`, always provide defaults for optional parameters:
`local mode="${2:-default}"`.

## Do Not

- Do not use `exit` inside library functions — use `return`.
- Do not use global variables inside functions — use `local` or pass as args.
- Do not inline colors (`\033[0;32m`) outside the constants block.
- Do not omit `print_status` even in short scripts — it provides the log.
- Do not split a script under 200 lines unless domains are genuinely distinct.
- Do not define `print_status` in callee files — it lives only in `utils.sh`.
- Do not leave functions without a section banner grouping them.
