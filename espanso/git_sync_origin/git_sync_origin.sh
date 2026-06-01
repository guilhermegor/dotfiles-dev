#!/usr/bin/env bash
# git_sync_origin.sh - Sync all local tracking branches to match origin.
# Fast-forwards branches that are only behind. Deletes local branches whose
# remote was removed — when they have no commits absent from every remote, or
# when their entire diff is already in the default branch (squash/rebase merge).
# Branches that still carry genuinely unmerged work are never touched.

set -euo pipefail

ensure_git_repository() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Not inside a git repository."
    exit 1
  }

  local git_dir
  git_dir="$(git rev-parse --git-dir)"
  if [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ] \
      || [ -f "$git_dir/MERGE_HEAD" ] || [ -f "$git_dir/CHERRY_PICK_HEAD" ]; then
    echo "Git operation in progress (merge/rebase/cherry-pick). Resolve it first."
    exit 1
  fi
}

count_commits_not_on_any_remote() {
  local branch="$1"
  local count
  count=$(git rev-list --count "$branch" --not --remotes 2>/dev/null || echo "0")
  echo "$count"
}

detect_default_branch() {
  if git show-ref --verify --quiet refs/remotes/origin/master 2>/dev/null; then
    echo "master"
  elif git show-ref --verify --quiet refs/remotes/origin/main 2>/dev/null; then
    echo "main"
  else
    echo ""
  fi
}

# True when the branch's entire net diff is already contained in the default
# branch, even if its commits were rewritten on merge (squash or rebase) and so
# carry new SHAs. count_commits_not_on_any_remote() compares by commit identity
# and therefore cannot see this; here we synthesise a single commit holding the
# branch's whole diff (its tree on top of the merge-base) and ask git cherry
# whether an equivalent patch already lives in the default branch — a squash
# merge produced exactly that patch, so the patch-ids match and cherry marks it
# with a leading "-".
is_merged_into_default() {
  local branch="$1" default_ref="$2"
  [ -n "$default_ref" ] || return 1

  local merge_base tree synthetic cherry
  merge_base=$(git merge-base "$default_ref" "$branch" 2>/dev/null) || return 1
  tree=$(git rev-parse "$branch^{tree}" 2>/dev/null) || return 1
  synthetic=$(git commit-tree "$tree" -p "$merge_base" -m _ 2>/dev/null) || return 1
  cherry=$(git cherry "$default_ref" "$synthetic" 2>/dev/null) || return 1

  [ "${cherry:0:1}" = "-" ]
}

ensure_git_repository

current_branch="$(git branch --show-current)"

echo "Fetching origin..."
git fetch origin --prune
echo ""

default_branch_name=$(detect_default_branch)
default_ref=""
[ -n "$default_branch_name" ] && default_ref="origin/$default_branch_name"

deleted=()
deleted_squashed=()
updated=()
skipped_unpushed=()
skipped_diverged=()
skipped_current_dirty=()
already_in_sync=()
no_upstream=()

mapfile -t local_branches < <(git branch --format='%(refname:short)')

