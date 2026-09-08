---
name: s:work-breakdown
description: Use when a problem has already been bounded (an `s:problem-framing` artifact exists, or scope is otherwise clear) and needs to become a set of issues ready to dispatch to parallel subagents. Orchestrates discovery, conditional prototyping, epic/issue decomposition, blast-radius partitioning (file collision AND file count), test-case enrichment, and handoff to `s:dev-loop`. Also use when the user says "break this into issues", "turn this into tickets I can parallelize", or "what can go out as separate PRs".
effort: high
argument-hint: [<shaped problem | issue #>]
allowed-tools: Read Glob Grep Bash AskUserQuestion
---

> **Priority:** this project's `CLAUDE.md` and `rules/*.md` take precedence over the guidance below whenever they conflict — treat this skill as a fallback, not a mandate.

# Work Breakdown — a problem into provably non-colliding issues

You are the layer between "problem is bounded" and "one ticket per subagent." This skill
**orchestrates other skills** — it does not reimplement discovery, shaping, issue creation, test
conventions, or execution. Each already exists; the gap is decomposing a bounded problem into N
issues that a fleet of subagents can run **in parallel without stepping on each other**, and
proving it rather than assuming it.

## What this skill does NOT do

| Piece | Owner | This skill |
|---|---|---|
| Bound the problem (appetite, scope cuts, out-of-scope) | `s:problem-framing` | starts where it ends |
| Create one issue + card + branch (work type, `hitl`/`afk`, assignee, column) | `/issue` | calls it per leaf, never reimplements it |
| Test conventions (AAA, `parametrize`, fixtures, properties) | `s:test` / `s:py-unit-test` / `s:py-hypothesis` | decides *which* apply, not *how* |
| Execute (quality gate, CI, review, merge, release) | `s:dev-loop` | hands off the finished set |

If a shaping artifact for this problem does not exist and the request looks like a persona-plus-
goal with no appetite set, load `s:problem-framing` first. Do not shape inline here.

---

## 1. Discovery

Establish what the problem actually is **against the existing code**, not against the request as
phrased. Read the touched area before writing anything down. End in a statement and acceptance
criteria — never in a solution. If discovery surfaces a design decision only the user can make, ask
it now; a decomposition built on an unresolved "what" collides by construction later.

## 2. Prototyping — conditional, and the rule has to be written down

"Prototype if needed" with no test collapses to "always" or "never." The test:

| Uncertainty is about | This is | Action |
|---|---|---|
| **how** — feasibility, API shape, cost | a prototype question | build a throwaway artifact; it answers cheaper than discussion |
| **what** — acceptance criteria itself | not a prototype question | back to discovery, not a spike |

Skip this step entirely when discovery already answered both.

## 3. Epics, issues, subissues

Hierarchy only when there are **two or more independently shippable deliverables** — the same bar
`/issue --parent` already uses. Every leaf becomes one call to `/issue`, which already resolves work
type, `hitl`/`afk`, assignee, oracle strength, card, and branch. Do not re-derive any of that here;
pass the leaf description through.

A flat set of issues (no parent) is the default and the common case. Reach for a parent only when
the deliverables genuinely do not stand alone — see the file-count split below for a case that
looks like this but is not.

## 4. Blast-radius partition — the part that makes "parallel" provable

This step decides what N subagents can actually run at once. Two independent constraints, both
mandatory, checked in order: **collision**, then **file count**.

### 4a. Collision is per FILE, never per directory

🔴 Partition by exact file path. Two issues in the same directory do not collide; two issues
touching the same file always do. Measured (dotfiles-dev#194): a per-directory calculation flagged
**9 of 11** candidate issues as colliding; redone per exact file, only **6 nominal files of 43**
were contended — most of the batch was free and the coarse calculation would have discarded it.

```bash
rtk gh pr view <n> --json files --jq '.files[].path'   # per open PR, if any exist yet
```

Build the file set each candidate issue would touch (from discovery, not guesswork) and intersect
pairwise. Two issues with disjoint file sets can run in parallel; any shared file serializes them.

### 4b. Wiring files are a serialized resource, not just another collision

A partition that ignores **wiring files** — the files where a new item *registers itself*
(`.pre-commit-config.yaml`, a `STEPS` array, a plugin manifest, a router table) — produces a batch
that is "parallel" in name only. Measured 2026-09-05: seven gate issues with completely disjoint
logic all needed to touch the same two wiring files. Whichever PR holds them blocks the other six
even though none of their actual logic collides.

- Identify the repo's wiring files up front — grep for the registration point a new item of this
  kind would need (a `case` dispatch, a manifest, a `STEPS`/routes array).
- Treat each one as an explicit serialized resource in the plan, not a normal collision.
- Where possible, split the leaf into **implement** (parallel — the new logic, its own file) and
  **wire** (serial — the one-line registration) so the bottleneck is a short step at the end, not
  the thing blocking the start.

### 4c. File count is a hard constraint too — collision-free is not enough

⚠️ A batch can be fully collision-free and still be unmergeable: a large diff can exceed the
**reviewer's** file-count ceiling outright, and that failure does not expire. Measured
(blueprintx#433): a 231-file reindentation PR hit CodeRabbit's 100-file limit — *"Review skipped:
231 files exceed the limit of 100"* — with no reviewer report ever possible. The required check
demands a report; the reviewer refuses on file count; rebasing changes nothing. Permanent deadlock,
not a queue.

**Read the limit from the repo, never hardcode it.** `.review-bots.yaml` already holds this repo's
reviewer roster — read a `file_limit` from it if present. If the repo declares none, fall back to
the documented default: **limit 100, split threshold 85.** The 15-point margin exists because the
count at planning time is an *estimate* — a PR reliably grows between plan and open (a test file, a
doc line, a `CHANGELOG` entry), and 15% of headroom costs one extra issue against a failure whose
only remedy is splitting after the PR is already stuck.

**Two branches — the naive "split above N" rule only covers one of them:**

| Branch | Signal | Action |
|---|---|---|
| **A — decomposable** | files change for different reasons; a partial split leaves a valid intermediate state | split at the threshold, **as separate sibling issues** |
| **B — atomic mechanical** | the diff is produced by running one tool (`ruff format`, `eslint --fix`, a codemod); a single config line drives every changed file | do **not** split — flag the review-gate exemption instead |

Decide with the checklist, not judgment — it is meant to be decidable:

- Is the diff produced by running a tool, not written by hand? → B.
- Does one config line (an indent style, a formatter rule) drive every changed file? → B.
- Do the files change for unrelated reasons? → A.
- Would a partial split leave a valid, buildable intermediate state on `main`? → A, if yes.

**Branch A.** Split the leaf into sibling issues at the threshold, sized by coherent slices (not an
arbitrary file-count chop). ⚠️ **Sibling issues, not parent/sub-issues** — step 3's hierarchy
guarantees "one PR per piece, each independently mergeable"; a parent-plus-children split implies
branching from the first child, which is the opposite of what a file-count split needs. Each sibling
is its own `/issue` call, its own branch, its own PR, and none of them contains the others.

**Branch B.** Do not recommend splitting — the 92-of-100 files in the measured case were formatter
output; isolating the other 8 leaves the 92 exactly as blocked, and a partial split of the 92 leaves
`main` with a config that describes a tree it does not match, failing the format check on every
subsequent PR. Instead, write into the issue:

> ⚠️ This change is mechanically generated and cannot be split below the reviewer's limit. Human
> review of formatter output is theatre — the correct verification is re-running the formatter and
> confirming the tree does not move. Confirm the gate has an exemption path before starting.

Flag this as a **prerequisite**, not a follow-up — the exemption has to exist before the issue is
dispatched, not after it gets stuck.

### The tension — ask for both numbers

Collision cost pushes a change **bigger** (fewer shared-file rebases); reviewability pushes it
**smaller** (under the file-count ceiling). Only the collision cost is visible at planning time (N
issues × a rebase each), which is why it wins by default when nobody asks the other question. This
step must compute **both** — the collision count from 4a/4b and the file count from 4c — before
deciding a batch's shape. A batch that wins on collision and loses on file count is not done.

## 5. Enrich each issue with test cases — before dispatch, not after

For every leaf issue, decide (not implement) what the ticket requires:

- **Unit** — AAA structure, `parametrize` for the input/output table.
- **Integration / e2e** — where the change crosses a boundary.
- **Performance** — only when it pays (e.g. an API call, a hot path).
- **Fixtures** — what setup the tests need.
- **Properties** — when the case is an invariant, not an example: commutativity, identity element,
  round-trip. Reach for this when "for all X" is the actual claim, not "for this X."

The *how* (AAA shape, parametrize table format, hypothesis strategy) is `s:test` /
`s:py-unit-test` / `s:py-hypothesis`'s job — load whichever applies while writing the issue body.
This step only decides which categories a given ticket needs, and writes that into its Escopo
before it goes out, so the subagent that picks it up already knows what "done" tests for.

## 6. Handoff

The batch — issues, milestone, labels, wiring-file notes, file-count split, test requirements — goes
to `s:dev-loop`. The boundary is hard: this skill decides **what** and **in what order**;
`s:dev-loop` **does**. Do not start dispatching subagents from inside this skill.

---

## Do Not

- Do not reimplement `s:problem-framing`, `/issue`, the test skills, or `s:dev-loop` — call them.
- Do not partition by directory. Only exact file paths prove non-collision (dotfiles-dev#194).
- Do not treat wiring files as an ordinary collision — they serialize a whole batch if missed.
- Do not stop at collision-free. A collision-free batch can still fail the reviewer's file-count
  ceiling outright; check both.
- Do not hardcode the file-count limit. Read it from the repo's `.review-bots.yaml` (or documented
  equivalent); fall back to 100/85 only when the repo declares nothing.
- Do not recommend splitting an atomic mechanical change (Branch B) — flag the review-gate
  exemption instead, as a prerequisite.
- Do not split a file-count batch into parent/sub-issues. Siblings only — a split exists to make
  each piece independently mergeable, and hierarchy implies the opposite.
- Do not skip the prototype-vs-discovery test in step 2 — "prototype if needed" with no test is not
  a rule.
