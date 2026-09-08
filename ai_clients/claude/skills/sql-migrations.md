---
name: s:sql-migrations
description: Use when designing, reviewing, or writing database schema migrations for any tool — Alembic, Flyway, Liquibase, Prisma Migrate, Rails ActiveRecord::Migration, golang-migrate, sqlx. Evolutionary database design reasoning that holds regardless of which migration tool is in play. For Alembic/SQLAlchemy-specific commands and flags, see s:sql-alembic.
effort: medium
argument-hint: [none]
allowed-tools: Read Glob Grep
---

> **Priority:** this project's `CLAUDE.md` and `rules/*.md` take precedence over the guidance below whenever they conflict — treat this skill as a fallback, not a mandate.

**Comment discipline:** read `~/.claude/skills/code-comments/SKILL.md` before
emitting a migration — an explanation long enough to need a comment is
documentation in disguise; put it in `docs/` and leave at most a one-line
pointer.

Evolutionary database design: the reasoning that is true whether the tool is Alembic,
Flyway, Liquibase, Prisma Migrate, ActiveRecord, golang-migrate, or sqlx. This skill is
the agnostic half — the tool-specific half is `s:sql-alembic`.

Source: *Refactoring Databases — Evolutionary Database Design* (Ambler & Sadalage).

## The argument

A schema modelled once, up front, before the software starts is a bet that the design
was right the first time. Agile delivery reshapes a system continuously, so the schema
must be refactored continuously too. The alternative to "design it all up front" is not
"no design" — it is **incremental design with a versioned, reversible history**, checked
into the same repository as the code that depends on it.

What that buys, and each is a failure mode when absent:

- every schema change lives in one place, in commit order;
- an incident can roll the schema back the way it rolls the code back;
- app and schema cannot drift, because one commit carries both;
- any environment — laptop, CI, staging — is rebuildable from zero to any revision.

## Rules

- **Every schema change is a migration.** Not "every change a DBA remembers to script" —
  every change, including a hand-run 2am incident fix. A schema state no migration
  produces is a state no environment can be rebuilt into.
- **A migration is versioned WITH the application.** Same repository, same commit, same
  review. A migration in a separate repo reintroduces the drift the practice removes.
- **Both directions.** `up` and `down`. A `down` that cannot faithfully reverse a data
  change should say so in its docstring and refuse, rather than write a lossy inverse
  that looks like a rollback and is not.
- **Idempotent by construction.** Re-running a migration is a no-op, not an error and not
  a duplicate. This is what makes dev/CI/prod reproducible rather than merely similar.
- **Migrations carry more than schema.** Seeds the system needs to operate, default
  rows, an administrative user, fixture test data. These have different lifetimes and
  different blast radii from a `CREATE TABLE` — name the distinction rather than letting
  a seed and a schema change look identical.
- **CI applies migrations too.** A migration that only ever ran on a developer's machine
  is untested. The pipeline must build a database from zero and apply the full history.

## The DDL / DML split, and why "DDL only" is a real position

| | changes | rollback | typical blast radius |
|---|---|---|---|
| **DDL** (`CREATE`/`ALTER`/`DROP`) | structure | loses structure | usually fast on modern engines |
| **DML** (`INSERT`/`UPDATE`/`DELETE`) | data | **loses data** | can lock a large table for minutes |

Many teams allow only DDL in migrations, for legitimate reasons: a poorly written DML is
not idempotent; an `UPDATE` without a suitable index can lock a table with millions of
rows long enough to take the application down; dev/staging/prod hold *different data*,
so an `UPDATE` verified against ten local rows can violate a constraint in production;
and a DDL rollback loses structure while a DML rollback can lose unrecoverable
information.

**"DDL only" still does not close.** Splitting `full_name` into `first_name` and
`last_name` is a schema refactor whose entire point is moving data. The honest position
is DDL **and** DML with discipline:

1. guard every DML with a predicate that makes a re-run a no-op (`WHERE col IS NULL`);
2. batch it when the table is large, rather than one statement over millions of rows;
3. order it as **add nullable → backfill → constrain**, so no window exists where the
   schema demands a value the data does not yet have;
4. let a data `downgrade()` refuse loudly instead of guessing.

## Two failure modes this skill exists to prevent

Both are **silent**, which is why prose about "being careful" does not fix them:

- **A migration that generates nothing.** Many tools compare only what they are
  configured to compare; a change outside that set produces an empty migration and a
  successful exit. The tool reports success for having detected nothing.
- **A migration that runs on the wrong database.** A connection string committed to the
  repository is both a leak and an inflexibility. One code path resolves the DSN from
  the environment, with local/CI and production differing only in that value — never a
  second config file, never a hardcoded URL under version control.

## Boundaries

- **The active repository's conventions win.** Where this skill and a project's
  `CLAUDE.md`/`CONTRIBUTING.md` disagree — file naming, folder name, commit format, the
  DDL/DML rule — the project decides. Say so explicitly rather than assuming.
- No tool-specific commands here. `revision --autogenerate`, `env.py`, batch mode — see
  `s:sql-alembic`.
- Naming a migration file is deliberately out of scope — a local, project-specific
  convention, not a community standard.

## Related

- `s:sql` — the DQL/DDL/DML/DCL/TCL taxonomy this skill's DDL/DML split assumes.
- `s:sql-alembic` — the Alembic + SQLAlchemy implementation of everything above.
- `s:sql-orm` / `s:sql-sqlalchemy` — model definition, not migrations; migrations are
  this skill's and `s:sql-alembic`'s job.
