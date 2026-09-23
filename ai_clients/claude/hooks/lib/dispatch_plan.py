"""Compute the non-colliding dispatch set for round_dispatch_guard.sh (dotfiles-dev#433).

Invoked with NO arguments, from the current working directory — a checkout of the target
repo, the same convention round_dispatch_guard.sh's own ``python3 "$PLANNER"`` call relies
on (it never ``cd``s anywhere first). Prints exactly one JSON object to stdout::

    {"dispatchable": [{"issue": 433, "surface": ["a/b.py"]}],
     "excluded":     [{"issue": 426, "reason": "..."}]}

Never re-derives collision logic. Every exact-path comparison against a live agent's or
open PR's file set runs through the existing ``gate_free_surface``/``free_classify_files``
pair in ``lib/free_surface.sh`` (dotfiles-dev#340) — this script only orchestrates around
them: parsing each issue's declared surface, expanding globs against the repo tree, and
turning the three-way classify verdict into a dispatchable/excluded record. Collapsing
``would-need-a-held-file`` into ``held`` was the specific bug that hid 97% of a free
directory behind a directory-level summary (#340); the mapping below keeps all three
states apart on purpose.

An issue's file surface is declared as a fenced ```surface block in its body — the
convention dotfiles-dev#426 formalises with an issue-template requirement; here it is
read, not enforced. An issue with no such block, or an empty one, is UNKNOWN, never
"collides with nothing": it is excluded with its own named reason, same as one whose
surface is held.

Fails LOUD, not closed-and-quiet, on anything that breaks the read itself (``gh`` missing,
not authenticated, a malformed response): an uncaught exception prints a traceback to
stderr and nothing parseable to stdout, which is exactly what round_dispatch_guard.sh's own
shape check reads as UNREADABLE and blocks on — the fail-closed behaviour lives in the
caller, so this script does not need to fake a valid-looking empty answer to get it. A
*recoverable* gate failure (a rate limit, a bad compare) is different: gate_free_surface
already reports that as its own clean "unknown" state, so it is surfaced here as a named
exclusion reason on every open issue — still a valid, still fail-closed JSON object.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

LIB_DIR = Path(__file__).resolve().parent
FREE_SURFACE_SH = LIB_DIR / "free_surface.sh"
GH_TIMEOUT = 20
GATE_TIMEOUT = 25

SURFACE_BLOCK_RE = re.compile(r"```surface\s*\n(.*?)```", re.DOTALL)
GLOB_CHARS = ("*", "?", "[")

# Runs gate_free_surface exactly once and classifies every candidate against it in the SAME
# bash process (never one subprocess per issue): FREE_HELD_PATHS is a plain shell variable the
# gate sets, not exported, so free_classify_files can only see it from inside that same process.
_GATE_SCRIPT = r"""
set -eu
owner="$1"; repo="$2"; free_surface_sh="$3"
# shellcheck source=/dev/null
source "$free_surface_sh"

# Same per-call timeout dispatch_free_surface_guard.sh already wraps gh in — a Stop hook is
# synchronous and gh has no default request deadline of its own.
gh() { timeout "${DISPATCH_PLAN_GH_TIMEOUT:-15}" gh "$@"; }

# Read every classify request BEFORE the network calls below: issue<TAB>file1|file2|...,
# one per line. gate_free_surface never touches stdin, so this ordering is safe.
mapfile -t requests

if ! gate_free_surface "$owner" "$repo"; then
	echo "GATE_STATUS:unknown"
	exit 0
fi
echo "GATE_STATUS:ok"
echo "===UNCLAIMED==="
printf '%s\n' "$FREE_UNCLAIMED_ISSUES"
echo "===RESULTS==="
for line in "${requests[@]}"; do
	[ -n "$line" ] || continue
	issue="${line%%$'\t'*}"
	files="${line#*$'\t'}"
	IFS='|' read -r -a filearr <<<"$files"
	verdict="$(free_classify_files "${filearr[@]}")"
	printf '%s\t%s\n' "$issue" "$verdict"
done
"""


def _run(cmd: list[str]) -> str:
	"""Run a command and return its stripped stdout.

	Raises on any non-zero exit or timeout, deliberately: a broken read here must surface as
	this script's own failure (see the module docstring's "fails loud" note), never as a
	silently empty answer.
	"""
	result = subprocess.run(  # noqa: S603 - fixed argv lists, no shell, no user input
		cmd, capture_output=True, text=True, timeout=GH_TIMEOUT, check=True
	)
	return result.stdout.strip()


def repo_slug() -> str:
	"""Return ``owner/name`` for the repo rooted at the current working directory."""
	return _run(["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"])


def repo_root() -> Path:
	"""Return the working tree root, for expanding a declared surface's glob tokens."""
	return Path(_run(["git", "rev-parse", "--show-toplevel"]))


