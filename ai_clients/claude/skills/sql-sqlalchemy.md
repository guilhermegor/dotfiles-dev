---
name: s:sql-sqlalchemy
description: Use when writing or reviewing SQLAlchemy 2.0 model code — declarative style, Base lifecycle, mixin __table_args__ concatenation, dialect-dependent constraints, and and_/or_ over bitwise operators. For raw SQL hazards see s:sql; for ORM-agnostic reasoning see s:sql-orm; for Alembic migrations see s:sql-alembic.
effort: medium
argument-hint: [none]
allowed-tools: Read Glob Grep
---

> **Priority:** this project's `CLAUDE.md` and `rules/*.md` take precedence over the guidance below whenever they conflict — treat this skill as a fallback, not a mandate.

The SQLAlchemy-specific layer of the SQL skill family — one implementation, SQLAlchemy
2.0. Raw-SQL hazards are `s:sql`; framework-agnostic ORM reasoning (including DB vs.
application validation, which this skill only adds the SQLAlchemy validator to) is
`s:sql-orm`. Migrations are a separate tool-specific skill, `s:sql-alembic`.

## Declarative style: modern, not classic

The classic style uses `Column` directly with no type hints. The modern style uses
`Mapped` + `mapped_column`, which integrates with PEP 484 and gives real IDE support.
**The modern style is the current recommendation and the one to use.** Both are valid
SQLAlchemy, so nothing fails — the classic style just silently forfeits every type
signal, which is exactly the signal an AI-written model most needs to be checked
against.

## `Base` lifecycle — three rules that are one rule

- Define `Base = declarative_base()` (or `class Base(DeclarativeBase): pass`) **before**
  any model.
- Create tables with the **same** `Base` instance the models were defined against.
  Across files, import `Base` from the models module — do not re-declare it.
- Run `create_all` **after** every model has been imported/defined, so `metadata` is
  populated.

All three failures are silent in the same way: a second `Base` or an early `create_all`
produces an **empty or partial `metadata`**, and `create_all` succeeds having created
nothing. No exception, no table.

## Mixins

Worth it for **reuse** (`id`, `created_at`, `updated_at` recur across tables), **single
responsibility** per mixin (`TimestampMixin`, `UserValidationMixin`), and
**maintenance** (one edit reaches every table that uses it).

**The `__table_args__` hazard.** SQLAlchemy concatenates the `__table_args__` tuples of
all base classes in MRO order, left to right. **Two constraints sharing a `name=` do not
error — one overwrites the other** (generally the rightmost). Give every constraint a
unique name, or keep one tuple per mixin.

**Cross-mixin column dependencies.** A constraint referencing columns from another mixin
(`last_login >= created_at`) requires those columns to be resolved first: inherit the
validation mixin *after* the mixins that define the columns, or define all columns first
and place the constraints on the final class.

## Constraints — the parts that are dialect-dependent

- **`String(n)` over `Text` + `CheckConstraint`.** `String(n)` emits `VARCHAR(n)`, which
  bounds the length natively and performantly. Reach for
  `CheckConstraint("LENGTH(bio) <= 500")` only where the type cannot carry the bound —
  and note it is `LEN` on SQL Server, not `LENGTH`.
- **Regex syntax is per-dialect and fails at the wrong time.** `~` / `~*` are
  PostgreSQL. MySQL spells it `REGEXP` with different regex semantics. The constraint
  string is an **opaque literal to SQLAlchemy** — it is accepted at model-definition
  time and only rejected at DDL, on a database nobody ran locally. This is the
  highest-value decidable check in this skill (see Gate candidates below).
- **Multi-column constraints** (`last_login IS NULL OR last_login >= created_at`) are
  the point of `CheckConstraint` — business rules spanning columns.

## `and_` / `or_` / `not_`, never bitwise `&` `|` `~`

This one is a **silent wrong answer with a clean green test**. Python's `&` binds
tighter than `==`, so

```python
User.age == 18 & User.is_active == True
```

evaluates as `User.age == (18 & User.is_active) == True` — a valid expression producing
a valid query returning wrong rows. `and_(...)` cannot be mis-parenthesised, reads
better with many conditions, and accepts a dynamic list via `and_(*list_conditions)`.

## Routing by decidability

**Gate candidates** — a checker can answer these from the source alone:

- [ ] bare `Column(` in a model that also uses `mapped_column` — mixed styles in one tree
- [ ] bitwise `&` / `|` / `~` inside `.where(...)` / `.filter(...)` — AST-detectable
- [ ] duplicate `name=` across the `__table_args__` of one class's MRO
- [ ] dialect-specific regex operator (`~`, `~*`, `REGEXP`) inside a `CheckConstraint`
      string, where the project targets a different dialect
- [ ] more than one `declarative_base()` / `DeclarativeBase` subclass in a tree

**Skill-only** — no checker can decide these without knowing the domain:

- whether a rule belongs in the database or the application
- whether a mixin decomposition is the right one
- whether `String(n)` or `Text` is correct for a given field

**Measure before gating.** Each gate above needs a should-fail witness in both
directions before it ships; a checker that matches nothing is indistinguishable from an
absent one, and one that fires on correct code teaches everyone to disable it.

## Comment discipline

Explanation goes to `docs/`, `CONTRIBUTING.md`, `README.md`, or `.specs`, with at most a
one-line pointer in the code — or the code is decomposed into smaller self-explanatory
units. This applies to every code sample this skill emits. Any code this skill emits
must also respect the target project's own constraints: cyclomatic-complexity ceilings,
one class per module, and the module/folder organisation the project's architecture
dictates.

## Related

- `s:sql` — agnostic SQL hazards and the DQL/DDL/DML/DCL/TCL taxonomy.
- `s:sql-orm` — the framework-agnostic version of the rules above (N+1, session
  lifetime, DB vs. application validation).
- `s:sql-alembic` — migrations against these models; out of scope here.
