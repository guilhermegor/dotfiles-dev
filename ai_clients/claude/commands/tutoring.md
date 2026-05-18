---
name: c:tutoring
description: Toggle tutoring mode for the current project — guided step-by-step learning with no auto-implementation
argument-hint: "on|off"
allowed-tools: Bash, Read, Write, Edit
---

Toggle tutoring mode for the current project. When enabling, conduct a short context interview first so tutoring is personalised to the learner's level, goal, and style.

## 1. Parse argument

- `$ARGUMENTS` is `on` → check for existing session (step 2b), then run context interview (step 3) or resume, then enable tutoring mode (step 4)
- `$ARGUMENTS` is `off` → disable tutoring mode (step 5)
- anything else → show current status and usage (step 6)

## 2. Derive memory path

Run `pwd` to get the current working directory. Encode it:

```bash
PROJECT_PATH=$(pwd)
ENCODED=$(echo "$PROJECT_PATH" | sed 's|/|-|g')
MEMORY_DIR="$HOME/.claude/projects/$ENCODED/memory"
PROJECT_NAME=$(basename "$PROJECT_PATH")
SESSION_FILE="$MEMORY_DIR/tutoring_session.md"
```

This mirrors Claude Code's internal project memory path convention.

## 2b. Check for existing session (only when enabling)

Before running the interview, check if `$SESSION_FILE` exists:

```bash
test -f "$SESSION_FILE"
```

If it **exists**:
1. Read the file and extract the current step (the line marked `[>]`) and the total step count.
2. Count completed steps (lines marked `[x]`) and pending steps (lines marked `[ ]`).
3. Ask the user:

   > "Found a previous session on '<topic from file>'. You completed <N> of <M> steps.
   > Next up: step <current number> — '<current step name>'.
   > Resume from here? (yes/no — 'no' starts a fresh session)"

4. If **yes** → skip the interview entirely, go directly to step 4 with `RESUMING=true`.
5. If **no** → proceed with the full interview (step 3); the old session file will be overwritten in step 4b.

If the file **does not exist** → proceed with the full interview (step 3).

## 3. Context interview (only when enabling and not resuming)

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

**Q9 — Curriculum**
> "Should I draft a step-by-step curriculum for this topic? This creates a plan you can track and resume across sessions — no session is lost if you stop halfway."
> (yes/no)

Collect all nine answers, then proceed to step 4.

## 4. On — enable tutoring mode

Create `$MEMORY_DIR/feedback_tutoring_mode.md` with the interview answers embedded in the profile section.

If `RESUMING=true`, preserve the existing learner profile values from the old file; only refresh the tutoring rules and session continuity sections.

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

## Session continuity

A `tutoring_session.md` file may exist in this memory directory. If it does:

1. **Session start** — read it immediately. Announce:
   "Resuming: Step <N> of <M> — '<step name>'. Steps done: <N-1>. Steps remaining: <M-N+1>."
   Then present step <N> as the next action.

2. **After step verified as done** — update `tutoring_session.md`:
   - Change the `[>]` marker on the completed step to `[x]`
   - Change the `[ ]` marker on the very next step to `[>]`
   - Update the `**Current step:**` field to the new step number
   - Update `**Last active:**` to today's date

3. **Session complete** — when all steps are `[x]`, announce:
   "All steps complete! Topic: '<topic>', Goal: '<goal>'. Well done."
   Do not advance further or invent new steps.

## Step review protocol (apply after every "done")

When the user says they completed a step (any form of "done", "saved", "y"), run this three-phase cycle. Never skip a phase.

### Phase 1 — Gather evidence (always re-gather, never trust memory)

