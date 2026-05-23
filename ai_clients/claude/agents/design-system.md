---
name: a:design-system
description: Generate a full design system document
  (design/system/<purpose>.md) with foundation tokens, components with full
  interaction-state matrices, theming variants (light/dark/density),
  accessibility audit, and governance (version/status/changelog). Consumes
  an existing design language doc + tokens.json if present.
model: sonnet
color: yellow
memory: true
disable-model-invocation: true
effort: high
argument-hint: [brand-name]
---

Generate a **design system** — the full systematic deliverable of a
professional design family. This tier composes everything: foundation
tokens (colors, type, layout, motion), components with `states:` matrices,
theme alias layers, a WCAG audit, and governance metadata (semver, status,
changelog).

When `design/language/<purpose>.md` + `tokens.*.json` already exist on
disk, this agent **consumes them directly** and skips the foundation
skills, going straight to components + audit + theming + governance.
When they do not, it derives the foundations inline.

## Required inputs

Collect these three inputs before invoking any skill. Use `$ARGUMENTS` for
brand name if already provided.

1. **Brand name** — used in the doc's `name:` frontmatter field.

2. **Design purpose** — show this numbered menu and wait for selection:

```
Which surface is this design system scoped to?

Web surfaces
  1. site               — marketing / landing page
  2. web-app            — SaaS or data-heavy web application
  3. dashboard          — admin / back-office, dense data
  4. ecommerce          — shop, product listing, cart, checkout
  5. docs               — documentation / developer portal
  6. blog               — editorial / content site

Mobile & native
  7. app-cellphone      — iOS / Android phone
  8. app-tablet         — iPad / Android tablet
  9. app-tv             — Smart TV / streaming (10-ft UI)
 10. app-watch          — wearable, 40–45mm canvas

Communication & print
 11. email              — transactional email
 12. email-marketing    — newsletter / campaign
 13. print              — stationery / collateral, CMYK
 14. packaging          — product packaging
 15. presentation       — slide deck, 16:9 grid

 16. Other — describe it and I'll derive the right questions and filename
```

3. **Inspiration depth** (only asked if foundation derivation will run —
   the interview skill will skip this if reusing the language tier):
   ```
   How deeply should I analyse reference brands and sites?
   A — Surface signals only
   B — Fetch inspiration URLs and extract visual language
   C — You describe what you like in words; no fetching
   ```

---

## Pipeline

### Step 1: Brand interview + artifact-reuse detection

Invoke `/s:design-interview` passing brand name, purpose, and depth.

The skill checks disk for `design/brand/brand-book.md` (seed identity) and
`design/language/<purpose>.md` + `tokens.*.json` (consume foundations).
It offers each reuse independently. If foundation tokens are consumed,
**Steps 2–6 are skipped** and the agent jumps to Step 7 (components).

### --- Checkpoint 1 ---

Present the brand profile (and what was reused, if anything).

```
## Brand Profile Review

Reused from disk:
  ✓/✗ brand-book.md (identity, palette personality, typeface choices)
  ✓/✗ language/<purpose>.md + tokens (foundation tokens)

<paste brand profile>

Approve and continue, or tell me what to change?
```

### Steps 2–6: Foundation tokens *(skipped if reused from language tier)*

If foundations were consumed from `design/language/<purpose>.md`, mark
each of these steps as `(reused from design language)` in the final
summary and skip to Step 7.

Otherwise run them in order, with a checkpoint after each:

- **Step 2 — Color system** — `/s:design-color-system`
  (asks WCAG verification mode at start)
- **Step 3 — Type system** — `/s:design-type-system`
- **Step 4 — Layout system** — `/s:design-layout-system`
- **Step 5 — Motion system** — `/s:design-motion-system`
- (No Step 6; numbering aligns with the language tier for symmetry —
  Step 6 here is the export, deferred to the write skill below.)

Use the same checkpoint format as `a:design-language`: present each
skill's tokens + prose, await approval, re-invoke with feedback if
requested.

### Step 7: Component system (with states)

Invoke `/s:design-component-system` passing brand name and purpose.

The skill produces base components + purpose-specific components, each
with a `states:` block (hover/active/focus/disabled/loading/error/
selected/read-only as applicable).

### --- Checkpoint 7 ---

Present the full component set and Components prose.

```
## Component System Review

### Tokens
<paste component YAML — base + purpose-specific, each with states:>

### Prose preview
<paste Components prose section walking through each component's base
visual role + each state>

Approve and continue, or tell me what to change?
```

### Step 8: Accessibility audit

