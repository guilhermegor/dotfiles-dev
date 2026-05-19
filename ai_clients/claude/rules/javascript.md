---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/package.json"
  - "**/tsconfig.json"
---

# JavaScript / TypeScript Preferences

> **Priority rule:** These are personal JS/TS defaults — they apply to JavaScript and
> TypeScript files alike, including JSX/TSX. Whenever a project-level CLAUDE.md
> (or any instruction inside the active repository) conflicts with anything here, the project
> context takes precedence. Treat this file as a fallback, not a mandate.

## `ls`-after-save filename verification

Immediately after a user reports "done" for a step that created or renamed
files, run `ls` (or its RTK equivalent) on the affected directory and
visually confirm every filename matches the expected name **before**
running linters/tests or marking the step complete.

**Why this is TS/JS-specific.** In compiled languages with eager
resolution (Rust, Go), a typo'd filename fails at compile time. In
languages with runtime imports (Python), it fails at first execution.
TS/JS hides filename typos behind several layers of tolerance:

- Ambient `*.module.css` / `*.css` declarations in `declarations.d.ts`
  accept any wildcard-matching string as "typed", so `tsc` passes.
- Jest's `moduleNameMapper` regexes use catch-all patterns for CSS, so
  unit tests pass.
- ESLint's `import/no-unresolved` (when configured) catches JS/TS path
  typos but **not** CSS path typos, because of the ambient declarations
  above.
- Webpack-resolve catches them only at `npm start` / build time, which
  is after the lint stack has already given a green light.

Real examples from this user's projects (recurring across weeks of
tutoring): `inedx.tsx` (transposed letters), `styles.,module.css`
(stray comma), `CountDown.modules.css` (extra `s`), `MainFrom.tsx`
(typo'd word). All four passed the full lint stack.

**The rule.** A 50ms `ls` is the cheapest mitigation for an entire bug
class no static tool reliably catches. Run it before the lint stack,
not after.

## Module resolution and import hygiene

- Prefer `eslint-plugin-import` with `import/no-unresolved`,
  `import/no-duplicates`, `import/no-cycle`, and `import/order`. If a
  project lacks these, suggest installing them at the first import-typo
  bug.
- The `*.css` wildcard ambient is intentional — needed for side-effect
  CSS imports like `import '@/shared/styles/global.css'`. Don't try to
  remove it to "catch CSS typos"; the cure is worse than the disease.
  The `ls`-after-save convention above is the right mitigation.
- Path aliases (`@/` etc.) must include the slash. `@/shared/...`
  resolves to the project's source root; `@shared/...` (no slash) is
  interpreted by TS as an npm-scoped package and fails resolution.

## Test scoping

- Unit-test framework: prefer Jest with `@testing-library/react` for
  React projects, configured via `babel-jest` so the test transform
  matches the build transform.
- Co-locate component tests as `*.test.tsx` next to the component.
- E2E framework: prefer Playwright. Namespace scripts as
  `test:e2e:frontend` / `test:e2e:api` / `test:e2e:db` so a static SPA
  layout can grow into a fullstack one without renaming. Visual
  regression via `toHaveScreenshot` baselines committed to the repo.

## CSS Modules pitfalls

CSS Modules accept unitless non-zero lengths silently (e.g.
`border-radius: 50` instead of `50%` — invalid, browser drops the rule,
renders the wrong shape). Neither stylelint-config-standard nor any
type checker catches this class. Visual inspection in a browser is the
only reliable check; a Playwright `toHaveScreenshot` baseline is the
automated proxy.

The other CSS-Modules pitfall: importing `styles` then writing a
literal string like `className="className"` instead of
`className={styles.className}`. The DevTools-inspect class is
`"className"` (literal), not the hashed CSS-Module class. Easy to miss
without a render check.

## Boundary rules (FSD + DDD)

When a project ships `eslint-plugin-boundaries` (e.g. blueprintx-based
React projects), respect the layer hierarchy:

- `domain` → nothing
- `application` → `domain` (+ `infrastructure` only when a use-case
  needs to call a side-effect adapter directly, e.g. toast confirm)
- `infrastructure` → `domain` (never `shared`, never `ui`)
- `ui` → `application`, `domain`, `context`, `shared`
- `context` (composition root) → all four layers
- `shared` → `shared`
- `routes` → `barrel`, `shared`

**Specifically: `infrastructure → shared` is a DDD anti-pattern** if
`shared/` holds UI primitives (components, styles). Infrastructure
adapters that need a UI component (e.g. react-toastify's
`toast(Component, ...)` API) should accept the component via dependency
injection at the call site, not import it directly.

## When in doubt

If a TS/JS step produced surprising behavior despite a clean lint
stack, suspect:

1. Filename typo (run `ls` first — see top of this file)
2. CSS Modules misuse (literal class string, missing unit, wrong file
   extension)
3. Semantic JSX bug (missing element, wrong icon/handler pairing —
   write a `@testing-library/react` spec before guessing further)
4. Boundary violation (a use-case importing UI, an adapter importing
   shared/components/, etc.)
