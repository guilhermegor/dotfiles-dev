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

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	echo "review_thread_gate.sh is meant to be sourced, not executed." >&2
	exit 1
fi

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

# The jq program behind `problems`, extracted so tests can run it against a fixture without a
# network round-trip -- same shape as _gate_query() above.
#
# ⚠️ `index()` evaluates its ARGUMENT with `.` bound to index's own input, which here is the
# $bots ARRAY -- not the comment. The same fault sat in _gate_running_filter (`.creator.login`,
# `.checkSuite.app.slug`) and was found only once that filter became reachable from a test. Writing `$bots | index(.author.login)` therefore indexes an
# array with a string, and jq aborts the whole program with exit 5:
#
#     jq: error (at <stdin>:0): Cannot index array with string "author"
#
# Under the workflow's `set -euo pipefail` that killed the step before it could print a verdict,
# so the required check failed with no diagnostic at all. Binding the comment to $c first is what
# keeps the lookup pointed at the comment. The bug was invisible for as long as it existed
# because it needs BOTH a roster file (else the __NO_ROSTER__ branch runs, which never touches
# index()) AND at least one review thread (else `nodes[]` yields nothing and the filter is never
# evaluated) -- every PR gated until PR #325 had zero threads.
_gate_problems_filter() {
	cat <<'JQ'
($roster | split("\n") | map(select(length > 0))) as $bots
| .data.repository.pullRequest.reviewThreads.nodes[]
| . as $t
| ($t.comments.nodes
   | map(. as $c | select(
       (if ($bots | index("__NO_ROSTER__"))
        then (($c.author.__typename // "") != "Bot")
        else ($bots | index($c.author.login // "") | not) end)
       and (($c.body // "" | length) >= $min)))
   | length) as $answers
| if $answers == 0 then
    "  \($t.path // "?"): needs a REPLY (and then a resolve)"
  elif ($t.isResolved | not) then
    "  \($t.path // "?"): replied — still needs RESOLVING"
  else empty end
JQ
}

# The jq program behind `truncated`, extracted for the same reason as _gate_problems_filter:
# a filter a test can reach is a filter a test can break.
_gate_truncated_filter() {
	cat <<'JQ'
.data.repository.pullRequest.reviewThreads as $rt
| [ (if ($rt.totalCount // 0) > ($rt.nodes | length) then
       "  UNREADABLE: \($rt.totalCount) review threads exist, only \($rt.nodes | length) fit one page"
     else empty end),
    ($rt.nodes[]
     | select((.comments.totalCount // 0) > (.comments.nodes | length))
     | "  UNREADABLE: \(.path // "?"): \(.comments.totalCount) comments, only \(.comments.nodes | length) read") ]
| join("\n")
JQ
}

# The jq program behind `running`.
_gate_running_filter() {
	cat <<'JQ'
($roster | split("\n") | map(select(length > 0)) | map(ascii_downcase)
 | map(select(. != "github-actions"))) as $bots
| (.data.repository.pullRequest.commits.nodes[0].commit.statusCheckRollup.contexts) as $c
| ([$c.nodes[]?
   | . as $n
   | if $n.__typename == "CheckRun" then
       select($n.status != "COMPLETED")
       | select(($bots | index(($n.checkSuite.app.slug // "") | ascii_downcase)) != null)
       | $n.name
     elif $n.__typename == "StatusContext" then
       select($n.state == "PENDING" or $n.state == "EXPECTED")
       | select(($bots | index(($n.creator.login // "") | ascii_downcase)) != null)
       | $n.context
     else empty end]
   + (if ($c.totalCount // 0) > ($c.nodes | length)
      then ["\($c.totalCount - ($c.nodes | length)) further check(s) this page could not read"]
      else [] end))
| join(", ")
JQ
}

# _gate_run_jq JSON FILTER ERRFILE [jq args...]
# Run FILTER over JSON, echo jq's stdout, return jq's exit status, and leave jq's stderr in
# ERRFILE -- a path the CALLER owns, because a command substitution runs in a subshell and the
# helper cannot hand the text back through a variable.
#
# ⚠️ Returning the status is the entire point. `jq ... 2>/dev/null` with the status discarded
# turns a program ABORT into empty output, and empty output is exactly what "nothing to report"
# looks like -- so a crashed filter reaches the `clean` branch (dotfiles-dev#331). Measured on
# the #329 bug: under the workflow's `set -euo pipefail` the step died with a bare `exit code 5`,
# but called from a hook -- neither hook caller uses `set -e` -- the same broken filter returned
# GATE_STATUS=clean. The `set -e` was an accident of one caller, never a property of this gate.
_gate_run_jq() {
	local json="$1" filter="$2" errfile="$3"
	shift 3
	printf '%s' "$json" | jq -r "$@" "$filter" 2>"$errfile"
}

# Record the unreadable verdict for a filter that aborted, carrying jq's own words so the failure
# is diagnosable from the check output instead of needing a bisect -- #329 took one.
_gate_filter_aborted() {
	local errfile="$1" which="$2" detail
	detail="$(head -1 "$errfile" 2>/dev/null)"
	rm -f "$errfile"
	GATE_STATUS="unreadable"
	GATE_DETAIL="the $which filter aborted -- state unknown, not clean${detail:+: $detail}"
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

	local jq_err
	jq_err="$(mktemp)"

	problems="$(_gate_run_jq "$threads" "$(_gate_problems_filter)" "$jq_err" \
		--argjson min "$_gate_min_reply_chars" --arg roster "$roster")" || {
		_gate_filter_aborted "$jq_err" "thread"
		return 0
	}

	# ⚠️ A single page is not the whole PR — a dropped thread reads exactly like an absent one.
	truncated="$(_gate_run_jq "$threads" "$(_gate_truncated_filter)" "$jq_err")" || {
		_gate_filter_aborted "$jq_err" "truncation"
		return 0
	}
	[ -n "$truncated" ] && problems="$(printf '%s\n%s' "$truncated" "$problems")"

	# Reviewer checks (CheckRun or StatusContext) still running, minus the repo's own CI app.
	running="$(_gate_run_jq "$threads" "$(_gate_running_filter)" "$jq_err" --arg roster "$roster")" || {
		_gate_filter_aborted "$jq_err" "running-checks"
		return 0
	}

	rm -f "$jq_err"

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
