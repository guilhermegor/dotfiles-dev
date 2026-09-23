---
name: s:intake-plan
description: Use when a refined queue of issues needs a concurrency plan before dispatch — "what can I run in parallel right now", "compute the dispatch set", or after s:intake-refine has scored and placed a batch of candidates and before s:dev-loop DISPATCH picks from them.
effort: medium
argument-hint: [owner/repo, default: current repo]
allowed-tools: Bash Read Glob Grep
---

# s:intake-plan

Planning only. Take the refined queue (the output of `s:intake-refine`, #425)
and compute which issues can run **simultaneously** — a set whose file
surfaces do not intersect, sized to the API budget — and print it as the
dispatch plan. Do not dispatch anything: `s:dev-loop`'s DISPATCH step reads
the plan and decides. Do not judge which free issue to run first or write a
brief — that stays DISPATCH's job.

Parent: `s:intake` (#422).

**Comment discipline:** read `~/.claude/skills/code-comments/SKILL.md`
before writing anything durable this skill produces (the printed plan, if
saved to disk) — not restated here.

## 🔴 Reuse the gate, never re-derive collision

`ai_clients/claude/hooks/lib/free_surface.sh` already answers "which open
issues does no PR hold" and classifies a candidate file list against what's
held. This skill's job is supplying that gate the right candidate lists
(each issue's declared File surface) and layering the two constraints below
on top of the free/held/would-need verdict it returns — never a second
collision implementation.

```bash
cd /absolute/path/to/<repo> && source ai_clients/claude/hooks/lib/free_surface.sh
gate_free_surface <owner> <repo> || echo "free surface UNKNOWN — do not plan on it"
```

`FREE_UNCLAIMED_ISSUES` is the candidate pool: an open issue with no PR
(open or merged) closing it. Everything below operates only on that pool.

⚠️ **Collision is exact-path, file by file — never a directory prefix.**
Measured 2026-09-04: a directory-level "concentration" summary reported 9
of 11 candidates as colliding; the exact recount showed a directory holding
6 of 200 files was 97% free. `free_classify_files` already does this
correctly — call it per issue, never summarize by directory.

## 1. Parse each candidate's File surface

A refined issue body carries a fenced ` ```surface ` block, one glob per
line:

    ```surface
    templates/*/src/chassis/db_schema/infrastructure/*_handler.py
    templates/python-common/CLAUDE.md
    ```

For each candidate in `FREE_UNCLAIMED_ISSUES`:

1. Read the issue body: `rtk gh issue view <n> --json body --jq .body`.
2. Extract the ` ```surface ` block.
3. Expand each glob against the worktree (`compgen -G` or `find`, per
   pattern — never assume a pattern matches something).

⚠️ **A surface block that is absent or wrong makes an issue UNPLANNABLE,
not parallel-safe.** Missing block, unparseable block, or a glob that
expands to nothing → mark the issue UNKNOWN and exclude it from the
concurrent set. Never default an unreadable surface to "collides with
nothing" — defaulting UNKNOWN to free is the same failure class #422
measured for directory-level aggregates, just at the missing-data end
instead of the summarized-data end. Report every UNKNOWN back so its
`File surface` block gets fixed.

## 2. Classify each candidate against the gate

Run `free_classify_files <candidate's expanded paths>` for every candidate
that parsed. Three states, not two:

- `free` — no open PR holds any of these paths → eligible.
- `held:<paths>` — every path is held → excluded, reason: blocked by the PR
  holding `<paths>`.
- `would-need-a-held-file:<paths>` — some paths free, one held → still
  eligible (usually one trivial line; land the conflict as its own commit
  at the end, per `s:dev-loop`'s own rule) — never collapse this into
  `held`.

## 3. Resolve collisions BETWEEN candidates, not just against open PRs

Two candidates the gate calls free can still collide with **each other** —
the gate only checks against open PRs and pushed branches, never against a
sibling candidate that has no branch yet. Pairwise-compare every eligible
candidate's expanded path set against every other candidate's:

- No intersection → both eligible in the same round.
- Intersection → **name an owner for the round, mark the rest
  blocked-on-owner.** Never let two candidates both believe they hold a
  path. Measured 2026-09-20: `templates/python-common/CLAUDE.md` was wanted
  by four issues at once (#561, #325, #549, #273) with no owner named, and
  a silent instance of this same failure put two worktrees on one branch
  the same day. Pick the lowest issue number, the highest `s:story-score`,
  or whatever tie-break the queue states — pick one and say why.

## 4. Cap the round by the API budget, and say why

⚠️ **API budget bounds concurrency before file collision does.** Measured
2026-09-20: 5 concurrent agents plus orchestrator queries drained the
5000/h **per-user** GitHub quota in roughly 35 minutes, and both the REST
and GraphQL buckets went flat 4 times in one day (`gh` mixes the two
buckets invisibly).

Derive the cap instead of hardcoding it:

1. Check remaining quota: `rtk gh api rate_limit --jq
   '.resources.core.remaining, .resources.graphql.remaining'`.
2. Divide the smaller bucket by the measured 2026-09-20 cost of roughly
   1000 calls per agent-hour (including this session's own orchestrator
   queries) — recompute this ratio if a later round measures a different
   cost, and state what changed.
3. Cap the round at the smaller of that number and the collision-free
   set's size from steps 2–3.

State the derivation in the output, not just the resulting number — a cap
with no derivation is a magic number the next session will raise blind.

## Output shape

Enough for a brief to be generated from it, not prose:

```
## Dispatch plan — <owner>/<repo>, <timestamp>

Concurrency cap: N (derivation: <quota / cost-per-agent math>)

ELIGIBLE (this round, N of M):
  #<issue> — surface: <expanded paths>
  ...

BLOCKED-ON-OWNER:
  #<issue> — <path> owned by #<owner-issue> this round

EXCLUDED:
  #<issue> — held:<paths held by PR #<n>>
  #<issue> — UNKNOWN: <missing surface block | glob matched nothing | ...>
```

## This is advisory input, never a dispatcher

⚠️ This skill emits the plan and stops. `s:dev-loop` DISPATCH reads it and
decides what actually runs — this repo has refused to build a router with
no consumer before (`/issue`'s oracle labels are "deliberately a query, not
an orchestrator"). Never spawn agents, open branches, or write briefs from
inside this skill.

## Documentation

Both measured constraints — the API-budget derivation and the
single-writer contention rule — live in this file with their numbers, so a
future session cannot silently raise the cap or drop the owner-assignment
step without noticing what broke.
