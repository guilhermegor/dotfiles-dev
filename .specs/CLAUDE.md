# .specs/

This is the one home for work-in-flight feature specs and plans in this repo —
what `s:brainstorming` and `s:writing-plans` (the `superpowers` plugin skills)
produce before and during implementation, and what `s:work-breakdown`'s
auto-sizing step (dotfiles-dev#306) produces for a decomposed feature. See
dotfiles-dev#303.

## What belongs here

Per feature, one directory: `.specs/features/<feature-name>/`

- `spec.md` — `s:work-breakdown`'s always-present output: acceptance criteria,
  sized one-liner/brief/full per its auto-sizing table (#306)
- `design.md` — a feature's design decisions: either the `s:brainstorming`
  output, or `s:work-breakdown`'s own Large-scope decisions (#306). Never
  `architecture.md` — it records one feature's decisions, not the system's.
- `plan.md` — the `s:writing-plans` output (a single-agent implementation plan)
- `tasks.md` — `s:work-breakdown`'s Large-scope per-task breakdown for a
  decomposed, multi-issue feature (#306) — a different shape than `plan.md`,
  written only when the feature was split into parallel-dispatchable issues

`design.md`/`tasks.md` are omitted at smaller scope by design (see #306's
sizing table) — that means the decisions stay inline in `spec.md`, not that
they were skipped.

`<feature-name>` is a kebab-case slug, not a dated filename — the directory
holds both artifacts for one feature, and git history already carries the
timeline. No feature directories are created by #303 itself; this file only
defines the shape new ones follow.

## What does NOT belong here

- Shipped or reference documentation → `docs/`
- Backlog / issue-triage notes → `docs/backlog/`
- Anything meant to outlive the feature it was written for (ADRs, README,
  CLAUDE.md changes)
- An audit-gate verdict or a cross-feature progress tracker — those are
  #305 and #313, both undesigned. Do not invent a place for them here ahead
  of that work; it only has to be redone.

## What happens to a feature directory once it ships

Undecided — Q-2 in the epic (#302) is still open (does a shipped feature's
`.specs/features/<name>/` get deleted, archived, or left in place; does it
migrate anywhere). Leave existing directories alone until that lands; moving
them now would just relocate the same open question.

## The out-of-repo rule

Not every project gets a `.specs/`. A repo you contribute to but do not
own — did not choose its layout, did not scaffold it, can't add a top-level
directory to it uninvited — does not get `.specs/` added. For that category
of repo, specs live outside it entirely, at
`~/.claude/specs/<repo-slug>/features/<feature-name>/`, using the exact same
`design.md` / `plan.md` shape as above. That is the normal path for those
repos, not a fallback — the value is highest exactly where a fresh session
has the least context to reconstruct, which is precisely the unfamiliar
codebase this rule is for.

**Which of the two locations applies is asked, never inferred** — guessing
wrong is either an unwanted directory in someone else's repo, or a spec
written where nobody will look. The redirect logic that makes this decision
before `s:brainstorming` / `s:writing-plans` write anything lives in
`ai_clients/claude/config/CLAUDE.md` (deployed to every session, not just
this repo) — this file only defines the shape once a location is chosen.

The two locations are deliberately identical in shape: no relative path, no
CI gate, no `make` target may assume the in-repo tree, because any of those
would silently break the out-of-repo case.
