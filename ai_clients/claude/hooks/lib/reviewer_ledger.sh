#!/bin/bash
# ai_clients/claude/hooks/lib/reviewer_ledger.sh
#
# SQLite ledger of reviewer asks and accepted findings by class
# (dotfiles-dev#488). Answers one question from data instead of session
# memory: what did we spend on each rung of the reviewer ladder
# (coderabbitai > codex > qwen > kimi), and what did it buy.
#
# Two tables, because the denominator is not the numerator:
#   ask     -- one row per ask: rung, PR, head SHA, timestamp, outcome
#              (refused/clean/found). A rung that was never asked and a
#              rung that was asked and found nothing must stay
#              distinguishable, or an unasked rung looks "ineffective".
#   finding -- one row per finding: its ask, claimed severity, a ternary
#              verdict (true/false/partial -- a finding can be real but
#              overstated), and a closed-vocabulary class.
#
# Capture is deliberately split (see the issue): this script is the
# deterministic half (the observable fact -- rung, PR, sha, outcome,
# severity). The verdict and class are a model judgement call, written
# explicitly by whoever resolves the finding -- never inferred here.
#
# Storage: NOT in the repo (issue: "it is data, and versioning it churns on
# every round"). Default path is ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/
# reviewer_ledger.db, covered by the existing backup_env backup. Override
# with REVIEWER_LEDGER_DB (tests point this at a tmp file).
#
# Usage (both sourced, for reviewer_ladder.sh's post path, and executed
# directly as a CLI for recording/reporting):
#   reviewer_ledger.sh init
#   reviewer_ledger.sh ask     --rung R --pr N --sha SHA --outcome O
#   reviewer_ledger.sh finding --ask-id N --severity S --verdict V --class C [--note TEXT]
#   reviewer_ledger.sh report  {rung-effectiveness|ladder-order|zero-true} [--min-asks N]
set -u

# The closed class vocabulary (issue: "the decision that makes or breaks the
# store"). Kept as one array so the CLI's validation and the CHECK
# constraint below can never independently drift from this list.
REVIEWER_LEDGER_CLASSES=(auth-bypass fail-open shell-robustness api-shape docs-vs-code test-gap other)

_reviewer_ledger_db() {
    printf '%s\n' "${REVIEWER_LEDGER_DB:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/reviewer_ledger.db}"
}

_reviewer_ledger_die() {
    echo "reviewer_ledger: $1" >&2
    exit 1
}

_reviewer_ledger_class_valid() {
    local class="$1" c
    for c in "${REVIEWER_LEDGER_CLASSES[@]}"; do
        [[ "$c" == "$class" ]] && return 0
    done
    return 1
}

# reviewer_ledger_init [DB] -- idempotent: CREATE TABLE IF NOT EXISTS, safe
# to call on every ladder run.
reviewer_ledger_init() {
    local db="${1:-$(_reviewer_ledger_db)}"
    mkdir -p "$(dirname "$db")" || _reviewer_ledger_die "cannot create $(dirname "$db")"
    sqlite3 "$db" <<'SQL' || _reviewer_ledger_die "schema init failed"
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS ask (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    rung      TEXT NOT NULL,
    pr_number INTEGER NOT NULL,
    head_sha  TEXT NOT NULL,
    asked_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    outcome   TEXT NOT NULL CHECK (outcome IN ('refused', 'clean', 'found'))
);

CREATE TABLE IF NOT EXISTS finding (
    id       INTEGER PRIMARY KEY AUTOINCREMENT,
    ask_id   INTEGER NOT NULL REFERENCES ask(id),
    severity TEXT NOT NULL,
    verdict  TEXT NOT NULL CHECK (verdict IN ('true', 'false', 'partial')),
    class    TEXT NOT NULL CHECK (class IN (
                 'auth-bypass', 'fail-open', 'shell-robustness',
                 'api-shape', 'docs-vs-code', 'test-gap', 'other'
             )),
    note     TEXT
);

CREATE INDEX IF NOT EXISTS idx_ask_rung ON ask(rung);
CREATE INDEX IF NOT EXISTS idx_finding_ask_id ON finding(ask_id);
SQL
}

