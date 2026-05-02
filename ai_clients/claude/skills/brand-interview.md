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
