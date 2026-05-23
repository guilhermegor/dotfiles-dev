---
name: s:design-motion-system
description: Use when generating the motion system for a design language or
  design system document. Receives brand profile and all previous tokens from
  conversation context. Produces motion tokens (duration, easing) and the
  Motion prose section.
effort: medium
argument-hint: [brand-name] [purpose]
allowed-tools: Read
---

Read brand profile and all tokens produced so far from conversation context.

## Rules (never violate)

- Motion choices are **brand-driven**, not defaults. Derive durations and
  easing curves from the look-and-feel adjectives and emotional tone in the
  brand profile.
- Tokens use raw values here (ms for durations, `cubic-bezier(...)` for
  easings). Other skills reference `{motion.*}` to consume them.
- Always include a reduced-motion strategy — even brands that lean into rich
  motion must degrade gracefully when `prefers-reduced-motion: reduce`.

## Step 1 — Derive the motion personality

Map brand adjectives to a motion register:

| Adjectives include… | Register | Implications |
|---|---|---|
| clinical, precise, efficient, minimal | Restrained | Durations ≤ 200ms, ease-out only, no spring |
| trustworthy, professional, calm | Balanced | Durations 150–300ms, ease-out + ease-in-out, no spring |
| friendly, warm, human | Lively | Durations 200–400ms, full easing set, gentle spring on key moments |
| playful, energetic, expressive | Bouncy | Durations 250–500ms, spring/overshoot common, motion as identity |
| editorial, premium, considered | Cinematic | Slower durations 300–600ms, deep ease-in-out, no spring |

If the brand adjectives span two registers, blend toward the more restrained
register for utility moments and the richer register for hero/identity moments.

## Step 2 — Duration scale

Choose a base unit (typically `base: 250ms`) and produce the scale. Adapt the
range to the register chosen above.

```yaml
motion:
  duration:
    instant: 0ms        # no animation — reduced-motion fallback, immediate state
    micro: 100ms        # color tints, opacity flickers
    fast: 150ms         # hover/focus, small UI transitions
    base: 250ms         # default — modal open, drawer slide, page tab change
    slow: 400ms         # full-screen transitions, large surface changes
    slower: 600ms       # cinematic moments, hero entrances (omit for Restrained)
```

Adapt for surface:
- Mobile / app-cellphone: shave 20–30% off all values (smaller canvas = faster
  perceived motion). `base: 200ms` typical.
- TV (10-ft UI): add 30–50% (large surfaces and remote-control input cadence).
- Email / print: no motion — emit a Known Gaps note that motion tokens were
  produced but the surface does not consume them.

## Step 3 — Easing scale

```yaml
motion:
  easing:
    linear: "cubic-bezier(0, 0, 1, 1)"            # progress bars, repeating loops
    standard: "cubic-bezier(0.4, 0, 0.2, 1)"      # default — bidirectional moves
    enter: "cubic-bezier(0.16, 1, 0.3, 1)"        # ease-out — incoming elements
    exit: "cubic-bezier(0.4, 0, 1, 1)"            # ease-in — outgoing elements
    spring: "cubic-bezier(0.34, 1.56, 0.64, 1)"   # gentle overshoot — Lively/Bouncy only
```

- Restrained / Balanced registers: emit only `linear`, `standard`, `enter`,
  `exit`. Omit `spring` and note it in Known Gaps.
- Lively / Bouncy / Cinematic registers: emit the full set; the prose names
  which surfaces use spring.

## Step 4 — Reduced motion strategy

Always produce a `motion.reduced` block describing the degradation rule:

```yaml
motion:
  reduced:
    rule: "@media (prefers-reduced-motion: reduce)"
    strategy: "Cross-fade only — replace translate/scale/spring with opacity
               transitions at duration.micro (100ms)."
    exceptions: []     # list any motion that must NOT be removed (rare —
                       # progress feedback, critical state changes)
```

## Motion prose section

Write into the conversation:

```markdown
## Motion

### Register
<One sentence naming the register (Restrained / Balanced / Lively / Bouncy /
Cinematic) and the brand adjectives that led to it.>

### Duration
- **`{motion.duration.fast}`** (Xms): <typical usage — hover, focus rings>
- **`{motion.duration.base}`** (Xms): <default — modal open, tab switch>
- **`{motion.duration.slow}`** (Xms): <larger transitions>
[…continue for each token emitted]

### Easing
- **`{motion.easing.standard}`** — default for bidirectional motion (drawer
  slide, accordion expand).
- **`{motion.easing.enter}`** — ease-out for elements entering view (toast,
  dropdown, modal content).
- **`{motion.easing.exit}`** — ease-in for elements leaving view.
[…spring entry only if emitted: name the specific surfaces that use it]

### Principles
<2–3 sentences. Examples:
"Motion is restrained. Functional transitions only — modal open, drawer
slide, hover tint. No motion as decoration. The system has no spring
easing; overshoot would undermine the precision the brand promises."

"Motion is part of the identity. Spring easing carries the primary CTA
press and the cart-add confirmation — the two moments the brand earns
expressiveness. Everything else uses standard ease-out.">

### Reduced Motion
Under `@media (prefers-reduced-motion: reduce)`, <describe the degradation
strategy — typically cross-fade at duration.micro replacing all transforms>.
<List any exceptions that must remain animated for usability — e.g.
progress feedback, loading spinners.>
```
