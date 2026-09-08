---
name: s:story-score
description: Use when a story, task, or issue needs a point score before work starts — estimating, sizing, or pointing a piece of work for any tracker (Linear, GitHub, or none at all). Also use when a proposed estimate seems to be measuring effort or duration rather than how much is still unknown.
effort: medium
argument-hint: [story or subtask description, or an issue reference already read into context]
---

> **Priority:** this project's `CLAUDE.md` and `rules/*.md` take precedence over the guidance below whenever they conflict — treat this skill as a fallback, not a mandate.

Score the given story or subtask on the **uncertainty scale** below. Follow these
steps exactly.

## The scale measures uncertainty, not effort

The question is never "how long will this take" — it is **"how much is still
unknown."** That is the whole point of the scale: uncertainty can be *resolved*
(a spike answers the question, a stakeholder confirms the scope), and when it
is, the score drops. An effort or duration score cannot do that — a task
doesn't get shorter because someone answered a question about it. Score by
duration and the number never moves until the work is done; score by
uncertainty and the number is the thing that tells you whether it's safe to
pick up yet.

| Points | Criterion |
|---|---|
| **1** | You know how to do it. Not ambiguous. Scope is already delimited. |
| **2** | You have an idea how it should be done, but need to iterate with someone for a double check. Scope looks defined; execution still needs validating. Some ambiguity. |
| **3** | You do not really know how to solve it. Larger blast radius, possibly an RFC. Ambiguity and exploration ahead. |
| **4** | **Not a score.** A signal to split into more stories — see step 3. |

The scale itself is the portable part — the same ruler applies whether the work
lives in Linear, in a GitHub issue, or nowhere at all yet. Nothing below reads
or writes a tracker; recording the result is a separate step for someone else
to do, deliberately outside this skill (see Do Not).

## 1. Identify the unit being scored

The score belongs to a **subtask**, never to a whole story. If the input is a
single atomic piece of work, that is the subtask. If the input is a story that
bundles several pieces of work, break it into subtasks first — do not average
or eyeball one number across the bundle.

## 2. Score each subtask against the criterion

For every subtask, walk the table top-down and stop at the first row that
genuinely holds. Give:

- the **point value** (1, 2, or 3)
- a **justification anchored in that row's criterion** — name the specific
  unknown, or say plainly that there is none

The justification is not decoration — it's what makes the score auditable
later, when someone asks "why was this a 3."

## 3. Refuse 4 — split instead

If a subtask lands on 4, do not emit it as a score. Say so, then propose a
decomposition: break the subtask into smaller pieces until each one scores 1–3,
and score those instead. A 4 is the scale telling you the unit is too coarse to
estimate, not a valid data point.

## 4. Roll up the story score

The story's total is the **sum of its subtask scores** — never a single number
assigned to the story as a whole. Report both: the per-subtask breakdown and
the sum.

## 5. Optional: cycle capacity check

Only if the user gives a target (points per cycle), sum the scored subtasks
against it and say whether the set fits — a plain sum-versus-target, not a
velocity forecast or a schedule.

## Output format

```
## Score: <story or subtask name>

- <subtask 1> — <points> — <justification>
- <subtask 2> — <points> — <justification>
...

Total: <sum>
[Cycle target <target>: fits / over by <n>]
```

## Do Not

- Do not score a whole story as one number — score subtasks, sum them.
- Do not emit 4 — propose the split and score the resulting subtasks instead.
- Do not estimate deadlines, dates, or hours. Converting a point into time
  destroys the property that makes the scale portable across trackers.
- Do not prioritise or sequence the scored subtasks — that's a separate
  decision this skill does not make.
- Do not write the score back to Linear, GitHub, or any tracker — scoring and
  recording are separate steps; this skill only produces the number and its
  justification.
