# Code Comments — the Macro Rule

Shared prose for every code-emitting skill (`py-*`, `bash-create`, the SQL/ORM
family, `prisma-migrate`). Not a skill itself — no frontmatter, no `s:` name,
never loaded by the Skill tool. Referenced by a one-line pointer plus the
`Read` tool, the same relationship those skills already have with
`py-standards.md`.

## The rule

**An explanation long enough to need a comment is documentation in disguise.**
It belongs in `docs/`, `CONTRIBUTING.md`, `README.md`, or `.specs`, with at
most a one-line pointer left in the code — or the code is decomposed into
units small enough to explain themselves. See `rules/common.md` →
Documentation for the decomposition mechanics (smaller named function over a
comment that explains a block); this file does not restate that section.

## Exempt: QA suppressions

Suppression directives are machine-read markers, not explanatory prose — they
stay, however long the surrounding line:

- `noqa`, `type: ignore`, `complexity-ok`, `codespell:ignore`
- any other lint/type/complexity suppression a project's own tooling defines

This list is anticipatory, not a tally of what has appeared so far — a
directive with zero occurrences today (`codespell:ignore`) is exempt from the
first time it is written, not from whenever it happens to become common.

## Respect the target project's own constraints

Emitted code must honor the project's own cyclomatic complexity ceilings,
one-class/one-thing-per-module rule, and module/folder organization — read
the target project's `CLAUDE.md`/`rules/`/lint config before emitting, and
follow it over any default assumed here.
