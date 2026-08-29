#!/bin/bash
# Shared review-thread gate: ONE implementation of "is this PR's review done?",
# extracted from open_review_threads_nudge.sh (dotfiles-dev#167) so a second
# caller (the SubagentStop board sweep) calls the SAME gate instead of
# re-deriving the verdict. blueprintx measured what re-deriving costs: its
# sweep re-implemented review-thread logic, inherited the gate's own bug PLUS
# a new one of its own (matched a bare `thread` substring inside a sentence
# that meant the opposite, misreporting 27 PRs clean). One implementation,
# called from both places, cannot drift from itself.
#
# Generic across repos: takes owner/repo/number/roster-file as arguments,
# nothing hardcoded. Callers are responsible for `cd` into the repo whose
# `.review-bots.yaml` (if any) should apply — this file reads it as a plain
# relative path, matching the convention the roster file itself established.
#
# Contract: call `gate_pr_thread_state OWNER REPO NUMBER [ROSTER_FILE]`.
# It sets two globals and returns nothing meaningful (check GATE_STATUS):
#   GATE_STATUS = clean | problems | running | unreadable
#   GATE_DETAIL = human-readable multi-line detail (empty when clean)
# shellcheck disable=SC2034 # both are read by every caller after the call returns
set -u

_gate_min_reply_chars=100

_gate_query() {
	cat <<'GRAPHQL'
query($owner:String!, $repo:String!, $number:Int!) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$number) {
      reviewThreads(first:100) {
        totalCount
        nodes {
          isResolved
          path
          comments(first:50) { totalCount nodes { author { login __typename } body } }
        }
      }
      commits(last:1) {
        nodes {
          commit {
            statusCheckRollup {
              contexts(first:100) {
                totalCount
                nodes {
                  __typename
                  ... on CheckRun {
                    name
                    status
                    checkSuite { app { slug } }
                  }
                  ... on StatusContext {
                    context
                    state
                    creator { login }
                  }
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
_gate_roster_logins() {
	local roster_file="$1"
	if [ -n "$roster_file" ] && [ -f "$roster_file" ]; then
		sed -n 's/^[[:space:]]*-[[:space:]]*login:[[:space:]]*//p' "$roster_file" \
			| sed 's/\[bot\]$//' | sed '/^$/d'
		return 0
	fi
	# No roster: fall back to treating any bot account as a reviewer, resolved per comment in the
	# jq filter below via `author.__typename == "Bot"` (GraphQL strips `[bot]`, so a suffix test
	# on this path matches nothing and every bot reply would misread as human).
	printf '__NO_ROSTER__\n'
}

gate_pr_thread_state() {
	local owner="$1" repo="$2" number="$3" roster_file="${4:-.review-bots.yaml}"
	local threads roster problems truncated running
	GATE_STATUS="unreadable"
	GATE_DETAIL="could not reach the GitHub API"

	local attempt attempts=3
	threads=""
	for attempt in $(seq 1 "$attempts"); do
		threads="$(gh api graphql -f query="$(_gate_query)" \
			-F owner="$owner" -F repo="$repo" -F number="$number" 2>/dev/null)" || threads=""
		# GraphQL answers 200 with a PARTIAL body: `errors` alongside a half-filled `data`.
		# Accepting that reads a truncated thread list as the whole truth.
		if printf '%s' "$threads" | jq -e '
			(.errors | not) and (.data.repository.pullRequest.reviewThreads != null)
		' >/dev/null 2>&1; then
			break
		fi
		threads=""
		[ "$attempt" -lt "$attempts" ] && sleep $((attempt * 3))
	done
	if [ -z "$threads" ]; then
		GATE_STATUS="unreadable"
		GATE_DETAIL="review threads unreadable after $attempts attempts — state unknown, not clean"
		return 0
	fi

	roster="$(_gate_roster_logins "$roster_file")"

	problems="$(printf '%s' "$threads" | jq -r \
		--argjson min "$_gate_min_reply_chars" \
		--arg roster "$roster" '
		($roster | split("\n") | map(select(length > 0))) as $bots
		| .data.repository.pullRequest.reviewThreads.nodes[]
		| . as $t
		| ($t.comments.nodes
		   | map(select(
		       (if ($bots | index("__NO_ROSTER__"))
		        then ((.author.__typename // "") != "Bot")
		        else ($bots | index(.author.login // "") | not) end)
		       and ((.body // "" | length) >= $min)))
		   | length) as $answers
		| if $answers == 0 then
		    "  \($t.path // "?"): needs a REPLY (and then a resolve)"
		  elif ($t.isResolved | not) then
		    "  \($t.path // "?"): replied — still needs RESOLVING"
		  else empty end
	' 2>/dev/null)"

	# ⚠️ A single page is not the whole PR — a dropped thread reads exactly like an absent one.
	truncated="$(printf '%s' "$threads" | jq -r '
		.data.repository.pullRequest.reviewThreads as $rt
		| [ (if ($rt.totalCount // 0) > ($rt.nodes | length) then
		       "  UNREADABLE: \($rt.totalCount) review threads exist, only \($rt.nodes | length) fit one page"
		     else empty end),
		    ($rt.nodes[]
		     | select((.comments.totalCount // 0) > (.comments.nodes | length))
		     | "  UNREADABLE: \(.path // "?"): \(.comments.totalCount) comments, only \(.comments.nodes | length) read") ]
		| join("\n")' 2>/dev/null)"
	[ -n "$truncated" ] && problems="$(printf '%s\n%s' "$truncated" "$problems")"

	# Reviewer checks (CheckRun or StatusContext) still running, minus the repo's own CI app.
	running="$(printf '%s' "$threads" | jq -r --arg roster "$roster" '
		($roster | split("\n") | map(select(length > 0)) | map(ascii_downcase)
		 | map(select(. != "github-actions"))) as $bots
		| (.data.repository.pullRequest.commits.nodes[0].commit.statusCheckRollup.contexts) as $c
		| ([$c.nodes[]?
		   | if .__typename == "CheckRun" then
		       select(.status != "COMPLETED")
		       | select(($bots | index((.checkSuite.app.slug // "") | ascii_downcase)) != null)
		       | .name
		     elif .__typename == "StatusContext" then
		       select(.state == "PENDING" or .state == "EXPECTED")
		       | select(($bots | index((.creator.login // "") | ascii_downcase)) != null)
		       | .context
		     else empty end]
		   + (if ($c.totalCount // 0) > ($c.nodes | length)
		      then ["\($c.totalCount - ($c.nodes | length)) further check(s) this page could not read"]
		      else [] end))
		| join(", ")' 2>/dev/null)"

	if [ -n "$problems" ]; then
		GATE_STATUS="problems"
		GATE_DETAIL="$problems"
	elif [ -n "$running" ]; then
		GATE_STATUS="running"
		GATE_DETAIL="$running"
	else
		GATE_STATUS="clean"
		GATE_DETAIL=""
	fi
}
