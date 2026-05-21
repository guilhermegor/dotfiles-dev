---
name: s:brand-write-book
description: Use when all brand-tier sections (identity, logo & imagery) are
  approved and ready to be assembled into the final design/brand/brand-book.md
  file. Receives the brand profile, identity block, and logo/imagery block
  from conversation context. Prose-heavy assembly; the identity palette and
  typefaces are emitted as small frontmatter blocks but the full token scale
  is not.
effort: medium
argument-hint: [brand-name]
allowed-tools: Read Write Bash
---

Assemble the approved brand-tier content into a single brand book at
`design/brand/brand-book.md`. The brand book is the **identity** deliverable
— prose-first, with a small seed-palette and typeface block that the
design-language tier consumes.

## Output path

```
design/brand/brand-book.md
```

A brand book is per-brand, not per-purpose — only one `brand-book.md` lives
under `design/brand/`. If a file already exists, ask the user before
overwriting.

## Assembly order (strict — do not reorder)

```
---
version: alpha
tier: brand-design
name: <brand name>
description: <one paragraph — mission, personality, voice register,
             dominant identity colour, type approach. Written fresh from the
             identity block.>
identity-palette:
  <paste 5-color identity-palette block from s:brand-identity>
typefaces:
  <paste typefaces list from s:brand-identity>
---

# <Brand Name> — Brand Book

<paste Mission section>

<paste Positioning section>

<paste Personality section>

<paste Voice section — spectrum + do/don't table>

<paste Logo section>

<paste Imagery section>

<paste Iconography section>

## Identity Palette

<For each of the 5 identity colours, write a paragraph block:>

### <Color brand name> — `{role}` · #<hex>
<2–3 sentences: where it shows up, the brand-level meaning, what it must
never be used for. Trace back to the personality adjective it carries.>

[…repeat for primary, secondary, ink, canvas, semantic-critical]

## Typefaces

### <Primary face name> — <role>
<Paragraph: classification, where it lives in the brand, what cultural signal
it sends, what the open-source / system fallback should be when unavailable.
Do NOT produce a fallback stack here — that's the design-language tier's
job.>

[…repeat for each typeface]

## Known Gaps

<Always include. List:>
- Identity dimensions the brand profile could not resolve (e.g. competitive
  positioning unclear; mission still in draft).
- Logo status — "no logo yet; brief documented" or "existing logo, files
  not yet vectorised."
- WCAG contrast: ink-on-canvas ratio + pass/fail note (no auto-correction
  at this tier).
- Sections deliberately scoped out: full token scale (→ design-language),
  component states (→ design-system), motion (→ design-language).
- Imagery production constraints (no budget / no rights cleared yet).
```

## Writing the description

The description paragraph in the frontmatter must cover, in this order:

1. Mission (one phrase)
2. Personality (two adjectives, the most distinctive)
3. Voice register (one phrase, e.g. "plain-language, warm")
4. Dominant identity color (name + role)
5. Type approach (e.g. "serif display + grotesque body" or "single
   variable sans across all roles")

## File writing steps

1. Create the `design/brand/` directory if it does not exist:
   ```bash
   mkdir -p design/brand
   ```

2. If `design/brand/brand-book.md` already exists, read it and ask:
   ```
   A brand book already exists at design/brand/brand-book.md for brand
   "<existing name>". Overwrite, or save this as a variant?
     O — overwrite
     V — save as design/brand/brand-book-<slug>.md
     X — abort
   ```

3. Write the assembled content to the chosen path using the Write tool.

4. Confirm the file:
   ```bash
   ls -lh design/brand/brand-book.md
   ```

5. Ask the user: "Add `design/` to `.gitignore`?"
   - If yes: check whether `design/` is already in `.gitignore`. If not
     present, append it:
     ```bash
     grep -qxF 'design/' .gitignore 2>/dev/null \
       || echo 'design/' >> .gitignore
     ```
   - If no: do nothing.

## Do Not

- Do not emit a `colors:`, `typography:`, `spacing:`, `rounded:`, `motion:`,
  or `components:` block in the frontmatter. The brand book carries only
  `identity-palette` and `typefaces`. The design-language tier expands them.
- Do not invoke `s:design-color-system` or `s:design-type-system` — those
  produce full token scales the brand tier does not need.
- Do not write any file before all checkpoints in the calling agent have
  been approved.
- Do not embed image files. Logo and imagery are specifications only.
