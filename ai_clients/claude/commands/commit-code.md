---
name: c:commit-code
allowed-tools: Bash(git diff*), Bash(git diff --staged*), Bash(git status*), Bash(git log*), Bash(git add*), Bash(git commit*), Bash(git push*), Bash(git tag*), Bash(find .claude/*), Read, Glob, Grep
description: Stage changes and create a conventional commit with structured message
argument-hint: <type> [scope] - e.g. feat auth | fix rounding | refactor ingestion
---

You are creating a git commit for this repository. Follow these steps exactly.

## 0. Verification gate

Before doing anything else, ask the user:

> "Do you want to skip pre-commit verification and commit immediately? (yes = skip, no = run full workflow)"

- If the user answers **yes** (or any affirmative): jump straight to step 5, staging and committing all currently staged changes as-is. Infer the commit message from `git diff --staged` and `git log --oneline -3` without further prompts.
- If the user answers **no** (or any negative): continue with the full workflow below.

## 1. Gather context

Run these in parallel:
- `!git diff --staged`
- `!git diff`
- `!git status --short`
- `!git log --oneline -5`

## 2. Determine type and scope

The `$ARGUMENTS` string contains the commit type and optional scope provided by the user (e.g. `feat auth` or `fix`).

Valid types (from CONTRIBUTING.md): `build`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`, `style`, `test`, `chore`, `revert`, `bump`.

If `$ARGUMENTS` is empty or the type is missing, infer it from the diff content.

## 3. Identify changed files

From the `git status` and `git diff` output, collect every file that was added, modified, or deleted. Group them by logical area (e.g. ingestion, analytics, tests, config).

## 4. Compose the commit message

Format (follow exactly — no deviations):

```
<type>(<scope>): <Title in sentence case, imperative mood, no period>

  - <concise topic describing what changed> → <file or files affected>
  - <concise topic describing what changed> → <file or files affected>
  ...
```

Rules:
- The title line must not exceed **72 characters** (including `type(scope): `).
- Each bullet line in the body must not exceed **80 characters total**
  (including the leading `  - ` prefix and the ` → filename` suffix).
- If any line is too long, shorten the description text — never wrap onto
  a continuation line.
- Omit `(<scope>)` if no scope was provided and none is obvious.
- Each bullet covers one logical change; combine trivially related files on
  the same bullet with `, `.
- Do not add boilerplate footers or `Co-Authored-By` lines unless explicitly
  asked.

## 4a. Verify line lengths before committing

After composing the message, measure every line with the shell and fix any
violations **before** proceeding to step 5:

```bash
# Check title (must be ≤ 72)
echo -n "<type>(<scope>): <your title here>" | wc -c

# Check each bullet (must be ≤ 80)
echo -n "  - <your bullet text> → <filename>" | wc -c
```

If any measurement exceeds the limit, shorten the text and re-measure.
Only proceed to step 5 once every line passes.

## 5. Stage, commit, and push

1. If there are unstaged changes the user likely wants included, stage them with `git add` targeting specific files — never `git add -A` blindly. Ask the user if it is ambiguous which files to include.
2. Show the composed message to the user for confirmation before running `git commit`.
3. Run `git commit -m "$(cat <<'EOF' ... EOF)"` using a heredoc to preserve formatting.
4. Run `git push origin HEAD` to push the branch to the remote.
5. Report the resulting commit hash, one-line summary, and push status.

## 6. Tag (optional)

After reporting the commit result, ask:

> "Do you want to create a git tag for this commit? (yes / no)"

- If **no**: skip this step entirely.
- If **yes**: ask:

  > "What should the tag name be? (e.g. v1.2.0)"

  Then:
  1. Create an annotated tag pointing at the new commit:
     ```bash
     git tag -a "<tag-name>" -m "<tag-name>"
     ```
  2. Push the tag to the remote:
     ```bash
     git push origin "<tag-name>"
     ```
  3. Report the tag name and the push status.
