---
name: s:prisma-migrate
description: Use when writing, reviewing, or running Prisma Migrate commands or config — `migrate dev`, `migrate deploy`, `db push`, `migrate diff`, `migrate resolve`, the shadow database, or drift in a TypeScript/Prisma project. The tool-specific half of migration work; the reasoning that survives the tool changing (idempotency, DDL/DML risk, versioning with the app) lives in the ORM-agnostic sibling skill, not here.
effort: medium
argument-hint: [none]
---

The Prisma Migrate half of migration work — the part that is true of *this* tool and
would be wrong advice for Alembic or Flyway. Grounded against the current Prisma ORM
docs (schema.prisma-based config, Prisma ≤6, is still the common case; Prisma 7's
`prisma.config.ts` equivalents are called out inline where the two diverge).

⚠️ **Do not restate the agnostic rules.** Idempotency, versioning migrations with the
app, seeds vs. schema, the DDL/DML risk split — those are true of every migration tool
and belong in the ORM-agnostic sibling skill. A line that would also be correct for
Alembic or Flyway belongs there, not here.

## The three commands that look interchangeable and are not

🎯 The distinction to make first, because the names are close and the blast radius is
not:

| | what it does | where it belongs |
|---|---|---|
| `prisma migrate dev` | diffs schema vs. DB, **writes** a migration file, applies it | development only |
| `prisma migrate deploy` | applies **pending, already-written** migrations; writes nothing | CI/CD and production |
| `prisma db push` | pushes the schema **without a migration file at all** | prototyping only |

`migrate deploy` does not detect drift, does not reset the database, does not
generate any artifacts, and does not touch the shadow database at all — it is a pure
"apply what's already on disk" operation, which is exactly why it is safe for
production and CI. `migrate dev` is the opposite on every one of those points.

⚠️ **`db push` is the trap**, and it is the exact inverse of the agnostic rule "every
change is a migration." It reaches the same schema with **no versioned artifact**:
nothing to review, nothing to roll back, nothing another environment can replay. A
database that arrived by `db push` and one that arrived by `migrate deploy` are
indistinguishable by inspection and completely different by provenance. `db push` and
`migrate dev` can coexist deliberately — pushing to prototype a first draft, then
running `migrate dev` once satisfied to initialize real migration history — but that
is the only legitimate reason to reach for it after day one.

🔴 **`migrate dev` in production is destructive, not merely wrong.** On detecting
drift it offers to reset the database — dropping data — which is acceptable on a
throwaway dev database and catastrophic anywhere else. This is why Prisma ships two
commands instead of one with a flag: `deploy` structurally cannot do the thing `dev`
is built to do.

## The shadow database — the piece with no Alembic analogue

`migrate dev` needs a second, **temporary** database to replay migration history into
and diff against — created and dropped per run. This is the single most common reason
`migrate dev` fails on a managed provider: the connection must be allowed to *create*
databases, and the app's runtime user frequently cannot.

- **Prisma ≤6** — set `shadowDatabaseUrl` inside the `datasource db { ... }` block of
  `schema.prisma`.
- **Prisma 7** — set `datasource.shadowDatabaseUrl` in `prisma.config.ts` (via
  `env("SHADOW_DATABASE_URL")`), alongside `datasource.url`.

Either way it is the escape hatch for providers that won't grant CREATE DATABASE to
the app user. `url` and `shadowDatabaseUrl` must **never** point at the same database
— pointing both at one target can mean total data loss, since the shadow database is
wiped as part of the diff.

⚠️ **`migrate deploy` needs none of this.** It never touches a shadow database, so a
CI pipeline that only deploys and still demands `shadowDatabaseUrl` be configured is
protecting nothing while looking careful — cut it. Only pipelines that run
`migrate dev` (rare, and normally only for local/ephemeral test databases) need it at
all.

## Drift detection

Prisma compares three things — the schema file, the migration history, and the live
database — and any pair disagreeing is drift. Alembic has no equivalent: it compares
models against the DB only, and trusts its own version table.

`migrate dev` surfaces drift by offering a reset. That is correct for a local dev
database and wrong everywhere else, so the response differs by environment:

- **Drift found in dev** is usually a manual change (a column added by hand, a
  constraint tweaked in a GUI) that needs folding into a real migration — write it,
  don't just let `migrate dev` erase the difference by resetting.
- **Drift found in production is an incident.** `migrate resolve --applied <name>` or
  `migrate resolve --rolled-back <name>` marks a migration applied or rolled back
  **without running it** — the honest way out when a DBA already applied the SQL by
  hand and the migration history just needs to catch up to reality. It is also how
  you baseline an existing database into Prisma Migrate for the first time.

## `migrate diff` — the Prisma answer to Alembic's offline SQL

When production access is restricted to a DBA, generate SQL instead of applying it
directly — the same shape as Alembic's `--sql` flag:

```bash
# Forward: bring a target up to the current schema
npx prisma migrate diff \
  --from-url "$DATABASE_URL_PROD" \
  --to-migrations ./prisma/migrations \
  --shadow-database-url "$SHADOW_DATABASE_URL" \
  --script > forward.sql

# Backward: revert a target to a prior point in migration history
npx prisma migrate diff \
  --from-migrations ./prisma/migrations \
  --to-url "$DATABASE_URL_PROD" \
  --script > backward.sql
```

`migrate diff` also generates the very first migration from an empty starting point
(`--from-empty --to-schema-datamodel prisma/schema.prisma --script`), and supports
`--exit-code` so a CI check can tell "no diff" (0) from "diff present" (2) from
"error" (1) without parsing output.

## Where `prisma generate` fits — version-dependent, and worth checking per project

⚠️ **This changed across major versions — verify against the installed Prisma
version rather than assuming.**

- **Prisma ≤6**: `migrate dev` (and `db push`) automatically re-run
  `prisma generate` after applying changes — the client is always in sync with the
  schema you just migrated to.
- **Prisma 7**: neither `migrate dev` nor `db push` regenerates the client anymore.
  `prisma generate` must run as an explicit step after every schema change, or the
  client silently serves stale types until someone runs it. This is exactly the same
  failure shape as Alembic's `Base.metadata.create_all` trap in reverse: a command
  that used to do the right thing implicitly, on the version everyone assumes is
  installed.

`migrate deploy` never generated the client on any version — production/CI builds
must always call `prisma generate` explicitly (commonly `"build": "prisma generate && <build>"`
in `package.json`), independent of which Prisma major is in use.

## Boundaries

- ⚠️ **The active repository's conventions win** over anything here — migration
  folder layout, naming, whether DML is allowed in a migration at all.
- The *why* of evolutionary schema design — idempotency, versioning with the app,
  the DDL/DML risk split — is the ORM-agnostic sibling skill's job, not this one's.
  For the SQL-specific reasoning underneath a Prisma migration (raw statements inside
  a migration, transactional DDL), defer to whatever SQL/database-migration skill
  the project has for that layer — this skill only owns the `prisma` CLI surface.
- This is a skill, not a template change. What Prisma config a generated project
  receives is a scaffolding concern, not this skill's.

## Do Not

- Do not run `migrate dev` against a staging or production database — use `deploy`.
- Do not use `db push` past the initial prototyping phase of a project.
- Do not require `shadowDatabaseUrl` in a pipeline that only runs `migrate deploy`.
- Do not assume `prisma generate` runs implicitly — check the installed Prisma major
  version before relying on `migrate dev`/`db push` to regenerate the client.
- Do not restate agnostic migration reasoning here — point to the sibling skill
  instead of duplicating it.
