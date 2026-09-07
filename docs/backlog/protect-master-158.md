# Protect `master` with required status checks — #158

This is a **repository-settings change**, not a code change. Nothing in this doc has been
applied. It records the current state, the exact commands to apply the fix, and the reasoning
behind the choices — for the repo owner to run by hand when no PRs are in flight.

## Current state (measured 2026-09-07)

### Classic branch protection — absent

```console
$ rtk gh api repos/guilhermegor/dotfiles-dev/branches/master/protection
{"message":"Branch not protected","documentation_url":"https://docs.github.com/rest/branches/branch-protection#get-branch-protection","status":"404"}
```

### Rulesets — one exists, but disabled and matches no branch

```console
$ rtk gh api repos/guilhermegor/dotfiles-dev/rulesets
[{"id":16690058,"name":"protect-master","target":"branch","enforcement":"disabled", ...}]

$ rtk gh api repos/guilhermegor/dotfiles-dev/rulesets/16690058
{
  "id": 16690058,
  "name": "protect-master",
  "target": "branch",
  "enforcement": "disabled",
  "conditions": {"ref_name": {"include": [], "exclude": []}},
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "pull_request", "parameters": {
      "required_approving_review_count": 0,
      "dismiss_stale_reviews_on_push": false,
      "required_reviewers": [],
      "require_code_owner_review": false,
      "require_last_push_approval": false,
      "required_review_thread_resolution": false,
      "require_extra_approval_for_unattributed_changes": true,
      "allowed_merge_methods": ["merge", "squash", "rebase"]
    }}
  ],
  "bypass_actors": [],
  "current_user_can_bypass": "never"
}
```

A ruleset named `protect-master` was already created (2026-05-21) with `deletion`,
`non_fast_forward`, and `pull_request` rules — which is exactly the "block force-push and direct
pushes" half of this issue's scope, and already has `required_approving_review_count: 0` (must
stay 0 — GitHub forbids self-approval, so ≥1 locks a solo maintainer out permanently). But:

- `enforcement` is `"disabled"` — the ruleset does nothing.
- `conditions.ref_name.include` is `[]` — even if enabled, it would match zero branches.
- There is **no `required_status_checks` rule** — none of the 10 CI checks are required.

So the fix is completing this existing ruleset, not creating a new one — matching the issue's own
"idempotent, looked up by name, PUT-if-present" convention (`bin/enable_repo_rules.sh` in
`blueprintx/templates/python-common/`), rather than a blind POST that would create a duplicate.

## Verbatim required-check names (from PR #244, merged, fully green)

```console
$ rtk gh pr checks 244 --repo guilhermegor/dotfiles-dev --json name,state,workflow
```

| Check name (verbatim) | Workflow |
|---|---|
| `artifact contracts` | tests |
| `bash -n (parse check)` | shellcheck |
| `make -n (target validity)` | tests |
| `shellcheck` | shellcheck |
| `bats (unit tests)` | tests |
| `actionlint (workflow lint)` | tests |
| `yamllint` | tests |
| `gitlint (commit messages)` | tests |
| `GitGuardian Security Checks` | (third-party app, no workflow) |
| `CodeRabbit` | (third-party app, no workflow) |

All 10 were `SUCCESS` on PR #244. Names are taken verbatim from this run — a required check
whose name doesn't match what a workflow actually emits blocks every PR forever.

⚠️ **Recommended initial required set is 8, not 10.** Per the issue's own warning ("start with a
SMALL required set and grow it... treat conditional or matrix jobs with suspicion: a check that is
skipped for some PRs is exactly the one that will block them"): `GitGuardian Security Checks` and
`CodeRabbit` are third-party app checks (empty `workflow` field, unlike the other 8 which all come
from this repo's own `tests`/`shellcheck` workflows that run unconditionally on every PR). Before
requiring them, confirm on a few more PRs that they report every time — including PRs that don't
touch secrets-scannable files or that CodeRabbit might skip. The command below requires only the
8 repo-owned checks; add the other two once confirmed.

## Exact command to apply (NOT executed — run by the owner)

```bash
rtk gh api --method PUT repos/guilhermegor/dotfiles-dev/rulesets/16690058 \
  -H "Accept: application/vnd.github+json" \
  --input - <<'EOF'
{
  "name": "protect-master",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/master"],
      "exclude": []
    }
  },
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "required_reviewers": [],
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "require_extra_approval_for_unattributed_changes": true,
        "allowed_merge_methods": ["merge", "squash", "rebase"]
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [
          {"context": "artifact contracts"},
          {"context": "bash -n (parse check)"},
          {"context": "make -n (target validity)"},
          {"context": "shellcheck"},
          {"context": "bats (unit tests)"},
          {"context": "actionlint (workflow lint)"},
          {"context": "yamllint"},
          {"context": "gitlint (commit messages)"}
        ]
      }
    }
  ],
  "bypass_actors": []
}
EOF
```

Verify afterward with:

```bash
rtk gh api repos/guilhermegor/dotfiles-dev/rulesets/16690058
```

Add `GitGuardian Security Checks` and `CodeRabbit` to the `required_status_checks` array in a
follow-up PUT once confirmed non-conditional.

## `enforce_admins` — decided explicitly

Rulesets have no `enforce_admins` boolean (that's a classic-branch-protection field); the
equivalent is `bypass_actors`. The command above keeps `bypass_actors: []`, and the ruleset
already reports `current_user_can_bypass: "never"` — **nobody bypasses, including the repo
owner/admin**, matching `blueprintx`'s `enforce_admins: true`. This is a deliberate choice, not a
default left unexamined.

## Why not the classic `branches/{branch}/protection` endpoint

`espanso/gh_protect_branch/gh_protect_branch.sh` already wraps that endpoint, but it's a generic
"apply standard protection to whatever `origin/HEAD` points to" tool with `required_status_checks:
{contexts: []}` always empty — it doesn't carry this repo's specific check names, and mixing the
classic API with an existing, purpose-named ruleset on the same branch would leave two protection
mechanisms in play. Completing the existing ruleset is the smaller, less surprising change.
