---
name: s:bdd
description: Use when writing, reviewing, or deciding whether to write a Gherkin `.feature` file — specification by example, `Scenario Outline` tables, or the call on whether a case belongs in BDD at all. Language- and framework-agnostic, no runner syntax. Tool-specific skills (s:py-bdd, and future TS/Java equivalents) import this vocabulary instead of restating it.
effort: medium
argument-hint: [none]
allowed-tools: Read
---

This is the language-agnostic layer of the BDD family. It answers *is this worth
specifying as Gherkin, and if so, how* — never *how a specific runner binds a
sentence to code*. Tool skills (`s:py-bdd`, and any future `ts-*`/`java-*`
equivalents) read this skill for vocabulary and the fit decision, then add only
what is specific to their runner. It is the BDD sibling of `s:test` — the same
relationship `s:py-unit-test` and `s:py-hypothesis` have to `s:test`.

## When BDD earns its cost — and when it doesn't

**The decisive test: would a wrong business decision here be expensive, or does
the flow branch heavily?** If yes, BDD. If the case is a pure function with no
business ambiguity — a formatter, a checksum, a sort — a unit test is cheaper to
write and cheaper to read; route to `s:test` (or `s:py-unit-test` for the pytest
form) instead. If the case is a property that must hold across a whole class of
generated inputs rather than a named business rule, it belongs to
`s:py-hypothesis`, not to a `Scenario Outline` reaching for the same job.

A skill that always recommends its own subject is a sales pitch, not a guide.
Concretely, **don't reach for `.feature` files** when:

- The logic has one obvious correct answer that any developer would agree on —
  no business analyst or QA needs to sign off on the rule.
- The branching is a data-shape concern (null handling, type coercion), not a
  business rule — that is `s:test` territory.
- You are about to write a `Scenario Outline` whose `Examples` table is really
  just a parametrized unit test wearing Gherkin syntax, with no stakeholder who
  reads it.

**Reach for it** when the rule is the kind a product owner would argue about —
refund eligibility, fraud thresholds, plan entitlements — where the cost of
encoding the rule wrong is measured in money or compliance, not just a failing
assertion.

## Gherkin structure

- **`Feature`** — the capability under specification, one per file.
- **`Scenario`** / **`Example`** (synonyms) — one concrete situation.
- **`Given`** — the initial state or preconditions, established before anything
  happens.
- **`When`** — the single action or event being specified.
- **`Then`** — the expected, observable outcome.
- **`And`** / **`But`** — continues the previous step's keyword without
  repeating it; use `But` only when the added step reads as a contrast.

**One `When` per scenario.** A scenario with two actions is two scenarios that
happen to share a `Given`.

## Which keywords: English or localised

Gherkin ships official translations of every keyword. A `# language: pt` header
at the top of the `.feature` file switches the parser to the localised set:

```gherkin
# language: pt
Funcionalidade: Aprovação de reembolso
  Cenário: Reembolso dentro do prazo legal
    Dado que o pedido foi entregue há 5 dias
    Quando o cliente solicita o reembolso
    Então o reembolso é aprovado automaticamente
```

