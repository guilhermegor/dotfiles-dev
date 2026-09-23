---
name: s:intake-refine
description: Use when open issues sit on the tracker with no work type, no oracle strength, no score, or no board card — "refine the backlog", "get the queue dispatch-ready", "classify these issues" — typically after s:intake-discover has filed candidates and before s:dev-loop DISPATCH runs.
effort: medium
argument-hint: [owner/repo, default: current repo] [--quick]
allowed-tools: Bash Read Glob Grep Skill AskUserQuestion
---

# s:intake-refine

Refinement only. Take issues that are on the tracker but not dispatchable —
missing work type, mode, oracle strength, score, or board card — and close
every gap until `s:dev-loop` DISPATCH can select from them without
re-reading a single title. Do not discover unfiled work (`s:intake-discover`,
#424) and do not compute parallelism (`s:intake-plan`, #426). Do not
re-score an issue that already has one — a present score is kept, never
re-derived.

Parent: `s:intake` (#422).

**Comment discipline:** read `~/.claude/skills/code-comments/SKILL.md`
before writing anything durable this skill produces (a label description,
a report saved to disk) — not restated here.

## 🔴 Reuse, never restate

- **`c:issue`** (`~/.claude/commands/issue.md`) owns the three axes
  (conventional type / work type / oracle strength), the work-type→column
  map (step 4), the score-then-create/update sequence (step 5a), and the
  board-card placement (step 7). This skill applies those exact steps per
  candidate — it does not carry its own copy of the table or the mapping.
- **`s:story-score`** owns the 1–3 uncertainty scale and the refuse-4-
  and-split rule. Load it via the Skill tool for step 5a; do not restate
  the scale here.

⚠️ **`/issue` is a slash command, not a callable subroutine.** Commands are
user-invoked only (`ai_clients/CLAUDE.md` § 3 vs § 1) — a skill cannot
dispatch `/issue` the way a user types it. Reuse here means: **read
`~/.claude/commands/issue.md`'s steps 4, 5a, and 7 and carry out the same
commands they document, per candidate**, never invoke the command itself
and never re-derive a parallel version of its tables. If a mechanical
per-issue driver ever needs to invoke `/issue` as a subroutine rather than
an agent following its steps, building that driver is separate, larger
work — file it. Do not fork step 4/5a/7's logic to route around the gap.

## 1. Resolve the target and the candidate pool

Resolve `owner/repo` from the argument, else the current repo
(`rtk gh repo view --json name,owner --jq '.owner.login,.name'`).

**Screen only issues with no open PR.** A labelled-but-in-flight issue
changes no dispatch decision — measured on blueprintx 2026-09-20: 10 of 41
open issues had no PR, the other 31 gained nothing from re-classifying.
One query gets the claimed set (any PR, open or merged, that closes an
issue — a merged PR that forgot `Closes #N` still leaves the issue open
and correctly unclaimed):

```bash
rtk gh api graphql -f query='{search(query:"repo:<owner>/<repo> is:pr",type:ISSUE,first:100){nodes{... on PullRequest{closingIssuesReferences(first:5){nodes{number}}}}}}' \
  --jq '[.data.search.nodes[].closingIssuesReferences.nodes[].number] | unique'
```

Then list open issues and subtract that set:

```bash
rtk gh issue list --repo <owner>/<repo> --state open --json number,title,body,labels --limit 200
```

A candidate is an open, unclaimed issue missing **any** of: a work-type
signal (issue type or `type:*` label), a mode label (`hitl`/`afk`), an
oracle label (`oracle:strong`/`oracle:weak`), a score (board `Points`
field), or a board card. An issue already carrying all five is fully
refined — drop it from the pool, do not touch it.

## 2. Probe issue types read-only, once

Before classifying anything, probe whether this repo has GitHub issue
types configured — `/issue` step 4's exact read-only query, reused
verbatim (never let `--type` on a mutating call be the probe):

```bash
rtk gh api graphql -f query='query($o:String!,$r:String!){repository(owner:$o,name:$r){issueTypes(first:20){nodes{name}}}}' \
  -F o=<owner> -F r=<repo>
```

No matching type names → every candidate uses the `type:<work-type>`
label fallback for the rest of this skill. A matching set → issue-type
field is available; `/issue` step 4 still decides which to use per
candidate.

## 3. Classify each candidate — bounded interactive cost

⚠️ **Bound the interactive cost or this is not a skill, it is an
afternoon.** Follow `--quick`'s existing contract from `c:issue`: accept
the derived classification and score without a per-issue confirmation,
and surface everything as one table for the operator to correct in a
single pass — never one `AskUserQuestion` per issue.

For each candidate, in order:

1. **Work type, mode, oracle strength** — `c:issue` step 4's table and
   test, applied by reading the issue's title and body (do not ask).
2. **Score** — load `s:story-score` via the Skill tool, passing the
   issue's Scope/description. A subtask landing on 4 is not scored;
   carry the skill's proposed split into the report instead of a number
   (see Output below) rather than forcing a value.
3. **Starting column** — `c:issue` step 4's work-type→column map, applied
   to the work type from (1).

## 4. Report the batch, then apply on confirmation

Print one table, then a single `AskUserQuestion`
(`Apply these N classifications?` / `Let me correct rows first`) covering
the whole batch — not one per row:

```
| # | Title | Type | Mode | Oracle | Score | Column |
|---|-------|------|------|--------|-------|--------|
| 512 | ... | task | afk | oracle:strong | 2 | Ready |
| 513 | ... | research | afk | oracle:weak | SPLIT (4): <skill's decomposition> | — |
```

A `SPLIT` row is not applied in step 5 — flag it for the operator to
re-file as smaller issues via `/issue`, per `s:story-score`'s own rule.

## 5. Apply — `c:issue` steps 4/5a/7, per confirmed row

For each confirmed, non-`SPLIT` row: create any missing label first
(`rtk gh label create "<name>" --force`, per step 4's label-exists note),
attach the work-type/mode/oracle labels (or `--type` if step 2 found a
match), add the card to the `<repo> kanban` project if not already on it,
set its Status to the derived column, and set its `Points` field to the
score — the exact operations step 7 documents, applied here rather than
re-described.

## Non-goals

- Do not discover unfiled work — that is `s:intake-discover` (#424).
- Do not compute parallelism or a dispatch order — that is `s:intake-plan`
  (#426).
- Do not re-score an issue that already carries a score.
- Do not touch a labelled-but-in-flight issue (has an open or merged PR
  closing it) — classifying it changes no dispatch decision.

## Documentation

The measured counts above (10/41 unclaimed, 31/41 zero-labelled) are this
skill's justification and stay in this file with their numbers, so a
future session cannot silently drop the no-open-PR screen without
noticing what it costs.
