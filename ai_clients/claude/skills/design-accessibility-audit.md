---
name: s:design-accessibility-audit
description: Use when auditing a design system's tokens and components against
  WCAG 2.2 AA (with AAA flags). Receives all tokens and component specs from
  conversation context. Verifies contrast pairs, touch targets, focus
  indicators, motion/reduced-motion compliance; writes the Accessibility
  section and surfaces failures into Known Gaps.
effort: high
argument-hint: [brand-name] [purpose]
allowed-tools: Read
---

Read all tokens (`colors`, `typography`, `spacing`, `motion`) and component
specs (with `states:` blocks) from conversation context. Run a structured
audit against WCAG 2.2 AA, flag AAA opportunities, and emit findings.

## Rules (never violate)

- The audit reports findings; it does **not** silently mutate tokens. Each
  failure surfaces as a row in the Accessibility section + an entry in
  Known Gaps with a suggested fix.
- AA is the minimum bar. AAA findings are advisory; do not fail an audit
  on AAA alone.
- If the design-color-system was run with WCAG mode = "skip", note that
  contrast was not verified at color derivation and run it now.
- Touch-target and motion checks apply only to surfaces where they are
  meaningful: touch targets on `app-cellphone`/`app-tablet`/`app-watch`/
  `app-tv`; reduced-motion on any surface that emits a `motion:` block.

## Step 1 — Contrast audit

Compute the contrast ratio for every interactive or text-bearing pair
implied by the tokens and components. Pairs to check (omit any that the
purpose's component set does not use):

```
Text-on-surface pairs:
  ink           on canvas         → AA ≥ 4.5:1 · AAA ≥ 7:1
  body          on canvas         → AA ≥ 4.5:1
  muted         on canvas         → AA ≥ 4.5:1
  ink           on surface-card   → AA ≥ 4.5:1
  ink           on surface-soft   → AA ≥ 4.5:1
  on-primary    on primary        → AA ≥ 4.5:1
  on-dark       on ink (tooltip)  → AA ≥ 4.5:1

Semantic pairs:
  error         on canvas         → AA ≥ 4.5:1
  success       on canvas         → AA ≥ 4.5:1
  warning       on canvas         → AA ≥ 4.5:1

UI element pairs (≥ 3:1 — WCAG 1.4.11 non-text contrast):
  hairline      on canvas         → ≥ 3:1
  border-strong on canvas         → ≥ 3:1
  primary       on canvas         → ≥ 3:1 (CTA edge legibility)
```

Use the WCAG relative-luminance formula. For each pair, report the
computed ratio and pass/fail vs AA. Where a failure occurs, propose a
concrete fix (e.g. "darken `ink` from #2A2A2A to #1A1A1A → 11.2:1") and
add it to Known Gaps.

## Step 2 — Touch-target audit

Applies to `app-cellphone`, `app-tablet`, `app-watch`, `app-tv` purposes.

Check every interactive component (`button-*`, `text-input`, `tab-bar`,
`fab`, `filter-pill`, etc.) for minimum hit-area:

| Surface         | Min target | Recommended |
|-----------------|------------|-------------|
| `app-cellphone` | 44 × 44 px (Apple HIG) / 48 × 48 dp (Material) | 48 × 48 |
| `app-tablet`    | 44 × 44 px | 48 × 48 |
| `app-watch`     | 38 × 38 px (smaller canvas) | 44 × 44 |
| `app-tv`        | Focus-state size ≥ 80 × 80 px (10-ft viewing) | 120 × 120 |

If a component's `height` × computed-width drops below the minimum,
record a finding. Note that *visual* size may be smaller than *hit area*
if the component reserves invisible padding — only flag if neither
the visual nor the documented hit-area meets the floor.

## Step 3 — Focus indicator audit

For every interactive component, confirm a `focus` state exists and that
it visually distinguishes the element. Rules:

- The `focus` state must change at least one of: `outline`, `borderColor`,
  `boxShadow`. Color change alone is insufficient (fails WCAG 2.4.7).
- `outline` width should be ≥ 2px and contrast ≥ 3:1 against the
  adjacent background.
- For dense components (table rows, tab bars), focus must be visible
  even when the row is `selected`.

Flag any component with `states:` block that omits `focus`, or whose
focus indicator relies on color alone.

## Step 4 — Reduced-motion audit

Applies when a `motion:` block is present.

- Verify `motion.reduced` exists with a non-empty `strategy`.
- For each motion-bearing component (modals, drawers, toasts, tab-bar
  transitions), confirm the Components prose describes the reduced-motion
  variant or the reduced-motion strategy is global enough to cover it.
- Vestibular safety: if any token references `spring` easing with
  duration > 400ms, flag it as a candidate for reduced-motion removal.

## Step 5 — Text-size & line-length audit (advisory)

- Body type `body-md` should be ≥ 16px on web and ≥ 14px on email.
- Type-scale tokens with `fontSize` < 12px on web are flagged unless used
  exclusively for `badge` / `micro-label` (non-essential text).
- Line length: if `grid.max-content-width` × body type allows lines
  > 80 characters at base font size, note it advisorily.

## Output

Write the Accessibility section into the conversation:

```markdown
## Accessibility

### Contrast (WCAG 1.4.3 AA, 1.4.6 AAA)

| Pair                       | Ratio | AA  | AAA | Note |
|----------------------------|-------|-----|-----|------|
| ink on canvas              | 14.2:1 | ✓ | ✓  |      |
| body on canvas             |  7.1:1 | ✓ | ✓  |      |
| muted on canvas            |  4.6:1 | ✓ | ✗  | acceptable for secondary labels |
| on-primary on primary      |  3.8:1 | ✗ | ✗  | **FAIL** — see Known Gaps |
| primary on canvas (≥ 3:1)  |  4.1:1 | ✓ |    | non-text |
[…all pairs checked]

### Touch targets (purposes: <list>)

| Component       | Visual size | Hit area | Min | Status |
|-----------------|-------------|----------|-----|--------|
| button-primary  | 48 × auto   | same     | 48  | ✓     |
| tab-bar item    | 56 × 56     | same     | 48  | ✓     |
| filter-pill     | 32 × auto   | same     | 48  | ✗ **FAIL** |

### Focus indicators

| Component       | Focus shape           | ≥ 3:1 vs bg | Status |
|-----------------|-----------------------|-------------|--------|
| button-primary  | outline 2px ink       | ✓           | ✓     |
| text-input      | outline 2px + border  | ✓           | ✓     |
| <component>     | color change only     | n/a         | ✗ FAIL |

### Reduced motion

- Strategy present: <yes/no>
- Components covered: <list>
- Vestibular risks: <list spring + long-duration pairs, or "none">

### Type & line length (advisory)

- Body baseline: <16px / fail at 14px / etc.>
- Sub-12px tokens: <list — only `badge`/`micro-label` allowed>
- Max line length at desktop: <chars> (target ≤ 80)
```

After writing the section, append each FAIL row as a Known Gaps entry:

```markdown
- Contrast — on-primary on primary 3.8:1 (need ≥ 4.5:1).
  Fix: lighten on-primary from #E8E8E8 to #FFFFFF (→ 4.7:1) or
       darken primary from #4A90E2 to #1F6FEB (→ 5.1:1).
- Touch target — filter-pill 32 × auto below 48 minimum.
  Fix: increase height to 40px and verify horizontal padding ≥ 16px.
- Focus indicator — <component> relies on color change alone.
  Fix: add outline 2px solid {colors.border-strong}, outlineOffset 2px.
```
