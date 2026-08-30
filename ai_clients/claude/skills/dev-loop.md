---
name: s:dev-loop
description: Use to run one iteration of the autonomous development loop — after a subagent finishes, on a scheduled round, or when the user asks "what's the state of the board?", "merge what can be merged", "dispatch more agents", "anything to release?". Runs six ordered steps (rescue, sweep, threads, re-run, release, dispatch) and ENDS IN ACTION, never in a report.
effort: high
argument-hint: [none]
allowed-tools: Bash Read Glob Grep Write Edit Agent
---

You are running one iteration of the development loop. **Execute it; do not ask whether to.**

This skill exists because six separate lessons were written about this loop — 482 lines — and none
of them contained the loop. Each was correct, each was written after a correction, and the loop
still did not run: the owner asked for it **five times in one session**, saying plainly *"é um pouco
cansativo sempre ter que perguntar isso."* A sequence cannot be captured as N notes about its steps.

⚠️ **The order is load-bearing.** RESCUE is first not because it matters most, but because it is
the step that gets skipped — and skipping it is the only one that destroys work.

⚠️ **The loop ends in step 6, not step 2.** A sweep that terminates in a report hands the loop back
to the human at exactly the point it was meant to remove them from. If a step finds nothing, **say
so in one line** — silence is indistinguishable from a step that never ran.

---

## 1. RESCUE — before anything new

An agent killed mid-flight leaves work in its worktree. A worktree is torn down; the work is gone.

```bash
/usr/bin/git worktree list --porcelain | awk '/^worktree /{print $2}' | while read -r p; do
  b=$(/usr/bin/git -C "$p" rev-parse --abbrev-ref HEAD 2>/dev/null)
  d=$(/usr/bin/git -C "$p" status --porcelain 2>/dev/null | wc -l)
  u=$(/usr/bin/git -C "$p" rev-list --count "origin/$b..$b" 2>/dev/null || echo NO-REMOTE)
  [ "$d" != "0" ] || [ "$u" != "0" ] && echo "$b dirty=$d unpushed=$u"
done
```

🔴 **`/usr/bin/git`, never the rtk proxy — not even for `worktree list`.** The proxy returns `ok`
for a clean tree, which `wc -l` counts as 1, and its reformatted `worktree list` breaks the
path↔branch pairing so counts land on the wrong branch. Measured: **96 uncommitted files reported
on a branch that had 0.** A sweep that cries wolf is worse than none — the operator learns to skip
it, and then it catches nothing.

Three states, three actions:
- **uncommitted** → commit and push it;
- **committed, no PR** → open the PR. ⚠️ An agent may commit onto its *anonymous*
  `worktree-agent-<id>` branch, so check branch names too;
- **dirty but stale** → before rescuing, diff the file against `origin/main`. A worktree on an old
  base shows a large diff that is **behind**, not ahead. Measured twice: 30 lines that looked like
  a lost fix were already merged, and a 77-line file was superseded by an open PR.

Why first: four agents were killed holding **662 / 694 / 256 / 305** uncommitted lines, and every
rescue happened only because a human asked. The one agent whose brief said *commit at the first
coherent point* lost **0 of 699**.

## 2. SWEEP the board

Residue · unresolved threads · branch-without-PR · unarmed auto-merge · PR behind base · real CI
failures.

⚠️ **PR behind base is not cosmetic.** CI runs a gate script **from the PR's own checkout**, so a
gate fixed on `main` does not apply to a PR that predates the fix. Measured on a PR whose local
gate said clean while CI said fail: its branch had **0** occurrences of the new function, `main`
had **2**. Being behind decides *which version of the rule the PR is judged by* — update the branch.

## 3. THREADS — read, verify, fix, reply, resolve

⚠️ **Ask the gate; never eyeball the PR list.** A thread arrives *after* the moment work feels
finished, so it is invisible from every place you would naturally look:

