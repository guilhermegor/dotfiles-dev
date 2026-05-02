# Brand Design Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a conversational agent (`a:brand-design`) that interviews the
user about a brand and generates a production-ready design document
(`brand_design/<purpose>.md`) in the awesome-design-md format.

**Architecture:** One agent orchestrates six skills in strict sequence with
a checkpoint after every skill. All design reasoning lives in skills — the
agent is a thin router. Skills communicate through conversation context, not
files. The output is a single markdown file with YAML token frontmatter
followed by rich prose sections.

**Tech Stack:** Claude Code agents + skills (markdown with YAML frontmatter),
awesome-design-md token format, bash for install verification.

**Spec:** `docs/superpowers/specs/2026-05-02-brand-design-agent-design.md`

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `ai_clients/claude/skills/brand-interview.md` | adaptive questionnaire → brand profile |
| Create | `ai_clients/claude/skills/brand-color-system.md` | color tokens + Colors prose |
| Create | `ai_clients/claude/skills/brand-type-system.md` | font roles + type scale tokens + Typography prose |
| Create | `ai_clients/claude/skills/brand-component-system.md` | component tokens + Components prose |
| Create | `ai_clients/claude/skills/brand-layout-system.md` | spacing/radius/grid tokens + Layout + Elevation + Responsive prose |
| Create | `ai_clients/claude/skills/brand-write-design-md.md` | assemble + write brand_design/<purpose>.md |
| Create | `ai_clients/claude/agents/brand-design.md` | orchestrator — collects inputs, runs pipeline, checkpoints |

---

## Task 1: Create `s:brand-interview`

**Files:**
- Create: `ai_clients/claude/skills/brand-interview.md`

- [ ] **Step 1: Verify skill directory exists**

```bash
ls ai_clients/claude/skills/
```

Expected: directory exists, shows existing `py-*.md` files.

- [ ] **Step 2: Write the skill file**

Create `ai_clients/claude/skills/brand-interview.md` with this exact content:

````markdown
---
name: s:brand-interview
description: Use when starting a brand design session to conduct the brand
  interview. Receives brand name, purpose, and inspiration depth from the
  calling agent. Asks questions adaptively until a complete brand profile
  can be produced.
effort: high
argument-hint: [brand-name] [purpose] [depth-a|b|c]
allowed-tools: WebFetch
---

Ask questions **one at a time**. Never ask multiple questions in one message.

You already have the brand name, design purpose, and inspiration depth from
`$ARGUMENTS`. Do not ask for them again.

## Universal questions (always, in this order)

1. **Inspirations** — "Which brands, sites, or visuals feel closest to what
   you want? Give me names, URLs, or describe them."
   - Depth A: note names/descriptions as surface signals only — do not fetch.
   - Depth B: fetch each URL using WebFetch. For each, extract: dominant
     palette (3–5 hex values), font family names from headings or CSS,
     shape language (sharp / soft / pill), density (airy / balanced / dense),
     tone (formal / casual / playful / premium). Record as extracted signals.
   - Depth C: ask "What specifically draws you to each reference — the
     colors, the typography, the feeling, the density?" Do not fetch.

2. **Market** — "What industry, sector, or category does this brand operate in?"

3. **Competitive position** — "Where does it sit relative to competitors?
   For example: premium or budget? Specialist or generalist?
   Challenger or established player?"

4. **Target audience** — "Who uses this? Describe their context, their
   technical comfort level, and what they care most about."

5. **Problem solved** — "What pain or need does this brand address? One
   sentence is enough."

6. **Look & feel** — "Give me 3–5 adjectives or mood words that describe how
   this should feel." Then probe: "Should it feel authoritative or
   approachable? Playful or serious? Minimal or rich?"

## Purpose-specific questions

After the universal questions, reason about the chosen purpose and derive
additional questions. Keep asking one at a time until you can answer:
what does it look like, who is it for, what does it need to do, and what
are the surface-specific constraints?

- `brand-identity` / `visual-identity` → "Do you have a logo or wordmark
  already, or is this greenfield?", "Any brand colors already locked in?"
