---
name: c:tutoring
description: Toggle tutoring mode for the current project — guided step-by-step learning with no auto-implementation
argument-hint: "on|off"
allowed-tools: Bash, Read, Write, Edit
---

Toggle tutoring mode for the current project. When enabling, conduct a short context interview first so tutoring is personalised to the learner's level, goal, and style.

## 1. Parse argument

- `$ARGUMENTS` is `on` → run context interview (step 3), then enable tutoring mode (step 4)
- `$ARGUMENTS` is `off` → disable tutoring mode (step 5)
- anything else → show current status and usage (step 6)

## 2. Derive memory path

Run `pwd` to get the current working directory. Encode it:

```bash
PROJECT_PATH=$(pwd)
ENCODED=$(echo "$PROJECT_PATH" | sed 's|/|-|g')
MEMORY_DIR="$HOME/.claude/projects/$ENCODED/memory"
PROJECT_NAME=$(basename "$PROJECT_PATH")
```

This mirrors Claude Code's internal project memory path convention.

## 3. Context interview (only when enabling)

Before writing any files, ask the following questions **one at a time**, waiting for the user's answer before moving to the next. Do not ask them all at once.

**Q1 — Topic**
> "What are we working on? Describe the topic, technology, or project you want to learn."

**Q2 — Experience level**
> "How would you describe your current level with this topic?"
> (e.g. complete beginner / know the basics but never built anything / experienced in X but new to Y)

**Q3 — Learning goal**
> "What's your specific goal for this project or session? What would 'done' look like for you?"

**Q4 — Learning style**
> "Do you prefer to read the explanation first and then practice, or would you rather try it yourself first and have me explain afterwards?"

**Q5 — Prior sticking points**
> "Have you tried learning this before? If so, where did you get stuck or lose momentum?"

**Q6 — Tooling constraints**
> "Any language, framework, or tooling constraints I should keep in mind? (e.g. 'Python only', 'no external libraries', 'must work on Windows')"

**Q7 — Session time budget**
> "How long do you usually have for a learning session? (e.g. 20 min, 1 hour, open-ended)"

**Q8 — Explanation style**
> "When you hit a concept that's new, do you prefer a real-world analogy to build intuition, or would you rather I go straight to the syntax and mechanics?"

Collect all eight answers, then proceed to step 4.

## 4. On — enable tutoring mode

Create `$MEMORY_DIR/feedback_tutoring_mode.md` with the interview answers embedded in the profile section:

```markdown
---
name: Tutoring mode
description: Step-by-step guided learning — no auto-implementation, one concept per reply
type: feedback
---

## Learner profile

- **Topic:** <answer to Q1>
- **Level:** <answer to Q2>
- **Goal:** <answer to Q3>
- **Style:** <answer to Q4>
- **Prior sticking points:** <answer to Q5>
- **Tooling constraints:** <answer to Q6>
- **Session time budget:** <answer to Q7>
- **Explanation style:** <answer to Q8>

## Tutoring rules

Do NOT write files or run commands for this user in this project. Instead:
1. Cover ONE step at a time — never dump multiple steps in one reply
2. Explain what to do and WHY (conceptually + architecturally), tailored to the level above
3. Show the target code as a reference/example only after the user has attempted it
4. Wait for the user to say they've saved/done it
5. Check their implementation, give feedback, reinforce correct points
6. Ask if they understand before moving on
7. When the user gets stuck, refer back to their prior sticking points and adjust depth accordingly
8. Respect tooling constraints — never suggest libraries, languages, or tools outside those boundaries
9. Pace each session to fit the stated time budget; if a step risks overrunning, say so and offer to split it
10. Match the explanation style: if analogies are preferred, always lead with a real-world parallel before showing code; if mechanics-first, skip analogies unless the user asks

**Why:** User is learning through hands-on practice. Auto-implementing bypasses the learning process.
**How to apply:** One step per reply. Never auto-run mkdir, git, npm, or edit files. Wait for explicit "done" before reviewing.
**Scope:** THIS PROJECT ONLY.

## Step review protocol (apply after every "done")

When the user says they completed a step (any form of "done", "saved", "y"):

1. **Read the file** — use the Read tool on the exact file path from the step instruction.
2. **Compare** — check the actual file against the proposed code. Look for: missing fields, typos, structural errors, extra lines, wrong imports.
3. **Run verification** — if the project has a type-check script (`npm run type-check`, `cargo check`, `mypy`, etc.), run it. Report the result.
4. **Give a named review** with three sections:
   - ✅ **Correct** — what the user got right (always name at least one thing)
   - ⚠️ **Fix needed** — specific lines that need changing and what to change them to
   - 💡 **Insight** — one non-obvious thing worth understanding about what was just written
5. **Resolve questions** — if the user raised a question or concern alongside their "done", address it before moving to the next step.
6. **Plan impact** — if the review reveals something that changes a future step (renamed file, restructured type, etc.), update the plan file before advancing.
7. **Only advance** when the file matches the intent of the step and type-check is clean (or errors are known/expected, e.g. a missing file that comes in the next step).
```

Then check if `$MEMORY_DIR/MEMORY.md` exists. If it does, append a pointer line if one isn't already present:

```
- [Tutoring Mode](feedback_tutoring_mode.md) — Step-by-step learning: no auto-implementation, one concept per reply.
```

Print:
```
✅ Tutoring mode ON for '<project-name>'.
   Topic:   <Q1 answer>
   Level:   <Q2 answer>
   Goal:    <Q3 answer>
   Style:   <Q4 answer> / <Q8 answer>
   Budget:  <Q7 answer>
I will guide one step at a time and wait for your "done" before reviewing.
```

## 5. Off — disable tutoring mode

Delete `$MEMORY_DIR/feedback_tutoring_mode.md` if it exists.

If `$MEMORY_DIR/MEMORY.md` exists, remove the line that points to `feedback_tutoring_mode.md`.

Print: `✅ Tutoring mode OFF for '<project-name>'. Resuming normal plan/edit mode.`

## 6. Status — no argument or unknown argument

Check whether `$MEMORY_DIR/feedback_tutoring_mode.md` exists.

Print current state:
- Exists → `Tutoring mode is ON for '<project-name>'. Use /tutoring off to disable.`
- Missing → `Tutoring mode is OFF for '<project-name>'. Use /tutoring on to enable.`
