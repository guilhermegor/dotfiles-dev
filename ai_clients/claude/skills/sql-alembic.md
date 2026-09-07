---
name: s:sql-alembic
description: Use when writing, reviewing, or debugging Alembic migrations against SQLAlchemy models — autogenerate vs sqlacodegen, Core vs declarative vs dataclass model styles inside a migration, compare_type/render_as_batch, SQLite batch mode, offline SQL generation, and DSN resolution. For the tool-agnostic reasoning behind these rules, see s:sql-migrations.
effort: medium
argument-hint: [none]
allowed-tools: Read Glob Grep
---

The Alembic + SQLAlchemy half of migration work. The reasoning that survives the tool
changing lives in the agnostic sibling, `s:sql-migrations` — this skill is the part that
is true of **this** tool and would be wrong advice for Flyway.

Alembic was written by Mike Bayer (SQLAlchemy's author), first released November 2011.
It operates on DDL, ships up/down scripts, and can emit SQL offline for a DBA to apply.

## Reverse engineering vs. forward generation — two tools, routinely confused

The distinction to make first, because the names sound interchangeable and the jobs are
opposite:

| | reads | writes | when |
|---|---|---|---|
| **`sqlacodegen`** | an existing **database** | Python **model classes** | adopting a database that already exists |
| **`alembic revision --autogenerate`** | the **models** vs. the live DB | a **migration script** | every schema change after that |

`sqlacodegen` is engineering *backwards*, once, to get models for a schema someone else
built. `--autogenerate` is forwards, continuously, and needs no `sqlacodegen` at all —
only an `env.py` that imports the models' `MetaData` and a reachable database.

`sqlacodegen` can emit three shapes (`--generator tables|declarative|dataclasses`),
matching SQLAlchemy's three model styles. **Alembic's `--autogenerate` always emits
Core**, whatever style the models are written in — the migration is
`op.add_column(...)`, never a model class.

## The model styles, and which belongs where

- **Core** (`Table`, `Column`) — the structural layer. Migrations are written here.
- **Declarative** (`declarative_base` + `Column`) — the classic ORM, common in existing
  code. See `s:sql-sqlalchemy` for the modern-vs-classic recommendation.
- **SQLAlchemy 2.0 dataclasses** (`MappedAsDataclass` + `Mapped` + `mapped_column`) —
  typed, generates `__init__`/`__repr__`/`__eq__`.

**Inside a migration, the choice is not cosmetic:**

- **Structure changes must use Core or raw SQL** — `op.add_column`, `op.alter_column`,
  `op.execute("ALTER TABLE …")`.
- **Never `Base.metadata.create_all(engine)` in an `upgrade()`.** It emits a full
  `CREATE TABLE`, not an `ALTER`. Against an existing table it errors or does nothing;
  it never performs the change you meant. This is a concrete, decidable defect and a
  strong gate candidate.
- **Data changes may use the ORM** (`Session(op.get_bind())`), but only **after** the
  structural change has run — querying a column that the same migration has not yet
  added fails, and the ordering is easy to get backwards because the model already
  declares it.

## The two flags nobody sets until they are burned

Both go in `context.configure(...)` — in **`run_migrations_online` and
`run_migrations_offline` both**, since a DBA-bound script generated without them is
wrong the same way and is the one nobody re-runs.

- **`compare_type=True`** — without it, `--autogenerate` does not compare the types of
  columns that already exist. Widening `String(50)` to `String(100)` produces an
  **empty migration and a successful exit**: the tool reports success for having
  detected nothing.
- **`render_as_batch=True`** — makes `--autogenerate` wrap same-table alterations in
  `op.batch_alter_table`. Only affects operations on an **existing** table;
  `create_table`, `drop_table`, and `create_index` are emitted normally.

## Batch mode — what it actually is, and what it does NOT fix

SQLite's `ALTER TABLE` supports only rename-table and add-column. Everything else —
change a type, rename a column, drop a column, add a constraint — requires SQLite's
official dance, which is exactly what `op.batch_alter_table` performs:

```sql
CREATE TABLE _alembic_batch_temp (...);
INSERT INTO _alembic_batch_temp (...) SELECT ... FROM some_table;
DROP TABLE some_table;
ALTER TABLE _alembic_batch_temp RENAME TO some_table;
```

**Batch mode does not remove the availability window.** The tempting reading is that
batching makes the change atomic. It does not. During the `INSERT … SELECT` the
original table is still readable; during `DROP` + `RENAME` it is briefly gone, and a
query landing in that instant gets *table not found*. Batch mode makes the alteration
**possible** on SQLite; it does not make it invisible.

On PostgreSQL and MySQL, batch mode does not copy at all — it emits the `ALTER`
directly, which is atomic and fast.

## SQLite concurrency — the part that gets stated wrong

SQLite **does** accept multiple simultaneous connections. Many can read; exactly one may
write at a time, serialised by locks. The journal mode changes what that costs: in the
default rollback mode a write blocks readers, while in **WAL** mode readers and the
writer proceed concurrently.

Practical consequences for a migration:

- enable WAL (`sqlite:///db.sqlite?journal_mode=WAL`) when reads must continue;
- run migrations **before** the server starts, which removes the concurrency question
  entirely;
- treat SQLite as the development and test backend — with concurrent workers in
  production, the answer is PostgreSQL or MySQL, not a better SQLite configuration.

## Offline migrations — and where the command belongs

When production access is restricted to DBAs, generate SQL instead of applying it:

```bash
alembic upgrade +1 --sql > upgrade.sql
alembic downgrade head:-1 --sql > downgrade.sql
```

Offline downgrade takes a **range** (`from:to`), unlike the online form. The relative
`head:-1` spelling avoids hunting revision ids out of `alembic history`; verify it
against the installed version rather than trusting it, since the relative syntax is the
part most likely to differ across releases.

**Both online and offline belong in the project's own command interface**, not only
offline. Online (`upgrade head`, `downgrade -1`) is what a developer runs locally and
what a deploy runs; offline is what goes to a DBA. And **a CI workflow must call that
task rather than reimplement the `alembic` invocation** — two hand-maintained
implementations of one command list is a duplication the same class as any other.

## The DSN — one code path, never a URL in the repository

`alembic.ini` ships `sqlalchemy.url`, and committing a real one is both a credential
leak and an inflexibility: local and CI want SQLite, production wants PostgreSQL. The
working shape:

```python
load_dotenv(override=True)
_DSN = os.getenv("DB_DSN", "")          # explicit DSN wins
...                                      # else compose via URL.create from DB_* vars
config.set_main_option("sqlalchemy.url", _DSN)
```

Note the ConfigParser trap: a placeholder written as `%(DB_DSN)s` is an
*interpolation*, so a subcommand that reads the option before `env.py` overrides it can
raise `InterpolationMissingOptionError`. Verify with `alembic history` and `alembic
current` and no `DB_DSN` set, rather than assuming the override always runs first.

## Boundaries

- **The active repository's conventions win** over anything here — folder name, file
  naming template, the DDL/DML rule. See `s:sql-migrations` for the general precedence
  statement.
- The *why* of evolutionary schema design is `s:sql-migrations`'s job, not this skill's.
- Naming and folder conventions are explicitly LOCAL, project-specific choices, not
  covered here.

## Related

- `s:sql-migrations` — the agnostic sibling; read it first for the reasoning this skill
  applies.
- `s:sql-sqlalchemy` — the model styles (Core/declarative/dataclass) this skill routes
  between.