1. **Read the file** — use the Read tool on the exact file path from the step instruction. Do this even if the user already pasted the code in chat.
2. **Run verification** — probe for available checkers and run **all that are found**, in parallel where possible.

   **Discover first** — probe which task runners and manifests exist before running anything. Check for each file with `test -f <file>` and read only the ones present:

   | File | Probe command |
   |---|---|
   | `Makefile` | `grep -E '^(lint\|type-check\|typecheck\|check\|verify\|validate\|ci)[[:space:]]*:' Makefile` |
   | `package.json` | `grep -E '"(type-check\|typecheck\|lint\|lint:css\|lint:style\|check\|verify\|validate\|ci)"' package.json` |
   | `pyproject.toml` | `grep -E '^\[tool\.(taskipy\|poe\.tasks\|hatch\.envs)' pyproject.toml` — covers taskipy, poethepoet, hatch |
   | `Justfile` / `justfile` | `grep -E '^(lint\|type-check\|typecheck\|check\|verify\|validate\|ci):' Justfile justfile 2>/dev/null` |
   | `Taskfile.yml` / `Taskfile.yaml` | `grep -E '^\s+(lint\|type-check\|typecheck\|check\|verify\|ci):' Taskfile.yml Taskfile.yaml 2>/dev/null` |
   | `tox.ini` | `grep -E '^\[testenv:(lint\|check\|typecheck)\]' tox.ini` |
   | `run.sh` (root) | `grep -E '^\s*(lint\|type.check\|check\|verify)' run.sh` |
   | `scripts/` (root) | `ls scripts/ 2>/dev/null \| grep -E '(lint\|check\|verify\|ci)'` — flag any matching script |
   | `deno.json` / `deno.jsonc` | `grep -E '"(lint\|check\|typecheck)"' deno.json deno.jsonc 2>/dev/null` |
   | `nx.json` + `project.json` | presence of `nx.json` → try `npx nx lint`, `npx nx type-check` |
   | `turbo.json` | presence of `turbo.json` → try `npx turbo lint`, `npx turbo type-check` |

   **Prefer a combined target when one exists.** Look for targets/tasks named `verify`, `check`, `ci`, `validate`, or `all` across any discovered runner — these often bundle type-check + lint in the correct order. Run that single target instead of individual tools.

   **If no combined target:** run type-checkers and linters separately using the table below.

   **Type checkers** (run whichever applies):
   - npm / deno: `npm run type-check` / `npm run typecheck` / `npx tsc --noEmit` / `deno check <file>`
   - Make / Just / Task: `make type-check` / `just type-check` / `task type-check`
   - taskipy: `poetry run task typecheck`
   - poethepoet: `poetry run poe typecheck`
   - hatch: `hatch run typecheck`
   - tox: `tox -e typecheck`
   - Rust: `cargo check`
   - Python standalone: `python -m mypy <file>` / `pyright <file>`

   **Linters** (run after type checkers; never auto-fix — report only):
   - npm / deno: `npm run lint` / `deno lint <file>`
   - Make / Just / Task: `make lint` / `just lint` / `task lint`
   - taskipy: `poetry run task lint`
   - poethepoet: `poetry run poe lint`
   - hatch: `hatch run lint`
   - tox: `tox -e lint`
   - `run.sh` / `scripts/lint.sh`: `bash run.sh lint` / `bash scripts/lint.sh` (inspect first to confirm it's safe to run)
   - Python standalone: `ruff check <file>` / `flake8 <file>`
   - Rust: `cargo clippy`

   **CSS / style linters** (run if the project has CSS or other style-language assets — independent of JS linters above):
   - npm: `npm run lint:css` / `npm run lint:style` / `npm run stylelint` (any of these script names if defined)
   - Standalone: `npx stylelint "**/*.css"` (or `.scss`, `.less` as applicable) if a `.stylelintrc*` config is present at the repo root
   - These catch CSS bugs (invalid values, duplicate properties, deprecated notations) that `tsc` and `eslint` never see. A passing `eslint` does NOT imply CSS is clean — always run the CSS linter separately when one is configured.

   **Test runners** (run after the linters above — they catch semantic correctness, not just syntax / style):
   - npm / yarn / pnpm: `npm test` / `npm run test` / `npx jest` / `npx vitest run` (whichever a `test` script or a `jest.config.*` / `vitest.config.*` file points to)
   - Make / Just / Task: `make test` / `just test` / `task test`
   - taskipy / poethepoet / hatch / tox: `poetry run task test` / `poetry run poe test` / `hatch run test` / `tox -e test`
   - Python standalone: `pytest` / `python -m pytest` (skip if no `tests/` folder and no `pytest.ini` / `pyproject.toml` config)
   - Rust: `cargo test`
   - Tests catch a class of bugs no linter can see: missing UI elements, wrong action/visual wiring, off-by-one logic, regressions. **If a test runner is configured, running it is part of every step review — not optional.**

   If no checker, linter, or test runner is found after all probes: state "No type-check, lint, or test runner detected; review is manual only."
3. **Compare** — diff the actual file against the step's suggested code. Flag: missing fields, extra lines, wrong imports, structural errors, naming deviations, style violations from project CLAUDE.md rules.
4. **Load patterns** — read `## Recurring issues` in `tutoring_session.md` so you know which mistakes to watch for before writing the review.

### Phase 2 — Structured review

Give a named review with these sections. **Omit any section that is empty** — do not write empty headers.

- ✅ **Correct** — name at least one specific thing done right. "Looks good" is not enough; say what exactly is correct and why it matters.
- ⚠️ **Must fix** — each item on its own line. Show: file path + line number, what is wrong, exact corrected code. No must-fix item should be vague.
- 🟡 **Warnings** — non-blocking diagnostics from the same verification tools used in "Must fix" (linter warnings, deprecation notices, formatter complaints, soft type-checker hints). For each: file path + line, rule/identifier name, one sentence on what it means, and the trade-off if ignored. Warnings do not block by themselves but they MUST be surfaced — never silent.
- 👍 **Good practice** — non-obvious things done well that are worth repeating (e.g. "used a guard clause here instead of nesting — keep doing this").
- 🔁 **Recurring issue** — if any must-fix item matches a pattern already in `## Recurring issues`, call it out explicitly: "This is the Nth time I've seen `<issue name>`. The root cause is…" Escalate the explanation depth each time it recurs.
- 💡 **Insight** — one non-obvious architectural or language-level point about what was just written. Tailor depth to the learner level from the profile.
- 🛠️ **Verification result** — paste the exact output of every checker and linter run. Show each tool's name as a sub-header. If a tool produced no output, write "clean". Example:
  - `tsc`: clean
  - `eslint`: `src/user.ts:12:5 — error no-unused-vars`

### Phase 3 — Resolve or advance

**If there are "Must fix" items:**
- Do NOT update the session file. Do NOT advance.
- Say: "Fix the items above and say 'done' when ready."
- On the user's next "done": restart Phase 1 entirely (re-read the file, re-run verification).
- In this second review, focus only on whether the previously flagged items are resolved — skip sections that were already clean.
- Repeat until no "Must fix" items remain and verification is clean.

**If there are no "Must fix" items but `Warnings` are present:**
- Do NOT update the session file. Do NOT auto-advance.
- For each warning, recap the trade-off and present three explicit options to the user:
  - **Fix** — apply the structural change that removes the warning at its source.
  - **Suppress** — add an inline suppression directive (linter/checker-specific) WITH a short comment explaining why the suppression is acceptable in this context.
  - **Accept as project pattern** — leave the warning in place because the surrounding codebase already accepts it. Requires citing at least one other file in the project that has the same warning.
- Ask the user: "How would you like to handle these warnings — fix, suppress, or accept? (per-warning answers are fine.)"
- Wait for an explicit decision per warning. Apply the chosen action.
- For every "accept as project pattern" decision, append a line to `## Feedback log` in the session file: `- Step N (<name>): warning <rule-name> accepted as project pattern (cf. <other-file>)`. This guarantees accepted warnings are never silent across sessions.
- Only after every warning has an explicit user decision applied, proceed to the "fully clean" branch below.

**If verification is fully clean (no "Must fix", no `Warnings`):**
1. **Resolve questions** — address any question or concern the user raised alongside their "done".
2. **Plan impact** — if the review reveals something that changes a future step (renamed file, restructured type, different interface), update those step descriptions in `tutoring_session.md` before advancing.
3. **Update session file** (`tutoring_session.md`):
   - Change `[>]` on completed step to `[x]`
   - Change next `[ ]` to `[>]`
   - Update `**Current step:**` and `**Last active:**`
   - Append to `## Feedback log`: `- Step N (<name>): <comma-separated issues found, or "clean">`
   - If a must-fix item appeared for the second time across steps, add or update an entry in `## Recurring issues`: `- <issue name>: steps N, M — <root cause one-liner>`
4. Confirm: "Step <N> complete. Moving to step <N+1>: '<name>'." Then present the next step.
```

Then check if `$MEMORY_DIR/MEMORY.md` exists. If it does, append a pointer line if one isn't already present:

```
- [Tutoring Mode](feedback_tutoring_mode.md) — Step-by-step learning: no auto-implementation, one concept per reply.
```

If `RESUMING=true`, print:
```
✅ Resuming tutoring for '<project-name>'.
   Topic:        <topic from session file>
   Current step: <N> of <M> — '<step name>'
   Completed:    <list of done step names>
I will pick up from where you left off.
```

Otherwise print:
```
✅ Tutoring mode ON for '<project-name>'.
   Topic:   <Q1 answer>
   Level:   <Q2 answer>
   Goal:    <Q3 answer>
   Style:   <Q4 answer> / <Q8 answer>
   Budget:  <Q7 answer>
I will guide one step at a time and wait for your "done" before reviewing.
```

## 4b. Generate session plan (only when Q9 = yes and not resuming)

Based on the full learner profile, generate a numbered list of **5–10 concrete, actionable steps** sized to the stated time budget. Each step should be something the user can do and verify in a single exchange.

Criteria for good steps:
- Specific enough to be actionable ("create `src/main.py` with a `main()` entry point") not vague ("learn Python basics")
- Ordered from foundational to advanced — prerequisites before dependents
- Respect tooling constraints from Q6
- Fit within the time budget from Q7 (if 20 min, fewer steps; if open-ended, more depth)

Write `$SESSION_FILE`:

```markdown
---
name: Tutoring session
description: Lecture progress — resume from step <N of M>
type: project
---

## Topic: <Q1>
**Goal:** <Q3>
**Level:** <Q2>
**Started:** <today's date>
**Last active:** <today's date>
**Current step:** 1

## Steps

- [>] 1. <first step title> — <one-line description> ← CURRENT
- [ ] 2. <second step title> — <one-line description>
- [ ] 3. <third step title> — <one-line description>
...

## Feedback log

<!-- Appended automatically after each verified step.
     Format: - Step N (<name>): <issues found, comma-separated — or "clean">
     Example: - Step 2 (data model): missing type annotation on id field, unused import os — clean after fix -->

## Recurring issues

<!-- Issues seen in 2+ steps. Claude escalates explanation depth each recurrence.
     Format: - <issue label>: steps N, M — <root cause one-liner>
     Example: - missing-type-annotations: steps 1, 2 — forgetting that mypy requires annotations on all public functions -->
```

Then check if `$MEMORY_DIR/MEMORY.md` exists. If it does, append a pointer line if one isn't already present:

```
- [Tutoring Session](tutoring_session.md) — Lecture curriculum with step-by-step progress tracking.
```

Show the user the full curriculum and ask: "Does this plan look right, or should I adjust any steps before we start?"

Wait for confirmation or adjustments. If the user requests changes, edit the session file accordingly, then proceed to the first step.

## 5. Off — disable tutoring mode

Delete `$MEMORY_DIR/feedback_tutoring_mode.md` if it exists.

If `$MEMORY_DIR/MEMORY.md` exists, remove the line that points to `feedback_tutoring_mode.md`.

If `$SESSION_FILE` exists, ask:
> "Keep your session progress for later? (yes = progress is saved, no = session file deleted)"

- If yes: leave `$SESSION_FILE` intact.
- If no: delete `$SESSION_FILE` and remove its pointer from `MEMORY.md`.

Print: `✅ Tutoring mode OFF for '<project-name>'. Resuming normal plan/edit mode.`

## 6. Status — no argument or unknown argument

Check whether `$MEMORY_DIR/feedback_tutoring_mode.md` exists.

If it exists and `$SESSION_FILE` also exists:
- Read the session file
- Count `[x]` (done), `[>]` (current), `[ ]` (pending) steps
- Print:
  ```
  Tutoring mode is ON for '<project-name>'.
  Topic:    <topic>
  Progress: <done> of <total> steps completed
  Next:     step <N> — '<step name>'
  Use /tutoring off to disable.
  ```

If it exists but no session file:
  Print: `Tutoring mode is ON for '<project-name>' (no session plan). Use /tutoring off to disable.`

If missing:
  Print: `Tutoring mode is OFF for '<project-name>'. Use /tutoring on to enable.`
