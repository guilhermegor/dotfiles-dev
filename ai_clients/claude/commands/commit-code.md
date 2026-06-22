---
name: c:commit-code
allowed-tools: Bash(git diff*), Bash(git diff --staged*), Bash(git status*), Bash(git log*), Bash(git add*), Bash(git commit*), Bash(git push*), Bash(git tag*), Bash(find .claude/*), Read, Glob, Grep
description: Stage changes and create a conventional commit with structured message
argument-hint: <type> [scope] - e.g. feat auth | fix rounding | refactor ingestion
---

You are creating a git commit for this repository. Follow these steps exactly.

## 0. Workflow gate

Before doing anything else, ask the user:

> "Do you want to skip the message-composition workflow and commit immediately? (yes = infer message and commit now, no = run full workflow) [default: no]"

- If the user answers **yes** (or any affirmative): jump straight to step 5, staging and committing all currently staged changes as-is. Infer the commit message from `git diff --staged` and `git log --oneline -3` without further prompts.
- If the user answers **no**, presses Enter without input, or gives any non-affirmative response: continue with the full workflow below.

Wait for the user's answer to the first question, then ask:

> "Do you want to bypass git hooks for this commit? (yes = add --no-verify, no = run hooks normally) [default: no]"

- If **yes**: add `--no-verify` to the `git commit` call in step 5.
- If **no** (or empty): omit `--no-verify`; hooks run normally.

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

## 4a. Verify line lengths before committing (deterministic — never eyeball)

You cannot reliably count characters by eye. Let the shell do it: write the
**full** composed message to a file and check every line in a single pass.

```bash
cat > /tmp/commit_msg.txt <<'EOF'
<your full composed message — title line, blank line, then body bullets>
EOF
awk 'NR==1 && length($0) > 72 { printf "TITLE FAIL (%d>72): %s\n", length($0), $0; bad=1 }
     NR>1  && length($0) > 80 { printf "BODY FAIL  (%d>80): %s\n", length($0), $0; bad=1 }
     END   { print (bad ? "✗ shorten the lines above, rewrite the file, re-run" : "✓ all lines within limits") }' /tmp/commit_msg.txt
```

(`awk` counts bytes, so for non-ASCII text it is *stricter* than gitlint's
character count — a `✓` here is always safe.) If any line FAILS, shorten that
line's text — never wrap a bullet onto a continuation line — rewrite the file,
and re-run until it prints `✓`. Only then proceed to step 5.

## 5. Stage, commit, and push

1. If there are unstaged changes the user likely wants included, stage them with `git add` targeting specific files — never `git add -A` blindly. Ask the user if it is ambiguous which files to include.
2. Show the composed message to the user for confirmation before running `git commit`.
3. Run `git commit [--no-verify] -F /tmp/commit_msg.txt` — commit the exact file you validated in step 4a (never retype the message in a heredoc, which can silently reintroduce a too-long line). Include `--no-verify` only if the user requested it in step 0.
4. Run `git push origin HEAD` to push the branch to the remote.
5. Report the resulting commit hash, one-line summary, and push status.

## 6. Tag (optional)

After reporting the commit result, ask:

> "Do you want to create a git tag for this commit? (yes / no) [default: no]"

- If **no** (or the user presses Enter without input): skip this step entirely.
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
