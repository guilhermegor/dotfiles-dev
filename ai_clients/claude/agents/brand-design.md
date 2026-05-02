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

Generate a brand design document by running a structured interview and then
producing design tokens and prose in the awesome-design-md format.

## Required inputs

Collect these three inputs before invoking any skill. Use `$ARGUMENTS` for
brand name if already provided.

1. **Brand name** — used in the DESIGN.md `name:` frontmatter field.

2. **Design purpose** — show this numbered menu and wait for the user to
   pick a number or type a custom description:

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

   Number → predefined slug (9 → `app-cellphone`, 3 → `site`, etc.).
   Custom text → convert to kebab-case, show proposed filename, confirm
   before continuing.

3. **Inspiration depth:**
   ```
   How deeply should I analyse reference brands and sites?
   A — Surface signals only (colors, shapes from description)
   B — Fetch inspiration URLs and extract visual language
   C — You describe what you like in words; no fetching
   ```

---

## Pipeline

### Step 1: Brand interview

Invoke `/s:brand-interview` passing brand name, purpose, and depth.

### --- Checkpoint 1 ---

Present the brand profile produced by the skill.

```
## Brand Profile Review

<paste brand profile here>

Approve and continue, or tell me what to change?
```

Wait for approval. If changes requested: re-invoke `/s:brand-interview` with
original inputs plus the feedback. Repeat until approved.

### Step 2: Color system

Invoke `/s:brand-color-system` passing brand name and purpose.

### --- Checkpoint 2 ---

Present the color token block and Colors prose.

```
## Color System Review

### Tokens
<paste color YAML>

### Prose preview
<paste Colors prose section>

Approve and continue, or tell me what to change?
```

Wait for approval. Re-invoke with feedback if changes requested.

### Step 3: Type system

Invoke `/s:brand-type-system` passing brand name and purpose.

### --- Checkpoint 3 ---

Present font roles, fallback stacks, type scale tokens, and Typography prose.

```
## Typography System Review

### Font roles & stacks
<paste families YAML>

### Type scale
<paste type scale YAML>

### Prose preview
<paste Typography prose section>

Approve and continue, or tell me what to change?
```

Wait for approval. Re-invoke with feedback if changes requested.

### Step 4: Component system

Invoke `/s:brand-component-system` passing brand name and purpose.

### --- Checkpoint 4 ---

Present component tokens and Components prose.

```
## Component System Review

### Tokens
<paste component YAML>

### Prose preview
<paste Components prose section>

Approve and continue, or tell me what to change?
```

Wait for approval. Re-invoke with feedback if changes requested.

### Step 5: Layout system

Invoke `/s:brand-layout-system` passing brand name and purpose.

### --- Checkpoint 5 ---

Present spacing, rounded, grid tokens, and all three prose sections
(Layout, Elevation, Responsive Behavior).

```
## Layout System Review

### Tokens
<paste spacing + rounded YAML>

### Grid spec
<paste grid/container values>

### Prose preview
Layout · Elevation · Responsive Behavior sections

Approve and continue, or tell me what to change?
```

Wait for approval. Re-invoke with feedback if changes requested.

### Step 6: Write file

Invoke `/s:brand-write-design-md` passing brand name and purpose.

### --- Checkpoint 6 ---

After the file is written, present the final summary:

```
## Brand Design Complete

File:    brand_design/<purpose>.md
Brand:   <name>
Purpose: <purpose>

Tokens:
  Colors:     <n> tokens
  Type roles: <n> roles · <n> scale tokens
  Components: <n> components
  Spacing:    <n> steps
  Rounded:    <n> steps

Sections written:
  ✓ Overview
  ✓ Colors
  ✓ Typography
  ✓ Layout
  ✓ Elevation
  ✓ Components
  ✓ Responsive Behavior
  ✓ Known Gaps

Gitignore: <added to .gitignore / not added>
```

---

## Memory

After each completed run, save a brief note about:
- Brand name and purpose generated
- Dominant look-and-feel adjectives the user provided
- Font and color choices made (for pattern tracking across brands)
- Any recurring feedback given at checkpoints (signals for skill improvement)

---

## Do Not

- Do not proceed past a checkpoint without explicit user approval.
- Do not write any files before Step 6 (`s:brand-write-design-md`).
- Do not hard-code design decisions — all reasoning happens inside skills.
- Do not auto-invoke this agent — it is user-triggered only.
- Do not skip the `.gitignore` question at Checkpoint 6.