`Funcionalidade`/`Cenário`/`Dado`/`Quando`/`Então`/`E`/`Mas` map onto
`Feature`/`Scenario`/`Given`/`When`/`Then`/`And`/`But` — same grammar, different
tokens. **The rule for this house:** `.feature` files may be written in
whichever language the business stakeholders who read them use (pt-BR, in this
repo's worked examples) — that is what makes them living documentation for
those readers. Everything *about* Gherkin — this skill, code review comments,
commit messages, issue text — stays in English, matching how the repo documents
itself everywhere else. Never mix the two inside one `.feature` file: pick the
header's language and use its keyword set throughout.

## `Scenario Outline` / `Esquema do Cenário`

The answer to combinatorial branching — many card brands, many error codes —
without duplicating near-identical scenarios. This is the feature most often
skipped, and its absence is what makes a BDD suite bloat into a scenario per
input instead of one scenario plus a table:

```gherkin
# language: pt
Esquema do Cenário: Bloqueio por limite insuficiente
  Dado que o cartão "<bandeira>" tem limite disponível de <limite>
  Quando o cliente tenta uma compra de <valor>
  Então a transação é <resultado>

  Exemplos:
    | bandeira | limite | valor | resultado |
    | Visa     | 100    | 50    | aprovada  |
    | Visa     | 100    | 150   | recusada  |
    | Master   | 0      | 10    | recusada  |
```

One scenario, one set of steps, N rows — each row is a separate test case at
run time, but the business rule is written once.

## Living documentation / audit trail

A `.feature` file is plain text a non-developer can read and a version-control
diff can show changing over time. For critical paths — refund rules, retry
policy on communication failures, anti-fraud thresholds — this is BDD's most
undersold value: the file *is* the audit trail of "what the system was
contractually supposed to do" at any point in the repo's history, independent
of whether anyone remembers to update a wiki page.

⚠️ **A `.feature` file alone is inert.** It is descriptive text — a specification
— until a runner (Cucumber, Behave, pytest-bdd, Behat) binds each sentence to
code that actually exercises the system. Writing the `.feature` file is not
"writing the test"; it is writing the contract the step definitions must then
satisfy. This is the most common beginner misconception and worth stating
plainly before someone ships a `.feature` file with no step module behind it
and believes it is under test.

## Worked domain examples

BDD earns its keep where branching is dense and a wrong rule is expensive — not
in CRUD or formatting code. By domain:

- **Payments/checkout** — insufficient limit (above), anti-fraud blocking after
  N attempts with different cards, Pix approval and its post-sale actions
  (stock reservation, notification, invoice issuance). The happy path is short;
  the error paths are many — exactly the shape BDD is for.
- **E-commerce & logistics** — dynamic shipping cost by weight/destination/carrier,
  cumulative or expiring discount coupons, stock restored automatically when a
  boleto expires unpaid.
- **Health & insurance** — plan waiting periods before a procedure is covered,
  policy pricing that varies by driver profile, automated triage priority from
  reported symptoms.
- **Fintech** — automated credit analysis gated by score and income bands, AML
  blocking on transfers that fall outside a customer's usual pattern.
- **SaaS/streaming** — simultaneous-screen limits enforced per plan tier,
  trial-to-premium transition behaviour when the card fails to charge on day 8.
- **Security & LGPD** (or GDPR, CCPA — the same shape under any privacy law) —
  right-to-erasure removing personal data while retaining records a separate
  law mandates keeping (fiscal, audit); RBAC where an editor may draft content
  but only an admin may publish or delete it:

```gherkin
# language: pt
Funcionalidade: Direito ao esquecimento (LGPD)
  Cenário: Exclusão de dados pessoais preserva registros fiscais obrigatórios
    Dado que o cliente possui notas fiscais emitidas nos últimos 5 anos
    Quando o cliente solicita a exclusão de seus dados pessoais
    Então os dados de contato e perfil são removidos
    Mas as notas fiscais permanecem armazenadas para cumprimento legal
```

Each of these is a rule someone outside engineering would recognise, argue
about, and need to see written down — that recognisability is the signal that
it belongs in Gherkin rather than in a unit test docstring.

## Anti-patterns to name explicitly

- **Steps that describe UI mechanics instead of behaviour** — `Quando clico no
  botão azul` describes an implementation detail, not a business action; prefer
  `Quando o cliente confirma o pagamento`. The scenario should survive a full
  UI redesign unchanged.
- **Scenarios coupled to selectors or field names** — the same failure as
  above, one layer lower; a step that embeds a CSS selector or a JSON key path
  breaks on every refactor that doesn't change the actual behaviour.
- **One scenario asserting many unrelated outcomes** — same discipline as
  "isolate the SUT" in `s:test`: a scenario proves one behaviour. Multiple
  `Then` steps for the *same* outcome are fine; unrelated outcomes bolted onto
  one `When` are not.
- **Step definitions with hidden shared state between scenarios** — the BDD
  form of the independence rule in `s:test`. If step B only passes because step
  A from a previous scenario left something behind, the scenarios are not
  independent; the tool skill (`s:py-bdd`) covers the runner-specific fix.

## Out of scope

No runner syntax lives here. Decorators, fixture wiring, `scenarios()` calls,
CLI flags, and report formats belong to the tool skill that wraps that runner.
Language conventions (typing, naming, project layout) belong to the `rules/`
files, not to this skill — this skill covers Gherkin and the fit decision only.

## Related skills

- `s:test` — the agnostic testing layer; owns the EBT/PBT boundary and the
  independence rule this skill borrows rather than restates.
- `s:py-unit-test` — where a case routed here as "not worth BDD" actually
  belongs when the tool is pytest.
- `s:py-hypothesis` — where a case routed here as "this is a property, not a
  business rule" actually belongs when the tool is pytest.
- `s:py-bdd` — the pytest-bdd implementation of everything specified here:
  `.feature` files bound to step modules, `parsers.parse`, scenario-scoped
  fixtures.