- `app-cellphone` → "iOS, Android, or both?", "Primary navigation pattern
  — tab bar, bottom drawer, or stack?", "Dark mode required?"
- `app-tablet` → "Does it share a codebase with the phone app?",
  "Split-view / master-detail expected?"
- `email` / `email-marketing` → "Which ESP?", "Dark mode support needed?",
  "Image-heavy or mostly text?"
- `dashboard` → "Data density — compact rows or spacious cards?",
  "Multiple user roles with different views?", "Chart style preference?"
- `ecommerce` → "How many product categories?", "Guest checkout or account
  required?", "Key trust signals — reviews, guarantees, certifications?"
- `docs` → "Code-heavy or prose-heavy?", "Dark mode default?",
  "Versioned content?"
- `print` / `packaging` → "Print process — offset, digital, or screen?",
  "Materials and finish?", "CMYK constraints?"
- `social-kit` → "Which platforms — Instagram, LinkedIn, X, TikTok?",
  "Static images only or motion/video too?"
- `presentation` → "Tool — PowerPoint, Keynote, Google Slides?",
  "Internal use or client-facing?"
- Custom purpose → reason about rendering environment, interaction model,
  grid constraints, and accessibility requirements for that surface.

## Output

When you have enough information, write the complete brand profile into
the conversation using this template:

```
# Brand Profile: <name> — <purpose>

## Identity
- Name: <brand name>
- Purpose: <design artifact, e.g. app-cellphone>
- Market: <industry/sector>
- Competitive position: <e.g. premium challenger in B2B SaaS>
- Audience: <description including context and tech comfort>
- Problem solved: <one sentence>

## Visual Direction
- Look & feel: <comma-separated adjectives>
- Emotional tone: <e.g. authoritative but approachable>
- Inspirations:
  - <name/url>: <notes on what to take from it>
- Extracted signals (depth B only — omit section for A and C):
  - Palette: <hex values>
  - Fonts: <family names seen>
  - Shape: <sharp / soft / pill>
  - Density: <airy / balanced / dense>
  - Tone: <formal / casual / premium / playful>

## Surface Constraints
<purpose-specific answers, one bullet per question answered>

## Inspiration Depth
<A / B / C — one sentence summary of how inspirations were processed>
```
````

- [ ] **Step 3: Validate frontmatter fields**

```bash
grep -c "^name: s:brand-interview$" \
  ai_clients/claude/skills/brand-interview.md
grep -c "^description: Use when" \
  ai_clients/claude/skills/brand-interview.md
grep -c "^effort: high$" \
  ai_clients/claude/skills/brand-interview.md
grep -c "^allowed-tools: WebFetch$" \
  ai_clients/claude/skills/brand-interview.md
```

Expected: each command prints `1`.

- [ ] **Step 4: Commit**

```bash
git add ai_clients/claude/skills/brand-interview.md
git commit -m "feat(skills): add s:brand-interview adaptive questionnaire"
```

---

## Task 2: Create `s:brand-color-system`

**Files:**
- Create: `ai_clients/claude/skills/brand-color-system.md`

- [ ] **Step 1: Write the skill file**

Create `ai_clients/claude/skills/brand-color-system.md` with this exact content:

````markdown
---
name: s:brand-color-system
description: Use when generating the color system for a brand design document.
  Receives the brand profile from conversation context. Produces color tokens
  and the Colors prose section.
effort: high
argument-hint: [brand-name] [purpose]
allowed-tools: Read
---

Read the brand profile from conversation context. Derive the full color token
set, then write the Colors prose section.

## Rules (never violate)

- Raw hex values live **only** in this token block. Component and typography
  tokens always reference `{colors.*}` — never raw hex.
- `ink` on `canvas` must meet WCAG AA minimum (4.5:1 contrast ratio).
- `primary` must be legible as a CTA on both `canvas` and `surface-card`.
- Flag any failing contrast pair in the final Known Gaps section.
- Depth-B inspiration signals are already in the brand profile. Do not
  re-fetch any URLs.

## Token set to produce

Derive every value from the brand profile's look-and-feel adjectives,
emotional tone, extracted inspiration signals, market, and audience.

