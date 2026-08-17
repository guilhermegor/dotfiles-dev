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
      commits(last:1) {
        nodes {
          commit {
            statusCheckRollup {
              contexts(first:100) {
                nodes {
                  __typename
                  ... on CheckRun { name status }
                }
              }
            }
          }
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

	# ⚠️ FAIL CLOSED on an unreadable answer. This used to `exit 0` when the query failed, so
	# during a GitHub outage the guard was silently ABSENT — indistinguishable from "nothing to
	# do", which is the exact blindness it exists to remove. Measured 2026-08-17: a run of
	# HTTP 503s swallowed a thread reply, and the thread then sat resolved with no reasoning
	# recorded. Retry a few times first, because a single 503 is normal and blocking on one
	# would cry wolf.
	local attempt
	threads=""
	for attempt in 1 2 3; do
		threads="$(gh api graphql -f query="$(read_query)" \
			-F owner="$owner" -F repo="$name" -F number="$number" 2>/dev/null)" || threads=""
		printf '%s' "$threads" | jq -e '.data.repository.pullRequest.reviewThreads' \
			>/dev/null 2>&1 && break
		threads=""
		sleep $((attempt * 3))
	done
	if [[ -z "$threads" ]]; then
		{
			echo "PR #${number}: could NOT read the review threads (GitHub API unreachable after"
			echo "3 attempts) — so their state is UNKNOWN, not clean."
			echo
			echo "Do not report this PR as finished on the strength of a check that never ran."
			echo "Re-read the threads when the API answers again."
		} >&2
		exit 2
	fi

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

	# ⚠️ "Zero open threads" is only a VERDICT once the reviewers have finished. While a check is
	# still running the reading is a SNAPSHOT: measured on blueprintx#186, threads read 0 and a
	# CodeRabbit re-review opened SIX new ones thirty seconds later — and the turn had already
	# been reported as clean. Nothing re-runs the CI gate on a resolve either, so waiting is the
	# only thing that turns the snapshot into an answer. Cheap, self-clearing, and it also
	# enforces the ordinary rule that a PR is not "done" while its checks are mid-flight.
	local running
	running="$(printf '%s' "$threads" | jq -r '
		[.data.repository.pullRequest.commits.nodes[0].commit.statusCheckRollup.contexts.nodes[]?
		 | select(.__typename == "CheckRun" and .status != "COMPLETED") | .name]
		| join(", ")' 2>/dev/null)"

	if [[ -z "$problems" && -n "$running" ]]; then
		{
			echo "PR #${number}: every review thread is answered and resolved RIGHT NOW, but"
			echo "checks are still running — so that reading is a snapshot, not a verdict."
			echo
			echo "  still running: ${running}"
			echo
			echo "A reviewer bot posts its findings when its own check finishes. Wait for the"
			echo "checks to go terminal and re-read the threads before reporting this PR as clean."
		} >&2
		exit 2
	fi

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
