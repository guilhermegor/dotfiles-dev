---
name: s:brand-write-design-md
description: Use when all brand design token sections and prose sections are
  approved and ready to be assembled into the final brand_design/<purpose>.md
  file. Receives all tokens and prose from conversation context.
effort: medium
argument-hint: [brand-name] [purpose]
allowed-tools: Read Write Bash
---

Assemble all approved tokens and prose from conversation context into a single
file in strict awesome-design-md format.

## Output path

```
brand_design/<purpose>.md
```

Where `<purpose>` is the kebab-case artifact name chosen at the start of the
session (e.g. `brand-identity`, `site`, `app-cellphone`).

## Assembly order (strict — do not reorder)

```
---
version: alpha
name: <brand name>
description: <one paragraph — tone, primary color, type approach, shape
             language, key differentiator. Write from the brand profile
             and the design decisions made across all skills.>
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
components:
  <paste component token block>
---

<paste Overview section — write fresh from all design decisions: describe the
canvas, primary color role, type approach, shape language, key characteristics
as a bulleted list>

<paste Colors prose section>

<paste Typography prose section>

<paste Layout prose section>

<paste Elevation prose section>

<paste Components prose section>

<paste Responsive Behavior prose section>

## Known Gaps

<Always include. List:>
- Any design decision that could not be resolved from the available information
- Interaction states not documented (hover, focus, loading) if not captured
- Sub-surface systems out of scope (illustration style, motion, sound)
- Font roles omitted and why
- WCAG contrast failures flagged during color derivation
- Any component group skipped for this purpose
```

## Writing the Overview section

The Overview section is written fresh (not assembled from sub-sections).
It must cover:
1. The canvas and base surface tone
2. The primary brand color and where it concentrates
3. The type system — font families and weight philosophy
4. The shape language — radius scale and what it signals
5. Key Characteristics — 5–8 bullet points naming the most distinctive
   design decisions (reference token names inline, e.g. `{colors.primary}`)

## File writing steps

1. Create the `brand_design/` directory if it does not exist:
   ```bash
   mkdir -p brand_design
   ```
2. Write the assembled content to `brand_design/<purpose>.md` using the
   Write tool.
3. Confirm the file was written:
   ```bash
   ls -lh brand_design/<purpose>.md
   ```
4. Ask the user: "Add `brand_design/` to `.gitignore`?"
   - If yes: check whether `brand_design/` is already in `.gitignore`.
     If not present, append it:
     ```bash
     grep -qxF 'brand_design/' .gitignore 2>/dev/null \
       || echo 'brand_design/' >> .gitignore
     ```
   - If no: do nothing.
