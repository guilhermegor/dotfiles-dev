---
name: s:py-bdd
description: Use when binding Gherkin `.feature` files to pytest step definitions with pytest-bdd — `scenarios()`, `@given`/`@when`/`@then`, `parsers.parse` with typed converters, scenario-scoped fixtures, or `Scenario Outline` + `Examples`. Trigger when asked to write, generate, or wire up pytest-bdd tests.
effort: high
argument-hint: [feature-file] [output-file]
allowed-tools: Read
---

> **Priority:** this project's `CLAUDE.md` and `rules/*.md` take precedence over the guidance below whenever they conflict — treat this skill as a fallback, not a mandate.

Generate pytest-bdd step definitions that bind the provided Gherkin `.feature`
file to executable pytest code. This is the pytest weapon of the BDD family —
for Gherkin syntax, the localised-keyword rule, and the decision of *whether* a
case belongs in BDD at all, read `s:bdd` first; this skill only covers what is
specific to `pytest-bdd`.

**Why `pytest-bdd`, not `behave`:** it runs inside pytest, so it reuses the
fixtures, plugins, markers, and reporting this repo's Python skills already
assume, instead of standing up a second parallel test runner.

## Required inputs

Before doing anything else, ask the user for both of the following if they have
not already been provided in `$ARGUMENTS`:

1. **Feature file** — the path to the `.feature` file to bind.
2. **Output file** — the exact path where the step-definition module should be
   written.

Do not infer either path. Wait for explicit confirmation of both before reading
the feature file or writing any code.

## Prerequisites

Check the project's dependency file (`pyproject.toml`, `requirements*.txt`) for
**pytest-bdd**. If absent, abort and notify the user — do not add it yourself.
Adding a dependency is a template concern, not something this skill does on
demand.

```bash
pip install pytest pytest-bdd
```

## Coding standards

Before writing any code, read the shared standards documents:

    Read ~/.claude/skills/bdd/SKILL.md
    Read ~/.claude/skills/test/SKILL.md
    Read ~/.claude/skills/py-standards/SKILL.md

`s:bdd` owns Gherkin syntax, the localised-keyword rule, and the fit decision.
`s:test` owns the independence rule this skill applies to fixtures below. Apply
every rule in all three documents; the sections here are additional standards
specific to `pytest-bdd`.

## Layout and wiring

A `.feature` file plus its step module, bound with `scenarios()`:

```
meu_projeto/
└── tests/
    ├── calculadora.feature
    └── test_calculadora.py
```

`scenarios("calculadora.feature")` at module level in `test_calculadora.py`
generates one pytest test function per `Scenario` in the file — this is the
one call that turns the otherwise-inert `.feature` file (per `s:bdd`) into
something pytest collects and runs.

## Worked example: feature, step definitions, and a scenario-scoped fixture

```gherkin
# language: pt
# content of calculadora.feature
Funcionalidade: Calculadora
  Esquema do Cenário: Soma de dois números
    Dado que a calculadora está zerada
    Quando eu somo <a> e <b>
    Então o resultado deve ser <esperado>

    Exemplos:
      | a  | b  | esperado |
      | 2  | 3  | 5        |
      | 10 | -4 | 6        |
```

```python
"""Step definitions for the calculator feature (pytest-bdd)."""

import pytest
from pytest_bdd import given, parsers, scenarios, then, when

from calculadora import Calculadora

scenarios("calculadora.feature")


@pytest.fixture
def calc() -> Calculadora:
    """Fresh calculator instance per scenario — never a module-level singleton."""
    return Calculadora()


@given("que a calculadora está zerada")
def _(calc: Calculadora) -> None:
    assert calc.resultado == 0


@when(parsers.parse("eu somo {a:d} e {b:d}"), target_fixture="resultado")
def _(calc: Calculadora, a: int, b: int) -> int:
    return calc.somar(a, b)


@then(parsers.parse("o resultado deve ser {esperado:d}"))
def _(resultado: int, esperado: int) -> None:
    assert resultado == esperado, (
        f"Erro: Esperava {esperado}, mas o resultado foi {resultado}"
    )
```

This single example carries every element the sections below explain:
`scenarios()`, a typed `parsers.parse` converter (`{a:d}` receives an `int`,
never a string), a `calc` fixture rebuilt per scenario, `target_fixture` to
hand the `When` step's return value to `Then`, type hints throughout, and an
assertion message naming both sides.

## Step decorators and typed parsing

`@given`, `@when`, `@then` bind a step string (or `parsers.parse`/`parsers.re`
pattern) to a function. Plain strings match literally; `parsers.parse` extracts
placeholders as **strings by default** — reach for the typed converter form
whenever a step carries a number, or a silent string/int bug enters silently:

