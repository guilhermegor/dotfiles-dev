#!/bin/bash
# Stop hook: refuse to end the turn when the free dispatch surface has
# unclaimed issues and nothing of this session's own is currently working
# them — the deterministic half of s:dev-loop step 6 (DISPATCH), sibling of
# uncommitted_worktree_guard.sh (dotfiles-dev#396).
#
# The owner asked four times why subagents were not dispatched in parallel.
# Two distinct causes, only one of them the model forgetting:
#   1. gate_free_surface itself failed closed on any repo with an orphan
#      branch and the caller read that failure as "nothing to do" — fixed at
#      the gate in #395. This hook is the OTHER half: even a correct gate is
#      still just prose someone has to remember to call.
#   2. DISPATCH lived only in a skill. uncommitted_worktree_guard.sh already
#      proved that a correct, written-down "commit early" rule still gets
#      skipped without a hook enforcing it — same defect, different step.
#
# ⚠️ UNKNOWN is reported loudly, never as routine silence. A gate that fails
# closed (#395) is the right behaviour for the gate; a caller that swallows
# that failure and falls through quiet turns it back into a disabled feature
# nobody can see — the exact shape of cause 1. So an unreadable gate blocks
# too, with its own wording, distinct from "issues are free, dispatch them".
#
# Fires only when the transcript shows this session actually ran s:dev-loop
# AND has no Agent-tool dispatch of its own still unresolved — both read
# from the transcript (data), never inferred from what the session "knows"
# about itself, the same decidability test the skill's own Do Not section
# applies to the (deliberately un-hooked) pre-dispatch budget judgement.
#
# Fails OPEN on everything it cannot resolve (no repo, no transcript, no
# dev-loop evidence) — a guard that blocks on its own blindness gets
# disabled, same rule as every sibling Stop hook here.
set -u

GIT=/usr/bin/git
command -v jq >/dev/null 2>&1 || exit 0
command -v gh >/dev/null 2>&1 || exit 0

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/free_surface.sh
source "$HOOK_DIR/lib/free_surface.sh"

# dev_loop_invoked TRANSCRIPT
# Pure data: did this session's transcript ever call the Skill tool with
# skill "dev-loop"? A session that never ran the loop is not this hook's
# concern — never fire on an unrelated session.
dev_loop_invoked() {
	local transcript="$1"
	[ -r "$transcript" ] || return 1
	grep -qF '"skill":"dev-loop"' "$transcript" 2>/dev/null
}

# subagents_running TRANSCRIPT
# An Agent tool_use with no matching tool_result anywhere later in the
# transcript is still in flight. ponytail: this is a proxy for "is a
# subagent running" (no live process list is readable from a bash hook),
# so it reads "dispatched, no result recorded yet" as running — including
# the one turn between dispatch and the harness appending its result.
# Upgrade path: a real running-agent registry, if the harness ever exposes
# one to hooks.
subagents_running() {
	local transcript="$1"
	[ -r "$transcript" ] || return 1
	local dispatched resolved id
	dispatched="$(jq -r 'select(.message.content != null) | .message.content[]? | select(.type=="tool_use" and .name=="Agent") | .id' "$transcript" 2>/dev/null)"
	[ -n "$dispatched" ] || return 1
	resolved="$(jq -r 'select(.message.content != null) | .message.content[]? | select(.type=="tool_result") | .tool_use_id' "$transcript" 2>/dev/null)"
	while read -r id; do
		[ -n "$id" ] || continue
		printf '%s\n' "$resolved" | grep -qxF "$id" || return 0
	done <<<"$dispatched"
	return 1
}

main() {
	local payload active cwd transcript repo owner name

	payload="$(cat)"

	# Never block a stop that a hook already caused — one nudge per turn.
	active="$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null)"
	[[ "$active" == "true" ]] && exit 0

	cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"
	[ -n "$cwd" ] || cwd="${CLAUDE_PROJECT_DIR:-$PWD}"
	transcript="$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)"
	[ -n "$transcript" ] || exit 0

	$GIT -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

	dev_loop_invoked "$transcript" || exit 0
	subagents_running "$transcript" && exit 0

	repo="$(cd "$cwd" && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"
	[ -n "$repo" ] || exit 0
	owner="${repo%%/*}"
	name="${repo##*/}"

	if ! gate_free_surface "$owner" "$name"; then
		{
			echo "free surface UNREADABLE (gh API failure) — not the same as empty."
			echo
			echo "s:dev-loop step 6 (DISPATCH) cannot tell right now whether there is unclaimed"
			echo "work. Re-run the gate once the API answers, before reporting the board clear —"
			echo "a gate that fails closed and is then read as routine silence is exactly the"
			echo "defect this hook exists to catch (dotfiles-dev#396)."
		} >&2
		exit 2
	fi

	[ -n "$FREE_UNCLAIMED_ISSUES" ] || exit 0

	{
		echo "Free dispatch surface is non-empty and nothing of this session's own is"
		echo "currently working it — do not stop here without dispatching."
		echo
		echo "Unclaimed open issues (no PR, open or merged, closes them):"
		printf '%s\n' "$FREE_UNCLAIMED_ISSUES" | sed 's/^/  #/'
		echo
		echo "Run s:dev-loop step 6 (DISPATCH): classify each issue's files with"
		echo "free_classify_files, confirm it is not already done, then dispatch what is free."
	} >&2
	exit 2
}

main "$@"
