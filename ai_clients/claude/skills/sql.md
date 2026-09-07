---
name: s:sql
description: Use when writing, reviewing, or debugging raw or generated SQL for any database engine — WHERE-less mutations, formatted values compared unnormalised, dialect-specific regex, isolation levels, keyset vs OFFSET pagination, and the DQL/DDL/DML/DCL/TCL vocabulary the rest of the SQL skill family assumes. For ORM/framework guidance see s:sql-orm; for SQLAlchemy specifically see s:sql-sqlalchemy; for migrations see s:sql-migrations.
effort: medium
argument-hint: [none]
allowed-tools: Read Glob Grep
---

The database layer is where a model's plausible-looking output does the most damage,
because SQL is the archetype of the **silent wrong answer**: a query that returns *a*
number, just not the right one, reports nothing. A crash announces itself; a dirty read
does not.

This is the agnostic layer of the SQL skill family — true of every engine, raw or
generated. ORM-specific reasoning is `s:sql-orm`; SQLAlchemy specifically is
`s:sql-sqlalchemy`; migrations are `s:sql-migrations` (agnostic) and `s:sql-alembic`
(Alembic-specific).

## The sublanguage taxonomy

The rest of this skill family leans on this vocabulary — know it before anything else:

| | covers | why it matters |
|---|---|---|
| **DQL** | `SELECT` | the read path — where a wrong answer is silent by construction |
| **DDL** | `CREATE` / `ALTER` / `DROP` | what a migration is mostly made of |
| **DML** | `INSERT` / `UPDATE` / `DELETE` | allowed in a migration, and the half that must be idempotent |
| **DCL** | `GRANT` / `REVOKE` | why a migration can pass in dev and fail in prod without the SQL changing |
| **TCL** | `COMMIT` / `ROLLBACK` / `SAVEPOINT` | the boundary every other rule in this family is stated against |

Two of these are easy to skip and should not be:

- **DCL** is why a migration can pass in dev and fail in production without the SQL
  itself changing — the app user in production may not hold the grant the statement
  needs. A review that never names permissions leaves that failure looking like a bug
  in the query.
- **TCL** is the boundary "idempotent", "rollback", and "batch" are stated against —
  they have no meaning without it. It is also where the read-modify-write race lives:
  two transactions each commit successfully, and one of them is silently wrong.

## Agnostic hazards

- **WHERE-less mutation.** An `UPDATE`/`DELETE` with no `WHERE` (or a `WHERE` that
  always evaluates true) touches every row. Always require an explicit, reviewed
  predicate before a mutating statement runs, and prefer a dry-run `SELECT` with the
  same predicate first.
- **Formatted values compared unnormalised.** Comparing a formatted display value
  (trimmed, cased, locale-formatted) against a raw stored value silently returns zero
  or wrong rows. Normalise both sides the same way before comparing, or compare the
  underlying value instead of its formatted rendering.
- **Dialect-specific regex.** A regex operator or syntax that is valid on one engine and
  either invalid or semantically different on another. Worked example — `WITH (NOLOCK)`:
  the *hazard* is "reading uncommitted rows," which is agnostic and belongs here; the
  *spelling* `WITH (NOLOCK)` is MSSQL-only, and its remedy (an RCSI-equivalent isolation
  setting) is per-engine and belongs in that engine's own skill layer, not here.
- **Isolation levels.** Know what the connection's default isolation level actually
  guarantees (read committed vs. repeatable read vs. serializable) before relying on it
  to prevent a race — the default differs by engine.
- **Keyset vs. `OFFSET` pagination.** `OFFSET` re-scans and re-discards every prior row
  on each page and produces duplicate/skipped rows under concurrent writes. Keyset
  pagination (`WHERE id > :last_seen ORDER BY id LIMIT :n`) is stable under writes and
  does not degrade as the offset grows.

## Routing rule for this whole skill family

Content lands in the **most agnostic layer that can hold it**, or the specific layer
becomes the de-facto home and the next stack (a second engine, a second ORM) inherits
nothing. The `WITH (NOLOCK)` example above is the pattern to copy: state the hazard here
in engine-neutral terms, push only the differing spelling down to the specific layer.

The same principle applies to gating: a decidable check (something a checker can answer
from source alone) belongs in a lint/CI gate, not repeated skill prose; anything that
needs domain judgement stays in the skill. Each family member states its own concrete
gate candidates — this skill does not enumerate them, since none of the hazards above are
mechanically decidable without engine and schema context.

## Related

- `s:sql-orm` — ORM/framework-agnostic reasoning (model/migration parity, N+1, session
  lifetime, DB vs. application validation).
- `s:sql-sqlalchemy` — SQLAlchemy 2.0 specifics (declarative style, `Base` lifecycle,
  mixins, constraints).
- `s:sql-migrations` / `s:sql-alembic` — migrations, agnostic and Alembic-specific.
- Comment discipline for generated SQL/code is a separate, cross-cutting macro skill
  (tracked as its own issue) — not duplicated here.