```python
# Untyped — {a} and {b} are str; "2" + "3" == "23", not 5.
@when(parsers.parse("eu somo {a} e {b}"))
def _(a, b): ...

# Typed — {a:d} and {b:d} are int, via Python's format-spec mini-language.
@when(parsers.parse("eu somo {a:d} e {b:d}"))
def _(a: int, b: int): ...
```

`converters={"campo": tipo}` is the alternative form when the placeholder
itself can't carry a format spec (e.g. a custom parser function) — pass a
mapping of placeholder name to converter callable instead.

## State through fixtures, never module globals

A `@pytest.fixture` returning a fresh instance per scenario is what keeps
scenarios independent — the same independence rule `s:py-unit-test` states for
plain pytest tests, applied here to scenario state instead of test state.
Cross-reference it rather than restating it: no test may depend on order or on
state another test left behind, and in `pytest-bdd` terms that means the
`calc`-style fixture above is `scope="function"` (the default) so it is rebuilt
before every scenario, never a module-level instance or dict that scenarios
mutate and hand off to each other.

Use `target_fixture="cucumbers"` (see `s:bdd`'s own `Scenario Outline` example,
mirrored here as `calc`) whenever a later step needs the value a `Given`/`When`
step produced — this is the sanctioned way to pass state between steps.
Reaching for a module-level variable instead reintroduces the exact
cross-scenario dependency the independence rule bans.

## `Scenario Outline` + `Examples` bound through `parsers.parse`

This is the main reason to reach for BDD at all when the branching is
payment/checkout-shaped (per `s:bdd`'s domain examples): one `Scenario Outline`
with typed `parsers.parse` placeholders replaces N near-duplicate scenarios,
and `pytest-bdd` runs one generated test per `Examples` row automatically — no
extra wiring beyond what the worked example above already shows.

## Localised Gherkin

`# language: pt` at the top of the `.feature` file switches Gherkin's official
keyword set, and `pytest-bdd` understands it out of the box — the underlying
parser maps every language's `Given`/`When`/`Then`-equivalent keyword onto the
same internal step type, so `@given`/`@when`/`@then` still bind correctly
regardless of which language wrote the `.feature` file.

⚠️ **The decorator string must match the localised sentence text exactly** —
minus the keyword itself. `Dado que a calculadora está zerada` in the feature
file binds to `@given("que a calculadora está zerada")` in Python: the keyword
(`Dado`) is stripped by the parser, the remaining Portuguese sentence is what
the decorator argument must match character-for-character (or via a matching
`parsers.parse` pattern). A decorator written in English against a
Portuguese-language feature file will not match anything, and the failure mode
is a confusing "step not found" rather than an obvious language mismatch.

## Reporting

The artefacts that make BDD useful to non-developers — the whole point of
writing `.feature` files instead of plain pytest tests is that someone outside
engineering can read the result:

```bash
pytest --junitxml=resultado.xml          # CI-consumable
pip install pytest-html && pytest --html=relatorio.html   # human-readable
```

Wire `--junitxml` into CI where the testing family's other skills already
assume a CI-consumable report exists; reach for `--html` when the audience for
a given `.feature` file (per `s:bdd`'s living-documentation section) is a
business stakeholder who will not open a terminal.

## Type hints on step functions

Per the house Python rules, every step function carries type hints on its
parameters and return value — the worked example above is the standard, not
the exception. A step function with no type hints is exactly as much a lint
violation here as it would be in `s:py-unit-test`.

## Assertion messages that name both sides

A BDD failure is read by someone who did not write the step — often the same
non-developer the `.feature` file exists for in the first place. A bare
`assert resultado == esperado` wastes the practice's main benefit; name both
sides:

```python
assert resultado == esperado, (
    f"Erro: Esperava {esperado}, mas o resultado foi {resultado}"
)
```

## When NOT to reach for it

`s:bdd` owns the call on *whether* a case is BDD-shaped at all; this is the
pytest-specific trigger for it. Stop writing a `.feature` file and route
instead when:

- **The case is a pure function with no business ambiguity** — a formatter, a
  checksum, a pure calculation with one obviously correct answer. Cheaper as a
  plain unit test; load `s:py-unit-test` instead.
- **The assertion is a property that must hold across generated inputs**, not a
  named business rule (`parse(serialize(x)) == x`, commutativity). That belongs
  to `s:py-hypothesis`'s strategies, not to a `Scenario Outline` reaching for
  the same combinatorial coverage by hand-picked rows.

Do not absorb either sibling skill's content here — route to it by name.

## Related skills

- `s:bdd` — the agnostic layer: Gherkin syntax, the localised-keyword rule, the
  fit decision, and the domain examples this skill's worked example draws its
  shape from.
- `s:test` — the independence rule and AAA/GWT vocabulary this skill applies to
  scenario-scoped fixtures.
- `s:py-unit-test` — where a case that fails `s:bdd`'s fit test actually
  belongs when the tool is pytest.
- `s:py-hypothesis` — where a case that turns out to be a property, not a
  business rule, actually belongs.
