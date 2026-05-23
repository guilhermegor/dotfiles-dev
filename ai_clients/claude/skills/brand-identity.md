---
name: s:brand-identity
description: Use when generating the identity layer of a brand book — mission,
  positioning, personality, voice & tone, identity palette (5 colors), and
  chosen typefaces (1–3). Receives the brand profile from conversation
  context. Light-touch derivations only; the full token scale belongs to the
  design-language tier.
effort: high
argument-hint: [brand-name]
allowed-tools: Read
---

Read the brand profile from conversation context. Derive the brand's identity
layer — the parts of a brand book that are *about who the brand is*, not
*about how to build with it*. This is prose-first; tokens are kept minimal.

## Rules (never violate)

- This skill stops at **identity-level** decisions: 5 named colors, 1–3
  typefaces, voice register. It does **not** produce the full token scale —
  that is the design-language tier's job (`s:design-color-system`,
  `s:design-type-system`).
- Voice & tone is **brand-specific**, not generic. Every adjective must trace
  back to a line in the brand profile (look & feel, emotional tone, audience,
  problem solved).
- Ask **one question at a time** if any identity dimension cannot be derived
  from the brand profile alone. Do not invent a mission or voice the user
  has not signalled.

## Step 1 — Mission & positioning

Derive from `Identity` and `Visual Direction` in the brand profile.

```
## Mission
<One sentence — what does this brand do for whom, and why does it matter?
Avoid corporate boilerplate. Should be specific enough that a competitor
could not adopt it verbatim.>

## Positioning statement
For <target audience> who <key need>, <brand> is the <category> that
<key differentiation>. Unlike <competitor archetype>, we <unique approach>.
```

If the brand profile lacks competitive positioning detail, ask one focused
question: "How do you want users to describe this brand vs. the closest
alternative?"

## Step 2 — Personality

A short, durable description of how the brand behaves. Four to six adjectives
maximum, each with a one-line gloss anchoring it to a behaviour, not a feeling.

```
## Personality
- **<Adjective>** — <behaviour: "we explain before we sell">
- **<Adjective>** — <behaviour: "we name the trade-off, not just the win">
- …
```

Personality adjectives are **chosen from**, not the same as, the brand
profile's look-and-feel adjectives. Look-and-feel describes the surface;
personality describes the conduct.

## Step 3 — Voice & tone

Two parts:

### 3a. Voice spectrum

Position the brand on three axes. Use the brand profile's "authoritative vs
approachable" answer plus competitive position as the anchor.

```
## Voice
                Formal  ─────●────  Casual
              Serious  ──●───────   Playful
              Minimal  ────●─────   Rich / expressive
            Technical  ─────●────   Plain-language
```

### 3b. Do / Don't pairs

Three to four contrasts. Each pair is a *real phrase the brand might
write*, not abstract guidance.

```
## Tone in practice

| ✓ We say                                  | ✗ We don't say                         |
|-------------------------------------------|-----------------------------------------|
| "Your payment didn't go through. Try…"    | "Oops! Something went wrong 😅"          |
| "Built for teams that need both."         | "The ultimate solution for everyone."   |
| "Cancel any time — no questions."         | "Subject to our terms and conditions."  |
[3–4 rows]
```

## Step 4 — Identity palette (5 colors)

A **curated** palette — not the design-token scale. Five colors with
brand-level names plus the system role each one maps to. This block is the
seed the design-language tier consumes when deriving the full scale.

```yaml
identity-palette:
  primary:
    hex: "#…"
    name: "<brand name for this color — e.g. 'Signal Blue'>"
    role: "primary"           # maps to {colors.primary} downstream
    rationale: "<why this hex — adjective trace>"
  secondary:
    hex: "#…"
    name: "<brand name>"
    role: "accent" | "supporting"
    rationale: "…"
  ink:
    hex: "#…"
    name: "<brand name — 'Obsidian', 'Graphite', etc.>"
    role: "ink"
    rationale: "…"
  canvas:
    hex: "#…"
    name: "<brand name — 'Bone', 'Vellum', etc.>"
    role: "canvas"
    rationale: "…"
  semantic-critical:
    hex: "#…"
    name: "<brand name>"
    role: "error"
    rationale: "…"
```

Verify ink-on-canvas contrast (≥ 4.5:1 WCAG AA). If failing, note it in
the brand book's Known Gaps — but do **not** auto-correct here; the
design-language tier owns full WCAG verification.

## Step 5 — Typefaces (1–3)

Pick one to three typefaces with brand-level rationale. Do not produce
fallback stacks or a type scale — those belong to `s:design-type-system`.

```yaml
typefaces:
  - role: "display"               # display | body | accent
    primary: "<font name>"
    classification: "<serif | sans | display | mono | script>"
    rationale: "<why this face — adjective trace + cultural signal>"
    license: "<open-source / commercial / system>"
  - role: "body"
    primary: "<font name>"
    classification: "<…>"
    rationale: "<…>"
    license: "<…>"
  # optional third for accent / mono
```

## Output

Write the assembled identity block — mission, positioning, personality,
voice (spectrum + do/don't), identity palette, typefaces — into the
conversation as a single block, ready for the calling agent's checkpoint.