def open_issues(slug: str) -> list[dict]:
	"""Return every open issue's number and body for ``slug`` (``owner/name``)."""
	raw = _run(
		[
			"gh",
			"issue",
			"list",
			"--repo",
			slug,
			"--state",
			"open",
			"--limit",
			"500",
			"--json",
			"number,body",
		]
	)
	return json.loads(raw) if raw else []


def declared_surface(body: str) -> list[str]:
	"""Parse the fenced ```surface block out of an issue body into path/glob tokens.

	An absent block and an empty one return the same thing (``[]``) — the caller reads both
	as "no declared surface", never as "collides with nothing" (dotfiles-dev#426).
	"""
	match = SURFACE_BLOCK_RE.search(body or "")
	if not match:
		return []
	return [line.strip() for line in match.group(1).splitlines() if line.strip()]


def expand_tokens(tokens: list[str], root: Path) -> list[str]:
	"""Expand each glob token against the repo tree.

	A literal token (no glob character) passes through unchanged whether or not it exists
	yet — an issue's declared surface may name a file its own solution would create. A glob
	that matches nothing yet is kept as its literal pattern for the same reason, rather than
	silently dropped.
	"""
	files: list[str] = []
	for token in tokens:
		if any(ch in token for ch in GLOB_CHARS):
			matches = sorted(str(p.relative_to(root)) for p in root.glob(token))
			files.extend(matches or [token])
		else:
			files.append(token)
	return files


def run_gate(
	owner: str, repo: str, requests: list[tuple[int, list[str]]]
) -> tuple[bool, set[int], dict[int, str]]:
	"""Run gate_free_surface once and classify every request against it in one process.

	Returns ``(gate_ok, unclaimed_issue_numbers, {issue: classify_verdict})``. ``gate_ok`` is
	False exactly when gate_free_surface itself reported FREE_STATUS=unknown — a recoverable,
	expected condition (gh rate limit, an unhandled compare error), never a crash.
	"""
	stdin = "".join(f"{issue}\t{'|'.join(files)}\n" for issue, files in requests)
	proc = subprocess.run(  # noqa: S603, S607 - fixed argv, script is a module constant
		["bash", "-c", _GATE_SCRIPT, "dispatch_plan", owner, repo, str(FREE_SURFACE_SH)],
		input=stdin,
		capture_output=True,
		text=True,
		timeout=GATE_TIMEOUT,
		check=True,
	)
	lines = proc.stdout.splitlines()
	if not lines or lines[0] != "GATE_STATUS:ok":
		return False, set(), {}

	results_at = lines.index("===RESULTS===")
	unclaimed = {int(n) for n in lines[2:results_at] if n.strip()}
	verdicts = {}
	for line in lines[results_at + 1 :]:
		if not line.strip():
			continue
		issue, verdict = line.split("\t", 1)
		verdicts[int(issue)] = verdict
	return True, unclaimed, verdicts


def build_plan() -> dict:
	"""Assemble the {"dispatchable": [...], "excluded": [...]} plan for every open issue."""
	slug = repo_slug()
	owner, name = slug.split("/", 1)
	root = repo_root()
	issues = open_issues(slug)

	surfaces: dict[int, list[str]] = {}
	expanded: dict[int, list[str]] = {}
	for issue in issues:
		tokens = declared_surface(issue.get("body") or "")
		if tokens:
			number = issue["number"]
			surfaces[number] = tokens
			expanded[number] = expand_tokens(tokens, root)

	requests = list(expanded.items())
	gate_ok, unclaimed, verdicts = run_gate(owner, name, requests)

	dispatchable: list[dict] = []
	excluded: list[dict] = []
	for issue in issues:
		number = issue["number"]
		if not gate_ok:
			excluded.append(
				{
					"issue": number,
					"reason": "free surface gate UNKNOWN (gh API failure) — "
					"verify non-collision by hand",
				}
			)
		elif number not in unclaimed:
			excluded.append(
				{"issue": number, "reason": "already claimed by an open or merged pull request"}
			)
		elif number not in surfaces:
			excluded.append(
				{
					"issue": number,
					"reason": "no declared file surface (no ```surface block in the issue body)",
				}
			)
		else:
			verdict = verdicts.get(number, "")
			if verdict == "free" or verdict.startswith("would-need-a-held-file"):
				dispatchable.append({"issue": number, "surface": expanded[number]})
			else:
				held = verdict.split(":", 1)[1] if ":" in verdict else "unreadable classify verdict"
				excluded.append(
					{
						"issue": number,
						"reason": f"surface held by an open pull request or live branch: {held}",
					}
				)

	return {"dispatchable": dispatchable, "excluded": excluded}


def main() -> int:
	"""Print the dispatch plan as one JSON object and return 0."""
	print(json.dumps(build_plan()))
	return 0


if __name__ == "__main__":
	sys.exit(main())
