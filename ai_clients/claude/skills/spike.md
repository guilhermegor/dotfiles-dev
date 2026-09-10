---
name: s:spike
description: Use when an uncertainty is about feasibility or feel rather than agreement — whether a state model holds up, whether an API is shaped the way you think, what a screen should look like — and the fastest way to find out is to build the smallest throwaway thing and look at it, rather than write a spec for something not yet understood.
effort: medium
argument-hint: [the question the spike must answer]
allowed-tools: Read Glob Grep
---

> **Priority:** this project's `CLAUDE.md` and `rules/*.md` take precedence over the guidance below whenever they conflict — treat this skill as a fallback, not a mandate.

A spike is **throwaway code that answers a question.** The question decides the shape.

## Spec first, or spike first — pick by the kind of uncertainty

Not every uncertainty is resolved by specifying harder. There are two kinds:

- **Uncertainty about *agreement*** — what should this do, who decides, what counts as
  done — is resolved by specifying. Write the spec.
- **Uncertainty about *feasibility or feel*** — does this state model hold up, is this
  API shaped the way I think, does this interaction feel right — is resolved by building
  the smallest thing that answers it and looking at it. Use this skill.

Specifying a thing you do not yet understand produces a confident document about a guess.
That is worse than no document, because it gets treated as the agreement it never was.

## Pick a branch — the question decides the artifact

Identify which question is being answered, from the prompt, the surrounding code, or by
asking if the user is around. The two branches produce **very different artifacts**, so
getting this wrong wastes the whole spike.

- **"Does this logic / state model feel right?"** → build something that pushes the state
  machine through the cases that are hard to reason about on paper, and that a
  non-developer can drive. A single shareable HTML file with free-play buttons plus a
  guided walkthrough is the richest form; for a shell or Python module, a small
  interactive script is usually enough.
- **"What should this look like?"** → generate several *radically different* variations on
  one route or screen, switchable without a rebuild (a URL search param and a floating
  switcher bar). Several bland variations answer nothing — the spread is the point.

If the question is genuinely ambiguous and the user is not reachable, default by shape —
a backend module or a hook is a logic question, a page or component is a UI one — and
state the assumption at the top of the spike.

## Rules that apply to both

1. **Throwaway from day one, and marked as such.** Put the spike next to the module or
   page it is spiking for, so the context is obvious — but name it so a casual reader
   sees immediately that it is not production. Follow whatever routing or layout convention
   the project already has; do not invent a new top-level structure for it.
2. **Trivial to run.** One command from the project's own task runner (`make …`,
   `pnpm …`, `python …`), or a single file the user double-clicks. No thinking required to
   start it, or it will not get run.
3. **No persistence by default.** State lives in memory. Persistence is usually the thing
   being *checked*, not something to depend on. If the question genuinely involves a
   database, use a scratch one with an unmistakable "SPIKE, wipe me" name.
4. **Skip the polish.** No tests, no error handling beyond what makes it runnable, no
   abstractions. ⚠️ This is the one place in this toolchain where "leave a runnable check
   behind" does **not** apply — a spike that earns a test suite has stopped being
   throwaway.
5. **Surface the state.** After every action, or on every variant switch, print or render
   the full relevant state. An answer you cannot see is not an answer.
6. **Capture it when done — as a primary source, not garbage.** Fold the validated decision
   into the real code. Then commit the spike itself to a **throwaway branch, off main**,
   and leave a pointer to that branch on the implementation issue, along with the verdict and
   the question it settled. The main branch keeps only the validated decision.

⚠️ Rule 6 is the one most often got wrong in both directions. Deleting the spike outright
throws away the evidence for a decision someone will question later; merging it ships code
nobody specified. The branch-plus-pointer keeps the evidence reachable and unmergeable.

## Name the question before writing anything

If you cannot state the question in one sentence, you are not ready to spike — go find
the question first. Well-formed examples:

- "Does this state machine handle cancel-during-retry without a third state?"
- "Is this the shape I think it is once real pagination tokens flow through it?"
- "Does swipe-to-dismiss feel right at this velocity threshold, or does it need a bigger
  deadzone?"

## Record the answer where the uncertainty lives

The deliverable is the answer, not the diff. Put it where the question came from:

- an assumption, marked resolved;
- an open question, marked answered;
- a line in the feature's design notes stating what was learned.

If the answer changes the plan, that is a normal planning update — it just happened before
the spec was written instead of after, which is the entire point.

## Do Not

- Do not specify a design you do not yet understand — spike the unclear part first.
- Do not let the spike grow past the one question it was built to answer.
- Do not merge spike code into main, even after cleanup. If it is worth merging, it is
  worth specifying and rewriting as real work.
- Do not skip naming the question — an unnamed question produces an unscoped spike that
  never finishes.
- Do not build several *similar* UI variations. If they could be confused for each other,
  they answer nothing.
