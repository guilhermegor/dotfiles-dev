---
name: c:issue
allowed-tools: Bash(rtk gh issue*), Bash(rtk gh project*), Bash(rtk gh repo*), Bash(rtk gh api*), Bash(rtk git*), Bash(rtk proxy curl*), AskUserQuestion, Read, Grep
description: Create or resume a tracked issue (assigned to you), add it to the kanban, and open a linked recommended-name branch
argument-hint: "<description | #number | issue-url> [--new] [--parent <n>] [--work <type>] [--label <name>] [--project <name|number>] [--tracker <github|linear>]"
---

You are taking a work item end to end: an issue, its kanban card, and a linked branch — the
authoring half of a Linear-style flow. This command only sets the card's *starting* column
(step 7); the runtime transitions are then automatic and NOT set here:

- **In progress** (on branch open) and **In review** (on PR open) are driven by the
  `kanban_lifecycle.sh` PostToolUse hook — GitHub Projects' native workflows cannot trigger
  on those events.
- **Done** is driven by GitHub Projects' own "item closed / PR merged → Done" workflow (the
  `Closes #N` link in step 9 feeds it).

Follow these steps exactly. `$ARGUMENTS` holds an issue reference *or* a work description,
plus optional flags.

## Two type axes — never conflate them

| Axis | Values | Drives |
|---|---|---|
| **Conventional type** | `feat` `fix` `docs` `refactor` `test` `chore` | title prefix, branch name |
| **Work type** (`--work`) | `research` `prototype` `grilling` `task` | issue type field, HITL/AFK label, **starting column** |

Conventional type says *what the change is*. Work type says *how the ticket gets resolved*.
A `feat` is perfectly able to be a `research` ticket.

## 0. Resolve the tracker

Precedence — identical to `branch_requires_issue_guard.sh`, so hook and command can never
disagree about a repo:

1. `--tracker <github|linear>` in `$ARGUMENTS`
2. `$CLAUDE_ISSUE_TRACKER`
3. `~/.claude/issue-trackers.conf` — lines `<match>  <github|linear|none>`, first match wins.
   `<match>` is a substring tested against the `origin` remote URL first, then the repo
   directory name. Read it with the **Read** tool; `#` and blank lines are comments.
4. auto-detect: a `github.com` origin → `github`, otherwise `none`.

`none` → **stop.** Say the repo has no tracker configured and point at
`~/.claude/issue-trackers.conf`. Do not guess a tracker and do not create anything.

`linear` → check `LINEAR_API_KEY` is set (`printf '%s' "${LINEAR_API_KEY:+set}"`). If it is
**not**, stop and say so, then offer exactly two ways forward — never authenticate on your own:

> This repo tracks in Linear, but `LINEAR_API_KEY` is unset, so I cannot reach the API.
> Either export a Linear personal API key (the same one
> `branch_requires_issue_guard.sh` uses), or say the word and I will run
> `mcp__linear__authenticate` for this session only.

All Linear API calls in this command go through `rtk proxy curl` — **raw, unfiltered**, because
the responses are JSON parsed by `jq` and the token-filtering proxy would corrupt them:

```
rtk proxy curl -sS --max-time 15 -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" -H 'Content-Type: application/json' \
  --data "$(jq -n --arg q '<query>' --argjson v '<variables>' '{query:$q,variables:$v}')"
```

Never use the Linear MCP server here. It requires OAuth and, once authenticated, its tools
surface in every session of every project — a standing token cost for a command that is mostly
run against GitHub.

## 1. Detect workspace context

**github:** `rtk gh repo view --json name,owner,defaultBranchRef` → `name` (repo),
`owner.login`, `defaultBranchRef.name` (base branch).

**linear:** resolve the team. Take the key from `--tracker`'s companion if given, else the
`issue-trackers.conf` match, else ask. Then one query for everything downstream needs:

```graphql
query($k:String!){ viewer{ id }
  teams(filter:{key:{eq:$k}}){ nodes{ id key name
    states{ nodes{ id name type position } }
    labels{ nodes{ id name } } } } }
```

