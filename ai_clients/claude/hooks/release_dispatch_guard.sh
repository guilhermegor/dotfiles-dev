#!/bin/bash
# PreToolUse (Bash matcher) hook: guard a PyPI release dispatch against releasing an UNCHANGED
# shipped artifact.
#
# Why this exists: "minor-bump on every merge" ships byte-identical wheels under new version
# numbers — a version stops being a claim about the artifact. The release trigger must be a diff
# in the SHIPPED artifact (src/ + pyproject.toml for a Python lib), never "a PR merged". A hook
# CANNOT fire on a merge (that is a GitHub event, not a tool call) — so the binding interception
# point is the release *dispatch*: `gh workflow run release-{test-,}pypi.yaml -f version=X.Y.Z`.
#
# Division of labour with the s:release skill: the skill (model-driven, network-capable) owns the
# full bump math and the next-version-across-BOTH-indices computation. This guard owns only what is
# deterministic and OFFLINE, so it never false-blocks:
#   * shipped diff since the last tag is EMPTY   -> BLOCK (the byte-identical-wheel case);
#   * an obvious over-bump (a non-breaking change taking the minor/major axis, pre-1.0)
#     -> ADVISORY note only (never a block — a legit Test PyPI floor jump can look identical).
# The absolute version number is NOT checked here: it depends on max(PyPI, Test PyPI), which needs
# the network, and a wrong offline guess would false-block. That check stays in the skill.
#
# Hook I/O contract (same as the other guards): a hard block is exit 2 + stderr; an advisory is a
# stdout JSON additionalContext on exit 0. It fails OPEN everywhere: not a release dispatch, no
# tags yet (first release), unparseable versions, or any unresolvable state exits 0.

set -u

command -v jq >/dev/null 2>&1 || exit 0

main() {
    local payload tool command version root last_tag paths signal bump

    payload="$(cat)"
    tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"
    [[ "$tool" == "Bash" ]] || exit 0

    command="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    [[ -n "$command" ]] || exit 0

    is_release_dispatch "$command" || exit 0
    version="$(extract_version "$command")" || exit 0   # no -f version= → cannot reason → allow

    root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
    last_tag="$(git describe --tags --abbrev=0 2>/dev/null)" || exit 0   # no tags → first release

    mapfile -t paths < <(shipped_paths "$root")
    shipped_diff_empty "$last_tag" "${paths[@]}" && block_no_shipped_change "$last_tag" "${paths[@]}"

    # Everything below is advisory only.
    signal="$(highest_signal "$last_tag")"
    bump="$(bump_axis "$last_tag" "$version")" || exit 0
    advise_if_overbump "$last_tag" "$version" "$signal" "$bump"
}

is_release_dispatch() {
    # `gh workflow run <...release...pypi...>.y[a]ml` (optionally rtk-prefixed).
    printf '%s' "$1" | grep -Eiq \
        '^[[:space:]]*(rtk[[:space:]]+)?gh[[:space:]]+workflow[[:space:]]+run[[:space:]].*release[^[:space:]]*pypi[^[:space:]]*\.ya?ml'
}

extract_version() {
    # Emit the value of `-f version=X.Y.Z` / `--field version=...` / `-f version X.Y.Z`.
    local s=" $1"
    if [[ "$s" =~ [[:space:]](-f|--field)[[:space:]=]*version[[:space:]=]+([^[:space:]\"\']+) ]]; then
        printf '%s' "${BASH_REMATCH[2]}"
        return 0
    fi
    return 1
}

shipped_paths() {
    # One path/glob per line: the repo's .claude/release.conf if present, else the Python default.
    # Committed on purpose (unlike the tracker map): a repo's shipped layout is its own metadata,
    # and you only release repos you control.
    local root="$1" conf="$1/.claude/release.conf"
    if [[ -r "$conf" ]]; then
        grep -vE '^[[:space:]]*(#|$)' "$conf"
        return
    fi
    printf '%s\n' "src/" "pyproject.toml"
}

shipped_diff_empty() {
    local last_tag="$1"; shift
    local out
    out="$(git diff --name-only "$last_tag"..HEAD -- "$@" 2>/dev/null)" || return 1
    [[ -z "$out" ]]
}

highest_signal() {
    # breaking > feat > fix > none, over commit subjects+bodies since the tag.
    local last_tag="$1" log
    log="$(git log "$last_tag"..HEAD --format='%s%n%b' 2>/dev/null)" || { printf 'none'; return; }
    printf '%s' "$log" | grep -Eq 'BREAKING[ -]CHANGE|^[a-z]+(\([^)]*\))?!:' && { printf 'breaking'; return; }
    printf '%s' "$log" | grep -Eq '^feat(\([^)]*\))?:' && { printf 'feat'; return; }
    printf '%s' "$log" | grep -Eq '^fix(\([^)]*\))?:' && { printf 'fix'; return; }
    printf 'none'
}

bump_axis() {
    # Which axis the requested version moves relative to the last tag: major | minor | patch | other.
    # "other" (equal, lower, or unparseable) fails open upstream.
    local lm ln lp rm rn rp
    read -r lm ln lp < <(semver "$1") || return 1
    read -r rm rn rp < <(semver "$2") || return 1
    if   (( rm >  lm )); then printf 'major'
    elif (( rm == lm && rn >  ln )); then printf 'minor'
    elif (( rm == lm && rn == ln && rp > lp )); then printf 'patch'
    else printf 'other'
    fi
}

semver() {
    # Emit "MAJOR MINOR PATCH" from vX.Y.Z / X.Y.Z (pre-release/build suffix ignored); fail if the
    # core three numbers are not present.
    local v="${1#v}"
    [[ "$v" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]] || return 1
    printf '%s %s %s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
}

advise_if_overbump() {
    local last_tag="$1" version="$2" signal="$3" bump="$4" major
    read -r major _ _ < <(semver "$last_tag") || exit 0
    # Only the clear pre-1.0 over-bump: a non-breaking change taking the minor or major axis.
    # (breaking → minor is correct pre-1.0; any >=1.0 shape is the skill's call.)
    (( major == 0 )) || exit 0
    [[ "$signal" == "feat" || "$signal" == "fix" ]] || exit 0
    [[ "$bump" == "minor" || "$bump" == "major" ]] || exit 0

    jq -n --arg v "$version" --arg t "$last_tag" --arg s "$signal" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            additionalContext: ("release_dispatch_guard (advisory): \($v) moves the minor/major axis from \($t), but the highest commit signal since the tag is \($s). Pre-1.0, a feat or fix is a PATCH bump. This is only correct if you are deliberately clearing a Test PyPI floor — otherwise reconsider the version. Not blocking.")
        }
    }' 2>/dev/null || true
    exit 0
}

block_no_shipped_change() {
    local last_tag="$1"; shift
    {
        echo "BLOCKED: no shipped-artifact change since ${last_tag} — refusing to release."
        echo
        echo "git diff --name-only ${last_tag}..HEAD -- $* is empty. A ci/docs/chore/test change"
        echo "that does not alter the wheel must not be released: it would ship a byte-identical"
        echo "artifact under a new version number, and the version stops meaning anything."
        echo
        echo "If the shipped layout is wrong, set the paths in .claude/release.conf (one per line)."
        echo "Otherwise there is genuinely nothing to release."
    } >&2
    exit 2
}

main "$@"