# reviewer_ledger_record_ask --rung R --pr N --sha SHA --outcome O
# Prints the new ask id on stdout. Called from the ladder's own post path
# once per rung invocation.
reviewer_ledger_record_ask() {
    local db rung="" pr="" sha="" outcome=""
    db="$(_reviewer_ledger_db)"
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --db) db="$2"; shift 2 ;;
        --rung) rung="$2"; shift 2 ;;
        --pr) pr="$2"; shift 2 ;;
        --sha) sha="$2"; shift 2 ;;
        --outcome) outcome="$2"; shift 2 ;;
        *) _reviewer_ledger_die "ask: unknown argument $1" ;;
        esac
    done
    [[ -n "$rung" && -n "$pr" && -n "$sha" && -n "$outcome" ]] ||
        _reviewer_ledger_die "ask: --rung, --pr, --sha, --outcome are all required"
    case "$outcome" in
    refused | clean | found) ;;
    *) _reviewer_ledger_die "ask: --outcome must be refused|clean|found, got '$outcome'" ;;
    esac
    reviewer_ledger_init "$db"
    sqlite3 "$db" \
        "INSERT INTO ask (rung, pr_number, head_sha, outcome) VALUES ('${rung//\'/\'\'}', ${pr}, '${sha//\'/\'\'}', '${outcome//\'/\'\'}'); SELECT last_insert_rowid();" ||
        _reviewer_ledger_die "ask insert failed"
}

# reviewer_ledger_record_finding --ask-id N --severity S --verdict V --class C [--note TEXT]
# The one explicit model write: verdict and class are judgement, never
# inferred by this script.
reviewer_ledger_record_finding() {
    local db ask_id="" severity="" verdict="" class="" note=""
    db="$(_reviewer_ledger_db)"
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --db) db="$2"; shift 2 ;;
        --ask-id) ask_id="$2"; shift 2 ;;
        --severity) severity="$2"; shift 2 ;;
        --verdict) verdict="$2"; shift 2 ;;
        --class) class="$2"; shift 2 ;;
        --note) note="$2"; shift 2 ;;
        *) _reviewer_ledger_die "finding: unknown argument $1" ;;
        esac
    done
    [[ -n "$ask_id" && -n "$severity" && -n "$verdict" && -n "$class" ]] ||
        _reviewer_ledger_die "finding: --ask-id, --severity, --verdict, --class are all required"
    case "$verdict" in
    true | false | partial) ;;
    *) _reviewer_ledger_die "finding: --verdict must be true|false|partial, got '$verdict'" ;;
    esac
    _reviewer_ledger_class_valid "$class" ||
        _reviewer_ledger_die "finding: --class must be one of: ${REVIEWER_LEDGER_CLASSES[*]} -- got '$class'"
    reviewer_ledger_init "$db"
    sqlite3 "$db" \
        "INSERT INTO finding (ask_id, severity, verdict, class, note) VALUES (${ask_id}, '${severity//\'/\'\'}', '${verdict//\'/\'\'}', '${class//\'/\'\'}', $( [[ -n "$note" ]] && printf "'%s'" "${note//\'/\'\'}" || printf 'NULL' ));" ||
        _reviewer_ledger_die "finding insert failed"
}

# --- reports ---------------------------------------------------------------
# All three read counts only -- never a computed ratio -- per the issue's own
# point that a raw accept/reject ratio ranks reviewers wrong. A percentage is
# also a stored/compared float this repo's numeric-precision rule forbids;
# printing "true=N of M" side-steps needing one at all.