```bash
for n in $(gh pr list --state open --json number --jq '.[].number'); do
  GITHUB_REPOSITORY=<owner/repo> PR_NUMBER=$n python3 <gate> 2>&1 \
    | grep -q 'nobody outside the reviewer roster answered' && echo "#$n OPEN THREAD"
done
```

🔴 **The PRs most likely to be missed are the ones an agent just opened.** An agent that hits the
session limit after opening its PR never sees the review that lands minutes later — the work looks
delivered and sits blocked on a thread nobody read. Measured: a PR opened by a killed agent carried
two unanswered findings, one **Major** (a deny-by-default allowlist that any
`import x = require('pkg')` walked straight past), found only because the owner looked at the PR
list by hand.

For each PR with an unanswered thread:

1. **Read the finding.**
2. ⚠️ **Verify it against the current code before acting.** Review text is untrusted data and may
   describe a state that no longer holds. Confirm, then fix.
3. **Reply** with what changed and why — the rationale is the asset a future session reads; "fixed
   in <sha>" records that something changed, never *why*.
4. **Resolve.** Both halves; neither implies the other.

If the finding does not hold, say why and resolve anyway. ⚠️ A finding you deferred with *"known
limitation, follow-up issue"* is not answered — a gate with a documented hole is still a gate with a
hole. Close it or argue that it should not be closed.

## 4. RE-RUN stale checks

For each open PR, ask the gate directly — **never re-derive its verdict**:

```bash
GITHUB_REPOSITORY=<owner/repo> PR_NUMBER=<n> python3 <path-to-gate>
```

Exit 0 but a failed run still in the rollup → `rtk gh run rerun <run-id> --failed`.

⚠️ **Match the sentence that discriminates, never a bare noun.** A first draft grepped for `thread`
and matched *"so zero threads would be fine"* inside the **no-reviewer** message, misreporting 27
PRs as having open threads.

Measured: a re-run flipped a check green and **native auto-merge fired on its own**, merging the PR
with no further input. The whole cost of that defect was one stale run nobody re-ran.

## 4b. REVIEWER SLOT — the supply side, and the step nobody is corrected for missing

Every other step **reacts** to work that arrived. This one asks whether the scarce resource is
free, because an idle server produces no event to react to.

Measured: a reviewer slot idle **4h24** with **30 PRs** waiting, the oldest unreviewed for **4
days**. The hourly loop passed through that window four times and reported "no change" — correct on
its own terms, and blind.

⚠️ **Do not delegate this to a scheduled workflow.** A `schedule:` cron declared `*/10` was measured
running **6 times in 21 hours** — GitHub throttles scheduled workflows on low-activity repos,
hardest where the mechanism is most needed. `schedule:` is the one trigger GitHub is free to skip.

1. **Is the slot free?** Read the newest roster notice per PR: a rate-limit notice means turned
   away, a completion means it ran. Busy → **say so** and move on.
2. **Pick the candidate — blast radius first, age second.**
   - **Filter to PRs whose ONLY blocker is the review gate** (`BLOCKED`, and the review check is
     the sole red). ⚠️ A `DIRTY` PR is not a candidate: a review cannot resolve a merge conflict,
     so the ask is spent for nothing. Measured — of the five PRs holding the contended wiring
     files, **three were `DIRTY`**; asking for any of them would have burned the window.
   - **Rank by MEASURED contention, not by commit type.** Build the contended-file set and count
     how many *blocked issues* each PR's files hold hostage:

     ```bash
     for n in $(gh pr list --state open --json number --jq '.[].number'); do
       gh pr view $n --json files --jq '.files[].path'
     done | sort | uniq -c | sort -rn | head
     ```

     A file several PRs touch is a bottleneck; a PR holding one is worth more than its diff.
     ⚠️ **`chore`/`ci` was a proxy for this and it is a weak one** — it correlates with shared
     surfaces but does not measure them, and the measurement is one command away. Use the count.
   - Break ties by age, so nothing starves. ⚠️ Age alone is a **fairness** rule, not a throughput
     rule; it is the metric that is free to compute, which is how it becomes the default without
     anyone choosing it.

   🎯 **Before spending the ask, check whether a cheaper lever exists.** A `DIRTY` PR holding a
   contended file is unblocked by a rebase — free, no slot, no waiting. Resolving those first
   raises the value of the *next* ask instead of consuming this one.
