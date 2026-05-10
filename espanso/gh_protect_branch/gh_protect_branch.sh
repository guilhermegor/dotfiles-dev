#!/usr/bin/env bash
# gh_protect_branch.sh - Apply standard GitHub branch protection to the default branch.

set -euo pipefail

CONFIRM="${1:-no}"
SOLE_MAINTAINER="${2:-no}"

if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Error: Not inside a git repository."
    exit 1
}

ORIGIN_URL=$(git remote get-url origin 2>/dev/null) || {
    echo "Error: No 'origin' remote found. Add one with: git remote add origin <url>"
    exit 1
}

if [[ "$ORIGIN_URL" =~ ^https://github\.com/([^/]+)/([^/]+?)(\.git)?$ ]]; then
    OWNER="${BASH_REMATCH[1]}"
    REPO="${BASH_REMATCH[2]}"
elif [[ "$ORIGIN_URL" =~ ^git@github\.com:([^/]+)/([^/]+?)(\.git)?$ ]]; then
    OWNER="${BASH_REMATCH[1]}"
    REPO="${BASH_REMATCH[2]}"
else
    echo "Error: Could not parse a GitHub owner/repo from origin URL: $ORIGIN_URL"
    exit 1
fi

BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's|origin/||') \
    || BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) \
    || BRANCH="main"

if [ "$SOLE_MAINTAINER" = "yes" ]; then
    GH_USER=$(gh api user --jq .login 2>/dev/null) || {
        echo "Error: Could not detect GitHub username. Check: gh auth status"
        exit 1
    }
    BYPASS_JSON=$(jq -cn --arg u "$GH_USER" '{"users":[$u],"teams":[],"apps":[]}')
else
    BYPASS_JSON='{"users":[],"teams":[],"apps":[]}'
fi

PAYLOAD=$(jq -n \
    --argjson bypass "$BYPASS_JSON" \
    '{
        required_status_checks: {strict: true, contexts: []},
        enforce_admins: true,
        required_pull_request_reviews: {
            dismiss_stale_reviews: true,
            require_code_owner_reviews: false,
            required_approving_review_count: 1,
            bypass_pull_request_allowances: $bypass
        },
        restrictions: null,
        allow_force_pushes: false,
        allow_deletions: false,
        required_linear_history: true
    }')

if echo "$PAYLOAD" | gh api --method PUT \
    -H "Accept: application/vnd.github+json" \
    "/repos/${OWNER}/${REPO}/branches/${BRANCH}/protection" \
    --input -
then
    if [ "$SOLE_MAINTAINER" = "yes" ]; then
        echo "Branch protection applied to '${BRANCH}' on ${OWNER}/${REPO} (bypass granted to ${GH_USER})."
    else
        echo "Branch protection applied to '${BRANCH}' on ${OWNER}/${REPO}."
    fi
else
    echo "Error: Failed to apply protection to '${BRANCH}' on ${OWNER}/${REPO}."
    echo "Check: gh auth status — ensure you have admin rights on the repository."
fi
