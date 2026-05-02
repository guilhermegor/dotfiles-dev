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