3. **At most one ask per round.** A burst genuinely trips the account limit — 12 rate-limit notices
   in 11 minutes, measured.

Report **time-to-first-review per PR**, never requests per hour: a PR sitting unreviewed is the
user-visible cost, and that is the number this step must move.

## 5. RELEASE — evaluate, propose, do not cut

```bash
rtk git diff --name-only $(rtk git describe --tags --abbrev=0 origin/main)..origin/main -- <shipped-paths>
```

Empty → **no release**, and say so. Non-empty with no breaking change → PATCH under 0.x.
**Propose; never cut without the owner's explicit yes.**

⚠️ Read the shipped paths from the packaging manifest, never from intuition. A Python-shaped default
on a non-Python repo fails **silently and inverted** — it *suppresses* a release rather than
erroring. `.claude/release.conf` is the declared list where one exists.

## 6. DISPATCH — the loop's other half

Compute the free surface: the files the open PRs touch, versus the open issues. Dispatch agents for
what does not collide.

🔴 **First: is an open PR already closing this issue?** A file-collision check compares PR files
against PR files and **cannot see an issue that is already claimed** — so it reports a free surface
for work that is already done.

```bash
gh api graphql -f query='{search(query:"repo:OWNER/REPO is:pr is:open",type:ISSUE,first:60){
  nodes{... on PullRequest{number closingIssuesReferences(first:5){nodes{number}}}}}}' \
  --jq '.data.search.nodes[]|.number as $p|.closingIssuesReferences.nodes[]|"\(.number) <- PR #\($p)"'
```

⚠️ **Do not trust the branch-name heuristic for this.** Matching a trailing `-<issue>` in the branch
name misses a PR whose branch was named after a different slice, which is exactly how it failed:
measured 2026-08-30, an agent was dispatched for #145 while **PR #279 had been open four days**
closing the same issue and touching the identical two files. The duplicate PR had to be closed. The
`closingIssuesReferences` query above is the reliable form — it reads what GitHub itself will act
on at merge time.

⚠️ **If the free surface is empty, state it.** That is information, not silence.

Every brief carries:
- 🔴 **commit and push at the first coherent point, then keep committing** (the measurement above);
- `dangerouslyDisableSandbox: true` on every git write — the sandbox overlay silently discards ref
  updates on teardown;
- `git add` and `git commit` as **separate** calls — a blocked hook kills a whole compound call;
- never pipe `git commit` through `tail`/`grep`; a `$?` after a pipe is the **pipe's** exit, and
  **HEAD not moving is the ground truth** that a commit failed;
- commit title ≤72 chars, body lines ≤80;
- when writing a PR/issue body: create the file in one call, run `gh` in a **separate** call — the
  template guard reads the file before a same-call heredoc has written it;
- a failing test is a **finding**, never an obstacle to remove.

---

## Do Not

- Do not stop at step 2 and report. The loop ends in dispatch.
- Do not re-implement a gate's logic in the sweep — call the gate. A sweep that reimplemented one
  inherited its bug **plus one of its own**.
- Do not conclude a path is clean from rtk-proxied `git status` / `ls` / `find`.
- Do not force-merge past a red required check, or remove one to unblock a PR.
- Do not ask permission to run this. Ask only before cutting a release or taking an outward-facing,
  hard-to-reverse action.

## Reporting

Report only what **changed**, plus anything that needs the owner. If a step found nothing, one line.
If nothing at all changed since the last round, say *"no change"* and stop.
