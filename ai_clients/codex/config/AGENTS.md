# AGENTS.md

Global instructions for the OpenAI Codex CLI, loaded from `$CODEX_HOME/AGENTS.md`
(defaults to `~/.codex/AGENTS.md`) on every session. Deployed by
`./ai_clients/main.sh codex agents_md`. Edit this source file, never the
deployed copy — it is overwritten on every deploy
(source of truth: `ai_clients/codex/config/AGENTS.md` in dotfiles-dev).

## Core Philosophy

- Simplicity first: make every change as small and targeted as possible.
- Separation of concerns: one module/function owns one responsibility.
- DRY: every piece of knowledge has a single authoritative representation.
- Explicit over implicit: no hidden side effects, no magic conventions.
- Fail fast: raise meaningful, descriptive errors early.
- Root cause over symptom, even when it is more work.

## Version Control

- Conventional Commits: `feat:`, `fix:`, `chore:`, `test:`, `docs:`, `refactor:`.
- Atomic commits: one logical change per commit.
- Never commit secrets, credentials, or local config files.

## What to Always Do

- Show complete, runnable code — no placeholders unless explicitly requested.
- Validate external input at the boundary before any transformation.
- Use guard clauses / early returns; keep the happy path unindented.

## What to Never Do

- Use bare `catch`/`except` without re-raising or logging.
- Use `float` for money, precise measurements, or cumulative calculations.
- Store secrets in source code or committed environment files.
