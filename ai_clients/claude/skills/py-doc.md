---
name: py-doc
description: Generate mkdocs documentation pages from Python source code using mkdocstrings directives. Trigger when asked to document, generate docs, create API reference, or build mkdocs pages for a Python module or package.
effort: high
argument-hint: [source-file-or-directory]
---

Generate mkdocs-compatible markdown pages for Python source code using
mkdocstrings directives. The existing numpy-style docstrings are the single
source of truth — this skill creates the pages that render them, not the
docstrings themselves.

## Required inputs

Before doing anything else, ask the user for the following if not already provided
in `$ARGUMENTS`:

1. **Source** — path to a `.py` file or a package directory.
2. **Output directory** *(optional)* — where to write the generated markdown pages.
   If not provided, read `docs_dir` from the project's `mkdocs.yml`; default to
   `docs/` if neither is available.

Do not infer the source path. Wait for explicit confirmation before reading files.

## Prerequisites check

Before generating pages, verify the project's `mkdocs.yml`:

- **mkdocstrings plugin** — check that `mkdocstrings` (or `mkdocstrings[python]`)
  appears in the `plugins:` list. If absent, **warn the user** that the generated
  pages will not render without it and suggest adding:

```yaml
plugins:
  - mkdocstrings:
      handlers:
        python:
          options:
            docstring_style: numpy
            show_source: false
            heading_level: 2
            members_order: source
```

- **nav section** — note whether a `nav:` key exists (needed for the nav update step).

## Behaviour

### Detecting source type

- If the source path ends in `.py` → **single file mode**.
- If the source path is a directory containing `.py` files or `__init__.py` →
  **package directory mode**.
- Otherwise, abort with a clear error message.

### Single file mode

1. Determine the fully qualified module name from the file path and the project
   root (look for `pyproject.toml`, `setup.py`, or the nearest parent with
   `__init__.py`).
2. Generate **one markdown page** using the page template below.
3. Write it to `<output_dir>/<module_name>.md`.

### Package directory mode

1. Walk the directory recursively, collecting all `.py` files.
2. Skip `__init__.py` unless it defines public API (classes, functions, or
   `__all__`).
3. Generate **one page per module**, preserving the package hierarchy as
   subdirectories under the output directory.
4. Generate an **index page** (`index.md`) for each sub-package listing its
   modules with brief descriptions (taken from the first line of each module
   docstring).

### Page template

Each generated page follows this structure:

```markdown
# module_name

::: package.module_name
    options:
      show_source: false
      docstring_style: numpy
      heading_level: 2
      members_order: source
```

For modules with both classes and standalone functions, use **separate directives**
per public class/function if the module is large (> 10 public members), so the
rendered page has clear navigation. Otherwise, a single module-level directive
is sufficient.

### Sub-package index page

```markdown
# package_name

Overview of the `package_name` sub-package.

| Module | Description |
|--------|-------------|
| [module_a](module_a.md) | First line of module_a docstring. |
| [module_b](module_b.md) | First line of module_b docstring. |
```

## Nav update

After generating all pages:

1. Read `mkdocs.yml`.
2. Find the `nav:` key. If absent, create one.
3. Find or create an **"API Reference"** section within `nav`.
4. Insert/update entries for every generated page, mirroring the package
   hierarchy. Example:

```yaml
nav:
  - Home: index.md
  - API Reference:
    - analytics:
      - Overview: reference/analytics/index.md
      - binary_comparator: reference/analytics/binary_comparator.md
      - curve_fitter: reference/analytics/curve_fitter.md
```

5. **Preserve** all existing nav entries outside the "API Reference" section.
6. Do not reorder or remove entries the user placed manually.

## Do Not

- Do not write or modify Python source code.
- Do not extract docstrings into static markdown — use mkdocstrings directives only.
- Do not remove existing nav entries unrelated to the generated pages.
- Do not assume mkdocstrings plugin is configured — check and warn if missing.
- Do not generate pages for test files (`test_*.py`, `*_test.py`, `conftest.py`).
- Do not generate pages for migration scripts or setup files (`setup.py`,
  `conftest.py`, `manage.py`).

## Output format

After generating, report:

- Number of pages generated and their paths.
- Whether `mkdocs.yml` nav was updated.
- Any warnings (missing mkdocstrings plugin, modules without docstrings, etc.).