```yaml
colors:
  primary: "#…"          # dominant brand color — CTAs, focus rings, key moments
  primary-active: "#…"   # press state (darken primary ~12%)
  primary-disabled: "#…" # disabled CTA (desaturate + lighten primary)

  # Sub-brand accents — only if the brand has distinct sub-products or tiers
  # accent-[name]: "#…"

  ink: "#…"              # dominant text: headlines, body (near-black, not pure)
  body: "#…"             # running text (slightly lighter than ink)
  muted: "#…"            # secondary labels, inactive states
  muted-soft: "#…"       # disabled / placeholder text

  canvas: "#…"           # default page / screen background
  surface-soft: "#…"     # subtle fill: disabled fields, hover backgrounds
  surface-card: "#…"     # card background
  surface-strong: "#…"   # stronger fill: icon button surfaces, active rows

  on-primary: "#…"       # text/icons on primary-colored backgrounds
  on-dark: "#…"          # text/icons on dark surfaces

  hairline: "#…"         # default 1px divider
  hairline-soft: "#…"    # lighter divider for long-scroll separators
  border-strong: "#…"    # heavier stroke: focus outline, disabled button border

  error: "#…"            # inline validation error text
  error-hover: "#…"      # error text on hover
  success: "#…"          # confirmation / positive state
  warning: "#…"          # caution state

  scrim: "#…"            # modal backdrop base hex — opacity applied at render time
```

## Colors prose section

After deriving the tokens, write the prose section into the conversation:

```markdown
## Colors

### Brand & Accent
- **<Primary color name>** (`{colors.primary}` — #<hex>): <where it appears>
- **<Primary Active>** (`{colors.primary-active}` — #<hex>): <press state>
- **<Primary Disabled>** (`{colors.primary-disabled}` — #<hex>): <disabled CTA>
[sub-brand accents if any]

### Surface
- **Canvas** (`{colors.canvas}` — #<hex>): <default background description>
- **Surface Soft** (`{colors.surface-soft}` — #<hex>): <lightest fill — usage>
- **Surface Card** (`{colors.surface-card}` — #<hex>): <card surface>
- **Surface Strong** (`{colors.surface-strong}` — #<hex>): <stronger fill>

### Hairlines & Borders
- **Hairline** (`{colors.hairline}` — #<hex>): <default divider contexts>
- **Hairline Soft** (`{colors.hairline-soft}` — #<hex>): <lighter contexts>
- **Border Strong** (`{colors.border-strong}` — #<hex>): <heavier stroke>

### Text
- **Ink** (`{colors.ink}` — #<hex>): <dominant text usage>
- **Body** (`{colors.body}` — #<hex>): <running text>
- **Muted** (`{colors.muted}` — #<hex>): <secondary labels>
- **Muted Soft** (`{colors.muted-soft}` — #<hex>): <disabled / placeholder>
- **On Primary** (`{colors.on-primary}` — #<hex>): <text on CTAs>
- **On Dark** (`{colors.on-dark}` — #<hex>): <text on dark surfaces>

### Semantic
- **Error** (`{colors.error}` — #<hex>): <validation error contexts>
- **Error Hover** (`{colors.error-hover}` — #<hex>): <hover variant>
- **Success** (`{colors.success}` — #<hex>): <confirmation contexts>
- **Warning** (`{colors.warning}` — #<hex>): <caution contexts>

### Scrim
- **Scrim** (`{colors.scrim}` — #<hex> at 50% opacity): <modal backdrop usage>
```
````

- [ ] **Step 2: Validate frontmatter fields**

```bash
grep -c "^name: s:brand-color-system$" \
  ai_clients/claude/skills/brand-color-system.md
grep -c "^description: Use when" \
  ai_clients/claude/skills/brand-color-system.md
```

Expected: each prints `1`.

- [ ] **Step 3: Commit**

```bash
git add ai_clients/claude/skills/brand-color-system.md
git commit -m "feat(skills): add s:brand-color-system token generator"
```

---

## Task 3: Create `s:brand-type-system`

**Files:**
- Create: `ai_clients/claude/skills/brand-type-system.md`

- [ ] **Step 1: Write the skill file**

Create `ai_clients/claude/skills/brand-type-system.md` with this exact content:

