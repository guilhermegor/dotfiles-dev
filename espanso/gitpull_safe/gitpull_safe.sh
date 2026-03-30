#!/usr/bin/env bash
# gitpull_safe.sh - Safely update local main from origin/main, optionally create a branch or reset the current branch to main.

set -euo pipefail

BRANCH_CONVENTION='^(feature|feat|bugfix|fix|hotfix|release|docs|refactor|chore)/[a-z0-9][a-z0-9.-]*$'

print_branch_hint() {
  echo "Branch naming convention: <purpose>/<branch-task>"
  echo "Purposes: feature|feat, bugfix|fix, hotfix, release, docs, refactor, chore"
  echo "Examples: feat/user-authentication, fix/login-validation-issue, docs/update-api-reference"
}

is_valid_branch_name() {
  local branch_name="$1"
  [[ "$branch_name" =~ $BRANCH_CONVENTION ]]
}

print_usage() {
  echo "Usage: $(basename "$0") [branch-name] [--force-invalid]"
  echo "       $(basename "$0") --reset-current-branch-to-main"
}

ensure_git_repository_state() {
  # Must be inside a git repo.
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Not inside a git repository."
    exit 1
  }

  # Stop if there are uncommitted or untracked changes.
  if [ -n "$(git status --porcelain)" ]; then
    echo "Working tree is not clean. Commit/stash/discard changes first."
    git status --short
    exit 1
  fi

  # Stop if a merge/rebase/cherry-pick is in progress.
  git_dir="$(git rev-parse --git-dir)"
  if [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ] || [ -f "$git_dir/MERGE_HEAD" ] || [ -f "$git_dir/CHERRY_PICK_HEAD" ]; then
    echo "Git operation in progress (merge/rebase/cherry-pick). Resolve it first."
    exit 1
  fi
}

sync_main_branch() {
  git fetch origin --prune
  git switch main
  git pull --ff-only origin main
  echo "Local main is now up to date with origin/main."
}

force_invalid=0
branch_name=""
reset_current_branch_to_main=0

for arg in "$@"; do
  case "$arg" in
    --force-invalid)
      force_invalid=1
      ;;
    --reset-current-branch-to-main)
      reset_current_branch_to_main=1
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      if [ -z "$branch_name" ]; then
        branch_name="$arg"
      else
        echo "Unexpected argument: $arg"
        print_usage
        exit 1
      fi
      ;;
  esac
done

if [ "$reset_current_branch_to_main" -eq 1 ] && [ -n "$branch_name" ]; then
  echo "Cannot combine a branch name with --reset-current-branch-to-main."
  print_usage
  exit 1
fi

ensure_git_repository_state

if [ "$reset_current_branch_to_main" -eq 1 ]; then
  current_branch="$(git branch --show-current)"

  if [ -z "$current_branch" ]; then
    echo "Detached HEAD is not supported for --reset-current-branch-to-main."
    exit 1
  fi

  sync_main_branch

  if [ "$current_branch" = "main" ]; then
    echo "Current branch is already main. Nothing else to reset."
    exit 0
  fi

  git switch "$current_branch"
  git reset --hard main
  echo "Reset branch '$current_branch' to match main without deleting the branch."
  exit 0
fi

sync_main_branch

# Optional: create a new branch if argument is passed.
if [ -n "$branch_name" ]; then
  if ! is_valid_branch_name "$branch_name"; then
    echo "Invalid branch name: $branch_name"
    print_branch_hint

    if [ "$force_invalid" -eq 1 ]; then
      echo "Validation skipped with --force-invalid. Creating branch anyway."
    elif [ -t 0 ]; then
      read -r -p "Create this branch anyway? (y/N): " answer
      case "$answer" in
        y|Y|yes|YES)
          echo "Validation skipped by user confirmation."
          ;;
        *)
          echo "Branch creation cancelled."
          exit 1
          ;;
      esac
    else
      echo "To create it anyway, rerun with --force-invalid."
      exit 1
    fi
  fi

  git switch -c "$branch_name"
  echo "Created and switched to new branch: $branch_name"
fi
