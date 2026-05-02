---
name: s:brand-component-system
description: Use when generating the component token set for a brand design
  document. Receives brand profile, color tokens, and type tokens from
  conversation context. Produces component tokens and the Components prose
  section.
effort: high
argument-hint: [brand-name] [purpose]
allowed-tools: Read
---

Read brand profile, color tokens, and type tokens from conversation context.

## Rules (never violate)

- Component tokens use **only** `{colors.*}` and `{typography.*}` references.
  Never use raw hex values, raw px sizes, or raw font names in this block.
- Every property that can reference a token must reference one.
- `padding`, `height`, and `border-radius` use raw values here (e.g. `14px
  24px`, `48px`) because they are layout values, not color or type tokens.
  Border-radius should reference `{rounded.*}` tokens once the layout skill
  defines them — leave as raw px for now and note in Known Gaps.

## Base component set (all purposes)

Always produce these components:

```yaml
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    typography: "{typography.button-md}"
    padding: "14px 24px"
    height: 48px

  button-primary-active:
    backgroundColor: "{colors.primary-active}"
    textColor: "{colors.on-primary}"

  button-primary-disabled:
    backgroundColor: "{colors.primary-disabled}"
    textColor: "{colors.on-primary}"

  button-secondary:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.button-md}"
    padding: "13px 23px"
    height: 48px

  button-tertiary-text:
    backgroundColor: transparent
    textColor: "{colors.ink}"
    typography: "{typography.button-md}"

  text-input:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.body-md}"
    padding: "14px 12px"
    height: 56px

  text-input-focus:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    borderColor: "{colors.ink}"

  text-input-error:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.error}"
    borderColor: "{colors.error}"
```

## Purpose-specific components

Add the relevant group(s) for the chosen purpose. Use the same token-reference
pattern as the base set above.

**`site` / `web-app`:**
```yaml
  top-nav:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.nav-link}"
    height: 64px

  hero:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.display-xl}"

  card:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.ink}"
    typography: "{typography.body-sm}"

  footer:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.body-sm}"
    padding: "48px 80px"
```

**`dashboard`:**
```yaml
  sidebar:
    backgroundColor: "{colors.surface-soft}"
    textColor: "{colors.ink}"
    typography: "{typography.ui-sm}"

  data-table-row:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.mono-sm}"
    padding: "12px 16px"

  data-table-row-hover:
    backgroundColor: "{colors.surface-soft}"
    textColor: "{colors.ink}"

  badge:
    backgroundColor: "{colors.surface-strong}"
    textColor: "{colors.ink}"
    typography: "{typography.badge}"

  tooltip:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.on-dark}"
    typography: "{typography.caption-sm}"

  chart-legend:
    textColor: "{colors.muted}"
    typography: "{typography.caption-sm}"
```

**`ecommerce`:**
```yaml
  product-card:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.ink}"
    typography: "{typography.body-sm}"

  price-tag:
    textColor: "{colors.ink}"
    typography: "{typography.title-md}"

  price-tag-sale:
    textColor: "{colors.primary}"
    typography: "{typography.title-md}"

  filter-pill:
    backgroundColor: "{colors.surface-strong}"
    textColor: "{colors.ink}"
    typography: "{typography.button-sm}"

  filter-pill-active:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    typography: "{typography.button-sm}"

  cart-item:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.body-sm}"

  checkout-step:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.body-md}"
```

**`app-cellphone`:**
```yaml
  tab-bar:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.muted}"
    typography: "{typography.caption-sm}"
    height: 56px

  tab-bar-active:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.primary}"
    typography: "{typography.caption-sm}"

  list-row:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.body-md}"
    padding: "14px 16px"

  bottom-sheet:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.ink}"
    typography: "{typography.body-md}"

  fab:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    height: 56px

  toast:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.on-dark}"
    typography: "{typography.body-sm}"
```

**`email` / `email-marketing`:**
```yaml
  email-header:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    typography: "{typography.display-md}"
    padding: "32px 40px"

  email-cta-block:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.body-md}"
    padding: "24px 40px"

  email-footer:
    backgroundColor: "{colors.surface-soft}"
    textColor: "{colors.muted}"
    typography: "{typography.caption-sm}"
    padding: "24px 40px"
```

**`blog`:**
```yaml
  article-header:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.display-lg}"

  pull-quote:
    backgroundColor: "{colors.surface-soft}"
    textColor: "{colors.ink}"
    typography: "{typography.display-sm}"
    padding: "24px 32px"

  author-card:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.body-sm}"

  tag-pill:
    backgroundColor: "{colors.surface-strong}"
    textColor: "{colors.ink}"
    typography: "{typography.caption}"
```

**`docs`:**
```yaml
  code-block:
    backgroundColor: "{colors.surface-strong}"
    textColor: "{colors.ink}"
    typography: "{typography.mono-md}"
    padding: "16px 20px"

  callout:
    backgroundColor: "{colors.surface-soft}"
    textColor: "{colors.ink}"
    typography: "{typography.body-sm}"
    padding: "12px 16px"

  sidebar-nav-item:
    backgroundColor: transparent
    textColor: "{colors.muted}"
    typography: "{typography.ui-sm}"

  sidebar-nav-item-active:
    backgroundColor: "{colors.surface-strong}"
    textColor: "{colors.ink}"
    typography: "{typography.ui-sm}"
```

**`print` / `packaging`:**
```yaml
  page-header:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    typography: "{typography.display-lg}"

  section-divider:
    backgroundColor: "{colors.hairline}"

  caption-block:
    backgroundColor: transparent
    textColor: "{colors.muted}"
    typography: "{typography.caption-sm}"
```

For custom purposes: reason about which UI patterns the surface requires
and produce an appropriate component list using the token-reference pattern.

## Components prose section

After deriving the tokens, write the Components prose section into the
conversation. Group components logically (Buttons → Inputs → Navigation →
Cards/Content → Purpose-specific → Footer/Legal). For each component,
describe its visual role and when it appears.

```markdown
## Components

### Buttons
**`button-primary`** — <color name> fill, <on-primary> text, <height>px height.
The primary CTA across the system: <list of usages>.

**`button-primary-active`** — Press state. Background flips to
`{colors.primary-active}`. <Describe any transform or shadow change, or
"No transform, no shadow change.">

**`button-primary-disabled`** — <Describe disabled appearance and cursor>.

**`button-secondary`** — <Describe secondary button role and usage>.

**`button-tertiary-text`** — Plain text, no surface. <Describe usage>.

### Forms
**`text-input`** — <Describe input appearance, focus, error states>.

### [Purpose-specific sections]
<One subsection per component group, matching the tokens above>
```