````markdown
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
````

- [ ] **Step 2: Validate frontmatter**

```bash
grep -c "^name: s:brand-type-system$" \
  ai_clients/claude/skills/brand-type-system.md
grep -c "^description: Use when" \
  ai_clients/claude/skills/brand-type-system.md
```

Expected: each prints `1`.

- [ ] **Step 3: Commit**

```bash
git add ai_clients/claude/skills/brand-type-system.md
git commit -m "feat(skills): add s:brand-type-system font roles and scale"
```

---

## Task 4: Create `s:brand-component-system`

**Files:**
- Create: `ai_clients/claude/skills/brand-component-system.md`

- [ ] **Step 1: Write the skill file**

Create `ai_clients/claude/skills/brand-component-system.md` with this exact content:

````markdown
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

Read brand profile, color tokens, and type tokens from conversation context.

## Rules (never violate)

- Component tokens use **only** `{colors.*}` and `{typography.*}` references.
  Never use raw hex values, raw px sizes, or raw font names in this block.
- Every property that can reference a token must reference one.
- `padding`, `height`, and `border-radius` use raw values here (e.g. `14px
  24px`, `48px`) because they are layout values, not color or type tokens.
  Border-radius should reference `{rounded.*}` tokens once the layout skill
  defines them — leave as raw px for now and note in Known Gaps.

## Base component set (all purposes)

Always produce these components:

```yaml
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    typography: "{typography.button-md}"
    padding: "14px 24px"
    height: 48px

  button-primary-active:
    backgroundColor: "{colors.primary-active}"
    textColor: "{colors.on-primary}"

  button-primary-disabled:
    backgroundColor: "{colors.primary-disabled}"
    textColor: "{colors.on-primary}"

  button-secondary:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.button-md}"
    padding: "13px 23px"
    height: 48px

  button-tertiary-text:
    backgroundColor: transparent
    textColor: "{colors.ink}"
    typography: "{typography.button-md}"

  text-input:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.body-md}"
    padding: "14px 12px"
    height: 56px

  text-input-focus:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    borderColor: "{colors.ink}"

  text-input-error:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.error}"
    borderColor: "{colors.error}"
```

## Purpose-specific components

Add the relevant group(s) for the chosen purpose. Use the same token-reference
pattern as the base set above.

**`site` / `web-app`:**
```yaml
  top-nav:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.nav-link}"
    height: 64px

  hero:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.display-xl}"

  card:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.ink}"
    typography: "{typography.body-sm}"

  footer:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.body-sm}"
    padding: "48px 80px"
```

**`dashboard`:**
```yaml
  sidebar:
    backgroundColor: "{colors.surface-soft}"
    textColor: "{colors.ink}"
    typography: "{typography.ui-sm}"

  data-table-row:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.mono-sm}"
    padding: "12px 16px"

  data-table-row-hover:
    backgroundColor: "{colors.surface-soft}"
    textColor: "{colors.ink}"

  badge:
    backgroundColor: "{colors.surface-strong}"
    textColor: "{colors.ink}"
    typography: "{typography.badge}"

  tooltip:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.on-dark}"
    typography: "{typography.caption-sm}"

  chart-legend:
    textColor: "{colors.muted}"
    typography: "{typography.caption-sm}"
```

**`ecommerce`:**
```yaml
  product-card:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.ink}"
    typography: "{typography.body-sm}"

  price-tag:
    textColor: "{colors.ink}"
    typography: "{typography.title-md}"

  price-tag-sale:
    textColor: "{colors.primary}"
    typography: "{typography.title-md}"

  filter-pill:
    backgroundColor: "{colors.surface-strong}"
    textColor: "{colors.ink}"
    typography: "{typography.button-sm}"

  filter-pill-active:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    typography: "{typography.button-sm}"

  cart-item:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.body-sm}"

  checkout-step:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.body-md}"
```

**`app-cellphone`:**
```yaml
  tab-bar:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.muted}"
    typography: "{typography.caption-sm}"
    height: 56px

  tab-bar-active:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.primary}"
    typography: "{typography.caption-sm}"

  list-row:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.body-md}"
    padding: "14px 16px"

  bottom-sheet:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.ink}"
    typography: "{typography.body-md}"

  fab:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    height: 56px

  toast:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.on-dark}"
    typography: "{typography.body-sm}"
```

