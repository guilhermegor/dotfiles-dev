#!/usr/bin/env bash
# gitpull_safe.sh - Safely update local main from origin/main, optionally create a branch.

set -euo pipefail

# 1) Must be inside a git repo
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "Not inside a git repository."
  exit 1
}

# 2) Stop if there are uncommitted or untracked changes
if [ -n "$(git status --porcelain)" ]; then
  echo "Working tree is not clean. Commit/stash/discard changes first."
  git status --short
  exit 1
fi

# 3) Stop if a merge/rebase/cherry-pick is in progress
git_dir="$(git rev-parse --git-dir)"
if [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ] || [ -f "$git_dir/MERGE_HEAD" ] || [ -f "$git_dir/CHERRY_PICK_HEAD" ]; then
  echo "Git operation in progress (merge/rebase/cherry-pick). Resolve it first."
  exit 1
fi

# 4) Update and switch to main
git fetch origin --prune
git switch main

# 5) Pull latest safely
git pull --ff-only origin main

echo "Local main is now up to date with origin/main."

# 6) Optional: create a new branch if argument is passed
if [ "${1:-}" != "" ]; then
  git switch -c "$1"
  echo "Created and switched to new branch: $1"
fi
