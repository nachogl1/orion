---
name: fable-project-updates-orion
description: |
  Turn a raw list of updates, corrections, bugs, and ideas for an EXISTING project into
  agent-ready GitHub epics/stories — discussing with the user ONLY the items that genuinely
  need them. Phase 1 fans out one grounding agent per item in parallel (ultracode Workflow):
  each deep-dives the actual code to verify the item's claims, classify it (bug / improvement /
  feature / question / already-done), and either drafts a complete agent-ready issue or flags
  it as needing a human decision. Phase 2 walks ONLY the needs-discussion pile (plus anything
  the user flags) one item at a time, itemize-style: plain restatement, options with pros/cons,
  one recommendation, wait for the user's pick. Feature-sized items get an in-session epic/story
  breakdown reviewed with the user before filing. Phase 3 dedupes against existing open issues
  (mandatory deep dive — reuse over create) and files everything as GitHub issues, grouped
  under epics where natural, each meeting the agent-ready bar so a downstream pipeline (e.g.
  /fable-sequential-gh-orion-v1) can execute it unattended. Use when the user says
  "/fable-project-updates-orion", "here's my list of fixes/updates", "turn these notes into
  issues", or pastes a backlog-shaped list for an existing codebase.
---

# fable-project-updates-orion

> [!NOTE]
> This skill has **no `-vN` convention** — it's edited in place. If you change behaviour,
> update this file directly and keep the repo CHANGELOG-free for it.

You take a user-supplied list of items about an **existing** project and leave behind a clean,
deduped, agent-ready GitHub backlog — having consumed as little of the user's attention as
possible: items an agent can fully understand from the code are never discussed; items needing
a human decision are discussed properly, one at a time.

GitHub Issues are the source of truth. No methodology files. Project-agnostic: detect stack,
conventions, and tracker vocabulary (labels, epic style) from the target repo at run time.

---

## Phase 0 — Intake

1. If invoked without a list: ask the user to paste it (bullets, numbered lines, prose chunks,
   a file path — all fine). Parse into discrete items; show the parsed list with item numbers
   and ask only if parsing was genuinely ambiguous (merged/split items).
2. Pre-flight: `gh auth status` + `gh repo view` must succeed. Detect the repo's issue
   conventions: how epics are represented (labels? milestones? tracking issues?), existing
   label set, title patterns. Mirror what the repo already does; invent nothing.
3. Ask ONE scoping question (AskUserQuestion) only when needed: "any items you already know
   you want to discuss in person?" (multiSelect over the parsed items, default none).

## Phase 1 — Parallel grounding (ultracode Workflow; no user contact)

Fan out **one read-only grounding agent per item** (cap parallelism at the Workflow's natural
limit; all read-only, so no isolation needed). Each agent receives the item text + repo root
and must:

- **Verify every claim against the live code** (the v4 grounding rule): does the described bug
  reproduce in the code path? Does the feature already exist? Is the assumption about current
  behaviour accurate? Cite file:line evidence for every conclusion.
- **Classify**: `bug` / `improvement` / `feature` / `question-for-user` / `already-done` /
  `wont-reproduce`.
- **Size**: S / M / L / epic-sized (informational; epic-sized triggers Phase 2 breakdown).
- **Draft or flag**: if the item is fully understandable from code + item text, return a
  complete draft issue (title, body with context + acceptance criteria + evidence paths +
  suggested labels). If anything requires a product/design/priority decision a human must make,
  return `needs-discussion` with the SPECIFIC decision(s) spelled out, options sketched, and a
  recommendation — so Phase 2 starts ready.
- Return schema: `{classification, size, evidence: [...], draft: {...} | null,
  needsDiscussion: [{decision, options, recommendation}] | null}`.

Present the triage table to the user: per item — classification, size, one-line conclusion,
and DISCUSS vs AUTO-DRAFTED vs ALREADY-DONE (with evidence). `already-done`/`wont-reproduce`
items are reported with their evidence and dropped unless the user objects.

## Phase 2 — Discussion (one item at a time; itemize-orion protocol)

Walk ONLY: `needs-discussion` items + `question-for-user` items + anything the user flagged in
Phase 0 or after the triage table. For each, the itemize discipline applies verbatim:

- Restate plainly (junior-dev framing: zero stack/domain knowledge assumed); context brief with
  real file paths from the grounding evidence; 2–4 options each with pros/cons; exactly ONE
  recommendation defended in a sentence; then WAIT for the user's pick. One item at a time —
  never bundle. Record each decision; "back to item N" / "skip" / "add: <item>" navigation
  supported throughout.
- **Epic-sized items** (from any pile): before filing, do the breakdown IN-SESSION — propose
  the epic + child stories (each story independently shippable, agent-ready, with ACs), show
  the tree, iterate until the user approves it. No cloud planning tools; the review happens
  right here in the conversation.

## Phase 3 — Dedupe & file

1. **Mandatory dedupe deep-dive before filing anything** (the repo rule): for every draft,
   search open AND recently-closed issues with multiple term variations AND check whether code
   already covers it. Read candidates, don't count them. Match found → link/comment on the
   existing `#N` instead of filing; report the reuse. State what was searched per item.
2. File the issues: epics first (using the repo's own epic convention), then stories/bugs
   referencing their epic. Each body: plain description, context + evidence paths from
   grounding, acceptance criteria, suggested labels (create tolerantly), decision record
   ("Scope decision: ..." self-contained comment) for anything resolved in Phase 2 — so a
   downstream agent never needs this conversation.
3. Confirm each filed URL back to the user. No assignees unless asked.

## Phase 4 — Summary

One table: item → outcome (filed `#N` / reused `#N` / already-done / dropped / deferred-unresolved)
+ decisions taken. Then: "anything else to add to the list?" — append and continue, or done.

## Rails

- No file output in the target repo; the conversation + filed issues are the artifact.
- Never assign, close, or edit issues beyond what this flow defines; never start implementing
  (that's the pipeline's job — suggest `/fable-sequential-gh-orion-v1` at the end if the user
  wants the new backlog executed).
- When the user is mid-discussion and goes off-script: answer, then re-anchor ("back to item K?").
