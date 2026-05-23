---
name: s:design-write-system
description: Use when all design-system token sections, component specs with
  states, accessibility audit, theming variants, and governance metadata are
  approved and ready to be assembled into the final
  design/system/<purpose>.md file. Receives everything from conversation
  context plus, optionally, an existing design/language/<purpose>.md to
  consume foundation tokens from.
effort: medium
argument-hint: [brand-name] [purpose]
allowed-tools: Read Write Bash
---

Assemble the approved tokens, component specs (with `states:`), theming
aliases, accessibility findings, and governance metadata into a single
file at `design/system/<purpose>.md` — the **full design system**
deliverable. This document is the canonical artifact a component library
implementation consumes.

## Output path

```
design/system/<purpose>.md
```

Where `<purpose>` is the kebab-case artifact name chosen at the start of
the session (e.g. `web-app`, `app-cellphone`, `dashboard`).

## Foundation reuse

Before assembling, check whether `design/language/<purpose>.md` exists on
disk. If it does, **reuse its foundation tokens verbatim** (colors,
typography, rounded, spacing, motion) — do not re-emit. The system doc
references the language tokens; the system doc adds the components,
themes, accessibility, governance layers on top.

If the language doc is absent, the foundation tokens were derived in the
current session and are emitted directly here.

## Assembly order (strict — do not reorder)

```
---
version: <semver from s:design-governance>
tier: design-system
name: <brand name>
description: <one paragraph — tone, primary color, type approach, shape
             language, motion register, component coverage breadth, theme
             variants, accessibility posture. Write from all decisions.>

# --- Foundation tokens (reuse design/language/<purpose>.md if present) ---
colors:        <paste or reference>
typography:    <paste or reference — families + scale>
rounded:       <paste or reference>
spacing:       <paste or reference>
motion:        <paste or reference — duration + easing + reduced>

# --- System layer ---
components:
  <paste all components with their states: blocks>

themes:
  <paste theme alias layers if any — dark, high-contrast, compact>
  # omit this block entirely if no theme variants were generated

# --- Governance ---
component-status:
  <paste status map from s:design-governance>

deprecation-policy:
  <paste policy block>

contribution-rules:
  <paste rules block>

changelog:
  <paste changelog list, newest first>
---

<paste Overview section — written fresh from all decisions: canvas, primary,
type, shape, motion register, component coverage, theme variants, a11y
headline (e.g. "AA across base; AAA on high-contrast variant")>

<paste Colors prose section>

<paste Typography prose section>

<paste Layout prose section>

<paste Elevation prose section>

<paste Motion prose section>

<paste Components prose section — group by Buttons / Forms / Navigation /
Cards & Content / Purpose-specific. For each component, document the base
visual role AND walk through each entry in its states: block.>

<paste Theming prose section — only if themes were generated>

<paste Accessibility prose section from s:design-accessibility-audit>

<paste Governance prose section — version, status table, changelog,
deprecation policy, contribution>

<paste Responsive Behavior prose section>

## Known Gaps

<Always include. List:>
- Any design decision that could not be resolved from the available
  information.
- Accessibility failures flagged by `s:design-accessibility-audit` that
  the user chose not to fix (with the suggested fix repeated).
- Deprecated components: name, replacement, removal version.
- Theme variants explicitly omitted (e.g. "no high-contrast variant in
  this release").
- Motion register omissions (e.g. spring easing dropped for a restrained
  brand).
- Surface-specific systems still out of scope (illustration motion,
  sound design).
- Earlier changelog history not captured (if applicable).
```

## Writing the Overview section

Write fresh (not assembled from sub-sections). It must cover:

1. Canvas and base surface tone
2. Primary brand color and where it concentrates
3. Type system — families + weight philosophy
4. Shape language — radius scale signal
5. Motion register — name + the moments it animates
6. Component coverage — "N base + M purpose-specific components, all with
   states: matrices"
7. Theme variants — name each one or "no theme variants in this release"
8. Accessibility posture — "WCAG 2.2 AA across the base theme; failures
   listed in Known Gaps and Accessibility section"
9. Key Characteristics — 5–8 bullets naming distinctive decisions
   (reference token + component names inline, e.g. `{components.button-primary}`,
   `{motion.duration.base}`)

## File writing steps

1. Create the `design/system/` directory if it does not exist:
   ```bash
   mkdir -p design/system
   ```

2. If `design/system/<purpose>.md` already exists, read its `version`
   (the governance skill should already have done this for changelog
   computation) and ask:
   ```
   design/system/<purpose>.md exists at version <prior>.
   Writing new version <new>. Overwrite, or save as variant?
     O — overwrite (recommended — changelog preserves history)
     V — save as design/system/<purpose>-<new>.md (keep both)
   ```

3. Write the assembled content using the Write tool.

4. Confirm:
   ```bash
   ls -lh design/system/<purpose>.md
   ```

5. Invoke `/s:design-token-export` to emit machine-readable artifacts
   alongside the markdown. Pass `out-dir=design/system/`.

6. Ask the user: "Add `design/` to `.gitignore`?"
   - If yes: append `design/` to `.gitignore` if not already present.
   - If no: do nothing.

## Do Not

- Do not write any file before all checkpoints in the calling agent have
  been approved.
- Do not silently bump version. The governance skill should have asked
  the user; if not, raise it here before writing.
- Do not omit the `Components prose` walkthrough of `states:` blocks — a
  state matrix is useless without prose describing each state's role.
- Do not write a `brand_design/<purpose>.md` file. That path is retired.
- Do not modify token values during assembly — paste exactly as approved.