**`email` / `email-marketing`:**
```yaml
  email-header:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    typography: "{typography.display-md}"
    padding: "32px 40px"

  email-cta-block:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.body-md}"
    padding: "24px 40px"

  email-footer:
    backgroundColor: "{colors.surface-soft}"
    textColor: "{colors.muted}"
    typography: "{typography.caption-sm}"
    padding: "24px 40px"
```

**`blog`:**
```yaml
  article-header:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.display-lg}"

  pull-quote:
    backgroundColor: "{colors.surface-soft}"
    textColor: "{colors.ink}"
    typography: "{typography.display-sm}"
    padding: "24px 32px"

  author-card:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.body-sm}"

  tag-pill:
    backgroundColor: "{colors.surface-strong}"
    textColor: "{colors.ink}"
    typography: "{typography.caption}"
```

**`docs`:**
```yaml
  code-block:
    backgroundColor: "{colors.surface-strong}"
    textColor: "{colors.ink}"
    typography: "{typography.mono-md}"
    padding: "16px 20px"

  callout:
    backgroundColor: "{colors.surface-soft}"
    textColor: "{colors.ink}"
    typography: "{typography.body-sm}"
    padding: "12px 16px"

  sidebar-nav-item:
    backgroundColor: transparent
    textColor: "{colors.muted}"
    typography: "{typography.ui-sm}"

  sidebar-nav-item-active:
    backgroundColor: "{colors.surface-strong}"
    textColor: "{colors.ink}"
    typography: "{typography.ui-sm}"
```

**`print` / `packaging`:**
```yaml
  page-header:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    typography: "{typography.display-lg}"

  section-divider:
    backgroundColor: "{colors.hairline}"

  caption-block:
    backgroundColor: transparent
    textColor: "{colors.muted}"
    typography: "{typography.caption-sm}"
```

For custom purposes: reason about which UI patterns the surface requires
and produce an appropriate component list using the token-reference pattern.

## Components prose section

After deriving the tokens, write the Components prose section into the
conversation. Group components logically (Buttons → Inputs → Navigation →
Cards/Content → Purpose-specific → Footer/Legal). For each component,
describe its visual role and when it appears.

```markdown
## Components

### Buttons
**`button-primary`** — <color name> fill, <on-primary> text, <height>px height.
The primary CTA across the system: <list of usages>.

**`button-primary-active`** — Press state. Background flips to
`{colors.primary-active}`. <Describe any transform or shadow change, or
"No transform, no shadow change.">

**`button-primary-disabled`** — <Describe disabled appearance and cursor>.

**`button-secondary`** — <Describe secondary button role and usage>.

**`button-tertiary-text`** — Plain text, no surface. <Describe usage>.

### Forms
**`text-input`** — <Describe input appearance, focus, error states>.

### [Purpose-specific sections]
<One subsection per component group, matching the tokens above>
```
````

- [ ] **Step 2: Validate frontmatter**

```bash
grep -c "^name: s:brand-component-system$" \
  ai_clients/claude/skills/brand-component-system.md
grep -c "^description: Use when" \
  ai_clients/claude/skills/brand-component-system.md
```

Expected: each prints `1`.

- [ ] **Step 3: Commit**

```bash
git add ai_clients/claude/skills/brand-component-system.md
git commit -m "feat(skills): add s:brand-component-system token generator"
```

---

## Task 5: Create `s:brand-layout-system`

**Files:**
- Create: `ai_clients/claude/skills/brand-layout-system.md`

- [ ] **Step 1: Write the skill file**

Create `ai_clients/claude/skills/brand-layout-system.md` with this exact content:

````markdown
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

Read brand profile and all tokens produced so far from conversation context.

## Spacing scale

Choose a base unit (4px for tight/dense UIs, 8px for standard, 12px for
airy/editorial). Named steps must be multiples of the base unit.

