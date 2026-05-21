---
name: s:design-token-export
description: Use when emitting machine-readable token artifacts from an
  awesome-design-md frontmatter token block. Asks the user which JSON shape(s)
  and CSS naming convention to emit, then renders deterministically. Receives
  the full token block (colors, typography, rounded, spacing, motion) and an
  output directory from conversation context.
effort: medium
argument-hint: [brand-name] [purpose] [out-dir]
allowed-tools: Read Write Bash
---

Render the approved frontmatter token block into machine-readable artifacts.
The markdown frontmatter is the **single source of truth** — exports are pure
derivations, never hand-authored, never the place to introduce new tokens.

## Step 1 — Ask runtime preferences

Ask the user, **one menu at a time**, in this order:

### Menu A — JSON shape(s)

```
Which token JSON format(s) should I emit? (choose one or more)

  1. W3C Design Tokens (DTCG) — $value/$type schema, Figma/Style-Dictionary
     interop. Recommended for portability.
  2. Flat namespaced JSON   — { "color.primary": "#…" }; simplest to consume
     by hand; loses $type metadata.
  3. Style Dictionary source — nested { value, type } (no $-prefix); pick if
     Style Dictionary is the build tool.
  4. Skip JSON.

Reply with the number(s), e.g. "1" or "1,3".
```

Record selections. If the user picks 4, skip the JSON emission step entirely.

### Menu B — CSS naming convention

```
Which CSS custom-property naming should I emit?

  1. Dot-flattened — :root { --color-primary; --spacing-base; }
     Drops the container plural. Conventional and Tailwind-compatible.
  2. Path-preserved — :root { --colors-primary; --spacing-base; }
     Keeps the frontmatter container name. 1:1 mapping back to JSON.
  3. Tailwind v4 @theme — @theme { --color-*; --font-*; --spacing-*; }
     Drop-in for any Tailwind v4 project. Opinionated naming.
  4. Skip CSS.

Reply with a single number.
```

## Step 2 — Resolve token references

Before rendering, **flatten all `{path.to.token}` references** to their
literal values. The frontmatter uses references like
`"{colors.primary}"` inside component tokens; downstream consumers need the
literal hex. Reference-flattening rules:

- `{colors.X}`  → look up `colors.X` in the frontmatter and substitute.
- `{typography.X}` → if `X` is a leaf (`families.body`), substitute the
  string; if `X` is a scale token (`body-md`), expand to the object's
  resolved values.
- `{spacing.X}` / `{rounded.X}` / `{motion.X}` → literal value substitution.
- Unresolvable reference → leave as-is and add a Known Gaps entry naming the
  broken path.

## Step 3 — Render JSON (per selection)

### 3a. W3C DTCG (`tokens.dtcg.json`)

Group tokens by category. Use `$value` and `$type`. Type vocabulary:
`color`, `dimension`, `fontFamily`, `fontWeight`, `duration`, `cubicBezier`,
`typography` (composite), `shadow` (composite).

```json
{
  "color": {
    "primary":      { "$value": "#1F6FEB", "$type": "color" },
    "surface-card": { "$value": "#FFFFFF", "$type": "color" }
  },
  "spacing": {
    "base": { "$value": "16px", "$type": "dimension" }
  },
  "radius": {
    "md": { "$value": "8px", "$type": "dimension" }
  },
  "font-family": {
    "body": { "$value": ["Inter", "-apple-system", "sans-serif"], "$type": "fontFamily" }
  },
  "typography": {
    "body-md": {
      "$value": {
        "fontFamily": "{font-family.body}",
        "fontSize":   "16px",
        "fontWeight": 400,
        "lineHeight": 1.5,
        "letterSpacing": "0"
      },
      "$type": "typography"
    }
  },
  "duration": {
    "base": { "$value": "250ms", "$type": "duration" }
  },
  "easing": {
    "standard": { "$value": [0.4, 0, 0.2, 1], "$type": "cubicBezier" }
  }
}
```

Container rename: `colors`→`color`, `rounded`→`radius`, `motion.duration`→
`duration`, `motion.easing`→`easing`. The DTCG ecosystem uses singular names.

### 3b. Flat namespaced (`tokens.flat.json`)

