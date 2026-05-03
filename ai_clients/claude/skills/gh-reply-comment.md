---
name: s:gh-reply-comment
description: Use when a:gh-resolve-reviews needs to post a reply to a specific
  pull request review comment thread via the GitHub REST API
effort: low
argument-hint: <repo_owner> <repo_name> <pr_number> <comment_id> <reply_text>
allowed-tools: Bash(rtk gh *)
---

Post a reply to a GitHub pull request review comment thread.
Follow these steps exactly.

## 1. Receive input

The caller provides:
- `repo_owner`: repository owner
- `repo_name`: repository name
- `pr_number`: pull request number
- `comment_id`: the GitHub comment ID to reply to — this is the
  `gh_comment_id` of the top-level comment in the thread (stored in
  `review_comments.gh_comment_id`)
- `reply_text`: the reply body (must be non-empty)

## 2. Validate

If `reply_text` is empty or whitespace-only, return:
```
Error: reply_text must not be empty — no reply posted.
```
and stop.

## 3. Post the reply

```bash
rtk gh api \
  repos/<repo_owner>/<repo_name>/pulls/<pr_number>/comments/<comment_id>/replies \
  --method POST \
  --field body="<reply_text>"
```

## 4. Return result

Extract the `id` field from the JSON response — this is the new reply's
GitHub comment ID.

Return:

```text
## Reply posted

Thread comment: <comment_id>
New reply ID:   <new_reply_id>
```

If the API call fails (non-zero exit or error field in the response body),
return:

```text
Error: Failed to post reply to comment <comment_id>
<error message from gh>
```

Do not retry on failure — report the error and let the caller decide.
