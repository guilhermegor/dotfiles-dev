---
name: c:issue
allowed-tools: Bash(rtk gh issue*), Bash(rtk gh project*), Bash(rtk gh repo*), Bash(rtk git*), AskUserQuestion, Read, Grep
description: Create a GitHub issue (assigned to you), add it to the repo's kanban, and open a linked recommended-name branch
argument-hint: "<description of the work> [--label <name>] [--project <name|number>]"
---

You are creating a new work item end to end: a GitHub issue, its kanban card, and a linked
branch — the authoring half of a Linear-style flow. The runtime transitions (Ready → In
progress → Done) are handled by GitHub Projects' own workflows, NOT by this command. Follow
these steps exactly. `$ARGUMENTS` holds the work description (plus optional `--label` /
`--project`).

## 1. Derive title, type, and slug

From the description:
- Infer a Conventional type: `feat` (default), `fix`, `docs`, `refactor`, `test`, or `chore`.
- **Title:** `<type>: <concise summary>`.
- **Slug:** kebab-case of the summary — lowercase ASCII, words joined by `-`, no accents.

## 2. Detect repo context

Run: `rtk gh repo view --json name,owner,defaultBranchRef`
Extract `name` (repo), `owner.login`, and `defaultBranchRef.name` (base branch).

## 3. Create the issue

Build the body from this template (the **Documentação** section is mandatory — it is a standing
requirement, keep it verbatim):

```
## Objetivo
<one-paragraph statement of what this work delivers>

## Escopo
- <bullet(s) scoping the change>

## Documentação
- Atualizar `docs/` e o `README.md` quando necessário — novo comportamento, mudança na API
  pública, ou novo exemplo de uso. A entrega só está completa com a documentação em dia.
```

Create it (add `--label <name>` only if `--label` was passed in `$ARGUMENTS`):

`rtk gh issue create --title "<title>" --body "<body>" --assignee @me [--label <name>]`

Capture the issue number `<N>` and URL from the output.

## 4. Find the kanban project

List the owner's projects: `rtk gh project list --owner <owner> --format json`.
Match the project whose title equals **`<repo> kanban`** (e.g. `filings-cvm kanban`).

- If `--project <name|number>` was passed, use that instead.
- **If no match is found and none was passed → ask the user** (AskUserQuestion) how to proceed.
  Offer: (a) **create** a new project named `<repo> kanban` (recommended), (b) create one under a
  different name they type, or (c) use an existing project they name. Do not guess and do not
  silently create.
- To create: `rtk gh project create --owner <owner> --title "<chosen name>" --format json`, then
  record its number and node id.

  **Then normalize the Status columns.** A `gh`-created board ships GitHub's *default* options
  (`Todo` / `In Progress` / `Done`), which do **not** match the standard kanban (`Backlog` /
  `Ready` / `In progress` / `In review` / `Done`). Bring it into line so every board created by
  this command is consistent — get the Status field id from `field-list`, then:

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

Record the project's number and node id.

## 5. Add the card and set its status

Add the issue to the board: `rtk gh project item-add <project-number> --owner <owner> --url <issue-url>`

Then choose the status. **Ask the user** (AskUserQuestion) which bucket the card starts in, and
**explain the design in the prompt** so the choice is deliberate, not arbitrary:

- **`Ready`** — all **three** upstream questions are answered: **why** (*discovery* — the
  problem is validated and worth doing), **what** (*specification* — scope and acceptance
  criteria are written down), and **how** (*technical feasibility* — the approach is known, no
  blocking unknowns). Product upstream = discovery + specification; technical upstream =
  feasibility. Pull-ready for implementation.
- **`Backlog`** — **at least one** of the three is still open: the *why* is unvalidated, the
  *what* is unspecified (no acceptance criteria), or the *how* is unproven. It needs
  discovery / specification / spiking before it can be picked up.
- **Other** — any other board column, if the user names one.

**Default to `Ready`** when the user gives no answer (assume both upstreams are cleared). If the
board genuinely lacks a `Ready` option (e.g. a not-yet-normalized board), fall back to the first
not-started option.

Resolve the field + option ids and set it:
- `rtk gh project field-list <project-number> --owner <owner> --format json` → the `Status`
  field id and the chosen option's id.
- `rtk gh project item-edit --project-id <project-node-id> --id <item-id> --field-id <status-field-id> --single-select-option-id <option-id>`

(`item-add` prints the item id; if not, get it from `rtk gh project item-list … --format json`.)

## 6. Open the linked branch

Create a branch linked to the issue (this is the recommended-name step — it makes the future PR
auto-associate with the issue):

`rtk gh issue develop <N> --repo <owner>/<repo> --name <type>/<N>-<slug> --base <base> --checkout`

## 7. Report

Output, concisely:
- Issue: `#<N>` + URL
- Board: `<project> → <status>`
- Branch: `<type>/<N>-<slug>` (checked out)
- **PR snippet:** ```Closes #<N>``` — tell the user to paste it in the PR body so merging the PR
  closes the issue, which the board's "Item closed → Done" workflow then moves to Done.
