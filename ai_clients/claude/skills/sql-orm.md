---
name: s:sql-orm
description: Use when writing, reviewing, or debugging ORM or query-builder code for any framework — SQLAlchemy, Prisma, Django ORM, ActiveRecord, or similar. Model/migration parity, N+1 queries, session/connection lifetime, and where database constraints end and application validation begins, stated framework-agnostically. For raw SQL hazards see s:sql; for SQLAlchemy specifically see s:sql-sqlalchemy.
effort: medium
argument-hint: [none]
allowed-tools: Read Glob Grep
---

The ORM/framework-agnostic layer of the SQL skill family: reasoning true of SQLAlchemy,
Prisma, Django ORM, ActiveRecord, and any comparable tool. Raw-SQL hazards are `s:sql`;
the SQLAlchemy-specific implementation is `s:sql-sqlalchemy`.

## Model / migration parity

The model definitions in code and the migration history that built the live schema must
describe the same structure. They drift the moment someone edits a model without writing
the matching migration, or hand-edits the database without updating the model. Treat
drift as a build-breaking condition, not a lint warning: most frameworks ship a
diff/check command (compare live schema against models) — run it in CI, not only locally.

## N+1 queries

A loop that issues one query to fetch a collection and then one additional query per
item to fetch each item's related data. It works, returns correct rows, and is silent —
the only symptom is response time, which is exactly the kind of defect that looks fine
in a review with ten test rows and falls over in production with ten thousand. Every ORM
in this family provides an eager-loading mechanism (`joinedload`/`selectinload` in
SQLAlchemy, `include` in Prisma, `select_related`/`prefetch_related` in Django,
`includes` in ActiveRecord) — reach for it whenever a loop accesses a relationship.

## Session / connection lifetime

A session (unit of work) has a lifetime, and getting it wrong is silent until it is not:

- **One session per logical unit of work** — typically one per request/task, not one
  shared across the app's lifetime and not a fresh one per query.
- **Never share a session across threads or async tasks.** Sessions are not
  thread-safe; concurrent use produces intermittent, hard-to-reproduce corruption.
- **Close/commit the boundary explicitly** rather than relying on garbage collection —
  an uncommitted session holds a connection and, depending on isolation level, locks.

## Database constraints vs. application validation — use both, for different things

|  | guarantees | costs |
|---|---|---|
| **Database** (constraints) | absolute integrity, even for other systems writing directly | generic errors (*"check constraint violated"*), hard to read once rules get complex |
| **Application** (framework validators) | friendly messages, rules needing extra queries | bypassed entirely by anyone writing SQL directly |

**Practice:** database constraints for immutable structural rules (types, sizes,
ranges); application-level validation for business rules with custom messages and
lookups. Neither replaces the other — a constraint absent from the database is a rule
only the application enforces, which any direct-SQL write bypasses; a rule absent from
the application is a raw database error surfaced to a user. The concrete validator
mechanism (SQLAlchemy's `@validates`, Pydantic, Prisma's schema, ActiveRecord
validations) is the specific layer's concern, not this one's.

## Related

- `s:sql` — the agnostic SQL hazards and DQL/DDL/DML/DCL/TCL taxonomy this skill assumes.
- `s:sql-sqlalchemy` — the SQLAlchemy-specific implementation of everything above.
- `s:sql-migrations` / `s:sql-alembic` — migrations are out of scope here; model
  definition and migration are related but distinct concerns.
