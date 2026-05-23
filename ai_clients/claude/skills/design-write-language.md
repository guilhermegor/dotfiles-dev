---
name: s:design-write-language
description: Use when all design-language token sections and prose sections are
  approved and ready to be assembled into the final design/language/<purpose>.md
  file. Receives all tokens and prose from conversation context.
effort: medium
argument-hint: [brand-name] [purpose]
allowed-tools: Read Write Bash
---

Assemble all approved tokens and prose from conversation context into a single
file in strict awesome-design-md format — the **design language / foundations**
deliverable. This document is the canonical source the design-system tier
consumes; do not include component-level decisions here.

## Output path

```
design/language/<purpose>.md
```

Where `<purpose>` is the kebab-case artifact name chosen at the start of the
session (e.g. `brand-identity`, `site`, `app-cellphone`).

## Assembly order (strict — do not reorder)

```
---
version: alpha
tier: design-language
name: <brand name>
description: <one paragraph — tone, primary color, type approach, shape
             language, motion register, key differentiator. Write from the
             brand profile and all decisions made across foundation skills.>
colors:
  <paste complete color token block>
typography:
  families:
    <paste families block>
  <paste type scale tokens>
rounded:
  <paste rounded token block>
spacing:
  <paste spacing token block>
motion:
  duration:
    <paste duration tokens>
  easing:
    <paste easing tokens>
  reduced:
    <paste reduced-motion strategy>
---

<paste Overview section — write fresh from all design decisions: describe the
canvas, primary color role, type approach, shape language, motion register,
key characteristics as a bulleted list>

<paste Colors prose section>

<paste Typography prose section>

<paste Layout prose section>

<paste Elevation prose section>

<paste Motion prose section>

<paste Responsive Behavior prose section>

## Known Gaps

<Always include. List:>
- Any design decision that could not be resolved from the available information
- WCAG contrast failures flagged during color derivation (per the user's
  chosen verification mode)
- Font roles omitted and why (mono / accent)
- Motion register omissions (e.g. spring easing dropped for a restrained brand)
- Surface-specific tokens out of scope (illustration style, icon grid)
- Components — explicitly note: "Component specs live in the design-system
  tier, not the language tier."
```

## Writing the Overview section

Write fresh (not assembled from sub-sections). It must cover:

1. The canvas and base surface tone
2. The primary brand color and where it concentrates
3. The type system — font families and weight philosophy
4. The shape language — radius scale and what it signals
5. The motion register — name the register and the moments it animates
6. Key Characteristics — 5–8 bullet points naming the most distinctive
   design decisions (reference token names inline, e.g. `{colors.primary}`,
   `{motion.duration.base}`)

## File writing steps

1. Create the `design/language/` directory if it does not exist:
   ```bash
   mkdir -p design/language
   ```
2. Write the assembled content to `design/language/<purpose>.md` using the
   Write tool.
3. Confirm the file was written:
   ```bash
   ls -lh design/language/<purpose>.md
   ```
4. Invoke `/s:design-token-export` to emit machine-readable artifacts
   alongside the markdown. Pass `out-dir=design/language/`.
5. Ask the user: "Add `design/` to `.gitignore`?"
   - If yes: check whether `design/` is already in `.gitignore`.
     If not present, append it:
     ```bash
     grep -qxF 'design/' .gitignore 2>/dev/null \
       || echo 'design/' >> .gitignore
     ```
   - If no: do nothing.

## Do Not

- Do not include a `components:` section in the frontmatter. Components are
  the design-system tier's concern; the language tier stops at primitives.
- Do not write any file before all checkpoints in the calling agent have
  been approved.
- Do not modify token values during assembly — paste exactly as approved.