```yaml
spacing:
  xxs: 2px     # micro gaps — icon padding, tight inline spacing
  xs: 4px      # tight spacing — badge padding, dense row gutters
  sm: 8px      # small gaps — between label and input, icon + text
  md: 12px     # medium gaps — internal card padding, list item gaps
  base: 16px   # base unit — default horizontal padding, grid gutters
  lg: 24px     # large gaps — section sub-headings, card internal padding
  xl: 32px     # extra large — between card groups, button group spacing
  xxl: 48px    # double extra — footer column gutters, modal padding
  section: 64px # section breaks — major page band vertical padding
```

Adjust for purpose:
- Print: use `pt` not `px`; map roughly 1px ≈ 0.75pt
- Email: constrain to multiples of 8px; table-based layouts need round
  numbers for reliable rendering across clients
- Mobile: add `safe-area-top` and `safe-area-bottom` tokens (use
  `env(safe-area-inset-*)` values with `16px` fallback)
- TV (10-ft UI): multiply all tokens by ~3× for legibility at distance

## Border-radius tokens

Shape language (sharp vs. soft vs. pill) must match the brand adjectives
from the brand profile. A "clinical" or "precise" brand uses small radii
(0–4px); a "friendly" or "human" brand uses larger radii (8–16px) and pills.

```yaml
rounded:
  none: 0px
  xs: 2px    # micro — table cell corners, tight chips
  sm: 4px    # small — inputs, standard buttons
  md: 8px    # medium — cards, modals, dropdowns
  lg: 16px   # large — featured cards, image containers
  xl: 24px   # extra large — pill buttons, search bars
  full: 9999px # pill / circle
```

## Grid & container

Adapt to purpose:

**Web (`site`, `web-app`, `dashboard`, `ecommerce`, `blog`, `docs`):**
```yaml
grid:
  max-content-width: 1280px
  columns: 12
  gutter: "{spacing.base}"    # 16px
  margin: "{spacing.lg}"      # 24px on tablet, 80px on desktop
```

**Mobile (`app-cellphone`):**
```yaml
grid:
  columns: 4
  gutter: "{spacing.base}"
  margin: "{spacing.base}"
  safe-area-top: "env(safe-area-inset-top, 16px)"
  safe-area-bottom: "env(safe-area-inset-bottom, 16px)"
```

**Tablet (`app-tablet`):**
```yaml
grid:
  columns: 8
  gutter: "{spacing.base}"
  margin: "{spacing.lg}"
```

**Email:**
```yaml
grid:
  max-width: 600px         # fixed — email clients ignore responsive grids
  columns: 1               # stack layout; 2-col only inside table cells
  padding: "{spacing.xxl}" # 48px left/right inner padding
```

**Print / packaging:**
```yaml
grid:
  page: "A4"           # or Letter, custom die-cut size
  margins: "20mm"
  columns: 12
  gutter: "5mm"
  bleed: "3mm"
```

## Responsive breakpoints

**Web:**
```yaml
breakpoints:
  xs: "< 480px"         # small phones, narrow viewports
  sm: "480px – 768px"   # large phones, small tablets
  md: "768px – 1024px"  # tablets, small laptops
  lg: "1024px – 1280px" # standard desktop
  xl: "> 1280px"        # wide desktop (content caps at max-width)
```

**Mobile:** not breakpoints — define device-size tiers instead:
```yaml
device-tiers:
  compact: "375px"    # iPhone SE, small Android
  standard: "390px"   # iPhone 15
  large: "428px"      # iPhone Plus / Pro Max, large Android
  orientation: "handle both portrait and landscape — test at 667px × 375px"
```

**Email:** single breakpoint — below 480px, stack columns to 1:
```yaml
breakpoints:
  mobile: "< 480px"
```

**TV:** base at 1080p, scale for 4K:
```yaml
breakpoints:
  hd: "1920 × 1080"    # baseline design target
  uhd: "3840 × 2160"   # scale all tokens ×2 for 4K
```

**Print / packaging:** no breakpoints — define page sizes as variants.

## Elevation

Define shadow tiers. A minimal brand uses one or zero shadow tiers; a rich
brand may use three. Derive from brand adjectives (flat = minimal, depth =
richer). Most brands need at most:

```yaml
elevation:
  flat: "none"          # 95% of surfaces — body, hero, editorial bands
  raised: >             # card hover, dropdown menus, search bar at rest
    "rgba(0,0,0,0.02) 0 0 0 1px,
     rgba(0,0,0,0.04) 0 2px 6px 0,
     rgba(0,0,0,0.10) 0 4px 8px 0"
  overlay: >            # modal dialogs, drawers, popovers (above raised)
    "rgba(0,0,0,0.08) 0 8px 24px 0,
     rgba(0,0,0,0.12) 0 16px 32px 0"
```

For flat/minimal brands, consider:
```yaml
elevation:
  flat: "none"
  raised: "0 1px 3px rgba(0,0,0,0.08), 0 1px 2px rgba(0,0,0,0.04)"
```

## Output

Write the following into the conversation:
1. `spacing` and `rounded` YAML token blocks
2. Grid/container spec as YAML comments
3. **Layout prose section**
4. **Elevation prose section**
5. **Responsive Behavior prose section**

### Layout prose template

```markdown
## Layout

### Spacing System
- **Base unit:** <Xpx>
- **Tokens:** `{spacing.xxs}` Xpx · `{spacing.xs}` Xpx · `{spacing.sm}` Xpx
  · `{spacing.md}` Xpx · `{spacing.base}` Xpx · `{spacing.lg}` Xpx
  · `{spacing.xl}` Xpx · `{spacing.xxl}` Xpx · `{spacing.section}` Xpx
- **Section padding (vertical):** `{spacing.section}` (Xpx) — <rationale>
- **Card internal padding:** <tokens and values>
- **Gutters:** <how gutters are applied>

### Grid & Container
<Describe max-width, columns, gutter, margin per the purpose-specific values above>

### Whitespace Philosophy
<2–3 sentences on how the brand balances density and breathing room>

## Elevation

<Describe the shadow tiers and where each applies. For a single-tier system:
"The system has one shadow tier plus the flat baseline. Flat is the default
for 95% of surfaces. The raised tier applies to <list> on hover/focus.
The modal scrim (`{colors.scrim}` at 50% opacity) is the global backdrop.">

## Responsive Behavior

| Name | Width | Key Changes |
|------|-------|-------------|
| Mobile | < Xpx | <nav collapse, card stacking, search bar behaviour, etc.> |
| Tablet | X–Xpx | <partial nav, card count change, etc.> |
| Desktop | X–Xpx | <full nav, max card count, reservation rail, etc.> |
| Wide | > Xpx | <content width cap, gutter absorption> |

### Touch Targets
<Only for app-cellphone, app-tablet, app-watch purposes>
- Primary CTAs: minimum 48×48px
- <List key interactive elements and their actual sizes>

### Collapsing Strategy
<Describe how navigation, search, grids, and key components collapse
across breakpoints>
```
````

- [ ] **Step 2: Validate frontmatter**

```bash
grep -c "^name: s:brand-layout-system$" \
  ai_clients/claude/skills/brand-layout-system.md
grep -c "^description: Use when" \
  ai_clients/claude/skills/brand-layout-system.md
```

Expected: each prints `1`.

- [ ] **Step 3: Commit**

```bash
git add ai_clients/claude/skills/brand-layout-system.md
git commit -m "feat(skills): add s:brand-layout-system spacing and grid"
```

---

## Task 6: Create `s:brand-write-design-md`

**Files:**
- Create: `ai_clients/claude/skills/brand-write-design-md.md`

- [ ] **Step 1: Write the skill file**

Create `ai_clients/claude/skills/brand-write-design-md.md` with this exact content:

````markdown
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
````

- [ ] **Step 2: Validate frontmatter**

```bash
grep -c "^name: s:brand-write-design-md$" \
  ai_clients/claude/skills/brand-write-design-md.md
grep -c "^description: Use when" \
  ai_clients/claude/skills/brand-write-design-md.md
grep -c "^allowed-tools: Read Write Bash$" \
  ai_clients/claude/skills/brand-write-design-md.md
```

Expected: each prints `1`.

- [ ] **Step 3: Commit**

