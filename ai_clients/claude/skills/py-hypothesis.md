---
name: s:py-hypothesis
description: Use when writing property-based tests in Python with Hypothesis — verifying an invariant across generated inputs, adding boundary coverage a hand-written example list would miss, or picking up a case s:py-unit-test flagged as property-shaped rather than example-shaped.
effort: high
argument-hint: [source-file] [output-file]
allowed-tools: Read
---

Generate property-based tests for the provided Python module using Hypothesis.
This is the PBT weapon of the testing family — for the vocabulary that decides
*whether* a case is EBT or PBT in the first place, and for AAA/SUT/independence,
read `s:test` first; this skill only covers what is specific to Hypothesis.

## Required inputs

Before doing anything else, ask the user for both of the following if they have not
already been provided in `$ARGUMENTS`:

1. **Source file** — the path to the Python module to be tested.
2. **Output file** — the exact path where the generated test file should be written.

Do not infer either path. Wait for explicit confirmation of both before reading the
source file or writing any code.

## Prerequisites

Check the project's dependency file (`pyproject.toml`, `requirements*.txt`) for
**hypothesis**. If absent, abort and notify the user — do not add it yourself.
Adding `hypothesis` to a project's dev-dependencies is a template concern, not
something this skill does on demand.

## Coding standards

Before writing any code, read the shared standards documents:

    Read ~/.claude/skills/test/SKILL.md
    Read ~/.claude/skills/py-standards/SKILL.md

Apply every rule in both documents. The sections below are additional standards
specific to Hypothesis.

## Why Hypothesis, not `pytest` + a `for` loop with `random`

This is the objection every reviewer raises first, and it fails on three concrete
points:

1. **Shrinking.** A random loop that fails at `x=38472, y=291` hands you *that*
   case. Hypothesis automatically reduces a failure to the **smallest exemplar that
   still fails** (`x=0, y=1`) — the difference between receiving the bug and
   receiving the bug already debugged.
2. **Reproducibility.** A failure is saved to `.hypothesis/examples/` and replayed
   **first** on the next run. A `for` loop seeded from `random` produces an
   intermittent failure with no saved seed — indistinguishable from flake, and it
   trains everyone to just re-run until it passes.
3. **Non-uniform strategies.** Hypothesis's built-in strategies deliberately visit
   edges (`0`, `1`, `-1`, `sys.maxsize`, empty list, empty string, unicode) instead
   of sampling uniformly. It is the boundary heuristic from `s:test`, automated
   instead of dependent on whoever remembered it.

## Fundamentals

**Property vs example.** The canonical case is addition: commutativity and the
neutral element are both testable **without knowing a single concrete example**.

```python
from hypothesis import given
from hypothesis import strategies as st


@given(x=st.integers(), y=st.integers())
def test_add_is_commutative(x: int, y: int) -> None:
    """Property: add(x, y) == add(y, x) for every pair of integers."""
    assert add(x, y) == add(y, x)


@given(x=st.integers())
def test_add_zero_is_identity(x: int) -> None:
    """Property: 0 is the neutral element of add."""
    assert add(x, 0) == x
```

**Decorators**: `@given` drives generation; `@example(...)` pins a specific input
alongside the generated ones; `@settings(max_examples=..., verbosity=...)` tunes
how many cases run and how much Hypothesis logs.

⚠️ **`@example(...).xfail(reason=...)` and `.via("issue 572")`** — pin a **known**
edge case next to the generation instead of only relying on the generator to find
it again, and link it to the ticket that tracks it:

```python
from hypothesis import example, given
from hypothesis import strategies as st


@given(st.text())
@example("").xfail(reason="empty input crashes parser", raises=ValueError)
def test_parse_does_not_crash(value: str) -> None:
    """Property: parse never raises for well-formed text; empty is a known gap."""
    parse(value)
```

This is the best of both worlds and the reason PBT does not replace EBT: a known,
named edge stays documented and tracked even while the generator explores the rest
of the input space.

