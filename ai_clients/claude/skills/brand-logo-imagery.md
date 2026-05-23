---
name: s:brand-logo-imagery
description: Use when generating the visual-asset chapter of a brand book —
  logo usage rules (clear space, sizing, misuse), photography/illustration
  direction, and iconography style. Receives brand profile and brand
  identity from conversation context. Pure specification — does not assume
  asset files exist on disk.
effort: medium
argument-hint: [brand-name]
allowed-tools: Read
---

Read brand profile and identity (from `s:brand-identity`) from conversation
context. Produce the visual-asset rules a designer or developer needs to
*apply* the brand without re-deriving it — logo rules, imagery direction,
iconography.

## Rules (never violate)

- **No file-path assumptions.** Do not reference logo files or asset paths.
  This skill produces specification only; the user supplies actual artwork
  separately. Where a file would be useful, name what to *create*, not what
  exists.
- Visual direction must trace back to the brand profile and identity. A
  "warm, human" brand cannot prescribe austere black-and-white photography
  without a stated reason.
- One question at a time if a dimension cannot be derived. Common gaps:
  whether the brand has a logo yet, photography rights/budget, icon library
  preference.

## Step 1 — Logo direction

If the brand already has a logo (the brand profile may state this), document
its rules. If not, document the **brief** — what the future logo should
embody.

### If logo exists

```
## Logo

### Construction
<Describe the mark: type-only wordmark, monogram, combination, abstract symbol,
pictorial. Name what is uniquely brand-specific (slant, ligature, counter
shape, etc.).>

### Clear space
Minimum padding around the logo equals <X> on all sides, where X = <half the
cap-height / the height of the lowercase 'o' / a specific unit>. No content
may enter this zone.

### Minimum size
- Digital: <X>px width (legibility floor)
- Print:   <X>mm width
- Favicon / app icon: <X>×<X>px — use the <monogram / symbol-only> variant

### Variants
- Primary:    <full lockup on canvas>
- Reverse:    <lockup on dark / on-primary>
- Mono:       <single-color usage>
- Symbol:     <mark only — for tight spaces>

### Misuse (do not)
- Do not stretch, skew, or rotate.
- Do not recolor outside the approved palette ({colors.primary},
  {colors.ink}, {colors.canvas} reverse).
- Do not place on photography without a scrim ({colors.scrim} at ≥ 40%).
- Do not add drop shadows, outlines, or effects.
- [add 2–3 brand-specific misuses that are likely to come up]
```

### If logo does not exist (greenfield)

```
## Logo brief

A future logo for this brand should:
- Embody <2–3 adjectives from personality>
- Sit at <register on a continuum: monogram / wordmark / symbol + wordmark>
- Avoid <1–2 anti-patterns the brand profile rules out — e.g. "no generic
  tech swooshes" or "no overly literal industry icons">
- Read clearly at favicon size (16×16px) — bias toward simple silhouettes
  over detail
```

## Step 2 — Photography & illustration direction

Pick **one primary** track (photography OR illustration as the dominant
imagery mode) plus rules for when the other appears.

```
## Imagery

### Primary track: <Photography | Illustration | Hybrid>

### Subject matter
<What the brand photographs/illustrates: people in context, products in
isolation, environments, abstract textures. Tie back to brand mission and
audience.>

### Treatment
- Lighting: <natural / studio / dramatic / flat>
- Color cast: <neutral / warm / cool — and how it relates to {colors.primary}>
- Composition: <close-up vs environmental, negative space, focal hierarchy>
- People: <how people appear: posed / candid, representation goals,
  do-not-do rules>
- Post-processing: <grading, grain, contrast — and the technical limits>

### Illustration style (if used)
- Line: <weight, geometry vs hand-drawn>
- Color: <restricted to palette / extended>
- Perspective: <flat / isometric / dimensional>
- Texture: <flat vector / gradient / grain>

### Do not
- [3–4 brand-specific avoidances, e.g. "no stock-photo handshakes",
  "no abstract gradient meshes", "no AI-generated faces"]
```

## Step 3 — Iconography

```
## Iconography

### Library / source
<Recommend an open-source icon set that matches the shape language
(rounded → Lucide / Heroicons-rounded; sharp → Phosphor regular / Tabler;
duotone → Phosphor duotone). If the brand uses a custom set, describe the
construction rules.>

### Grid & stroke
- Grid: <16×16 / 24×24 base — choose what matches the type scale>
- Stroke width: <1.5px / 2px — should feel consistent with body type weight>
- Corner treatment: <sharp / 1–2px rounded / fully rounded — matches the
  rounded.sm radius token>

### Color usage
- Default: {colors.ink} or {colors.muted}
- Active / selected: {colors.primary}
- On dark surfaces: {colors.on-dark}
- Semantic icons (error, success, warning) inherit the matching colour
  token, never the brand primary.

### Sizing
- Inline with body text: 16×16 (cap-height aligned)
- UI controls (buttons, inputs): 20×20
- Navigation / feature: 24×24
- Hero / illustration accent: 48+
```

## Output

Write the assembled visual-asset block — logo direction, imagery, iconography
— into the conversation, ready for the calling agent's checkpoint.

## Do Not

- Do not invent assets. Do not write `![logo](path/to/logo.png)` or any
  image embed unless the user explicitly provided the path.
- Do not produce token blocks. Reference identity-palette role names
  (`primary`, `ink`, `on-dark`) in prose; the calling agent's brand-write-book
  skill resolves these to identity hex values.
- Do not duplicate the design-language layout/spacing decisions. If the
  brand book needs grid rules, note "see design language tier" rather than
  re-deriving.