```bash
git add ai_clients/claude/skills/brand-write-design-md.md
git commit -m "feat(skills): add s:brand-write-design-md file assembler"
```

---

## Task 7: Create `a:brand-design`

**Files:**
- Create: `ai_clients/claude/agents/brand-design.md`

- [ ] **Step 1: Verify agents directory exists**

```bash
ls ai_clients/claude/agents/
```

Expected: shows existing `py-*.md` agent files.

- [ ] **Step 2: Write the agent file**

Create `ai_clients/claude/agents/brand-design.md` with this exact content:

````markdown
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
````

- [ ] **Step 3: Validate frontmatter fields**

```bash
grep -c "^name: a:brand-design$" \
  ai_clients/claude/agents/brand-design.md
grep -c "^model: sonnet$" \
  ai_clients/claude/agents/brand-design.md
grep -c "^color: purple$" \
  ai_clients/claude/agents/brand-design.md
grep -c "^memory: true$" \
  ai_clients/claude/agents/brand-design.md
grep -c "^disable-model-invocation: true$" \
  ai_clients/claude/agents/brand-design.md
```

Expected: each prints `1`.

- [ ] **Step 4: Commit**

```bash
git add ai_clients/claude/agents/brand-design.md
git commit -m "feat(agents): add a:brand-design orchestrator"
```

---

## Task 8: Install and Smoke Test

**Files:** none created — install verification only.

- [ ] **Step 1: Install skills**

```bash
./ai_clients/claude/main.sh skills
```

Expected output: lines showing each `brand-*.md` file copied to
`~/.claude/skills/`. No errors.

- [ ] **Step 2: Verify skills installed**

```bash
ls ~/.claude/skills/brand-*.md
```

Expected:
```
/home/<user>/.claude/skills/brand-color-system.md
/home/<user>/.claude/skills/brand-component-system.md
/home/<user>/.claude/skills/brand-interview.md
/home/<user>/.claude/skills/brand-layout-system.md
/home/<user>/.claude/skills/brand-type-system.md
/home/<user>/.claude/skills/brand-write-design-md.md
```

- [ ] **Step 3: Install agent**

```bash
./ai_clients/claude/main.sh agents
```

Expected: `brand-design.md` copied to `~/.claude/agents/`. No errors.

- [ ] **Step 4: Verify agent installed**

```bash
ls ~/.claude/agents/brand-design.md
```

Expected: file exists with non-zero size.

- [ ] **Step 5: Verify skill description constraint**

All skill `description` fields must start with "Use when" (Claude reads
these to decide whether to load the skill):

```bash
for f in ai_clients/claude/skills/brand-*.md; do
  echo -n "$f: "
  awk '/^description:/{found=1} found && /Use when/{print "OK"; exit} found && /^[a-z]/{print "FAIL - missing Use when"; exit}' "$f"
done
```

Expected: all lines print `OK`.

- [ ] **Step 6: Final commit**

```bash
git add .
git commit -m "feat(ai_clients): install brand-design agent and skills"
```

---

## Self-Review Checklist

- [x] **Spec coverage:** brand profile output format (Task 1) ✓, full color
  token set with WCAG rule (Task 2) ✓, font roles + fallback stacks + scale
  (Task 3) ✓, base + purpose-specific components (Task 4) ✓, spacing +
  radius + grid + elevation + responsive (Task 5) ✓, assembly order +
  gitignore (Task 6) ✓, pipeline + 6 checkpoints + final summary (Task 7) ✓,
  installation (Task 8) ✓.
- [x] **No placeholders:** all task steps contain complete file content or
  exact commands.
- [x] **Type consistency:** token reference syntax `{colors.*}`,
  `{typography.*}`, `{spacing.*}`, `{rounded.*}` used consistently across
  Tasks 2–7.
- [x] **Elevation ownership:** assigned to `s:brand-layout-system` (Task 5)
  and assembled by `s:brand-write-design-md` (Task 6). ✓
- [x] **WebFetch scope:** only `s:brand-interview` has `allowed-tools: WebFetch`.
  Color/type/component/layout skills use `Read` only. ✓
- [x] **Context passing:** all skills receive inputs through conversation
  context. No file-path argument passing between skills. ✓
