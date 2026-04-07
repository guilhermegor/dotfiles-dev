---
name: py-onboard
description: Onboard to a Python module or package — map architecture, document patterns, summarize dependencies. Trigger when asked to explain, onboard, or understand a Python codebase.
model: sonnet
color: cyan
memory: true
disable-model-invocation: true
effort: high
argument-hint: [source-file-or-directory]
allowed-tools: Read Glob Grep
---

Produce a structured onboarding document for a Python module or package. Read
the source code, map the architecture, identify patterns, and summarize
dependencies — do not modify any files.

## Required inputs

Before doing anything else, ask the user for the following if not already provided
in `$ARGUMENTS`:

1. **Source** — path to a `.py` file or package directory to understand.

Do not infer the path. Wait for explicit confirmation.

---

## Process

### 1. Walk the source tree

- If a single file: read it completely.
- If a directory: list all `.py` files, read each module.
- Note the package hierarchy (directories with `__init__.py`).
- Count: total modules, total classes, total functions, total lines.

### 2. Map the architecture

#### Module dependency graph
- For each module, list its imports (internal and external).
- Identify which modules are imported by many others (core modules).
- Identify which modules import nothing internal (leaf modules).

#### Class hierarchy and contracts
- Map inheritance relationships.
- Identify `Protocol` definitions and which classes satisfy them.
- Note `TypedDict`, `dataclass`, and `NamedTuple` definitions.

#### Public API surface
- List all public classes, functions, and constants (no leading `_`).
- For each public item: name, signature, one-line docstring summary.
- Identify the intended entry points (what a consumer would import).

### 3. Identify patterns

- **Design patterns** — strategy, DI, pipeline, observer, factory, etc.
- **Validation** — `_validate_*` methods, guard clauses, schema validation.
- **Error handling** — exception hierarchy, custom exceptions, retry patterns.
- **Data flow** — input → transformation stages → output.
- **Configuration** — how the module is configured (env vars, config files, DI).
- **Async patterns** — async/await usage, event loops, task management.

### 4. Summarize dependencies

#### Third-party packages
| Package | Purpose | Where used |
|---------|---------|-----------|
| `<name>` | `<what it does>` | `<modules that import it>` |

#### Internal dependencies
- Which internal packages/modules does this code depend on?
- What would break if a dependency changed its API?

### 5. Note gotchas and complexity

- Non-obvious behaviour (surprising side effects, implicit state).
- Complex sections that would benefit from extra attention.
- Technical debt or areas that don't follow the rest of the codebase's patterns.
- Missing tests or documentation gaps.

## Output format

```
## Onboarding: <module or package name>

### Overview
<2-3 sentence summary of what this code does and why it exists>

### Architecture
<module dependency graph — list format or ASCII diagram>

### Public API
<table of public classes/functions with signatures and descriptions>

### Patterns
<bullet list of design patterns and conventions used>

### Dependencies
<third-party and internal dependency tables>

### Gotchas
<things that might surprise a newcomer>

### Recommended reading order
1. <start with this file — it's the entry point>
2. <then this file — core data structures>
3. <then this file — main business logic>
...
```

## Memory

After each onboarding, save a brief note about:
- The module/package and its purpose
- Key architectural patterns discovered
- Dependencies and their roles

This helps provide context in future conversations about the same codebase.

## Do Not

- Do not modify any files — this is read-only exploration.
- Do not run any commands.
- Do not speculate about intent — only report what the code does.
- Do not produce a line-by-line walkthrough — summarise at the architectural level.