for branch in "${local_branches[@]}"; do
  upstream=$(git for-each-ref --format='%(upstream:short)' "refs/heads/$branch")

  if [ -z "$upstream" ]; then
    squashed=0
    unpushed_count=$(count_commits_not_on_any_remote "$branch")
    if [ "$unpushed_count" -gt 0 ]; then
      if is_merged_into_default "$branch" "$default_ref"; then
        squashed=1
      else
        no_upstream+=("$branch ($unpushed_count unpushed commit(s), no upstream)")
        continue
      fi
    fi

    if [ "$branch" = "$current_branch" ]; then
      if [ -z "$default_branch_name" ]; then
        no_upstream+=("$branch (current branch, no upstream — could not detect default branch)")
        continue
      fi
      git checkout "$default_branch_name"
      current_branch="$default_branch_name"
    fi

    git branch -D "$branch"
    if [ "$squashed" -eq 1 ]; then
      deleted_squashed+=("$branch")
    else
      deleted+=("$branch")
    fi
    continue
  fi

  remote_exists=0
  git show-ref --verify --quiet "refs/remotes/$upstream" 2>/dev/null && remote_exists=1

  if [ "$remote_exists" -eq 0 ]; then
    squashed=0
    unpushed_count=$(count_commits_not_on_any_remote "$branch")
    if [ "$unpushed_count" -gt 0 ]; then
      if is_merged_into_default "$branch" "$default_ref"; then
        squashed=1
      else
        skipped_unpushed+=("$branch ($unpushed_count unpushed commit(s), remote deleted)")
        continue
      fi
    fi

    if [ "$branch" = "$current_branch" ]; then
      if [ -z "$default_branch_name" ]; then
        skipped_unpushed+=("$branch (current branch, remote deleted — could not detect default branch)")
        continue
      fi
      git checkout "$default_branch_name"
      current_branch="$default_branch_name"
    fi

    git branch -D "$branch"
    if [ "$squashed" -eq 1 ]; then
      deleted_squashed+=("$branch")
    else
      deleted+=("$branch")
    fi
    continue
  fi

  behind=$(git rev-list --count "${branch}..${upstream}" 2>/dev/null || echo "0")
  ahead=$(git rev-list --count "${upstream}..${branch}" 2>/dev/null || echo "0")

  if [ "$ahead" -gt 0 ]; then
    skipped_diverged+=("$branch ($ahead unpushed commit(s), $behind behind origin)")
    continue
  fi

  if [ "$behind" -eq 0 ]; then
    already_in_sync+=("$branch")
    continue
  fi

  if [ "$branch" = "$current_branch" ]; then
    if [ -n "$(git status --porcelain)" ]; then
      skipped_current_dirty+=("$branch (working tree not clean)")
      continue
    fi
    git pull --ff-only origin "$branch"
  else
    git branch -f "$branch" "$upstream"
  fi
  updated+=("$branch")
done

echo "========================================"
echo "Sync summary"
echo "========================================"

if [ "${#updated[@]}" -gt 0 ]; then
  echo ""
  echo "Updated (${#updated[@]}):"
  for b in "${updated[@]}"; do echo "  + $b"; done
fi

if [ "${#deleted[@]}" -gt 0 ]; then
  echo ""
  echo "Deleted — remote removed (${#deleted[@]}):"
  for b in "${deleted[@]}"; do echo "  - $b"; done
fi

if [ "${#deleted_squashed[@]}" -gt 0 ]; then
  echo ""
  echo "Deleted — squash-merged into ${default_branch_name:-default} (${#deleted_squashed[@]}):"
  for b in "${deleted_squashed[@]}"; do echo "  - $b"; done
fi

if [ "${#no_upstream[@]}" -gt 0 ]; then
  echo ""
  echo "Local only — no upstream (${#no_upstream[@]}):"
  for b in "${no_upstream[@]}"; do echo "  ? $b"; done
fi

if [ "${#already_in_sync[@]}" -gt 0 ]; then
  echo ""
  echo "Already in sync (${#already_in_sync[@]}):"
  for b in "${already_in_sync[@]}"; do echo "  = $b"; done
fi

skipped_total=$(( ${#skipped_unpushed[@]} + ${#skipped_diverged[@]} + ${#skipped_current_dirty[@]} ))
if [ "$skipped_total" -gt 0 ]; then
  echo ""
  echo "Skipped — action required ($skipped_total):"
  if [ "${#skipped_unpushed[@]}" -gt 0 ]; then
    for b in "${skipped_unpushed[@]}"; do echo "  ! $b"; done
  fi
  if [ "${#skipped_diverged[@]}" -gt 0 ]; then
    for b in "${skipped_diverged[@]}"; do echo "  ! $b"; done
  fi
  if [ "${#skipped_current_dirty[@]}" -gt 0 ]; then
    for b in "${skipped_current_dirty[@]}"; do echo "  ! $b"; done
  fi
fi
