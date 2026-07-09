---
name: s:tutoring-resume
description: Use when the user asks to resume, continue, or pick up tutoring "where we left off" — in plain natural language, not only via /tutoring on. Loads the mandatory discovery sequence that finds in-progress tutoring work before any new curriculum is generated.
effort: medium
argument-hint: [none]
allowed-tools: Read Glob Grep
---

Resume tutoring from in-progress work — never start a fresh curriculum until the
discovery sequence below has failed. Prior tutoring sessions encode the user's chosen
step ordering, completed work, accumulated feedback, and recurring-issue notes;
inventing a new step list silently throws all of that away and forces re-work.

This applies whenever the user asks to "resume tutoring", "continue tutoring", "pick up
where we left off", or anything semantically equivalent — regardless of which slash
command (or none) triggered it, and regardless of the model handling the conversation.
It overrides any default tendency to begin with a clean slate.

## Mandatory discovery sequence (in order)

1. **Project memory file.** Compute the encoded project memory path from the current
   working directory: replace every `/` with `-`, then look under
   `~/.claude/projects/<encoded>/memory/`. If `tutoring_session.md` exists there, read it
   and resume from the step marked `[>]`. Do **not** rewrite it from scratch and do **not**
   invent a new step list.

2. **Active plan file.** If `tutoring_session.md` is missing or empty, scan
   `~/.claude/plans/*.md` for any plan whose body references the current working directory,
   the repo name, or the project's `CLAUDE.md` topic. If one matches, use **its** task/step
   list as the curriculum and resume from the first unchecked item. Linking back to that plan
   in `tutoring_session.md` is fine; replacing its content with an invented parallel list is
   not.

3. **Only if both checks fail** may a fresh curriculum be generated — and only after explicit
   user confirmation ("yes, start from scratch").

The `/tutoring on` command implements this same check in its step 2b; this skill makes the
discipline mandatory for the natural-language path too.
