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
