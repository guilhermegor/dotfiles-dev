#!/usr/bin/env bats
#
# Unit tests for ai_clients/claude/hooks/lib/orphaned_issues.sh (dotfiles-dev#418).
# Both halves of the gate contract (ai_clients/CLAUDE.md, "A gate's contract"): success returns
# a usable, non-empty answer on a fixture that provably has content, and the fail-closed path
# leaves every global empty. All `gh` calls are stubbed -- never a live token.

setup() {
    source "$BATS_TEST_DIRNAME/../ai_clients/claude/hooks/lib/orphaned_issues.sh"
}

# --- _orphan_merged_pr_mentions: the mention-without-link extraction ----------------------------

@test "a merged PR mentioning an issue by title, with no closing link, is reported" {
    gh() {
        case "$*" in
            "api graphql -f query="*)
                cat <<'JSON'
{"data":{"search":{"pageInfo":{"hasNextPage":false,"endCursor":null},
"nodes":[{"number":509,"title":"identifier-masking gate for #355","body":"",
"headRefName":"feat/509-masking","closingIssuesReferences":{"nodes":[]}}]}}}
JSON
                ;;
            *) return 1 ;;
        esac
    }
    run _orphan_merged_pr_mentions o/r
    [ "$status" -eq 0 ]
    [[ "$output" == $'355\t509\t' ]]
}

@test "a merged PR that DOES declare the closing link is not reported" {
    gh() {
        case "$*" in
            "api graphql -f query="*)
                cat <<'JSON'
{"data":{"search":{"pageInfo":{"hasNextPage":false,"endCursor":null},
"nodes":[{"number":292,"title":"fix things","body":"Closes #135",
"headRefName":"fix/292","closingIssuesReferences":{"nodes":[{"number":135}]}}]}}}
JSON
                ;;
            *) return 1 ;;
        esac
    }
    run _orphan_merged_pr_mentions o/r
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "a branch name carrying the issue number is caught even with no title/body mention" {
    gh() {
        case "$*" in
            "api graphql -f query="*)
                cat <<'JSON'
{"data":{"search":{"pageInfo":{"hasNextPage":false,"endCursor":null},
"nodes":[{"number":467,"title":"alembic parity","body":"",
"headRefName":"refactor/migrations-folder-alembic-parity-373-381",
"closingIssuesReferences":{"nodes":[{"number":373}]}}]}}}
JSON
                ;;
            *) return 1 ;;
        esac
    }
    run _orphan_merged_pr_mentions o/r
    [ "$status" -eq 0 ]
    # 373 is declared closed and must be excluded; 381 is mentioned only by the branch and
    # must surface -- the exact blueprintx#381/PR#467 shape from the issue's own measurement.
    [[ "$output" == $'381\t467\t373' ]]
}

@test "a read failure fails the extraction closed" {
    gh() { return 1; }
    run _orphan_merged_pr_mentions o/r
    [ "$status" -eq 1 ]
}

# --- gate_orphaned_issues: the top-level contract, not just its sub-helper ----------------------

@test "gate_orphaned_issues: success sets ok with a non-empty, parseable candidate line" {
    gh() {
        case "$*" in
            "api repos/o/r --jq .default_branch") echo master ;;
            "issue list --repo o/r --state open --limit 500 --json number --jq .[].number")
                printf '355\n999\n' ;;
            "api graphql -f query="*)
                cat <<'JSON'
{"data":{"search":{"pageInfo":{"hasNextPage":false,"endCursor":null},
"nodes":[{"number":509,"title":"identifier-masking gate for #355","body":"",
"headRefName":"feat/509-masking","closingIssuesReferences":{"nodes":[]}}]}}}
JSON
                ;;
            *) return 1 ;;
        esac
    }

    gate_orphaned_issues o r
    local rc=$?

    [ "$rc" -eq 0 ]
    [ "$ORPHAN_STATUS" = "ok" ]
    [[ "$ORPHAN_REPORT" == "#355 may already be shipped by PR #509 (mentions #355, closingIssuesReferences=none) -- verify on master" ]]
}

@test "gate_orphaned_issues: a mentioned number that is not an open issue is not reported" {
    gh() {
        case "$*" in
            "api repos/o/r --jq .default_branch") echo master ;;
            # 355 already closed elsewhere -- not in the open-issue set.
            "issue list --repo o/r --state open --limit 500 --json number --jq .[].number")
                printf '999\n' ;;
            "api graphql -f query="*)
                cat <<'JSON'
{"data":{"search":{"pageInfo":{"hasNextPage":false,"endCursor":null},
"nodes":[{"number":509,"title":"identifier-masking gate for #355","body":"",
"headRefName":"feat/509-masking","closingIssuesReferences":{"nodes":[]}}]}}}
JSON
                ;;
            *) return 1 ;;
        esac
    }

    gate_orphaned_issues o r
    local rc=$?

    [ "$rc" -eq 0 ]
    [ "$ORPHAN_STATUS" = "ok" ]
    [ -z "$ORPHAN_REPORT" ]
}

@test "gate_orphaned_issues: a read failure fails the whole gate closed, no partial answer" {
    gh() {
        case "$*" in
            "api repos/o/r --jq .default_branch") echo master ;;
            "issue list --repo o/r --state open --limit 500 --json number --jq .[].number")
                printf '355\n' ;;
            "api graphql -f query="*) echo "gh: API rate limit exceeded (HTTP 403)" >&2; return 1 ;;
            *) return 1 ;;
        esac
    }

    local rc=0
    gate_orphaned_issues o r || rc=$?

    [ "$rc" -eq 1 ]
    [ "$ORPHAN_STATUS" = "unknown" ]
    [ -z "$ORPHAN_REPORT" ]
}
