#!/bin/bash
# Stop hook: refuse to end the turn while the current branch's PR has review threads that are
# not finished — no reply, or replied and still open.
#
# This is the LOOP half, and it is a different job from `pr_merge_threads_guard.sh`.
#
# That guard blocks a bad merge. It is necessary and it is not sufficient, because blocking the
# exit does not drive the work: a reviewer posts findings minutes after a push, the agent has
# already moved on to another task, and nothing brings it back. The threads then sit open until
# a HUMAN notices and asks — which is precisely the dependency being removed. Measured across
# blueprintx PRs #180 and #182: three separate rounds of review findings, each one surfaced by
# the user asking, never by the loop noticing.
#
# A Stop hook is the right shape because "am I done?" is exactly the question whose answer the
# open threads change. Exit 2 feeds stderr back to the model and makes it continue, so the loop
# closes without anyone remembering anything.
#
# ⚠️ `stop_hook_active` MUST be honoured. Claude Code sets it when the stop was itself triggered
# by a hook; ignoring it means blocking the stop that this very hook caused, forever. The model
# gets one nudge per turn, not an inescapable loop.
#
# Fails OPEN on everything it cannot resolve (no gh, no jq, no network, no PR, detached HEAD) —
# a nudge that fires on its own blindness is noise, and noise gets the hook deleted.

set -u

command -v jq >/dev/null 2>&1 || exit 0
command -v gh >/dev/null 2>&1 || exit 0

MIN_REPLY_CHARS=100
ROSTER_FILE='.review-bots.yaml'

read_query() {
	cat <<'GRAPHQL'
query($owner:String!, $repo:String!, $number:Int!) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$number) {
      reviewThreads(first:100) {
        nodes {
          isResolved
          path
          comments(first:50) { nodes { author { login } body } }
        }
      }
    }
  }
}
GRAPHQL
}

# ⚠️ Normalised WITHOUT the `[bot]` suffix: REST reports `coderabbitai[bot]`, GraphQL returns
# `coderabbitai`. Comparing the two literally is what left the repo-side gate silently vacuous.
roster_logins() {
	if [ -f "$ROSTER_FILE" ]; then
		sed -n 's/^[[:space:]]*-[[:space:]]*login:[[:space:]]*//p' "$ROSTER_FILE" \
			| sed 's/\[bot\]$//' | sed '/^$/d'
		return 0
	fi
	printf '__NO_ROSTER__\n'
}

main() {
	local payload active number repo owner name threads roster problems

	payload="$(cat)"

	# Never block a stop that a hook already caused.
	active="$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null)"
	[[ "$active" == "true" ]] && exit 0

	git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

	number="$(gh pr view --json number,state -q 'select(.state=="OPEN") | .number' 2>/dev/null)"
	[[ "$number" =~ ^[0-9]+$ ]] || exit 0

	repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" || exit 0
	owner="${repo%%/*}"
	name="${repo##*/}"
	[[ -n "$owner" && -n "$name" ]] || exit 0

	threads="$(gh api graphql -f query="$(read_query)" \
		-F owner="$owner" -F repo="$name" -F number="$number" 2>/dev/null)" || exit 0
	printf '%s' "$threads" | jq -e '.data.repository.pullRequest.reviewThreads' >/dev/null 2>&1 \
		|| exit 0

	roster="$(roster_logins)"

	problems="$(printf '%s' "$threads" | jq -r \
		--argjson min "$MIN_REPLY_CHARS" \
		--arg roster "$roster" '
		($roster | split("\n") | map(select(length > 0))) as $bots
		| .data.repository.pullRequest.reviewThreads.nodes[]
		| . as $t
		| ($t.comments.nodes
		   | map(select(
		       ((.author.login // "") as $l
		        | if ($bots | index("__NO_ROSTER__")) then ($l | test("\\[bot\\]$") | not)
		          else ($bots | index($l) | not) end)
		       and ((.body // "" | length) >= $min)))
		   | length) as $answers
		| if $answers == 0 then
		    "  \($t.path // "?"): needs a REPLY (and then a resolve)"
		  elif ($t.isResolved | not) then
		    "  \($t.path // "?"): replied — still needs RESOLVING"
		  else empty end
	' 2>/dev/null)"

	[[ -z "$problems" ]] && exit 0

	{
		echo "PR #${number} still has unfinished review threads — do not stop here."
		echo
		printf '%s\n' "$problems"
		echo
		echo "For each: verify the finding against the code (some are wrong — refute those with"
		echo "measurement), reply with what changed and why, then resolve the conversation."
		echo
		echo "Checked live. The CI check cannot be trusted for this: it is evaluated on push and"
		echo "on new comments, and NOTHING re-runs it when a thread is resolved."
	} >&2
	exit 2
}

main "$@"
