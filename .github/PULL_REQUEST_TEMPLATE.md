## Description
**What**: Briefly summarize the changes (e.g., "Added react-spa-webpack skeleton").
**Why**: Explain the motivation (e.g., "To support TypeScript scaffolding").
**How**: Link to implementation details (e.g., "Added bin/scaffold/ts_react_app.sh and templates/react-spa-webpack/").

---

## Changes Made
**Added**:
- New skeleton / script: [Description].
- New template file: [Path].

**Updated**:
- Refactored [Script/Template] for [Reason].

**Fixed**:
- Issue #[Number]: [Brief description].

---

## Testing
### Manual Testing
- **Dry-run**:
    - Steps: `make dry-run` → select [language] → select [skeleton]
    - Expected: Structure preview shown, no files created.
- **Full scaffold**:
    - Steps: `make dev` → select [language] → select [skeleton] → verify output in temp dir
    - Expected: Project created at expected path with correct files.

### Automated Testing
- **CI (this PR)**:
    - `lint-shell`: ShellCheck on `bin/**/*.sh` — Status: `OK/NOK`
    - `validate-meta`: skeleton.meta integrity — Status: `OK/NOK`
    - `docs-build`: MkDocs strict build — Status: `OK/NOK`
    - `dry-run-smoke`: all skeletons — Status: `OK/NOK`
    - `typecheck-ts`: tsc --noEmit — Status: `OK/NOK`
    - `spell-check`: codespell — Status: `OK/NOK`

**Not Applicable**:
- Explain (e.g., "Documentation-only change").

---

## Documentation
- **Docs site** (`docs/`): Added/updated [page].
- **CLAUDE.md**: Updated if scaffolding flow changed.
- **README**: Updated if new skeleton added.

---

## Additional Notes
**Dependencies**:
- Blocks/Depends on #[PR Number].

**Follow-up**:
- Tech debt: [Brief note].

**Reviewer Focus**:
- Pay attention to [specific files/logic].
