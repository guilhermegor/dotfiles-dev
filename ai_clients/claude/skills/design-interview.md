---
name: s:design-interview
description: Use when starting any tier of a design session (brand, language,
  or system) to gather the brand profile. Receives brand name, purpose, and
  inspiration depth from the calling agent. Detects and offers to reuse any
  lower-tier artifact already on disk, then asks questions adaptively until
  a complete brand profile can be produced.
effort: high
argument-hint: [brand-name] [purpose] [depth-a|b|c]
allowed-tools: Read WebFetch
---

Ask questions **one at a time**. Never ask multiple questions in one message.

You already have the brand name, design purpose, and inspiration depth from
`$ARGUMENTS`. Do not ask for them again. If any of the three is missing from
`$ARGUMENTS`, ask only for the missing item(s) before proceeding.

## Step 0 — Artifact-reuse detection

Before any interview questions, check the filesystem for an existing
lower-tier artifact that can seed this session:

- If called by **a:design-language** or **a:design-system**, look for
  `design/brand/brand-book.md`. If present, read it and offer:

  ```
  Found an existing brand book at design/brand/brand-book.md
  (brand: <name>, last updated: <mtime>).

  Reuse its identity, voice, palette personality, and typeface choices as
  the seed for this session?

    Y — reuse (I'll only ask about new surface/system concerns)
    N — fresh interview (ignore the file)
  ```

- If called by **a:design-system**, additionally look for
  `design/language/<purpose>.md` and `design/language/tokens.dtcg.json`
  (or `tokens.flat.json` / `tokens.style-dictionary.json`). If present:

  ```
  Found published design language tokens at
  design/language/<purpose>.md (+ <tokens file>).

  Consume these tokens directly?

    Y — skip foundation skills (color/type/layout/motion) and go straight
        to component specs
    N — re-derive foundations (ignore the file)
  ```

On **Y**, summarise what was seeded ("Seeding from brand book: palette
{primary, ink, canvas}, body=Inter, display=Playfair Display, register=
Balanced. Skipping universal questions 1–6.") and skip to the
purpose-specific questions only.

On **N**, proceed with the full interview below.

If no lower-tier artifact exists, proceed silently with the full interview.

## Universal questions (always, in this order)

1. **Inspirations** — "Which brands, sites, or visuals feel closest to what
   you want? Give me names, URLs, or describe them."
   - Depth A: note names/descriptions as surface signals only — do not fetch.
     If the user gave only a name with no description, ask one follow-up:
     "What specifically about [name] feels right — the colors, the density,
     the tone?"
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
   this should feel."
   After receiving the adjectives, ask as a **separate question**: "Should it
   feel authoritative or approachable? Playful or serious? Minimal or rich?"

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
- `site` / `web-app` → "Is this primarily a marketing / landing page or a
  product web app?", "What is the primary CTA — sign-up, contact, purchase?",
  "Is dark mode required?"
- `blog` → "Is this editorial / content-focused or more of a personal site?",
  "Will there be code snippets or technical content?", "What reading width
  feels right — narrow and focused or wide and magazine-like?"
- `app-tv` → "Target platform — Apple TV, Android TV, Samsung Tizen, other?",
  "Is this a streaming / video app or a data/utility app?", "Should the UI
  work with D-pad only, or also pointer/touch?"
- `app-watch` → "Target platform — watchOS, Wear OS, or both?",
  "Is this a glanceable complication or a full app with navigation?",
  "Does the app need ambient / always-on display support?"
- `push-notification` → "Are notifications transactional (receipts, alerts)
  or marketing (promos, re-engagement)?", "Which platforms — iOS, Android,
  web push?", "Should rich notifications show images or action buttons?"
- Custom purpose → reason about rendering environment, interaction model,
  grid constraints, and accessibility requirements for that surface.

When all four are answerable — what it looks like, who it is for, what it
needs to do, and what the surface-specific constraints are — **stop asking
and produce the output below**.

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
  - Palette: <3–5 hex values extracted from page CSS or screenshots>
  - Fonts: <family names found in headings or CSS — not user-stated>
  - Shape: <sharp / soft / pill>
  - Density: <airy / balanced / dense>
  - Tone: <formal / casual / premium / playful>

## Surface Constraints
<purpose-specific answers, one bullet per question answered>

## Inspiration Depth
<A / B / C — one sentence summary of how inspirations were processed>
```
