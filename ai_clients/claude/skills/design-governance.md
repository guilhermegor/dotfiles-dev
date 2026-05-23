---
name: s:design-governance
description: Use when generating the governance metadata for a design system —
  semantic version, component status (stable / beta / planned / deprecated),
  changelog, deprecation policy, and contribution rules. Receives the
  component set and any prior version of the design-system doc from
  conversation context. Embeds governance in the markdown frontmatter; no
  sidecar JSON.
effort: medium
argument-hint: [brand-name] [purpose]
allowed-tools: Read
---

Read the component set (with `states:` blocks) from conversation context.
If a prior `design/system/<purpose>.md` exists on disk, also read its
existing `version` and `changelog` to compute the new version. Produce
governance metadata as frontmatter blocks plus the Governance prose
section.

## Rules (never violate)

- Governance lives in the markdown frontmatter, not a sidecar JSON. The
  design system is one file the team reads — keep it co-located.
- Use **semantic versioning** (semver): MAJOR.MINOR.PATCH.
  - MAJOR: a token rename, removal, or component breaking change.
  - MINOR: a new token, new component, new theme variant, new state.
  - PATCH: token value tweak (within same role), prose-only edits.
- Component status is one of: `stable` · `beta` · `experimental` ·
  `deprecated` · `planned`. Default for any component this skill sees is
  `stable` unless the calling agent explicitly marks otherwise.
- A `deprecated` component **must** name its replacement and removal
  version. No silent deprecations.

## Step 1 — Detect or set the version

If a prior file exists at `design/system/<purpose>.md`:
1. Read its frontmatter `version` field.
2. Read its frontmatter `changelog` and the new component set in context.
3. Compute the new version by comparing:
   - Any `colors.*`, `typography.*`, `components.*` key removed or renamed
     → **MAJOR bump**.
   - Any new key added → **MINOR bump**.
   - Only value changes within existing keys → **PATCH bump**.

If no prior file: ask the user for a starting version. Default to
`0.1.0` (pre-release) unless they indicate otherwise.

```
No prior version detected. Start at:
  1. 0.1.0  — pre-release, breaking changes expected
  2. 1.0.0  — first stable release
  Or type a specific semver (e.g. "0.5.0").
```

## Step 2 — Component status assignment

For each component in the set, decide status. Defaults:
- All base components (`button-*`, `text-input`) → `stable`
- All purpose-specific components → `stable`
- If the calling agent passed a `[experimental]` flag for a component
  (e.g. user said "this is experimental"), honour it.
- If a component in the prior version is missing from the new set →
  emit it with status `deprecated` and ask the user for the replacement
  + removal version.

```yaml
component-status:
  button-primary:        stable
  button-secondary:      stable
  button-tertiary-text:  stable
  text-input:            stable
  card:                  stable
  hero:                  beta            # only if flagged
  legacy-modal:                          # only if deprecated
    status:      deprecated
    replaced-by: bottom-sheet
    remove-in:   "2.0.0"
    deprecated-in: "1.4.0"
```

## Step 3 — Changelog

Produce a `changelog` block as a list of entries, newest first. Each
entry names the version, date, and a categorised set of changes.

```yaml
changelog:
  - version: "1.2.0"
    date:    "2026-05-20"
    added:
      - "filter-pill component with selected/focus states"
      - "compact theme alias layer"
    changed:
      - "button-primary focus state now uses outlineOffset 2px"
    fixed:
      - "muted-on-canvas contrast 4.6:1 → 4.8:1"
    deprecated: []
    removed:   []
  - version: "1.1.0"
    date:    "2026-04-10"
    added:
      - "dark theme alias layer"
    changed: []
    fixed: []
    deprecated: []
    removed: []
```

If this is the initial release, the changelog has a single entry naming
"Initial release" + the contents.

## Step 4 — Deprecation policy

A short policy block describing how deprecations are communicated and
removed. This is prose, not metadata.

```yaml
deprecation-policy:
  notice-window: "one minor version"     # deprecated → removed gap
  signalled-in:  "Components prose + Known Gaps"
  removed-in:    "next MAJOR release"
  exception:     "security/accessibility regressions may bypass the window"
```

## Step 5 — Contribution rules

A minimal block describing how changes get into the system. This avoids
the "anyone adds tokens, scale rots" failure mode.

```yaml
contribution-rules:
  token-additions:    "require a design-system maintainer approval"
  component-additions: "require approval + usage example in Components prose"
  theme-additions:    "require contrast audit pass against AA"
  breaking-changes:   "require MAJOR version + 1-release deprecation notice"
```

## Governance prose section

Write into the conversation:

```markdown
## Governance

### Version
**`{version}`** — released <date>. <One-sentence summary of the headline
change, or "Initial release.">

### Component status

| Component       | Status      | Notes |
|-----------------|-------------|-------|
| button-primary  | stable      |       |
| hero            | beta        | API may change before 2.0 |
| legacy-modal    | deprecated  | Use `bottom-sheet`; removed in 2.0.0 |
[…all components]

### Changelog

#### {version} — {date}
- **Added**
  - …
- **Changed**
  - …
- **Fixed**
  - …
- **Deprecated**
  - …
- **Removed**
  - …

[…earlier entries, newest first]

### Deprecation policy

Deprecated components are signalled in the Components prose and Known
Gaps for <notice-window>; they are removed in the next MAJOR release.
Security and accessibility regressions may bypass this window.

### Contribution

- Adding tokens or components requires design-system maintainer approval.
- Theme additions must pass an accessibility audit at AA before merge.
- Breaking changes require a MAJOR version bump and one minor-release
  deprecation notice.
```

## Do Not

- Do not emit governance as a sidecar JSON file. It lives in frontmatter.
- Do not silently bump a MAJOR version. If you detect a breaking change,
  surface it explicitly to the user and ask "confirm MAJOR bump?"
- Do not invent changelog entries. If the prior file lacks a changelog,
  start fresh with "Initial release" + the current contents and note in
  Known Gaps that earlier history was not captured.