# Q1/Q2: is the ladder order right, and is each rung effective -- per rung,
# ask outcomes and finding verdicts.
_reviewer_ledger_report_rung_effectiveness() {
    local db="$1"
    sqlite3 -header -column "$db" <<'SQL'
SELECT
    a.rung,
    COUNT(*)                                            AS asks,
    SUM(a.outcome = 'refused')                          AS refused,
    SUM(a.outcome = 'clean')                             AS clean,
    SUM(a.outcome = 'found')                              AS found,
    COALESCE(SUM(f.verdict = 'true'), 0)                  AS true_findings,
    COALESCE(SUM(f.verdict = 'false'), 0)                 AS false_findings,
    COALESCE(SUM(f.verdict = 'partial'), 0)               AS partial_findings
FROM ask a
LEFT JOIN finding f ON f.ask_id = a.id
GROUP BY a.rung
ORDER BY true_findings DESC, a.rung;
SQL
}

# Q1: same data, ordered explicitly by true-finding count -- the argument
# for whether the CURRENT ladder order (coderabbitai > codex > qwen > kimi)
# still matches the value each rung has produced.
_reviewer_ledger_report_ladder_order() {
    _reviewer_ledger_report_rung_effectiveness "$1"
}

# Q3: rungs with at least --min-asks asks and zero true findings -- visible
# without any significance test, per the issue.
_reviewer_ledger_report_zero_true() {
    local db="$1" min_asks="$2"
    sqlite3 -header -column "$db" <<SQL
SELECT
    a.rung,
    COUNT(*) AS asks,
    COALESCE(SUM(f.verdict = 'true'), 0) AS true_findings
FROM ask a
LEFT JOIN finding f ON f.ask_id = a.id
GROUP BY a.rung
HAVING COUNT(*) >= ${min_asks} AND true_findings = 0
ORDER BY a.rung;
SQL
}

# reviewer_ledger_report {rung-effectiveness|ladder-order|zero-true} [--min-asks N] [--db PATH]
reviewer_ledger_report() {
    local db report="" min_asks=5
    db="$(_reviewer_ledger_db)"
    [[ $# -gt 0 ]] || _reviewer_ledger_die "report: one of rung-effectiveness|ladder-order|zero-true is required"
    report="$1"
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --db) db="$2"; shift 2 ;;
        --min-asks) min_asks="$2"; shift 2 ;;
        *) _reviewer_ledger_die "report: unknown argument $1" ;;
        esac
    done
    [[ -f "$db" ]] || _reviewer_ledger_die "report: no ledger at $db -- run 'init' first"
    case "$report" in
    rung-effectiveness) _reviewer_ledger_report_rung_effectiveness "$db" ;;
    ladder-order) _reviewer_ledger_report_ladder_order "$db" ;;
    zero-true) _reviewer_ledger_report_zero_true "$db" "$min_asks" ;;
    *) _reviewer_ledger_die "report: unknown report '$report' -- want rung-effectiveness|ladder-order|zero-true" ;;
    esac
}

_reviewer_ledger_usage() {
    cat <<'USAGE'
Usage:
  reviewer_ledger.sh init [DB]
  reviewer_ledger.sh ask     --rung R --pr N --sha SHA --outcome refused|clean|found [--db PATH]
  reviewer_ledger.sh finding --ask-id N --severity S --verdict true|false|partial --class C [--note TEXT] [--db PATH]
  reviewer_ledger.sh report  rung-effectiveness|ladder-order|zero-true [--min-asks N] [--db PATH]

Classes: auth-bypass, fail-open, shell-robustness, api-shape, docs-vs-code, test-gap, other
USAGE
}

main() {
    [[ $# -gt 0 ]] || { _reviewer_ledger_usage; exit 1; }
    local cmd="$1"
    shift
    case "$cmd" in
    init) reviewer_ledger_init "$@" ;;
    ask) reviewer_ledger_record_ask "$@" ;;
    finding) reviewer_ledger_record_finding "$@" ;;
    report) reviewer_ledger_report "$@" ;;
    -h | --help) _reviewer_ledger_usage ;;
    *) _reviewer_ledger_usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