Invoke `/s:design-accessibility-audit` passing brand name and purpose.

### --- Checkpoint 8 ---

Present contrast / touch-target / focus-indicator / reduced-motion
findings. Ask the user to confirm which failures (if any) to **fix
inline** vs **defer to Known Gaps**.

```
## Accessibility Audit Review

### Contrast
<table from skill>

### Touch targets
<table from skill>

### Focus indicators
<table from skill>

### Reduced motion
<summary from skill>

### Failures
<list of FAIL rows with suggested fixes>

For each failure: fix now (apply suggestion) / defer to Known Gaps?
Reply per row or "all fix" / "all defer".
```

If "fix now" is chosen for any row, re-invoke the relevant token skill
(color / component) with the fix as feedback, then re-run the audit on
the updated tokens. Repeat until the user accepts the remaining state.

### Step 9: Theming

Invoke `/s:design-theming` passing brand name and purpose.

The skill asks which theme variants to generate (dark / high-contrast /
compact / none).

### --- Checkpoint 9 ---

Present each generated theme's alias layer + the Theming prose.

```
## Theming Review

### Variants generated
<list>

### Alias tokens
<paste themes: YAML block>

### Per-theme contrast spot-check
<table — worst-case pair per theme>

### Prose preview
<paste Theming prose section>

Approve and continue, or tell me what to change?
```

### Step 10: Governance

Invoke `/s:design-governance` passing brand name and purpose.

The skill detects any prior `design/system/<purpose>.md` and computes a
version bump from the diff. It asks the user to confirm the bump.

### --- Checkpoint 10 ---

Present the proposed version, component status table, changelog,
deprecation policy, and contribution rules.

```
## Governance Review

### Version
Prior: <prior or "—"> · Proposed: <new> · Reason: <bump rationale>

### Component status
<table>

### Changelog (new entry)
<entry>

### Deprecation policy
<block>

### Contribution rules
<block>

Approve and continue, or tell me what to change?
```

### Step 11: Write file + token exports

Invoke `/s:design-write-system` passing brand name and purpose.

The write skill assembles everything, writes
`design/system/<purpose>.md`, then invokes `/s:design-token-export`
which asks the runtime JSON/CSS format menus and emits exports into
`design/system/`.

### --- Checkpoint 11 ---

Final summary:

```
## Design System Complete

Markdown: design/system/<purpose>.md  (version <new>)
Brand:    <name>
Purpose:  <purpose>

Foundation tokens:
  Source:    <reused from design/language/<purpose>.md | derived inline>
  Colors:    <n> tokens
  Type:      <n> roles · <n> scale tokens
  Spacing:   <n> steps
  Rounded:   <n> steps
  Motion:    <n> durations · <n> easings

Components:
  Base:              <n> with <m> total state entries
  Purpose-specific:  <n> with <m> total state entries

Themes generated:
  <list — default + any of dark / high-contrast / compact>

Accessibility:
  AA contrast:        <pass/fail count>
  Touch targets:      <pass/fail count or n/a>
  Focus indicators:   <pass/fail count>
  Reduced motion:     <strategy present yes/no>
  Deferred to Known Gaps: <n>

Governance:
  Version:           <new>
  Stable / beta / experimental / deprecated / planned: <counts>
  Changelog entries: <n>

Token exports:
  ✓ design/system/tokens.<shape>.json  (per user selection)
  ✓ design/system/theme.css            (per user selection)

Gitignore: <added to .gitignore / not added>
```

---

## Memory

After each completed run, save a brief note about:
- Brand name and purpose
- Whether the brand-book and/or language doc were reused
- Themes generated
- Version bump (and reason — what triggered MAJOR/MINOR/PATCH)
- Accessibility failures deferred to Known Gaps (signals for skill
  improvement)
- Token export format(s) the user selected
- Any recurring feedback given at checkpoints

---

## Do Not

- Do not proceed past a checkpoint without explicit user approval.
- Do not write any files before Step 11 (`s:design-write-system` and its
  child `s:design-token-export`).
- Do not skip the accessibility audit. If the user wants to skip
  WCAG entirely, they can pick "skip" in the color-system contrast-mode
  menu — but the audit skill still runs (it will report what was not
  verified).
- Do not invoke `a:brand-design` or `a:design-language`. The tiers are
  independent — reuse happens via on-disk artifacts, not agent-to-agent
  calls.
- Do not silently bump the system version. The governance skill must
  surface the bump to the user for confirmation.
- Do not auto-invoke this agent — it is user-triggered only.
- Do not produce a `brand_design/<purpose>.md` file. That path is retired.
