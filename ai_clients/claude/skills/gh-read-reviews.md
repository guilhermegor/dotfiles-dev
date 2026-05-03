---
name: s:gh-read-reviews
description: Use when a:gh-resolve-reviews needs to fetch all top-level review
  comments from a GitHub pull request — fetches reviews and inline comments via
  gh api, filters out reply threads, and returns a structured Review Report
effort: medium
argument-hint: <pr_number> <repo_owner> <repo_name>
allowed-tools: Bash(rtk gh *)
---

Fetch all top-level review comments for a GitHub pull request.
Follow these steps exactly.

## 1. Receive input

The caller provides:
- `pr_number`: pull request number
- `repo_owner`: repository owner (org or user login)
- `repo_name`: repository name

## 2. Fetch review summaries

```bash
rtk gh api repos/<repo_owner>/<repo_name>/pulls/<pr_number>/reviews \
  --jq '.[] | {id, reviewer: .user.login, state, submitted_at, body}'
```

## 3. Fetch inline review comments

```bash
rtk gh api repos/<repo_owner>/<repo_name>/pulls/<pr_number>/comments \
  --paginate \
  --jq '.[] | {
    id,
    pull_request_review_id,
    reviewer: .user.login,
    path,
    line,
    original_line,
    body,
    in_reply_to_id
  }'
```

Keep only top-level comments: those where `in_reply_to_id` is null.
Discard reply comments (non-null `in_reply_to_id`) — they are part of
existing threads, not new requests that need responses.

## 4. Include PR-level review body comments

For each review from Step 2 that has a non-empty `body`, include it as an
additional comment with `path = null` and `line = null`. These are review
summary comments (e.g. overall architecture feedback), not tied to a line.

## 5. Map review state to each comment

Join each inline comment to its review (via `pull_request_review_id` →
`review.id`) to obtain `review_state` (`CHANGES_REQUESTED`, `COMMENTED`,
or `APPROVED`). Use the same mapping for PR-level body comments.

## 6. Return structured Report

Output this block — the agent reads it directly:

```text
## Review Report

PR: <pr_number>
Total comments: <N>

### Reviews

| Reviewer | State | Submitted |
|----------|-------|-----------|
| @<user> | <state> | <submitted_at> |
...

### Comments

| # | gh_comment_id | Reviewer | File | Line | Review State | Thread ID | Body |
|---|---------------|----------|------|------|--------------|-----------|------|
| 1 | <id> | @<user> | <path or PR-level> | <line or —> | <state> | <pull_request_review_id> | <first 120 chars> |
...
```

Do not surface raw API JSON output to the user.

If no comments are found after filtering, return `Total comments: 0`.