Keep `viewer.id` (the assignee), the team id, its workflow states and its labels.

## 2. Resolve the target issue

The issue may already exist. This step decides; everything after is either *create* or *resume*.

If `$ARGUMENTS` has no description and no reference, ask the user what the work is.
If `--new` was passed, skip straight to step 3 (create path).

| `$ARGUMENTS` looks like | Action |
|---|---|
| `#42`, `42` | **github:** `rtk gh issue view 42 --repo <owner>/<repo> --json number,title,url,state,labels` |
| `ABC-42` | **linear:** query `issues(filter:{team:{key:{eq:"ABC"}},number:{eq:42}})` |
| a URL ending `/issues/42` | as above, using the owner/repo **from the URL** |
| anything else | search (below) |

**Search path.** Treat the text as a query, not a title:

- **github:** `rtk gh issue list --repo <owner>/<repo> --state all --search "<text>" --json number,title,url,state --limit 10`
- **linear:** `issueSearch(query:"<text>", first:10){ nodes{ identifier title url state{ name } } }`

Then:

- **Exactly one hit whose title clearly covers the request** → confirm with AskUserQuestion
  ("Resume `#<N> <title>`?" / "No — create a new issue"). Never adopt an existing issue silently.
- **Two or more plausible hits** → AskUserQuestion listing the top 3 as
  `#<N> — <title> (<state>)`, plus a final **"None of these — create a new issue"** option.
  Order by relevance as returned; prefer open over closed when scores are close.
- **Zero hits** → say so in one line and fall through to the create path.

Once resolved to an existing issue:

- If it is closed, ask whether to reopen (`rtk gh issue reopen <N>` / `issueUpdate` with the
  team's first `backlog` state) or create a new one. Do not reopen without an answer.
- Skip steps 3–6. Keep the existing title/body. Derive the **slug** from its title and the
  **conventional type** from its `<type>:` prefix (default `feat`). Read the **work type** and
  **mode** from its existing type field or `type:` / `hitl` / `afk` labels rather than re-asking.
- Continue at step 7 — the card and branch steps are idempotent: `item-add` on an issue already
  on the board is a no-op, and step 8 checks for an existing linked branch first.

## 3. Derive title, conventional type, and slug

From the description:
- Infer a Conventional type: `feat` (default), `fix`, `docs`, `refactor`, `test`, or `chore`.
- **Title:** `<type>: <concise summary>`.
- **Slug:** kebab-case of the summary — lowercase ASCII, words joined by `-`, no accents.

## 4. Classify work type and mode

Infer the work type from the description, then **confirm with AskUserQuestion** (skip the ask
entirely if `--work` was passed). Explain the table in the prompt so the choice is deliberate:

| Work type | Mode | Column | Which upstream is still open |
|---|---|---|---|
| `research` | AFK | `Backlog` | *how* — the approach is unproven, but an agent can settle it alone |
| `prototype` | HITL | `Backlog` | *how* — needs a cheap, rough, concrete artifact built with you |
| `grilling` | HITL | `Backlog` | *what* — no acceptance criteria written down yet |
| `task` | either | `Ready` | none — *why*, *what* and *how* are all cleared; pull-ready |

This **derives the starting column**, so step 7 confirms a value rather than re-judging the
three upstreams from scratch every time. The user can still override to any board column.

**Recording it.** GitHub issue *types* are defined at organisation level, so a personal-account
repo may not have them. Do not probe with a dry run — attempt `--type <work-type>` at create
time (step 6) and, if GitHub rejects it, retry without the flag and apply a `type:<work-type>`
label instead. Linear has no type field at all, so it always uses the label form.

The mode is always a label on both trackers: `hitl` or `afk`.

On Linear, resolve label ids from the team's labels fetched in step 1; create any that are
missing with `issueLabelCreate(input:{teamId:…,name:…})` before attaching them.

## 5. Decide hierarchy

Default to a single flat issue. Ask about a parent/sub-issue split **only** when at least one
of these holds — otherwise do not raise it at all:

- `--parent <n>` was passed → file directly as a sub-issue of `<n>`; skip the ask entirely.
- The **Escopo** section you are about to write would carry more than 3 bullets.
- The description names two or more independently shippable deliverables.
- A `s:shape-up` artifact for this work exists with more than one scope.

When you do ask, offer: one flat issue, or a parent plus one sub-issue per deliverable (list the
deliverables you inferred so the user can correct them).

Parent bodies carry **Objetivo** plus a checklist of their children; children carry the full
template. There is no separate `/epic` command — it would duplicate the repo, board and branch
logic for no gain.

## 6. Create the issue(s)

*(Create path only — skip if step 2 resolved an existing issue.)*

Body template. The **Documentação** section is mandatory and stays verbatim — it is a standing
requirement:

```
## Objetivo
<one-paragraph statement of what this work delivers>

## Escopo
- <bullet(s) scoping the change>

## Documentação
- Atualizar `docs/` e o `README.md` quando necessário — novo comportamento, mudança na API
  pública, ou novo exemplo de uso. A entrega só está completa com a documentação em dia.
```

Per-tracker operations — one spine, two arms:

| Operation | `github` | `linear` |
|---|---|---|
| create | `rtk gh issue create --title "<title>" --body-file <f> --assignee @me` | `issueCreate(input:{teamId,title,description,assigneeId})` |
| work type | `--type <work-type>`, else `type:<work-type>` label on rejection | `type:<work-type>` label |
| mode | `--label hitl\|afk` | label id |
| extra label | `--label <name>` when `--label` was passed | label id |
| parent | `--parent <n>` | `parentId` on `issueCreate` |

Write the body with the Write tool to a scratchpad file and pass `--body-file` — never inline a
multi-line body into the shell, where the accented characters and backticks get mangled.

Capture the issue number/identifier and URL. Create the parent first when splitting, so its
number is available for the children's `--parent`.

## 7. Board card and column

**linear:** skip this step entirely. Linear's workflow states *are* the board — set the issue's
state directly with `issueUpdate(input:{stateId:…})`. Map by state **`type`**, never by display
name (teams rename states freely): `Backlog` → the first state of type `backlog`, `Ready` → the
lowest-`position` state of type `unstarted`. Then go to step 8.

**github:** list the owner's projects with `rtk gh project list --owner <owner> --format json`
and match the project titled exactly **`<repo> kanban`** (e.g. `filings-cvm kanban`).

- **More than one project with that title → stop and ask which to use** (list them as
  `#<number> — items:<count>`). Never pick one silently: the lifecycle hook matches boards by
  title too, so two same-named boards make every card move non-deterministic. Offer to delete the
  extras once the user names the keeper (`rtk gh project delete <number> --owner <owner>`).
- If `--project <name|number>` was passed, use that instead.
- **No match and none passed → ask** (AskUserQuestion). Offer: (a) **create** a project named
  `<repo> kanban` (recommended), (b) create one under a name they type, or (c) use an existing
  project they name. Do not guess and do not silently create.
- To create: `rtk gh project create --owner <owner> --title "<chosen name>" --format json`, then
  record its number and node id.

  **Then normalize the Status columns.** A `gh`-created board ships GitHub's *default* options
  (`Todo` / `In Progress` / `Done`), which do **not** match the standard kanban. Get the Status
  field id from `field-list`, then:

  ```
  rtk gh api graphql -f query='
  mutation($fieldId: ID!) {
    updateProjectV2Field(input: { fieldId: $fieldId, singleSelectOptions: [
      {name: "Backlog",     color: GRAY,   description: "This item hasn'"'"'t been started"},
      {name: "Ready",       color: GREEN,  description: "This is ready to be picked up"},
      {name: "In progress", color: YELLOW, description: "This is actively being worked on"},
      {name: "In review",   color: PURPLE, description: "This item is in review"},
      {name: "Done",        color: PURPLE, description: "This has been completed"}
    ] }) { projectV2Field { ... on ProjectV2SingleSelectField { options { name } } } }
  }' -F fieldId="<status-field-id>"
  ```

  **Then tell the user to enable the Done workflows — the API cannot.** A `gh`-created board
  ships its built-in workflows **disabled**, and the GraphQL API exposes no mutation to enable
  them (only `deleteProjectV2Workflow`). So the "card → Done on merge" automation this command
  relies on is **off until a human flips it**. Print this and wait for confirmation:

  > Open `https://github.com/users/<owner>/projects/<number>/workflows` and enable, each with
  > **Set value → Status → Done**:
  > - **Item closed**
  > - **Pull request merged**
  >
  > Do **not** enable **Pull request linked to issue** — the `kanban_lifecycle` hook already
  > moves the card to *In review* when the PR opens, and enabling this native workflow would
  > fire at the same moment and race it (it defaults to *In progress*, dragging the card
  > backwards).

Add the card (parents and children both):
`rtk gh project item-add <project-number> --owner <owner> --url <issue-url>`
(Safe to re-run — an issue already on the board is not duplicated.)

Set the column to the value **derived in step 4**. State the derivation in one line
(`work type <x> → <column>`) and let the user override; do not re-ask the three upstreams.

**On the resume path**, first read the card's current status from `item-list --format json`; if
it is already past `Ready` (e.g. `In progress`), report it and leave it alone.

If the board genuinely lacks the derived option (a not-yet-normalized board), fall back to the
first not-started option.

Resolve the ids and set it:
- `rtk gh project field-list <project-number> --owner <owner> --format json` → the `Status`
  field id and the chosen option's id.
- `rtk gh project item-edit --project-id <project-node-id> --id <item-id> --field-id <status-field-id> --single-select-option-id <option-id>`

(`item-add` prints the item id; if not, get it from `rtk gh project item-list … --format json`.)

## 8. Open the linked branch — leaf issues only

**Never cut a branch for a parent issue.** `branch_requires_issue_guard.sh` would allow it (the
ref is real), but a parent is a container: a PR closing it would close the children's tracking
with work still outstanding. When step 5 produced a split, branch from the first child and say so.

First check whether the issue already has one:

**github:** `rtk gh issue develop <N> --repo <owner>/<repo> --list`

- **A linked branch exists** → check it out (`rtk git checkout <branch>`, fetching first if it
  is only on the remote). Do not create a second branch.
- **None** → create one linked to the issue (the recommended-name step — it makes the future PR
  auto-associate with the issue):

  `rtk gh issue develop <N> --repo <owner>/<repo> --name <type>/<N>-<slug> --base <base> --checkout`

**linear:** Linear has no branch-linking API, so create it directly:

`rtk git checkout -b <type>/<team-key-lowercase>-<number>-<slug>`

The ref must stay in **leading slug position**: `branch_requires_issue_guard.sh` strips the
`<type>/` prefix before matching `[A-Za-z][A-Za-z0-9]*-[0-9]+`, so `feat/dit-456-add-thing`
resolves to `DIT 456`. This deviates from Linear's own `username/dit-456-slug` convention on
purpose — the house `<type>/` prefix is what the rest of the toolchain reads.

## 9. Report

Output, concisely — omit any line that does not apply:

```
Mode:    created | resumed
Tracker: github | linear
Issue:   #<N> <url>                    (or <TEAM>-<n>)
Type:    <conventional> / <work-type> (<hitl|afk>)
Parent:  #<P>                          (omit when flat)
Board:   <project> → <column>          (omit for linear)
Branch:  <type>/<ref>-<slug> (checked out)   (omit for parents)
```

Then the **PR snippet:** ```Closes #<N>``` — tell the user to paste it in the PR body so merging
the PR closes the issue, which the board's "Item closed → Done" workflow then moves to Done.