## Strategies

- **Groups**: primitives (`st.none()`, `st.just(x)`, `st.booleans()`), numeric
  (`st.integers()`, `st.floats()`), text/emails/urls (`st.text()`, `st.emails()`),
  collections (`st.lists()`, `st.dictionaries()`), datetimes (`st.datetimes()`).
- **Modifiers**: `.filter()`, `.map()`, `.flatmap()`. ⚠️ A `filter` that is too
  tight raises `FailedHealthCheck` — Hypothesis gives up generating valid inputs
  because too many draws are discarded. Prefer `st.builds()` with a targeted
  strategy per field over filtering broad input down to a narrow one.
- **`@st.composite`** — draw your own strategy when no built-in shape fits:

```python
from hypothesis import strategies as st


@st.composite
def date_ranges(draw: st.DrawFn) -> tuple[date, date]:
    """Draw a (start, end) pair where start <= end."""
    start = draw(st.dates())
    end = draw(st.dates(min_value=start))
    return start, end
```

- **`st.from_type` and `st.builds`** over Pydantic models — use `builds` when one
  field needs its own strategy instead of the type-inferred default:

```python
from hypothesis import strategies as st

cpf_strategy = st.builds(
    CustomerData,
    cpf=st.from_regex(r"\d{11}", fullmatch=True),
)
```

## Measured pitfalls — the reason this skill exists

⚠️ **`str.isnumeric()` accepts more than you expect.** Superscripts (`²`), digits
from other numbering systems, and unicode fractions all pass. A CPF/document
validator that trusts it accepts input no hand-written example would have covered —
this is a **silent wrong answer**, not a crash, which is why example lists alone
never catch it.

⚠️ **A function-scoped fixture does not re-run per example.** Hypothesis runs N
generated cases **inside one call** of the test function, so a function-scoped
fixture is created once and its state leaks across examples — a direct collision
with the independence rule in `s:test`.
`@settings(suppress_health_check=[HealthCheck.function_scoped_fixture])` **silences
the warning, it does not fix the leak.** The fix is to recreate the state **inside**
the test body, not around it:

```python
from hypothesis import given, settings
from hypothesis import strategies as st


# Wrong: fixture-provided state is shared across every generated example
@given(item=st.integers())
def test_append_wrong(item: int, shared_list: list[int]) -> None:
    shared_list.append(item)
    assert item in shared_list  # passes, but shared_list grows across examples


# Right: state is created fresh inside the test body, once per example
@given(item=st.integers())
def test_append_right(item: int) -> None:
    fresh_list: list[int] = []
    fresh_list.append(item)
    assert fresh_list == [item]
```

## Use cases by domain

The EBT/PBT boundary lives in `s:test`; these are Hypothesis-specific applications.

- **API**: `@given(st.builds(TodoIn))` → assert the status code and that the
  response validates against the **output schema**, not against a literal dict —
  a literal comparison only re-tests one generated value, not the contract.
- **Data**: validators, cleaning rules, unit/magnitude checks; persistence
  round-trip (write → read → equal to the original).

## Do Not

- Do not replace an existing, named EBT case with a PBT property — keep both.
- Do not `.xfail()` a known edge without `.via("issue N")` linking it to a ticket.
- Do not suppress `HealthCheck.function_scoped_fixture` without also moving the
  state creation inside the test body.
- Do not compare API responses to a literal dict when a schema exists to validate
  against instead.

## Meta

Hypothesis is an MPL-licensed library created by David MacIver and Zac
Hatfield-Dodds — property-based testing applied at the unit level. Reference talk:
https://www.youtube.com/watch?v=ZLmFJhwh7hE&t=5551s

## Related skills

- `s:test` — the agnostic layer that decides *when* a case is a property.
- `s:py-unit-test` — the example-based weapon; the two reference each other instead
  of duplicating content.
