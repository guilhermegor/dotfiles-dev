#!/usr/bin/env bats
#
# Unit tests for the permissions.deny .env rules in ai_clients/claude/settings.json
#
# Context (issue #123 / #124): a single broad `Read(**/.env.*)` deny pattern also
# matched `.env.example` — a tracked, secret-free template every project needs
# editable (Edit requires Read; deny beats allow, so an `allow` entry cannot undo
# this). The fix replaced that one pattern with an enumerated list of suffixes
# that actually carry secrets. This suite asserts both directions so a future
# edit cannot silently collapse the list back to the broad pattern:
#   - every real-secret filename still matches at least one deny glob
#   - every known secret-free template filename matches none of them
#
# Run locally: bats tests/   (install with: sudo apt-get install -y bats)

setup() {
    SETTINGS="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/ai_clients/claude/settings.json"
}

# Extract the filename glob out of each `Read(**/<glob>)` .env deny entry.
_deny_globs() {
    jq -r '.permissions.deny[] | select(startswith("Read(**/.env"))' "$SETTINGS" \
        | sed -e 's/^Read(\*\*\///' -e 's/)$//'
}

# True (exit 0) if $1 matches any .env deny glob.
_matches_any_deny() {
    local name="$1" pat
    while IFS= read -r pat; do
        # shellcheck disable=SC2053  # intentional unquoted glob match
        [[ "$name" == $pat ]] && return 0
    done < <(_deny_globs)
    return 1
}

@test "settings.json is valid JSON" {
    run jq empty "$SETTINGS"
    [ "$status" -eq 0 ]
}

@test "the broad Read(**/.env.*) pattern is gone (would re-swallow templates)" {
    run jq -e '.permissions.deny | index("Read(**/.env.*)")' "$SETTINGS"
    [ "$status" -ne 0 ]
}

# --- real secrets: must stay denied ---------------------------------------

@test "real .env stays denied" {
    run _matches_any_deny ".env"
    [ "$status" -eq 0 ]
}

@test ".env.local stays denied" {
    run _matches_any_deny ".env.local"
    [ "$status" -eq 0 ]
}

@test ".env.production.local stays denied" {
    run _matches_any_deny ".env.production.local"
    [ "$status" -eq 0 ]
}

@test ".env.development stays denied" {
    run _matches_any_deny ".env.development"
    [ "$status" -eq 0 ]
}

@test ".env.production stays denied" {
    run _matches_any_deny ".env.production"
    [ "$status" -eq 0 ]
}

@test ".env.staging stays denied" {
    run _matches_any_deny ".env.staging"
    [ "$status" -eq 0 ]
}

@test ".env.homolog stays denied" {
    run _matches_any_deny ".env.homolog"
    [ "$status" -eq 0 ]
}

@test ".env.test stays denied" {
    run _matches_any_deny ".env.test"
    [ "$status" -eq 0 ]
}

@test ".env.ci stays denied" {
    run _matches_any_deny ".env.ci"
    [ "$status" -eq 0 ]
}

@test ".env.secret stays denied" {
    run _matches_any_deny ".env.secret"
    [ "$status" -eq 0 ]
}

# --- secret-free templates: must be readable ------------------------------

@test ".env.example is not denied" {
    run _matches_any_deny ".env.example"
    [ "$status" -ne 0 ]
}

@test ".env.sample is not denied" {
    run _matches_any_deny ".env.sample"
    [ "$status" -ne 0 ]
}

@test ".env.template is not denied" {
    run _matches_any_deny ".env.template"
    [ "$status" -ne 0 ]
}

@test ".env.dist is not denied" {
    run _matches_any_deny ".env.dist"
    [ "$status" -ne 0 ]
}
