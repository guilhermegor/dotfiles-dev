---
name: s:test
description: Use when writing, reviewing, or planning any test — deciding test structure, whether a test is independent, or whether a case should be example-based or property-based. Language-agnostic, no tool syntax. Tool-specific skills (s:py-unit-test, s:py-hypothesis, and future TS equivalents) import this vocabulary instead of restating it.
effort: medium
argument-hint: [none]
allowed-tools: Read
---

This is the language-agnostic layer of the testing family. It answers *what makes a
good test*, never *how a specific tool writes one*. Tool skills (`s:py-unit-test`,
`s:py-hypothesis`, and any future `ts-*` equivalents) read this skill for vocabulary
and decisions, then add only what is specific to their tool.

## Anatomy of a test

`arrange/act/assert`, `given/when/then`, and `setup/exercise/teardown` are three
names for the same skeleton — pick whichever your framework's community uses, but
**always make the phases visible** (a blank line or a comment between them is
enough). A test without visible phases hides which line is the subject: the reader
cannot tell "this sets up the world" from "this is the behaviour under test" from
"this is the check" at a glance, and that ambiguity is exactly what makes a failing
test expensive to read.

## Name the SUT

**SUT (system under test)** is the one object or call the test exists to exercise.
Isolate it and put it in evidence — the common pattern is a single `makeSut()` /
`make_sut()` helper that builds it, and a single line that performs the `act` phase.

**Rule:** if the reader cannot point at the SUT within two seconds of opening the
test, the test is exercising more than one thing. Split it.

## Independence between tests — the rule is not negotiable

No test may depend on the order tests run in, or on state left behind by another
test. This is an owner-mandated rule, not a style preference.

Practical consequences, in any language:

- No mutable global/module state shared **between** tests.
- Fixtures (or their equivalent) are created **per test**, not per module or per
  suite, whenever they write anything.
- A test must pass when run **alone** — if it only passes as part of the full
  suite, it has a hidden dependency.

⚠️ **This must be decidable by a gate, not by review, wherever the tool allows
it.** Running the suite in randomised order is a cheap check that turns
"independent" from a claim into a fact: a test that only passes in a fixed order
fails immediately under shuffling. The *how* (the flag, the plugin) is tool-specific
and belongs in the tool skill — the requirement that it be gate-checked belongs
here.

## Example-based vs property-based — the boundary

**Example-based testing (EBT)** covers what you remembered to cover.
Parametrization (`@mark.parametrize`, `subTest`, `test.each`, …) only widens the
table of examples — it does not widen what the test *reasons about*. The classic
mitigation is testing boundaries and extremes, and it still leaves a hole: user
input is creative in ways a fixed boundary list is not.

**Property-based testing (PBT)** describes an invariant property that must hold —
and lets the tool generate the exemplars, including ones a human would not have
thought to write by hand.

Deciding *"is this case EBT or PBT"* is the agnostic call and it is made here:

- The property holds for a whole **class** of inputs, not a handful of picked
  values → PBT.
- The case is a specific, named scenario (a known bug, a documented business rule)
  → EBT, and stays EBT even after a PBT suite exists alongside it.

The **how** — the library, the decorator, the strategy — is tool-specific and
belongs in the tool skill (`s:py-hypothesis` for Python). If an example needs an
`import`, it does not belong in this skill.

## Where properties show up, by domain

- **Web/API**: status code, response body shape, headers, schema, form round-trip
  (submit → read back → same values).
- **Data/DS**: validators (conditionals, cleaning rules, types, units/magnitudes),
  train/validation splits.
- **Both**: data models and persistence — round-trip is the universal property
  (write → read → equal to the original).

## Test layers

- **Unit** — one SUT, collaborators mocked at the boundary.
- **Integration / e2e** — real collaborators across a seam (DB, HTTP, filesystem).
- **Performance** — only where it pays (e.g. an API's latency/throughput budget).

**Criterion for not writing a layer:** skip it when it would only re-prove what a
cheaper layer below it already proves. Write a layer only when it can catch a fault
the layers below it structurally cannot — a unit test cannot catch a wrong route
wiring, an integration test cannot catch a wrong algorithm buried three calls deep.

## Out of scope

No tool syntax lives here. `import`, decorators, fixtures-as-implemented,
CLI flags, and library-specific APIs belong to the tool skill that wraps that tool.

## Related skills

- `s:py-unit-test` — the pytest example-based weapon; applies this vocabulary to
  pytest specifics (fixtures, `conftest.py`, `monkeypatch`, `tmp_path`).
- `s:py-hypothesis` — the Python property-based weapon; applies the EBT/PBT
  boundary decided here to Hypothesis strategies.
