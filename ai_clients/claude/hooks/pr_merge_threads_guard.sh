#!/bin/bash
# PreToolUse (Bash matcher) hook: refuse `gh pr merge` while any review thread is unanswered or
# unresolved. Queries GitHub LIVE, at the moment of merging.
#
# Why a hook and not a rule: the rule already existed, in prose, in three places, and was
# violated anyway. blueprintx PR #180 merged with two review threads open and unanswered, and
# every visible signal said it was fine. The failure needs no carelessness — it is structural:
#
#   1. CI evaluates review threads on `pull_request`, which fires WHEN YOU PUSH. A reviewer
#      posting after your last push does not re-trigger it, so the green check is a conclusion
#      about a PR state that no longer exists. A stale check looks exactly like a passing one.
#   2. A reviewer bot resolves its OWN threads on seeing the fix, so `isResolved` records the
#      bot's satisfaction rather than the author's reasoning — the reply can be missing while
#      everything reads closed.
#   3. Whoever merges is the same person who would have to remember to re-check. Any rule of the
#      form "remember to look again just before merging" is exactly the kind that fails.
#
# So this fires at the only moment that cannot go stale: immediately before the merge call.
# It is the LAST of three layers, each covering what the others cannot —
#   - GitHub's `required_conversation_resolution` ruleset: server-side, live, but enforces only
#     the RESOLVE half; it cannot tell a reply from silence.
#   - the repo's CI gate: checks both halves, but only when something re-triggers it.
#   - this guard: both halves, live, on the merge itself.
#
# Hook I/O contract: PreToolUse exit 2 BLOCKS the call and feeds stderr back to the model.
# It fails OPEN on anything it cannot resolve (no gh, no jq, no network, no PR, a PR in another
# repo) — a guard that blocks on its own blindness gets disabled, and then protects nothing.

set -u

command -v jq >/dev/null 2>&1 || exit 0
command -v gh >/dev/null 2>&1 || exit 0

# Prefixing the command makes the guard stand aside, for the rare deliberate case:
#   ALLOW_UNRESOLVED_THREADS=1 gh pr merge 123 --squash
ESCAPE_HATCH='ALLOW_UNRESOLVED_THREADS=1'

# Floor for a "substantive" reply, matching the repo-side gate: excludes "done" / "fixed"
# without ever arguing with a real answer.
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

# Reviewer logins whose comments are FINDINGS, never answers.
#
# ⚠️ Normalised WITHOUT the `[bot]` suffix. REST reports `coderabbitai[bot]` and the roster is
# written that way, but GraphQL's `author.login` returns `coderabbitai`. Comparing the two
# spellings literally is what made the repo-side gate silently vacuous for its whole life — it
# reported "all threads answered" on a PR where nobody had replied to anything.
roster_logins() {
	if [ -f "$ROSTER_FILE" ]; then
		sed -n 's/^[[:space:]]*-[[:space:]]*login:[[:space:]]*//p' "$ROSTER_FILE" \
			| sed 's/\[bot\]$//' | sed '/^$/d'
		return 0
	fi
	# No roster: fall back to treating any bot account as a reviewer. GraphQL strips the suffix,
	# so this is resolved per comment in the jq filter below instead.
	printf '__NO_ROSTER__\n'
}

main() {
	local payload tool command number repo owner name threads roster problems

	payload="$(cat)"
	tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"
	[[ "$tool" == "Bash" ]] || exit 0

	command="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
	[[ -n "$command" ]] || exit 0

	# Only `gh pr merge`, with or without the rtk proxy prefix.
	printf '%s' "$command" \
		| grep -Eq '(^|[;&|][[:space:]]*)(rtk[[:space:]]+)?gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)' \
		|| exit 0

	# Explicit opt-out.
	printf '%s' "$command" | grep -q "$ESCAPE_HATCH" && exit 0

	# PR number: explicit argument, else the current branch's PR.
	number="$(printf '%s' "$command" \
		| grep -oE 'gh[[:space:]]+pr[[:space:]]+merge[[:space:]]+[0-9]+' \
		| grep -oE '[0-9]+$')"
	if [ -z "$number" ]; then
		number="$(gh pr view --json number -q .number 2>/dev/null)" || exit 0
	fi
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

	# A thread is FINISHED when it holds a substantive comment from outside the reviewer roster
	# AND is resolved. Anything else is reported, with the reason.
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
		    "  \($t.path // "?"): no reply from anyone outside the reviewer roster"
		  elif ($t.isResolved | not) then
		    "  \($t.path // "?"): replied, but the conversation is still OPEN"
		  else empty end
	' 2>/dev/null)"

	[[ -z "$problems" ]] && exit 0

	{
		echo "BLOCKED: PR #${number} has review threads that are not finished."
		echo
		printf '%s\n' "$problems"
		echo
		echo "A finding takes BOTH halves, and neither implies the other:"
		echo "  1. REPLY with what changed and why — a reviewer bot resolving its own thread"
		echo "     records ITS satisfaction, never your reasoning, and the reasoning is what"
		echo "     the next session reads."
		echo "  2. RESOLVE the conversation once the reply is posted — otherwise nothing"
		echo "     distinguishes a finished exchange from one still in progress."
		echo
		echo "Checked live, because CI evaluates threads on push: a review arriving after your"
		echo "last push leaves that check green while showing a state that no longer exists."
		echo
		echo "Deliberate exception: ${ESCAPE_HATCH} <your command>"
	} >&2
	exit 2
}

main "$@"
