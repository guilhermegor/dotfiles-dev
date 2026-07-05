# Backlog — PR-template-guard PreToolUse hook

**Created:** 2026-07-05 19:28:53
**Branch:** `feat/pr-template-guard-hook`
**Motivation:** The "PR body must follow the repo's `.github/PULL_REQUEST_TEMPLATE.md`" rule has
recurred 7+ times across projects (lessons.md: 2026-05-11, 05-20, 05-25, 05-27, 07-05 ×2) despite
living in memory/lessons. Advisory context can't enforce; only a harness-run `PreToolUse` hook can.
User escalated on wwdates PRs #3/#4/#5. Decision: **block until compliant** (not soft-remind).

## Design

A `PreToolUse` hook on the `Bash` matcher that, before every Bash call:
1. Fails open (exit 0) unless the command is `gh pr create` or `gh pr edit` **with** a body flag
   (`--body`/`-b`/`--body-file`/`-F`). Title-only edits and non-`gh-pr` commands pass instantly.
2. Locates the PR template: repo `.github/PULL_REQUEST_TEMPLATE.md` (+ lowercase / `docs/` variants),
   else the dotfiles fallback `~/.claude/projects/-home-guilhermegor-github-dotfiles-dev/memory/feedback_pr_template.md`.
   No template anywhere → allow.
3. Extracts required section headers (`^##[[:space:]]`) from the template.
4. Checks the body source (inline command string, or the `--body-file` path's contents) contains
   each section's text. Any missing → **exit 2** with stderr = missing sections + full template +
   "re-run with a compliant `--body`". All present → exit 0 (allow).
5. Fails open on any internal error (missing `jq`, unreadable template) so it can never wedge all
   Bash calls.

## Tasks

- [x] `ai_clients/claude/hooks/pr_template_guard.sh` — the hook (functions + `main`; hook I/O
      contract, so **no** `print_status`/stdout noise — only exit 2 + stderr on block).
- [x] `ai_clients/claude/lib/hooks.sh` — add `copy_hook_file "pr_template_guard.sh" "$hooks_dir"`
      to `install_hooks()`.
- [x] `ai_clients/claude/settings.json` — add the hook as a 2nd command under the existing
      `PreToolUse` → `Bash` matcher (alongside `rtk hook claude`).
- [x] Test (local, pre-deploy): `bash -n` syntax OK; non-gh `git status` → allow(0); title-only
      edit → allow(0); non-compliant `gh pr edit --body "ad-hoc"` → **block(2)** listing missing
      sections + template; compliant 5-section body → allow(0). All against the real wwdates
      template.
- [x] Deploy: run the hooks install step (`make ai_clients` or the scoped hooks/settings step) so
      `~/.claude/hooks/pr_template_guard.sh` + `~/.claude/settings.json` update. **Takes effect next
      session** (Claude reads settings at startup).
- [ ] Open PR in dotfiles-dev following its own `.github/PULL_REQUEST_TEMPLATE.md` (dogfood the hook).
- [ ] Mark the lessons.md recurrence entry `**Promoted:** 2026-07-05` once merged + deployed.

## Notes

- Source-of-truth discipline: edit here in dotfiles-dev, deploy to `~/.claude/` — never the reverse
  (lessons.md 2026-04-21).
- Delete this backlog file once every box is `[x]`.
