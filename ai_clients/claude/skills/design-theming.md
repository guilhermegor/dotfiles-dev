---
name: s:design-theming
description: Use when generating theming variants (light/dark, density) over
  the base design-language tokens. Receives all foundation tokens from
  conversation context. Produces theme alias layers (not duplicate token
  blocks) and the Theming prose section.
effort: medium
argument-hint: [brand-name] [purpose]
allowed-tools: Read
---

Read foundation tokens (`colors`, `typography`, `spacing`) from conversation
context. Produce **alias layers** for light/dark and density variants — not
duplicate token sets.

## Rules (never violate)

- Themes are **alias layers over the base tokens**, not parallel full token
  blocks. A theme defines only the colors/spacing that *change* per mode.
- The base color tokens already produced by `s:design-color-system` are the
  **default theme** (typically light). Dark / high-contrast / dense are
  modeled as alias layers.
- A theme alias resolves to an existing token reference (`{colors.X}`) or a
  raw hex. Never invent token names that have no base counterpart.
- Always include a fallback rule: if a theme omits an alias, the consumer
  falls back to the base token.

## Step 1 — Ask which themes to produce

```
Which themes should I generate? (multi-select)

  1. Dark mode      — inverted surfaces, adjusted ink, dimmed primary
  2. High contrast  — WCAG AAA pairs, no muted intermediate tones
  3. Compact density — tighter spacing scale for data-dense surfaces
  4. None — base tokens only

Reply with number(s).
```

If the user picks 4, write a single Theming prose paragraph noting "no
theme variants in scope" and stop.

## Step 2 — Dark mode alias layer (if selected)

A professional dark mode is **not** an inversion of the base palette. Rules:

- Canvas in dark mode is not pure black (#000) — use a very dark neutral
  (typically `#0A0A0A`–`#121212`) to preserve elevation perception.
- Primary may need adjusting (saturate-down by ~10%) to avoid glare on
  dark surfaces.
- Ink and body get *brighter*, not just inverted — pure white (#FFF) on
  dark causes halation. Use off-white (`#F5F5F5`–`#FAFAFA`).
- Hairlines lighten substantially; surface-soft/strong shift relative
  to canvas.
- Re-verify ink-on-canvas contrast (AA ≥ 4.5:1) — flag any failure.

```yaml
themes:
  dark:
    colors:
      canvas:         "#0F0F12"
      surface-soft:   "#17171C"
      surface-card:   "#1C1C22"
      surface-strong: "#26262E"
      ink:            "#F5F5F5"
      body:           "#D0D0D0"
      muted:          "#8A8A8A"
      muted-soft:     "#5A5A5A"
      hairline:       "#2A2A2F"
      hairline-soft:  "#1F1F24"
      border-strong:  "#3A3A42"
      primary:        "#…"      # only if base primary fails contrast on dark canvas
      on-primary:     "#…"      # only if base fails on adjusted primary
      scrim:          "#000000" # opacity at render time
    # all unlisted tokens fall back to base
    elevation:
      flat: "none"
      raised: >
        "rgba(0,0,0,0.5) 0 1px 3px 0,
         rgba(0,0,0,0.3) 0 1px 2px 0"
      # shadows in dark mode are heavier and more diffuse
```

## Step 3 — High-contrast alias layer (if selected)

Tighten every contrast pair to AAA (≥ 7:1 for normal text, ≥ 4.5:1 for
non-text). Drop intermediate muted tones — high-contrast users need
binary state (text vs. not-text).

```yaml
themes:
  high-contrast:
    colors:
      ink:           "#000000"
      body:          "#000000"   # collapse body into ink — no soft tier
      muted:         "#3A3A3A"   # raised from base muted
      muted-soft:    "#3A3A3A"   # collapse
      canvas:        "#FFFFFF"
      surface-soft:  "#FFFFFF"   # collapse
      surface-card:  "#FFFFFF"   # collapse — borders carry separation
      hairline:      "#000000"
      border-strong: "#000000"
      primary:       "#0040A0"   # darken to meet AAA on canvas
      on-primary:    "#FFFFFF"
      focus-outline-width: "3px" # also widen focus rings
```

## Step 4 — Compact density alias layer (if selected)

Scale spacing by ~0.75× for data-dense surfaces. Type sizes are
unchanged; only spacing and component heights shrink.

```yaml
themes:
  compact:
    spacing:
      xxs: 2px
      xs:  3px      # was 4
      sm:  6px      # was 8
      md:  10px     # was 12
      base: 12px    # was 16
      lg:  18px     # was 24
      xl:  24px     # was 32
      xxl: 36px     # was 48
      section: 48px # was 64
    components:
      button-primary:
        height: 36px   # was 48
        padding: "8px 16px"
      text-input:
        height: 40px   # was 56
        padding: "10px 10px"
      data-table-row:
        padding: "6px 12px"
```

Density variants must **preserve touch-target floors** on touch surfaces.
If `compact` density is requested for `app-cellphone` etc., add a Known
Gaps entry noting that compact + touch is generally discouraged.

## Step 5 — Theming prose

Write into the conversation:

```markdown
## Theming

### Variants generated
- **Default** — base tokens, light mode.
- **Dark** — alias layer over base. <Sentence on the philosophy: e.g.
  "Canvas tones lift from #0F0F12 to surface-strong to preserve depth;
  primary saturates down 8% to avoid glare on dark.">
- **High contrast** — AAA throughout. Muted tier collapses into ink; borders
  carry separation instead of subtle surface tones.
- **Compact** — spacing scaled 0.75×; type unchanged. <Note any
  touch-floor exceptions.>

### Mode switching

Themes are alias layers — at runtime, swap the active theme's token map
in front of the base. Unspecified aliases fall through to base.

CSS implementation (when emitted by `s:design-token-export` with the
Tailwind v4 shape):
```css
@theme {
  /* base tokens */
  --color-canvas: #FAFAFA;
  --color-ink: #1A1A1A;
}

@media (prefers-color-scheme: dark) {
  @theme {
    --color-canvas: #0F0F12;
    --color-ink: #F5F5F5;
  }
}
```

### Fallback rule
Any token a theme does not alias inherits its base value. A theme cannot
introduce a token that does not exist in the base — only override.

### Contrast verification per theme
| Theme         | Worst-case text pair | Ratio  | AA  |
|---------------|----------------------|--------|-----|
| Default       | <pair>               | X:1    | ✓/✗ |
| Dark          | <pair>               | X:1    | ✓/✗ |
| High contrast | <pair>               | X:1    | ✓   |

(Re-run `s:design-accessibility-audit` per theme if any pair fails.)
```
