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

## 0. ARM — the skill arms its own schedules on invocation

Invoking this skill should be enough to make the loop run; remembering to arm the crons by hand
is the gap this step closes. The owner asking *"eu precisaria ter pedido ou já tem algo agendado
que rode?"* is the measurement that it didn't.

1. **`CronList` first.** Invoking the skill twice in one session must not produce four jobs
   firing in duplicate against the same PRs — check what already exists before creating anything.
2. **`CronCreate` whatever is missing:**
   - the round (all six steps below) at `:23`;
   - a thread sweep at `:53`.
3. **Say what you armed**, or that both already existed. A step that runs silently is
   indistinguishable from one that never ran.

### What triggers the round — and its limits

- **The session, and only the session.** These are `CronCreate` jobs, not a host timer — they
  die when the session ends. That is the requirement (*"enquanto dev-loop estiver ativo na
  sessão"*), not a defect to patch over with something more durable.
- **Recurring jobs expire after 7 days.** A session that outlives that window needs to re-arm;
  step 1 above already catches this, because `CronList` will show the gap.
- **Not GitHub Actions `schedule:`.** Disqualified by measurement, not preference — see step 4b:
  a `*/10` cron ran 6 times in 21 hours, because GitHub throttles scheduled workflows hardest on
  the low-activity repos that need them most.

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

### Quota kill: detect it, resume it, don't re-dispatch it

A session-limit kill is silent by construction — a killed agent is `idle`, byte-identical to one
that finished, and a worktree-isolated agent can **disappear from `ListAgents` entirely**. Measured
2026-09-04: five subagents died mid-flight to `HTTP 429 rate_limit`. Three had **already finished**
— one had even opened its PR — and died at the commit/push/PR step; their own completion text read
"task remains complete, stopping" / "No action needed," which is **misleading in both directions**.
The only reliable signal was inspecting the worktree and asking the forge for PR state.

1. **Compare `ListAgents` against the set dispatched this session.** Dispatched **and** absent from
   the list = killed, not finished. Never infer "finished" from silence or from `idle` alone.
2. **Decide "finished" vs "killed" from data, never from the agent's own sign-off text:**
   - `/usr/bin/git -C <worktree> status --short` + `git log --oneline origin/<branch>..HEAD` —
     uncommitted or unpushed work means it died mid-flight.
   - `gh pr list --head <branch> --state all` — the **forge**, never `git`, is the oracle for
     whether work already shipped: a squash-merged branch is never an ancestor of the base, so a
     git-only check reports "unmerged" for work that already merged.
3. **Resume with `SendMessage` to the agent's name/id — never a fresh `Agent` call.** `SendMessage`
   preserves the transcript, so the agent continues at zero re-reading cost; a new `Agent` starts
   from nothing and **re-does work already committed** — exactly the cost an exhausted quota cannot
   afford. Measured: four agents resumed by `SendMessage` continued cleanly from where they died.
4. **Brief the resumed agent on what moved underneath it while it was dead** — commits or pushes
   landed on its behalf, files or surfaces another agent has since taken, PRs opened or merged. An
   agent resumes assuming its pre-death world still holds; measured twice that assumption was false
   (189 lines it would have rewritten, three files that had left circulation).
5. **Resume the whole interrupted set, staggered, on either trigger** — the declared quota reset
   time, **or** the next successful call after the user switches accounts (an account switch does
   not wait for the stated reset; both triggers are needed). Stagger the resumes: firing every
   killed agent back in at once into a freshly-reset quota is how it was exhausted the first time —
   measured twice, three agents each.

🎯 **A dedicated `CronCreate` poll for "are they still alive?" was evaluated and skipped.** A tick
that only asks that question spends session quota from the very budget that is under limit, which
can worsen the failure it is meant to catch. The comparison in step 1 above, run at each round
boundary the loop already has, is the cheaper form of the same check.

### The stash stack is shared — read it too

`git stash` is scoped to the **repository**, not the worktree. Agents in separate worktrees push
onto the same stack, so `stash@{0}` means "whatever any agent stashed last," and a stash/pop to
reach a "clean" tree can silently move another agent's work onto your branch.

- **Read `git stash list` alongside `git status`.** A clean `git status` is no longer evidence that
  nothing is pending: zero uncommitted files plus a stash stack full of "not mine" entries is the
  pattern to look for. Measured 2026-09-04: an agent checked out its own branch inside a sibling's
  worktree, stashing the sibling's 189-line WIP to reach a clean tree — the sibling's worktree then
  reported clean, and a rescue sweep that only reads `git status` found nothing. The work was
  recovered only by reading `stash@{1}` by hand.
- **Never `git stash`, and never `git checkout <other-branch>`, inside a worktree you did not
  create, while other agents are running.** Both reach for a "clean tree" by moving shared state.
  The house alternative already exists: copy the file(s) you need out of the way to the scratchpad
  instead of stashing.

## 2. SWEEP the board

Residue · unresolved threads · branch-without-PR · unarmed auto-merge · PR behind base · free
dispatch surface — six questions, one versioned tool, never re-derived by hand:

```bash
bash ai_clients/claude/hooks/subagent_stop_sweep.sh <<<'{}' | jq -r '.hookSpecificOutput.additionalContext'
```

This is the same script the `SubagentStop` hook already runs on every agent completion
(dotfiles-dev#195 — it used to exist only in a session scratchpad, so the next session either
rewrote it from scratch or skipped it). It derives the repo and default branch from `git
remote`/`git ls-remote`, never a hardcoded owner/repo, and calls the shared
`gate_pr_thread_state` implementation in `hooks/lib/review_thread_gate.sh` instead of re-deriving
the review-thread verdict. Run it by hand here for the same report outside a `SubagentStop`
trigger — a fresh round, or a manual `/s:dev-loop` invocation with no subagent having just
finished.

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

1. **Classify the slot, three states plus an escape hatch — never a binary busy/free.** Read the
   newest roster notice, querying `is:pr` **without** `is:open`: a PR that merged since its last
   notice still spent the same account-level quota, and scoping to open PRs alone makes that spend
   invisible.

   | state | discriminator | means |
   |---|---|---|
   | `REVIEW-LIMITED` | body matches `rate limit`, no `chat message` | busy — honour the stated wait ("Please wait 4 minutes and 37 seconds") when the notice carries one; fixed-window only when it doesn't |
   | `CHAT-LIMITED` | body contains `chat message` | a **different** quota was hit — review slot untouched, treat as free |
   | `OK` | no rate-limit notice newer than the last completed review | free |
   | `UNKNOWN` | matches `rate limit` but neither phrase is conclusive | **not** free — treat as busy and say so; an unrecognised notice must never default to OK |

   🔴 Measured on blueprintx, 562 notices over 7 days: 89.5% REVIEW, 10.5% CHAT — and the *newest*
   notice decides, so one CHAT notice landing last must not read as an hour-long block when the real
   wait was 4m37s (blueprintx#363, 2026-08-30 18:44:28Z).

   ⚠️ **A push this round is an ask too, even with no notice.** CodeRabbit re-reviews on push, and a
   push-triggered re-review posts no roster comment — the notice can read `OK` while the quota is
   already spent. If RESCUE or THREADS pushed to any open PR earlier **this round**, treat the slot
   as already contended and **re-read the roster note immediately before step 3 below**, not from a
   read taken at the top of the round. Measured 2026-09-03: pushes at 12:25 and 12:32 (thread fixes)
   each triggered a silent re-review, and the deliberate ask at 12:33 was refused with "next included
   review will be available in 49 minutes" — a window that had grown from 8 minutes an hour earlier,
   priced by pushes nobody counted. ⚠️ Do not fix this with a `sleep`: the window is an account-level
   quota, not elapsed-time-since-last-ask, and sleeping into it stops the loop doing the other six
   things. 🎯 Whether THREADS should run *after* this step is a real question — a deliberate ask
   beats a push to the quota if issued first — but **measure before reordering**: THREADS unblocks
   merges directly and may be worth more than one ask. Keep the current order until that trade-off
   has a number behind it.
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
3. **Ask a human first — the bot is the fallback, not the default.** Read the Reviewers panel
   before spending the bot ask in item 4:

   ```bash
   rtk gh pr view <n> --json reviewRequests,reviews,author \
     --jq '{requested:[.reviewRequests[].login],
            reviewed:[.reviews[].author.login],
            author:.author.login}'
   ```

   | state | action |
   |---|---|
   | nobody requested, a non-author candidate exists | `rtk gh pr edit <n> --add-reviewer <login>` |
   | requested, no submitted review, request older than 24h | re-request — the ⟳ button in the panel: `rtk gh api -X POST repos/{owner}/{repo}/pulls/<n>/requested_reviewers -f 'reviewers[]=<login>'` |
   | requested and recent | leave it alone |
   | no assignable candidate | report once, fall through to item 4 |

   Candidates are `rtk gh api repos/{owner}/{repo}/collaborators --jq '.[].login'` minus the PR
   author. `triage` permission is enough to *be requested*; `write` is needed to *approve*.

   ⚠️ **GitHub rejects a review request from the PR's own author.** A repo with ONE maintainer
   therefore has a structurally empty Reviewers panel and this branch can never fire — measured on
   dotfiles-dev#260, which sat at `Reviewers: No reviews` with no assignable candidate. That is a
   configuration fact, not a defect in this step, and the required behaviour is to **degrade
   loudly**: say `no assignable reviewer (N collaborators)` exactly once, fall through to item 4,
   and never claim a review was requested. Precondition tracked in dotfiles-dev#268 — it needs a
   second collaborator on the repo, which is an owner action.

   ⚠️ **Re-request only a stale request, never every round.** A re-ping each cycle is spam, and it
   trains the one reviewer you have to ignore the notification — which costs more than the idle
   slot it was meant to fix. The 24h threshold is a default, not a measurement; move it when
   there is one.

4. **At most one ask per round — comment or push, whichever came first.** A burst genuinely trips
   the account limit — 12 rate-limit notices in 11 minutes, measured.

   🔴 **Then stop reading the ack.** CodeRabbit edits the acknowledgement **in place**: measured on
   blueprintx#330, 2026-09-01, the same comment id read `"Full review triggered"` at +10s and
   `"⚠️ Action not completed — Review rate limited."` after an edit at +8s post-create —
   `createdAt` unchanged, comment id unchanged, nothing about its identity revealing the swap. A
   poller that reads once and stops cannot tell an acceptance from a refusal-in-progress, and no
   fixed wait is safe against an edit that landed at +8s.

   The durable evidence is a **submitted review attributed to the head commit**, which step 4's gate
   already computes and cannot be edited away. So: **post the ask, report "requested — verdict
   pending," and let step 4 settle it next round.** Do not poll the ack — a refusal and an
   acceptance-then-refusal are the same outcome, and the ack only answers a question the gate answers
   more reliably.

Report **time-to-first-review per PR**, never requests per hour: a PR sitting unreviewed is the
user-visible cost, and that is the number this step must move.

Say **which branch fired** — human requested, re-requested, no assignable reviewer, or bot ask —
in one line. The four outcomes look identical from outside the loop, and "no assignable reviewer"
in particular is a standing configuration gap that stays invisible if the step only reports when
it acted.

## 5. RELEASE — evaluate and cut

```bash
rtk git diff --name-only $(rtk git describe --tags --abbrev=0 origin/main)..origin/main -- <shipped-paths>
```

Empty → **no release**, and say so. Non-empty with no breaking change → PATCH under 0.x.

🔴 **CUT IT. Do not ask.** Standing decision, 2026-08-30: *"sempre seguir com a release quando
possível, prefiro que sempre que possível seja publicado mediante o código estar funcional."* A
shipped diff that has passed the gates is a release; holding it for a confirmation adds no
information and leaves working code unpublished.

⚠️ **"Functional" is the condition, and it is already answered by the time you get here** — the
change is on the default branch, which means it cleared the required checks. Do not re-litigate it.

### The two former exceptions, one automated and one not — the split is decidability

**Breaking: compute it, do not ask.** `type!:` / `BREAKING CHANGE:` in `git log <tag>..HEAD` is a
grep, and the bump table settles the rest (0.x: breaking → MINOR, feat/fix → PATCH). There is no
judgment left to confirm. **Cut it and announce the bump you computed**, so a wrong table is
visible rather than silent.

```bash
git log "$tag"..origin/main --format='%s%n%b' | grep -cE '^[a-z]+(\(.+\))?!:|^BREAKING CHANGE:'
```

**A known defect in the shipped diff: signal, then decide — this one cannot be mechanised.** The
measured precedent is real: a vendor-allowlist PR merged at 01:11Z with an `import(variable)`
bypass, and the issue describing that bypass was opened at 01:35Z — *before* the cut was proposed.
Cutting would have shipped a deny-by-default gate with a documented hole to every generated
project, and **a gate that creates false confidence is worse than none.**

⚠️ **The obvious automation does not work, and it was measured.** Searching open issues for the
shipped filenames returned **6 matches for a 2-file diff**, none of them a defect in those files —
issues mention a path for context far more often than they report a fault in it. A veto on that
signal would block nearly every release; trusting it would be theatre.

So the rule is:

- surface it — list open issues referencing any shipped path, as **context, never a verdict**;
- ⚠️ hold **only** when a specific defect is known to be *in the shipped code* — which in practice
  means this session found it, or an issue names the shipped path as the location of a fault;
- otherwise cut, and say which issues you saw and why they do not block.

🎯 The distinction that decides it: *did something you already know make the shipped artifact
wrong?* That is a fact this session holds, not a query it can run.

Verify all three, none implies another: **per-job conclusions** (a skipped publish behind a
cancelled matrix reads as success at the run level), **the tag exists**, **the release is not a
draft** (a draft creates no tag, and tag-derived versioning then loses it silently).

⚠️ Read the shipped paths from the packaging manifest, never from intuition. A Python-shaped default
on a non-Python repo fails **silently and inverted** — it *suppresses* a release rather than
erroring. `.claude/release.conf` is the declared list where one exists.

## 6. DISPATCH — the loop's other half

### Pre-dispatch: is there room to finish what you're about to start?

🔴 **Check budget at spawn time, not at 90%.** A 90% context/quota alarm narrows the window in
which a kill does damage without shrinking the damage itself — three subagents measured killed
mid-flight held 662/694/256 uncommitted lines, and the loss was caused by holding work to the end,
not by an alarm threshold (dotfiles-dev#167). An agent takes roughly 10 minutes; dispatching one
at 85% of this session's own remaining budget is a predictable loss, not a risk to weigh.

This is a judgment call the orchestrating session makes about itself, not a hook — no script can
read another process's remaining context/quota, so unlike the checks above it stays session
knowledge (the same decidability test the `Do Not` section applies to every exception: data →
automate it, session knowledge → it stays a judgment, and it should say so). Before firing each
agent this round: note the visible context/quota remaining, skip or stagger dispatch when it is
low, and prefer a memory checkpoint over a fresh spawn when in doubt — a checkpoint is cheap and
its entire value is existing before the window closes, the same principle step 0 already applies
to the 7-day cron expiry.

Compute the free surface: the exact files the open PRs touch, versus the exact files each open
issue would touch. Dispatch agents for what does not collide.

⚠️ **Collision is exact-path, file by file — never a directory prefix.** Measured 2026-09-04:
reading a "concentration by top-5-directory" summary instead of the exact path list reported 9 of
11 candidate issues as colliding; the exact recount showed 43 files held by 14 PRs, and a directory
holding 6 of 200 files was 97% free the whole time. Three more agents were dispatched in the same
minute once the check switched to exact paths. An aggregate over a per-item constraint always
overestimates it — same family as the rtk-proxy `(empty)` collapse and a `wc -l` counting an empty
line: a lossy summary read as field truth. If a sweep tool hands you a directory-level
"concentration" figure, treat it as a human-reading aid only, never as the collision verdict.

Name three states, not two — collapsing the third into "blocked" is the failure:
- **free** — no open PR's exact file list intersects this issue's files.
- **held** — an open PR's exact file list intersects this issue's files.
- **would-need-a-held-file** — the issue's natural solution touches one file another PR holds, but
  the rest is free. Not a "no": it is usually one trivial line (e.g. an added `cp` line) — dispatch
  it anyway and land the small conflict as its own commit at the end, the house pattern for trivial
  overlaps.

🔴 **Before dispatching anything, confirm it is not already done.** A file-collision check only
sees PR-vs-PR overlap; it cannot see an issue already satisfied by code that already merged.
Measured 2026-09-04: 2 of 3 issues grouped into one agent were already shipped (one predated the
repo's own first commit), and a second issue's own reproduction no longer reproduced against
current `master`. The rule is symmetric:
- **Feature-shaped issue:** confirm the thing does not already exist — read the file/config it
  asks for before writing a duplicate line.
- **Defect-shaped issue:** confirm it still reproduces against current `master` — a sibling PR
  merged since filing may have already changed the behaviour.

State the command and its output in the PR (or in the issue, if closing without one). If already
satisfied, **stop and report — do not open a PR.** Closing an already-satisfied issue with
`git log -S` / `gh pr view` evidence is cheaper and more honest than a no-op PR, and it leaves the
reason in the thread. An issue's age is a decay signal worth weighing, not a decision by itself.

🔴 **The open-PR-already-claims-it check must also catch a merged PR that forgot the `Closes #N`
link.** `is:pr is:open` is invisible to a PR that shipped the fix and merged without declaring it —
measured: a dispatched agent spent ~104k tokens confirming blueprintx#135 was already done by PR
#292, merged days earlier, which closed two sibling issues and silently forgot this one. Drop
`is:open` from the query so merged PRs are visible too, and when a match or a suspicion surfaces,
confirm by reading the code on `main`/`master`, never by the PR's title alone — then close the
orphaned issue so the next round does not dispatch the same agent again.

```bash
gh api graphql -f query='{search(query:"repo:OWNER/REPO is:pr",type:ISSUE,first:60){
  nodes{... on PullRequest{number state closingIssuesReferences(first:5){nodes{number}}}}}}' \
  --jq '.data.search.nodes[]|.number as $p|.state as $s|.closingIssuesReferences.nodes[]|"\(.number) <- PR #\($p) (\($s))"'
```

⚠️ **Do not trust the branch-name heuristic for this.** Matching a trailing `-<issue>` in the branch
name misses a PR whose branch was named after a different slice, which is exactly how it failed:
measured 2026-08-30, an agent was dispatched for #145 while **PR #279 had been open four days**
closing the same issue and touching the identical two files. The duplicate PR had to be closed. The
`closingIssuesReferences` query above is the reliable form — it reads what GitHub itself will act
on at merge time.

⚠️ **If the free surface is empty, state it.** That is information, not silence.

Every brief carries:
- 🔴 **qualify the target — always, not just here.** Every repository command starts with
  `cd <absolute-path> &&`; every git command that compares with a base names it explicitly as
  `origin/<base>`, never a bare local branch or an implicit `HEAD`. The harness resets cwd after
  every Bash call, and it can reset to a **different repo** — an unqualified command then answers
  about whatever the shell happens to point at, and the wrong answer is plausible, not an error.
  Measured 2026-09-05 twice: cwd reset mid-task from a worktree to `~/github/blueprintx` with no
  `cd` run, and an unref'd `git describe --tags --abbrev=0` on a stale feature-branch checkout was
  16 tags behind `origin/main` — the release step's shipped-diff gate would have cut the wrong
  version with nothing going red. `git -C <path>` does not substitute for this: it fixes the
  directory but not the implicit-HEAD half of the bug (dotfiles-dev#229);
- 🔴 **confirm before writing** — the feature/defect check above; state the command and its output;
- 🔴 **commit and push at the first coherent point, then keep committing** (the measurement above);
- 🔴 **verify HEAD belongs to you and holds your diff — not just that it exists.** `git log -1`
  shows an empty commit and a foreign commit exactly as it shows a real one; the same
  `[branch abc1234] N files changed` success line prints regardless. Confirm with
  `git diff <sha>^ <sha> --stat`, never `git log -1` alone. Measured: a genuinely empty commit
  passed every hook with full "success" output, and a foreign commit leaked from a sibling agent
  onto the wrong branch the same way (dotfiles-dev#162);
- when `isolation: "worktree"` is in play, prefer an explicit `git worktree add <own-path>` over
  trusting the harness-provided directory to be exclusively yours if its identity is ever in
  doubt — two agents were measured sharing one physical worktree directory, one wiping the
  other's files mid-task (dotfiles-dev#162);
- 🔴 **never `git stash`, and never `git checkout` of another branch, inside a worktree you did not
  create** — the stash stack and the checkout are both shared across worktrees; copy to the
  scratchpad instead (step 1);
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
- Do not ask permission to run this, and do not ask before cutting a release — see step 5.
- Do not arm a host-level timer (systemd, a durable cron) for the round. `CronCreate` jobs dying
  with the session is the requirement from step 0, not a gap to fill with something durable.

⚠️ **The one standing ask, and it is scoped narrowly on purpose:** an outward-facing action that is
**hard to reverse and not this loop's own work** — changing branch protection or required checks,
force-pushing over someone else's commits, closing a PR that is not yours, changing a repo setting.
Everything the loop does routinely (commit, push, open a PR, reply, resolve, re-run a check, update
a branch, dispatch an agent, cut a release) is reversible or additive, and asking about those is
the ceremony this file exists to remove.

🎯 **The decidability test, for any exception added later:** does the check answer from **data**, or
from something **this session knows**? Data → automate it. Session knowledge → it stays a judgment,
and it should say so rather than pretending to be a rule.

Re-run that test on every carve-out when the rule it qualifies changes. ⚠️ **Exceptions inherit the
ceremony of the rule they qualify** — measured twice in this file: the release step became
autonomous while its two exceptions stayed asks, and this `Do Not` line still said "ask before
cutting a release" after step 5 had been rewritten to cut.

## Reporting

Report only what **changed**, plus anything that needs the owner. If a step found nothing, one line.
If nothing at all changed since the last round, say *"no change"* and stop.
