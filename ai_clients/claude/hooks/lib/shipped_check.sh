#!/bin/bash
# ai_clients/claude/hooks/lib/shipped_check.sh
#
# Shared "was this already shipped" gate for s:intake-shipped (dotfiles-dev#427,
# parent #422). Same contract shape as review_thread_gate.sh / roadmap_unblock.sh:
# one function, two globals, fail-closed on any read error.
#
# Why a script and not a prose-only skill: the two measured failures (blueprintx,
# 2026-09-20) were both mechanical, not judgment calls. (1) PR #509 shipped #355's
# content and merged with closingIssuesReferences = [] -- the GitHub link is
# reliable evidence of PRESENCE, never of absence, so it can only ever be
# supplementary. (2) Two branches sat 5 and 2 commits ahead of origin/main,
# indistinguishable by ancestry/diff/ls-remote from real unrescued work; a single
# content probe against origin/master settled both instantly. What this script
# does NOT decide: which paths/symbols a given issue actually promises -- that
# extraction is s:intake-shipped's job, never hardcoded here.
#
# Contract: call `shipped_check ISSUE_NUM OWNER/REPO DELIVERABLE [DELIVERABLE...]`
# A DELIVERABLE is a path (existence probe) or `path::pattern` (grep the path's
# origin/master content for an extended regex -- e.g. a gate wired into a CI yaml,
# not only a file that exists).
# Sets two globals, returns nothing meaningful (check SHIPPED_STATUS):
#   SHIPPED_STATUS = SHIPPED | OPEN | UNKNOWN
#   SHIPPED_DETAIL = evidence: the link check, one PRESENT/MISSING line per
#                    deliverable, and a present/missing tally
# shellcheck disable=SC2034 # both are read by every caller after the call returns
set -u

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "shipped_check.sh is meant to be sourced, not executed." >&2
    exit 1
fi

# _shipped_probe_one DELIVERABLE
# Content-tests one deliverable against origin/master. Never merge-base,
# ls-remote, or diff-emptiness -- see SKILL.md's table for why each of those
# lies about a squash-merged or delete-on-merge branch.
_shipped_probe_one() {
    local deliverable="$1" path pattern
    path="${deliverable%%::*}"
    if [[ "$deliverable" == *"::"* ]]; then
        pattern="${deliverable#*::}"
        if git show "origin/master:$path" 2>/dev/null | grep -qE "$pattern"; then
            echo "PRESENT $path (matches /$pattern/)"
            return 0
        fi
        echo "MISSING $path (no match for /$pattern/)"
        return 1
    fi
    if git cat-file -e "origin/master:$path" 2>/dev/null; then
        echo "PRESENT $path"
        return 0
    fi
    echo "MISSING $path"
    return 1
}

shipped_check() {
    local issue_num="$1" repo="$2"
    shift 2
    local -a deliverables=("$@")
    SHIPPED_STATUS="UNKNOWN"
    SHIPPED_DETAIL=""

    if ! git rev-parse --verify -q origin/master >/dev/null; then
        SHIPPED_DETAIL="origin/master not resolvable locally -- fetch it first"
        return
    fi

    if (( ${#deliverables[@]} == 0 )); then
        SHIPPED_DETAIL="no deliverables supplied -- nothing to content-test"
        return
    fi

    # closingIssuesReferences over is:pr WITHOUT is:open: a merged PR can close
    # the issue with an empty link (measured on #509), so this is supplementary
    # evidence only, reported alongside the content probe -- never the deciding
    # signal, and never restricted to is:open (a merged PR is never "open").
    local link_json
    if ! link_json="$(gh pr list --repo "$repo" --search "$issue_num" --state all \
            --json number,state,closingIssuesReferences --limit 50 2>/dev/null)"; then
        SHIPPED_DETAIL="gh pr list failed -- cannot read link evidence"
        return
    fi
    local linked_merged
    if ! linked_merged="$(jq -r --argjson n "$issue_num" \
            '[.[] | select(.state=="MERGED" and (.closingIssuesReferences[]?.number==$n))][0].number // empty' \
            <<<"$link_json" 2>/dev/null)"; then
        SHIPPED_DETAIL="jq could not parse gh pr list output"
        return
    fi

    local present=0 missing=0 lines="" d line
    for d in "${deliverables[@]}"; do
        if line="$(_shipped_probe_one "$d")"; then
            present=$((present + 1))
        else
            missing=$((missing + 1))
        fi
        lines+="$line"$'\n'
    done

    local link_note="no merged PR linked this issue via closingIssuesReferences"
    [[ -n "$linked_merged" ]] && link_note="merged PR #$linked_merged links this issue via closingIssuesReferences"

    if (( missing == 0 )); then
        SHIPPED_STATUS="SHIPPED"
    else
        # Present > 0 here is "partially shipped (N of M)" -- s:intake-shipped
        # derives that wording from the present/missing tally below; the gate
        # itself only distinguishes shipped-in-full from not-shipped-in-full.
        SHIPPED_STATUS="OPEN"
    fi
    SHIPPED_DETAIL="$link_note"$'\n'"${lines%$'\n'}"$'\n'"present=$present missing=$missing of $((present + missing))"
}