Single-level object, dot-joined keys, literal string values. No metadata.

```json
{
  "color.primary": "#1F6FEB",
  "color.surface-card": "#FFFFFF",
  "spacing.base": "16px",
  "radius.md": "8px",
  "typography.body-md.fontSize": "16px",
  "typography.body-md.fontWeight": "400",
  "duration.base": "250ms",
  "easing.standard": "cubic-bezier(0.4, 0, 0.2, 1)"
}
```

For composite tokens (typography scale), flatten each property to its own
key (`typography.body-md.fontSize`, `…fontWeight`, `…lineHeight`,
`…letterSpacing`).

### 3c. Style Dictionary (`tokens.style-dictionary.json`)

Same nesting as DTCG but uses `value`/`type` (no `$`):

```json
{
  "color": {
    "primary": { "value": "#1F6FEB", "type": "color" }
  }
}
```

## Step 4 — Render CSS (per selection)

### 4a. Dot-flattened (`theme.css`)

Drop the container plural (`colors`→`color`, `rounded`→`radius`). Keep
hyphenation; substitute `.` with `-`.

```css
:root {
  --color-primary: #1F6FEB;
  --color-surface-card: #FFFFFF;
  --spacing-base: 16px;
  --radius-md: 8px;
  --duration-base: 250ms;
  --easing-standard: cubic-bezier(0.4, 0, 0.2, 1);
  --font-family-body: "Inter", -apple-system, sans-serif;
  --text-body-md-size: 16px;
  --text-body-md-weight: 400;
  --text-body-md-line-height: 1.5;
}
```

### 4b. Path-preserved (`theme.css`)

Keep container names verbatim. 1:1 mapping back to frontmatter paths.

```css
:root {
  --colors-primary: #1F6FEB;
  --colors-surface-card: #FFFFFF;
  --spacing-base: 16px;
  --rounded-md: 8px;
  --motion-duration-base: 250ms;
  --motion-easing-standard: cubic-bezier(0.4, 0, 0.2, 1);
  --typography-families-body: "Inter", -apple-system, sans-serif;
  --typography-body-md-font-size: 16px;
}
```

### 4c. Tailwind v4 @theme (`theme.css`)

Use Tailwind v4's `@theme` block with its naming convention:
`--color-*`, `--spacing-*`, `--radius-*`, `--font-*`, `--text-*`,
`--shadow-*`, `--ease-*`. Typography scale tokens emit as `--text-<name>`
with paired `--text-<name>--line-height` and `--text-<name>--font-weight`.

```css
@import "tailwindcss";

@theme {
  --color-primary: #1F6FEB;
  --color-surface-card: #FFFFFF;
  --spacing-base: 16px;
  --radius-md: 8px;
  --font-body: "Inter", -apple-system, sans-serif;
  --text-body-md: 16px;
  --text-body-md--line-height: 1.5;
  --text-body-md--font-weight: 400;
  --ease-standard: cubic-bezier(0.4, 0, 0.2, 1);
  --duration-base: 250ms;
}
```

## Step 5 — Write files

The calling agent passes `out-dir` (e.g. `design/language/` or
`design/system/`). For each selected format:

1. Ensure `out-dir` exists (`mkdir -p "$OUT_DIR"`).
2. Write the rendered file to:
   - JSON shapes: `tokens.dtcg.json`, `tokens.flat.json`,
     `tokens.style-dictionary.json` (only those selected).
   - CSS: `theme.css` (single file — the user picked one CSS shape).
3. Confirm each file with `ls -lh`.

## Step 6 — Summary

Write a short emission summary to the conversation:

```
## Token Export

Wrote:
  ✓ <out-dir>/tokens.dtcg.json           — <n> tokens
  ✓ <out-dir>/theme.css                  — <n> custom properties

Source: <path>/<purpose>.md frontmatter (canonical)
JSON shape(s): <selected>
CSS convention: <selected>
Unresolved references: <count> (see Known Gaps)
```

## Do Not

- Do not introduce new tokens here. If a value is missing, surface it as a
  Known Gaps entry and continue.
- Do not write Tailwind config files, Style Dictionary build scripts, or
  any non-token artifact. This skill emits source tokens only.
- Do not edit the source markdown frontmatter — it is canonical.
