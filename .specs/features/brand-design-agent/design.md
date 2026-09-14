# Brand Design Agent — Spec

**Date:** 2026-05-02
**Status:** approved

---

## Overview

A conversational agent that interviews the user about a brand and generates a
production-ready design document in the
[awesome-design-md](https://github.com/VoltAgent/awesome-design-md) format.

The output is `brand_design/<purpose>.md` — a file combining a YAML frontmatter
block of machine-readable design tokens with rich prose sections explaining the
reasoning behind every token. One file per design artifact (brand identity,
site, mobile app, email, etc.). Multiple artifacts can coexist in `brand_design/`
for the same project.

---

## Files to Create

```
ai_clients/claude/agents/brand-design.md
ai_clients/claude/skills/brand-interview.md
ai_clients/claude/skills/brand-color-system.md
ai_clients/claude/skills/brand-type-system.md
ai_clients/claude/skills/brand-component-system.md
ai_clients/claude/skills/brand-layout-system.md
ai_clients/claude/skills/brand-write-design-md.md
```

7 files total. No existing files are modified.

---

## Agent: `a:brand-design`

### Frontmatter

```yaml
---
name: a:brand-design
description: Generate a brand design document (brand_design/<purpose>.md) by
  interviewing the user about their brand and producing design tokens + prose
  in the awesome-design-md format.
model: sonnet
color: purple
memory: true
disable-model-invocation: true
effort: high
argument-hint: [brand-name]
---
```

### Required inputs

Before invoking any skill, collect three inputs (use `$ARGUMENTS` for brand
name if provided):

1. **Brand name** — goes into the DESIGN.md `name:` frontmatter field.
2. **Design purpose** — shown as a numbered menu (see Purpose Menu below).
   User picks a number or types a custom description. Agent derives the
   kebab-case filename from the answer.
3. **Inspiration depth** — how deeply to analyse reference brands/sites:
   - A — surface signals only (colors, fonts, shapes from description)
   - B — fetch inspiration URLs with WebFetch and analyse their visual language
   - C — user describes inspirations in words; no fetching

### Purpose menu

```
What is this design for?

Core identity
  1. brand-identity     — palette, type, shape language; canonical source
  2. visual-identity    — extended system: elevation, motion, iconography

Web surfaces
  3. site               — marketing / landing page
  4. web-app            — SaaS or data-heavy web application
  5. dashboard          — admin / back-office, dense data
  6. ecommerce          — shop, product listing, cart, checkout
  7. docs               — documentation / developer portal
  8. blog               — editorial / content site

Mobile & native
  9. app-cellphone      — iOS / Android phone
 10. app-tablet         — iPad / Android tablet
 11. app-tv             — Smart TV / streaming (10-ft UI)
 12. app-watch          — wearable, 40–45mm canvas

Communication
 13. email              — transactional email
 14. email-marketing    — newsletter / campaign
 15. push-notification  — copy tone, icon specs, rich-notification layout

Physical & print
 16. print              — stationery / collateral, CMYK
 17. packaging          — product packaging, dieline, label hierarchy
 18. social-kit         — post templates, story frames, profile assets
 19. presentation       — slide deck, 16:9 grid

 20. Other — describe it and I'll derive the right questions and filename
```

Filename derivation: option number → predefined slug (e.g. `9` → `app-cellphone`).
Custom input → agent converts to kebab-case and confirms before continuing.

### Pipeline

```
[collect inputs]
        │
        ▼
s:brand-interview
        │
🔴 Checkpoint 1 — approve brand profile · revise or continue
        │
        ▼
s:brand-color-system
        │
🔴 Checkpoint 2 — approve color system · revise or continue
        │
        ▼
s:brand-type-system
        │
🔴 Checkpoint 3 — approve type system · revise or continue
        │
        ▼
s:brand-component-system
        │
🔴 Checkpoint 4 — approve components · revise or continue
        │
        ▼
s:brand-layout-system
        │
🔴 Checkpoint 5 — approve layout system · revise or continue
        │
        ▼
s:brand-write-design-md
        │
🔴 Checkpoint 6 — review written file · .gitignore? · done
```

### Checkpoint behaviour

At every checkpoint:
- Present a summary of what the skill produced.
- Ask: "Approve and continue, or what should change?"
- If the user requests changes: collect the feedback, re-invoke the same skill
  with the original inputs plus the feedback, present again.
- Loop until the user approves, then advance to the next skill.

### Final summary

After Checkpoint 6, print:

```
## Brand Design Complete

File:    brand_design/<purpose>.md
Brand:   <name>
Purpose: <purpose>
Tokens:  colors (<n>) · type roles (<n>) · components (<n>)

Sections written:
  ✓ Overview
  ✓ Colors
  ✓ Typography
  ✓ Layout
  ✓ Elevation
  ✓ Components
  ✓ Responsive Behavior
  ✓ Known Gaps

Gitignore: <added / not added>
```

### Memory

After each run, save a brief note about:
- Brand name and purpose
- Dominant look-and-feel adjectives used
- Any recurring patterns across multiple runs (common palettes, font choices)

### Do Not

- Do not proceed past a checkpoint without explicit user approval.
- Do not write any files before `s:brand-write-design-md`.
- Do not hard-code design decisions — all design reasoning happens inside skills.
- Do not auto-invoke this agent — it is user-triggered only.

---

## Skill: `s:brand-interview`

### Frontmatter

```yaml
---
name: s:brand-interview
description: Use when starting a brand design session to conduct the brand
  interview. Receives brand name, purpose, and inspiration depth. Asks
  questions adaptively until a complete brand profile can be produced.
effort: high
argument-hint: [brand-name] [purpose] [depth-a|b|c]
allowed-tools: WebFetch
---
```

### Behaviour

Ask questions **one at a time**. Never ask multiple questions in one message.

#### Universal questions (always, in this order)

1. **Inspirations** — "Which brands, sites, or visuals feel closest to what
   you want?" Ask for URLs or names.
   - Depth A: extract surface signals from the user's description only.
   - Depth B: fetch each URL with WebFetch and analyse the visual language
     (palette, type, shape, density, tone).
   - Depth C: ask the user to describe what they like about each reference in
     their own words; do not fetch.

2. **Market** — what industry, sector, or category does this brand operate in?

3. **Competitive position** — where does it sit relative to competitors?
   (premium/budget, specialist/generalist, challenger/incumbent)

4. **Target audience** — who uses this? Describe their context, tech comfort,
   and what they care about.

5. **Problem solved** — what pain or need does this brand address?

6. **Look & feel** — ask for 3–5 adjectives or mood words. Probe for
   emotional tone: "Should it feel authoritative or approachable?
   Playful or serious? Minimal or rich?"

#### Purpose-specific questions

After the universal questions, reason about the chosen purpose and derive
additional questions relevant to that surface. Keep asking until you have
enough to design all token layers. Examples:

- `app-cellphone` → platform (iOS / Android / both), primary navigation
  pattern, key gestures, dark mode required?
- `email` / `email-marketing` → ESP (Mailchimp, Sendgrid, etc.), dark mode
  support needed, image-heavy or text-heavy?
- `dashboard` → data density preference, role-based access (different surfaces
  per role?), chart/visualisation style
- `ecommerce` → number of product categories, trust signals needed, guest
  checkout or account-required?
- `print` / `packaging` → print process (offset, digital, screen), materials,
  CMYK constraints, finish (matte/gloss/uncoated)?
- `docs` → code-heavy or prose-heavy, dark mode default, versioned content?
- Custom purpose → reason about which design concerns that surface introduces
  and ask accordingly

Stop asking when you can answer: what does it look like, who is it for, what
does it need to do, and what are the surface-specific constraints?

### Output

A **structured brand profile** in markdown. Sections:

```markdown
# Brand Profile: <name> — <purpose>

## Identity
- Name: …
- Purpose: …
- Market: …
- Competitive position: …
- Audience: …
- Problem solved: …

## Visual Direction
- Look & feel: [adjectives]
- Emotional tone: …
- Inspirations: [list with notes]
- Extracted signals (depth B): [palette swatches, font names, shape notes]

## Surface Constraints
[purpose-specific answers]

## Inspiration Depth
[A / B / C — summary of how inspirations were processed]
```

---

## Skill: `s:brand-color-system`

### Frontmatter

```yaml
---
name: s:brand-color-system
description: Use when generating the color system for a brand design document.
  Receives the brand profile from conversation context. Produces color tokens
  and the Colors prose section.
effort: high
argument-hint: [brand-name] [purpose]
allowed-tools: Read
---
```

### Behaviour

Derive the full color token set from the brand profile in conversation context.
Depth-B inspiration analysis (palette extraction from fetched URLs) was already
performed by `s:brand-interview` — use the extracted signals already in the
brand profile; do not re-fetch.

#### Token set to produce

```yaml
colors:
  # Primary brand color + interaction states
  primary: "#…"
  primary-active: "#…"
  primary-disabled: "#…"

  # Sub-brand accents (only if the brand has distinct sub-products/tiers)
  # accent-[name]: "#…"

  # Text hierarchy
  ink: "#…"         # dominant text — headlines, body on light bg
  body: "#…"        # running text (slightly lighter than ink)
  muted: "#…"       # secondary labels, inactive states
  muted-soft: "#…"  # disabled text

  # Surface tiers
  canvas: "#…"      # default page background
  surface-soft: "#…"
  surface-card: "#…"
  surface-strong: "#…"

  # On-color text
  on-primary: "#…"
  on-dark: "#…"

  # Borders & hairlines
  hairline: "#…"
  hairline-soft: "#…"
  border-strong: "#…"

  # Semantic
  error: "#…"
  error-hover: "#…"
  success: "#…"
  warning: "#…"

  # Utility
  scrim: "#…"       # modal backdrop base (opacity applied at render time)
```

#### Rules

- Never use raw hex values in component or typography tokens — only in this
  color block.
- Ensure WCAG AA contrast between `ink` and `canvas` (minimum 4.5:1).
- Primary color should carry enough saturation to function as a CTA on
  `canvas` and `surface-card` backgrounds.
- Flag any color that fails contrast in the Known Gaps section.

### Output

Color token block (YAML) + **Colors prose section** explaining each group:
Brand & Accent → Surface → Hairlines & Borders → Text → Semantic → Scrim.

---

## Skill: `s:brand-type-system`

### Frontmatter

```yaml
---
name: s:brand-type-system
description: Use when generating the typography system for a brand design
  document. Receives brand profile and color tokens from conversation context.
  Produces font role definitions, type scale tokens, and the Typography prose
  section.
effort: high
argument-hint: [brand-name] [purpose]
allowed-tools: Read
---
```

### Behaviour

#### Step 1 — Define font roles

For each role, recommend a primary font and provide a full fallback stack.
Base recommendations on brand adjectives and surface constraints.

| Role | When to use | Example primaries |
|---|---|---|
| `display` | Hero headlines, section titles | Playfair Display, Fraunces, DM Serif Display |
| `body` | Running text, paragraphs | Inter, Source Sans 3, Lato |
| `ui` | Buttons, labels, nav (often same as body) | Inter, DM Sans |
| `mono` | Code, table data, prices, stats | JetBrains Mono, Fira Code, IBM Plex Mono |
| `accent` | Optional decorative moments | script or display variant |

Omit `mono` only if the brand profile explicitly has no data tables, code, or
numeric displays — and flag this in Known Gaps.
Omit `accent` unless the brand adjectives clearly call for a decorative moment.

#### Step 2 — Fallback stacks

Each role gets a full stack: primary → Google/custom alternative → system
equivalent → generic fallback.

```yaml
typography:
  families:
    display: "'Playfair Display', Georgia, 'Times New Roman', serif"
    body: "'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
    ui: "'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
    mono: "'JetBrains Mono', 'Fira Code', 'Courier New', monospace"
```

#### Step 3 — Type scale tokens

Each token references `{typography.families.<role>}`. Scale adapts to purpose
(mobile tokens use rem/px targets appropriate for 375px viewports; print tokens
use pt).

Minimum scale to produce (add or remove tokens based on purpose):

```
display-xl, display-lg, display-md, display-sm
title-md, title-sm
body-md, body-sm
ui-md, ui-sm
mono-md, mono-sm       (if mono role present)
caption, caption-sm
badge, micro-label
button-md, button-sm
link, nav-link
```

### Output

`families` block + type scale tokens (YAML) + **Typography prose section**:
Font Family → Hierarchy table → Principles → Fallback note.

---

## Skill: `s:brand-component-system`

### Frontmatter

```yaml
---
name: s:brand-component-system
description: Use when generating the component token set for a brand design
  document. Receives brand profile, color tokens, and type tokens from
  conversation context. Produces component tokens and the Components prose
  section.
effort: high
argument-hint: [brand-name] [purpose]
allowed-tools: Read
---
```

### Behaviour

Define component tokens using **only** `{colors.*}` and `{typography.*}`
references — never raw hex or px values in this block. Every property that
can reference a token must.

#### Component list adapts to purpose

Base set (all purposes):
- `button-primary`, `button-primary-active`, `button-primary-disabled`
- `button-secondary`, `button-tertiary-text`
- `text-input`, `text-input-focus`, `text-input-error`

Purpose-specific additions:

| Purpose | Additional components |
|---|---|
| `site` / `web-app` | `top-nav`, `footer`, `card`, `hero`, `search-bar` |
| `dashboard` | `sidebar`, `data-table-row`, `badge`, `tooltip`, `chart-legend` |
| `ecommerce` | `product-card`, `cart-item`, `price-tag`, `filter-pill`, `checkout-step` |
| `app-cellphone` | `tab-bar`, `bottom-sheet`, `list-row`, `fab`, `toast` |
| `app-tablet` | `split-pane`, `master-row`, `detail-header` |
| `email` | `email-header`, `email-cta-block`, `email-footer` |
| `blog` | `article-header`, `pull-quote`, `author-card`, `tag-pill` |
| `docs` | `code-block`, `callout`, `sidebar-nav-item`, `search-input` |
| `print` | `page-header`, `section-divider`, `caption-block` |

For custom purposes: reason about which UI patterns that surface requires and
derive an appropriate component list.

### Output

Component token block (YAML) + **Components prose section** describing each
component group.

---

## Skill: `s:brand-layout-system`

### Frontmatter

```yaml
---
name: s:brand-layout-system
description: Use when generating the layout and spacing system for a brand
  design document. Receives brand profile and all previous tokens from
  conversation context. Produces spacing, border-radius, and grid tokens,
  plus Layout, Elevation, and Responsive Behavior prose sections.
effort: high
argument-hint: [brand-name] [purpose]
allowed-tools: Read
---
```

### Behaviour

#### Spacing scale

Define a base unit (4px or 8px typical) and named steps:

```yaml
spacing:
  xxs: 2px
  xs: 4px
  sm: 8px
  md: 12px
  base: 16px
  lg: 24px
  xl: 32px
  xxl: 48px
  section: 64px
```

Adjust scale to purpose: print uses pt, email constrains to multiples of 8px
for table-based layouts, mobile may add `safe-area-top` and `safe-area-bottom`.

#### Border-radius tokens

```yaml
rounded:
  none: 0px
  xs: 2px
  sm: 4px
  md: 8px
  lg: 16px
  xl: 24px
  full: 9999px
```

Shape language (sharp vs. soft) must reflect brand adjectives from the profile.

#### Grid & container

- Max content width, column count, gutter width — adapted to purpose.
- Mobile: single-column base, breakpoints for tablet and desktop.
- Email: fixed 600px, no responsive grid (table-based).
- Print: page margins + column grid in pt/mm.

#### Responsive breakpoints

Adapted to purpose:
- Web: xs (< 480px), sm (480–768px), md (768–1024px), lg (1024–1280px), xl (> 1280px)
- Mobile: device size tiers (375px, 390px, 428px) + orientation
- Email: single breakpoint at 480px (below: stack to 1 column)
- TV: 1080p baseline, 4K scaling tier
- Print / packaging: no breakpoints — define page sizes instead

### Output

`spacing`, `rounded` token blocks + grid/container spec (YAML comments) +
**Layout prose section** + **Elevation prose section** (shadow tiers: flat
baseline, card-hover float, modal scrim) + **Responsive Behavior** section
(table of breakpoints + key changes per tier).

---

## Skill: `s:brand-write-design-md`

### Frontmatter

```yaml
---
name: s:brand-write-design-md
description: Use when all brand design token sections and prose sections are
  approved and ready to be assembled into the final brand_design/<purpose>.md
  file. Receives all tokens and prose from conversation context.
effort: medium
argument-hint: [brand-name] [purpose]
allowed-tools: Read Write Bash
---
```

### Behaviour

#### Assembly order (strict)

```
---                          ← YAML frontmatter open
version: alpha
name: <brand name>
description: <one-paragraph brand summary — tone, primary color, type approach,
             shape language, key differentiator>
colors: <token block>
typography: <families block + scale tokens>
rounded: <token block>
spacing: <token block>
components: <token block>
---                          ← YAML frontmatter close

## Overview
## Colors
### Brand & Accent
### Surface
### Hairlines & Borders
### Text
### Semantic
### Scrim
## Typography
### Font Family
### Hierarchy  ← table: token | size | weight | line-height | letter-spacing | use
### Principles
### Fallback Note
## Layout
### Spacing System
### Grid & Container
### Whitespace Philosophy
## Elevation
## Components
### Buttons
### [purpose-specific groups]
### Forms
### Footer / Nav
## Responsive Behavior  ← table: name | width | key changes
### Touch Targets       ← only for mobile/tablet purposes
### Collapsing Strategy
## Known Gaps
```

#### File writing

1. Create `brand_design/` directory if it does not exist.
2. Write the assembled content to `brand_design/<purpose>.md`.
3. Ask: "Add `brand_design/` to `.gitignore`?" — if yes, append the entry;
   do not duplicate if already present.

#### Known Gaps section

Always include. List any:
- Design decisions that could not be made from the available information
- States not documented (hover, focus, loading, error) if not captured
- Sub-surface systems not covered (e.g. illustration style, motion/animation)
- Font roles omitted and why (e.g. "mono omitted — no data tables in scope")
- WCAG contrast failures flagged by `s:brand-color-system`

### Output

Written file at `brand_design/<purpose>.md`.

---

## Output Format Reference

The assembled DESIGN.md follows the
[awesome-design-md](https://github.com/VoltAgent/awesome-design-md) format
exactly. Token references use `{section.token-name}` syntax throughout prose
and component definitions (e.g. `{colors.primary}`, `{typography.button-md}`,
`{rounded.full}`).

---

## Deployment

After creating the files:

```bash
./ai_clients/claude/main.sh agents   # install a:brand-design
./ai_clients/claude/main.sh skills   # install all s:brand-* skills
# or:
./ai_clients/claude/main.sh all
```

---

## Open Questions

None — all decisions resolved during brainstorming session (2026-05-02).
