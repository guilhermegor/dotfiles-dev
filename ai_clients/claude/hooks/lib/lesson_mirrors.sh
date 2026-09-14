#!/bin/bash
# Shared lesson-mirror definitions (dotfiles-dev#386) — sourced by BOTH
# session_capture_audit.sh (the checker) and generate_lesson_mirrors.sh (the
# generator), so the store list, the mirror's on-disk path, and the "did this
# lesson originate in this repo?" predicate live in exactly ONE place. Two
# hand-written copies of the same join rule is the drift class this file
# closes — a change here changes what both the checker and the generator
# agree on, together, always.
#
# Kept dependency-free and side-effect-free (only defines vars/functions, no
# I/O, no `set -e`) so sourcing it can never fail a caller that must never
# fail a session (session_capture_audit.sh's own contract).

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# All generalizable-lessons stores, each as "dir|mirror-basename|kind|target-repo".
# target-repo is the store's backport target: a lesson that ORIGINATED in that
# repo needs no mirror there (the mirror would be redundant), so
# mirror_expected_for_repo() below skips it. target-repo "-" (lessons-other,
# dotfiles-dev#356) is a sentinel, not a repo name: that store has no distinct
# backport target at all, so it never gets a mirror anywhere.
# Used by every file that sources this lib (session_capture_audit.sh,
# generate_lesson_mirrors.sh) — shellcheck can't see those callers.
# shellcheck disable=SC2034
LESSON_STORES=(
	"$CLAUDE_DIR/memory/lessons|blueprintx-lessons|blueprintx|blueprintx"
	"$CLAUDE_DIR/memory/lessons-dotfiles|dotfiles-dev-lessons|dotfiles|dotfiles-dev"
	"$CLAUDE_DIR/memory/lessons-other|lessons-other|other|-"
)

# A store's mirror path, relative to a repo's root — the ONE construction site
# (dotfiles-dev#386) instead of the "$cwd/docs/$mirror_base.md" string that used
# to be hand-typed in five separate files. Lives under .specs/ (not docs/): the
# mirror is a derived, git-ignored working artifact, not shipped documentation
# — see .specs/CLAUDE.md.
mirror_rel_path() {
	local mirror_base="$1"
	printf '.specs/lessons/%s.md\n' "$mirror_base"
}

# Absolute mirror path for repo checkout $cwd.
mirror_path() {
	local cwd="$1" mirror_base="$2"
	printf '%s/%s\n' "$cwd" "$(mirror_rel_path "$mirror_base")"
}

# Does a store need a mirror inside $repo at all? Same-repo-as-target and the
# "-" sentinel are both "no distinct backport target" cases — never expect a
# mirror either way (dotfiles-dev#356, #386).
mirror_expected_for_repo() {
	local target_repo="$1" repo="$2"
	[ "$target_repo" = "-" ] && return 1
	[ "$target_repo" = "$repo" ] && return 1
	return 0
}

# Does $file (a lesson in some store) name $repo on its **Origin:** line? The
# ONE predicate both check_mirrors() and the generator use to decide which
# lessons belong in a given repo's mirror (bullet optional: the stores use
# both "- **Origin:**" and a bare "**Origin:**").
lesson_originates_in_repo() {
	local file="$1" repo="$2"
	grep -qiE "^[[:space:]]*([-*][[:space:]]+)?\*\*Origin:\*\*.*\b${repo}\b" "$file"
}
