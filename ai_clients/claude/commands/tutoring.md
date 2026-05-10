---
name: c:tutoring
description: Toggle tutoring mode for the current project — guided step-by-step learning with no auto-implementation
argument-hint: "on|off"
allowed-tools: Bash, Read, Write, Edit
---

Toggle tutoring mode for the current project. Tutoring mode enforces step-by-step guided learning: one concept per reply, user writes code, assistant reviews — never auto-implements.

## 1. Parse argument

- `$ARGUMENTS` is `on` → enable tutoring mode
- `$ARGUMENTS` is `off` → disable tutoring mode
- anything else → show current status and usage

## 2. Derive memory path

Run `pwd` to get the current working directory. Encode it:

```bash
PROJECT_PATH=$(pwd)
ENCODED=$(echo "$PROJECT_PATH" | sed 's|/|-|g')
MEMORY_DIR="$HOME/.claude/projects/$ENCODED/memory"
PROJECT_NAME=$(basename "$PROJECT_PATH")
```

This mirrors Claude Code's internal project memory path convention.

## 3. On — enable tutoring mode

Create `$MEMORY_DIR/feedback_tutoring_mode.md`:

```markdown
---
name: Tutoring mode
description: Step-by-step guided learning — no auto-implementation, one concept per reply
type: feedback
---

Do NOT write files or run commands for this user in this project. Instead:
1. Cover ONE step at a time — never dump multiple steps in one reply
2. Explain what to do and WHY (conceptually + architecturally)
3. Show the target code as a reference/example
4. Wait for user to say they've saved/done it
5. Check their implementation, give feedback, reinforce correct points
6. Ask if they understand before moving on

**Why:** User is learning through hands-on practice. Auto-implementing bypasses the learning process.
**How to apply:** One step per reply. Never auto-run mkdir, git, npm, or edit files. Wait for explicit "done" before reviewing.
**Scope:** THIS PROJECT ONLY.
```

Then check if `$MEMORY_DIR/MEMORY.md` exists. If it does, append a pointer line if one isn't already present:
```
- [Tutoring Mode](feedback_tutoring_mode.md) — Step-by-step learning: no auto-implementation, one concept per reply.
```

Print: `✅ Tutoring mode ON for '<project-name>'. I will guide one step at a time and wait for your "done" before moving forward.`

## 4. Off — disable tutoring mode

Delete `$MEMORY_DIR/feedback_tutoring_mode.md` if it exists.

If `$MEMORY_DIR/MEMORY.md` exists, remove the line that points to `feedback_tutoring_mode.md`.

Print: `✅ Tutoring mode OFF for '<project-name>'. Resuming normal plan/edit mode.`

## 5. Status — no argument or unknown argument

Check whether `$MEMORY_DIR/feedback_tutoring_mode.md` exists.

Print current state:
- Exists → `Tutoring mode is ON for '<project-name>'. Use /tutoring off to disable.`
- Missing → `Tutoring mode is OFF for '<project-name>'. Use /tutoring on to enable.`
