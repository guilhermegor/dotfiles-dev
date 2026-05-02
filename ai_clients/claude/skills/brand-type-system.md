---
name: s:brand-type-system
description: Use when generating the typography system for a brand design
  document. Receives brand profile and color tokens from conversation context.
  Produces font role definitions with fallback stacks, type scale tokens, and
  the Typography prose section.
effort: high
argument-hint: [brand-name] [purpose]
allowed-tools: Read
---

Read the brand profile and color tokens from conversation context.

## Step 1 — Define font roles

For each role below, recommend a primary font and build a full fallback stack.
Base choices on brand adjectives, emotional tone, and surface constraints.

| Role | Usage | Good primaries |
|------|-------|----------------|
| `display` | Hero headlines, section titles | Playfair Display, Fraunces, DM Serif Display, Cabinet Grotesk |
| `body` | Running text, paragraphs | Inter, Source Sans 3, Lato, Plus Jakarta Sans |
| `ui` | Buttons, labels, nav (often same as body) | Inter, DM Sans, Geist |
| `mono` | Code, table data, prices, stats | JetBrains Mono, Fira Code, IBM Plex Mono |
| `accent` | Optional decorative moments | Caveat, Dancing Script, any script/display variant |

**Omit `mono`** only when the brand profile explicitly has no code, data
tables, or numeric displays — and add a Known Gaps entry: "mono font role
omitted — no data tables or numeric displays in scope for this artifact."

**Omit `accent`** unless brand adjectives clearly call for a decorative
typographic moment (e.g. "handcrafted", "personal", "editorial").

## Step 2 — Build fallback stacks

Pattern: primary → open-source alternative → system equivalent → generic.

```yaml
typography:
  families:
    display: "'<Primary>', <Alt>, <System>, serif|sans-serif"
    body:    "'<Primary>', <Alt>, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
    ui:      "'<Primary>', <Alt>, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
    mono:    "'<Primary>', '<Alt>', 'Courier New', monospace"
    accent:  "'<Primary>', cursive"   # only if accent role defined
```

Example (editorial brand):
```yaml
typography:
  families:
    display: "'Playfair Display', Georgia, 'Times New Roman', serif"
    body:    "'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
    ui:      "'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
    mono:    "'JetBrains Mono', 'Fira Code', 'Courier New', monospace"
```

## Step 3 — Type scale tokens

Each token references `{typography.families.<role>}`. Adapt sizes to purpose:
- Web / app: px targets standard for the viewport (16px body baseline)
- Mobile: scale down display tokens ~10–15% for 375px viewport
- Print: use pt instead of px
- Email: stick to web-safe sizes (14px body minimum for email clients)

Produce at minimum these tokens (add or remove based on purpose):

```yaml
typography:
  # display-xl is the largest headline — hero h1, rating numbers
  display-xl:
    fontFamily: "{typography.families.display}"
    fontSize: <px/pt/rem>
    fontWeight: <400|500|600|700>
    lineHeight: <ratio, e.g. 1.2>
    letterSpacing: <px or 0>

  display-lg:
    fontFamily: "{typography.families.display}"
    fontSize: …
    fontWeight: …
    lineHeight: …
    letterSpacing: …

  display-md:
    fontFamily: "{typography.families.display}"
    …

  display-sm:
    fontFamily: "{typography.families.display}"
    …

  title-md:
    fontFamily: "{typography.families.ui}"
    …

  title-sm:
    fontFamily: "{typography.families.ui}"
    …

  body-md:
    fontFamily: "{typography.families.body}"
    fontSize: 16px
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: 0

  body-sm:
    fontFamily: "{typography.families.body}"
    fontSize: 14px
    fontWeight: 400
    lineHeight: 1.43
    letterSpacing: 0

  ui-md:
    fontFamily: "{typography.families.ui}"
    …

  ui-sm:
    fontFamily: "{typography.families.ui}"
    …

  # mono-md / mono-sm — only if mono role is present
  mono-md:
    fontFamily: "{typography.families.mono}"
    fontSize: 14px
    fontWeight: 400
    lineHeight: 1.6
    letterSpacing: 0

  mono-sm:
    fontFamily: "{typography.families.mono}"
    fontSize: 13px
    …

  caption:
    fontFamily: "{typography.families.ui}"
    fontSize: 14px
    fontWeight: 500
    lineHeight: 1.29
    letterSpacing: 0

  caption-sm:
    fontFamily: "{typography.families.ui}"
    fontSize: 13px
    fontWeight: 400
    …

  badge:
    fontFamily: "{typography.families.ui}"
    fontSize: 11px
    fontWeight: 600
    …

  micro-label:
    fontFamily: "{typography.families.ui}"
    fontSize: 12px
    fontWeight: 700
    …

  button-md:
    fontFamily: "{typography.families.ui}"
    fontSize: 16px
    fontWeight: 500
    lineHeight: 1.25
    letterSpacing: 0

  button-sm:
    fontFamily: "{typography.families.ui}"
    fontSize: 14px
    fontWeight: 500
    …

  link:
    fontFamily: "{typography.families.body}"
    fontSize: 14px
    fontWeight: 400
    …

  nav-link:
    fontFamily: "{typography.families.ui}"
    fontSize: 16px
    fontWeight: 600
    …
```

## Typography prose section

Write the prose section into the conversation:

```markdown
## Typography

### Font Family
<Describe the font role choices and why they match the brand adjectives.
E.g.: "The system runs Inter for body and UI — a neutral, highly legible
grotesque that suits the clinical efficiency the brand needs — with Playfair
Display for display headlines to inject the editorial warmth that pure sans
would miss. JetBrains Mono handles the dense data tables in the dashboard.">

Fallback stacks walk: primary → open-source alt → system stack → generic.

### Hierarchy

| Token | Size | Weight | Line Height | Letter Spacing | Role family | Use |
|-------|------|--------|-------------|----------------|-------------|-----|
| `{typography.display-xl}` | <px> | <w> | <lh> | <ls> | display | <usage> |
| `{typography.display-lg}` | … | … | … | … | display | … |
[continue for all tokens]

### Principles
<2–3 sentences on the weight and scale philosophy. E.g.: "Display weights
stay modest — the hero h1 at 28px / 600 lets photography carry visual
hierarchy rather than typographic muscle. The single loud typographic moment
is the rating display at 64px / 700 — the peak trust signal on the listing
page.">

### Fallback Note
If <primary font> is unavailable, <closest open-source substitute> is the
best replacement. Adjust <specific property> by <amount> to match cap height.
```
