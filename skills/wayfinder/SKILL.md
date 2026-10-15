---
name: wayfinder
description: 'ORION - Plan a chunk of work too big for one agent session as a shared MAP of decision tickets on the repo''s issue tracker, then resolve them one at a time until the way to the destination is clear. Charting starts by naming the DESTINATION (the spec, decision, or change this effort is finding its way to), then fans out breadth-first to surface the open questions; every question that can be stated sharply becomes a child ticket of the map, everything still blurry stays as written-down "fog" that graduates into tickets later, and anything past the destination is ruled out of scope. Tickets are typed — research (agent alone), prototype (build a rough artifact to react to), grilling (conversation with the user), task (manual work that unblocks a decision) — and each carries an inline protocol, so the skill needs no companion skills. PLANNING, NOT BUILDING: it produces decisions, never the deliverable, unless the map''s Notes say otherwise. Tracker-agnostic: detects GitHub Issues, Jira, or falls back to a local markdown map, and verifies parent/child and blocking support at run time instead of assuming it. Resolves at most ONE non-research ticket per session. Use when the user says "/wayfinder", "help me plan this big thing", "this is too big for one session", "chart the work", "work the map", or hands over a loose idea with no clear route to the end.'
argument-hint: "A loose idea to chart, or a map URL/number to work through"
disable-model-invocation: true
---

# wayfinder

> [!NOTE]
> **Editing this skill?** This skill has **no `-vN` convention** — edit it in place (like `project-handover` / `handoff`; see the repo's `CLAUDE.md`).

A loose idea has arrived. It is too big for one agent session and wrapped in fog: the way from here to the **destination** is not visible yet. Wayfinding is about *finding the way*, not charging at the destination. This skill charts the way as a **shared map** on the repo's issue tracker, then works its **decision tickets** — questions whose answer is a decision, not slices of a build to execute — one at a time until the route is clear.

**Jargon, defined once:**

- **Destination** — what reaching the end of this map looks like. A spec to hand off, a decision to lock before planning starts, or a change made in place (e.g. a data-structure migration).
- **Map** — one issue on the tracker holding the whole effort at low resolution. The canonical artifact.
- **Ticket** — a child issue of the map. One question, sized to a single agent session.
- **Fog of war** — decisions you can tell are coming but cannot yet phrase sharply enough to ticket.
- **Frontier** — the tickets takeable *right now*: open, not blocked by anything unfinished, and not claimed by another session.
- **HITL / AFK** — "human in the loop" (needs a live exchange with the user) versus "away from keyboard" (the agent drives it alone).

## Why this exists

An agent session has a fixed memory. Work that spans weeks does not fit in one, so plans made in chat evaporate: the reasoning is gone next session, and the next agent restarts from zero or, worse, re-decides something already settled. This skill moves the plan out of the chat and onto the tracker, where it survives session boundaries, is visible to teammates, and can be worked in parallel by several sessions without collisions.

## Core rules

1. **Plan, don't do.** Each ticket resolves a *decision*. The map is done when nothing is left to decide before someone goes and builds the thing. The pull to just do the work is usually the signal that you have reached the edge of the map and it is time to hand off. An effort can override this in the map's **Notes** — absent that, produce decisions, not deliverables.
2. **Refer by name, never by number.** Every map and ticket is an issue, so it has a title. In everything the user reads, call it by that title, linked. A wall of `#42, #43, #44` is unreadable; names read at a glance. The number and URL ride *inside* the link — they never stand in for it.
3. **At most ONE ticket resolved per session.** The single exception is `research` tickets, which may run in parallel as sub-agents because they read rather than decide.
4. **Never invent a fact.** Every claim written onto the map or a ticket must be backed by something you read — a file, a command's output, a cited source, or the user's own words. If it is a guess, label it as an assumption on the ticket.
5. **Never resolve a HITL ticket by yourself.** An agent that answers its own grilling questions has broken the skill. Ask the user and wait.
6. **Don't chart what you can't see.** Incompleteness is the design, not a defect — see [Fog of war](#fog-of-war).

## Phase 0 — Detect the tracker (do this first, every session)

Never assume a tracker. Detect it, and detect what it actually supports, before writing anything:

1. **GitHub Issues** — the default when `gh auth status` succeeds *and* `gh repo view --json hasIssuesEnabled` reports issues enabled. Confirm the repo with `gh repo view --json nameWithOwner`.
2. **Jira / other tracker** — if the repo's `CLAUDE.md`, `README.md`, `CONTRIBUTING.md`, or PR template points at one, ask the user (clickable options) which to use before falling back.
3. **Local markdown fallback** — no usable tracker. Write the map as files under `~/wayfinder/<repo-name>-<map-slug>/` (`map.md` plus `tickets/<nnn>-<slug>.md`), **outside** the repo so it never pollutes the tree or gets committed by accident. Tell the user plainly that a local map is **not shareable** — if teammates or parallel sessions need it, a real tracker is required.

**Then probe the two relationships the map depends on — do not assume them:**

- **Parent/child (sub-issues).** On GitHub this is the sub-issues API — try it once on the first ticket (`gh api` against the repo's sub-issues endpoint for the map's issue number). If the call errors for this repo, fall back to a **body convention**: the map body carries a `## Tickets` checklist of linked ticket names, and each ticket body opens with `Part of <map name>` as a link.
- **Blocking.** Prefer the tracker's **native** dependency relationship — it renders the frontier visually in the tracker's own UI, so the user sees what is takeable without opening the map. Probe it the same way; if the repo does not have it, fall back to a `Blocked by: <ticket name>` line in the ticket body, and treat that line as authoritative.

Report which tracker and which relationship mechanism you landed on, in one line, before proceeding.

## The map

One issue, labelled `wayfinder:map`. Create the label if it does not exist. The map is an **index, not a store**: a decision lives in exactly one place — its ticket — so the map gists it and links, never restates it. Open tickets are **not** listed in the body; they are found by querying the tracker for open children.

```markdown
## Destination

<What reaching the end of this map looks like: the spec, decision, or change this
effort is finding its way to. One or two lines. Every session orients to this
before choosing a ticket.>

## Notes

<Domain context; the stack and conventions detected from this repo; any skills or
docs each session should consult; standing preferences for this effort; whether
execution (not just decisions) is in scope.>

## Decisions so far

<!-- The index: one line per closed ticket, enough to judge relevance, then follow
     the link for the detail the ticket holds. -->

- [<closed ticket title>](<url>): <one-line gist of the answer>

## Not yet specified

<!-- In-scope fog you cannot ticket yet; graduates as the frontier advances. -->

## Out of scope

<!-- Work consciously ruled beyond the destination. Never graduates. -->
```

## Tickets

Each ticket is a child of the map. Its body is the question, sized to **one agent session** (rule of thumb: a question one focused sitting can settle — if it needs three sittings, split it):

```markdown
## Question

<The single decision or investigation this ticket resolves.>

## Why it matters

<One line: what downstream work is waiting on this answer.>

## Assumptions

<Anything taken on trust rather than verified, so a later session can challenge it.
Omit the section if there are none.>
```

Rules:

- **Type label.** Every ticket carries exactly one `wayfinder:research` / `wayfinder:prototype` / `wayfinder:grilling` / `wayfinder:task` label. Create missing labels once, at charting time.
- **Claiming.** A session claims a ticket by **assigning it to the user driving the map — first, before any work** — so concurrent sessions skip it. That assignee *is* the claim: an open, unassigned ticket is unclaimed.
- **Blocked / unblocked.** A ticket is unblocked when every ticket blocking it is closed. The **frontier** is the open, unblocked, unclaimed children.
- **Answers live in comments,** not in the body. The body stays the question, so the ticket reads as a question forever.
- **Assets are linked, never pasted.** A prototype, a branch, a document — link it from the ticket.
- **Plan for parallelism.** When splitting a question into tickets, minimise the files, modules, and areas two tickets share, so two people (or two sessions) can work them at once without colliding. Where a dependency is unavoidable, state it explicitly as a blocking edge.

## Ticket types — and their inline protocols

This skill is **self-contained**: it does not call companion skills. Each type below carries the protocol to run. (If the user happens to have an installed skill of the same name, prefer it and say so.)

### research — AFK

Reading documentation, third-party APIs, or local resources to surface a fact a decision is waiting on. Use when the answer lives **outside** the current working directory.

Protocol: state the exact question → gather from primary sources (official docs, the dependency's own source, the repo's code) → **cite every claim** with a URL or `file:line` → give the answer plus a confidence line → list what you could *not* determine. Never fill a gap from memory. These are the only tickets that may run in parallel — spawn one sub-agent per research ticket, name each descriptively (e.g. `research-<topic>`), cap at ~4 concurrent, use a cheap model for mechanical reading, and give each a bounded brief ("a verdict plus at most 5 bullets, with citations").

### prototype — HITL

Raise the fidelity of the discussion by making something cheap, rough, and concrete for the user to react to: an outline, a stub, a throwaway UI, a sketch of the logic. Use when the key question is "how should it look" or "how should it behave".

Protocol: build the smallest artifact that makes the choice visible (throwaway quality is correct — say so out loud) → put it on a `wayfinder/<ticket-slug>` branch or in a scratch folder, never on `main` → show the user and ask for a *reaction*, not approval → record what the reaction decided. The prototype is evidence, not deliverable code; it is linked from the ticket and does not have to survive.

### grilling — HITL — the default

Conversation with the user, to turn a vague intention into a decision. Most tickets are this type.

Protocol: **one question at a time**, phrased for a junior developer with zero knowledge of the stack or domain — define any jargon on first use. Use clickable options (`AskUserQuestion`) with a marked recommendation. Push on the *why* behind each answer, name the trade-off you see, and say plainly when you disagree. Stop when the decision is stated in one sentence the user recognises as theirs.

Pair every grilling with a **domain-modelling** pass: name the real-world things involved, their relationships, and the words the user actually uses for them; feed contradictions in that vocabulary back as questions. Ambiguous names are where plans quietly rot.

### task — HITL or AFK

Manual work that must happen before a *decision* can be made: signing up for a service so its API can be judged, provisioning access, moving data so its shape can be seen. This is the one type that *does* rather than decides, and it earns its place by unblocking a decision — never by delivering the destination.

Protocol: the agent drives it alone where it can (AFK); otherwise it hands the user a precise numbered checklist and waits (HITL). Resolved when the work is done; the resolution comment records what was done and any facts later tickets depend on (where credentials live, new URLs, row counts). **Never write a credential, token, or personal detail into a ticket** — record *where* it lives, never the value.

## Fog of war

Beyond the live tickets lies the fog: decisions you can tell are coming but cannot yet pin down, because they hang on questions still open. Resolving a ticket clears the fog ahead of it, graduating whatever is now specifiable into fresh tickets — one at a time — until the way to the destination is clear and no tickets remain.

The map's **Not yet specified** section is where that dim view is written down: the suspected question, the area to revisit. It doubles as a signpost for anyone reading where the effort is headed.

**Fog or ticket?** The test is whether you can state the question precisely *now* — **not** whether you can answer it now.

- **Ticket** when the question is already sharp, even if it is blocked and you cannot act on it yet.
- **Not yet specified** when you cannot phrase it that sharply. Do not pre-slice the fog into ticket-sized pieces: one patch may graduate into several tickets, or none.

**Not yet specified** excludes what is already decided, what is already a live ticket, and what is out of scope.

## Out of scope

Fog only ever gathers *toward* the destination. The destination fixes the scope, so work beyond it is **out of scope** — it is not fog, and it does not belong in **Not yet specified**. Scope, not sharpness, lands it there. Out-of-scope work never graduates; it returns only if the destination is redrawn, and then as a fresh effort, not a resumption.

When an existing ticket turns out to sit past the destination — mis-scoped while charting, or exposed by a resolution — **close it** (a closed ticket is unambiguously off the frontier) and leave one line in **Out of scope**: the gist, why it is out, and a link to the closed ticket. It stays out of **Decisions so far**, which records only the route actually walked.

## Mode A — Chart the map

The user invokes with a loose idea (or with no argument, in which case ask what they want to chart).

1. **Name the destination.** Grill (see the grilling protocol) plus a domain-modelling pass to pin down what this map is finding its way to: the spec, the decision, or the change. The destination fixes the scope, so it is settled first. Read the repo before asking — `CLAUDE.md`, `README.md`, the manifest files, the existing issues — so the questions are informed, not generic.
2. **Map the frontier — breadth-first.** Grill again, fanning out across the whole space rather than deep on any one thread, surfacing the open decisions and the first steps takeable now. **If this surfaces no fog** — the way is already clear, the whole journey fits one session — say so and **stop**: a map would be pure overhead. Ask the user how they want to proceed instead.
3. **Dedupe before creating anything** — mandatory, see below.
4. **Create the map** with the `wayfinder:map` label: Destination and Notes filled in, Decisions-so-far empty, the fog sketched into **Not yet specified**.
5. **Create the tickets you can specify now** as children of the map, then wire the blocking edges in a **second pass** — issues need ids before they can reference each other. Wiring sorts them into the frontier and the blocked; anything you cannot yet specify stays in the fog.
6. **Fire the research sub-agents** for each `research` ticket just created, per the research protocol. Each captures its findings as a resolution comment on its own ticket.
7. **Stop.** Charting is one session's work; it hand-resolves nothing else. Report the map by name with its link, the frontier tickets by name, and how many patches are still in fog.

## Mode B — Work through the map

The user invokes with a map (URL or number). A specific ticket is **optional** — without one, *you* pick the next decision, not the user.

1. **Load the map** — the low-resolution view, not every ticket body.
2. **Choose the ticket.** If the user named one, use it. Otherwise take the first frontier ticket in order. **Claim it by assigning it before any work.**
3. **Resolve it.** Zoom as needed: fetch the full body or resolution of any related or closed ticket on demand; follow whatever the map's `## Notes` block points at. Run the protocol for the ticket's type.
4. **Record the resolution:** post the answer as a **resolution comment**, **close** the ticket, and **append one gist line** to the map's *Decisions so far*, linking it by name.
5. **Advance the frontier:** create newly-surfaced tickets (create-then-wire); graduate any fog the answer made specifiable and **delete that patch from *Not yet specified*** so it lives only as its new ticket; rule out of scope anything the answer pushed past the destination; update or delete tickets the decision invalidated.
6. **Stop after one ticket** (research excepted). Report: the ticket resolved by name, the decision in one line, and what is on the frontier now.

Expect **other sessions to be editing the tracker concurrently** — the user may run unblocked tickets in parallel. Re-read a ticket's current state immediately before writing to it, and never assume the frontier you loaded at step 1 is still current at step 5.

## Asking the user questions

Every question to the user goes through clickable options (`AskUserQuestion`): distinct options per question, your recommendation marked, plain language throughout. Assume zero knowledge of the stack and zero knowledge of the domain — define any technical term or acronym the first time it appears. One question at a time during grilling; batch only genuinely independent questions.

## MANDATORY dedupe deep-dive before creating any map or ticket

Before creating a map, a ticket, or *offering* to create one, confirm nothing already covers it. This gets skipped and gets it wrong; do it properly every time:

- Search the **tracker's open and recently-closed issues** with several term variations (`gh issue list --search …`, `gh search issues`, or the repo's equivalent) — not one keyword. **Read** the candidates; do not just count them.
- Search the **codebase** for an existing implementation, TODO, ADR, or design doc that already answers or intentionally defers the question.
- **Never defer to a closed issue.** If you point at an existing issue as the reason not to chart something, verify it is actually **open** first — a closed issue means nobody picks the work up and it silently falls through the cracks. If it is closed, or does not really cover the case, chart it anyway.
- If something does cover it, **link to it** instead of creating a duplicate, and say which item and why.

## Guardrails

- **Git.** Never commit to `main`. Anything this skill writes into the repo (rare — usually only prototypes) goes on a `wayfinder/<ticket-slug>` or `feat/<desc>` branch, with Conventional Commit messages (`type(scope): summary`) and a pull request a **human** merges. Never force-push, never `--no-verify`, never auto-merge.
- **Sensitive data.** Maps and tickets are visible to everyone with repo access. Never write credentials, tokens, personal data, or absolute machine paths into them — record where a thing lives, not what it is.
- **No silent scope growth.** If resolving a ticket tempts you into building the destination, stop and say so: that is the hand-off signal, not permission.
- **Destroy nothing quietly.** Deleting or closing a ticket someone else created, or rewriting the destination, needs the user's explicit go-ahead first.
- **Windows note.** When creating issue bodies from files, write them **without a byte-order mark** — PowerShell `Set-Content -Encoding utf8` adds one and it surfaces as stray characters in the issue. Use `[System.IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding $false))`, or write the file with Python `open(path, "w", encoding="utf-8")`, then pass it via `--body-file`.

## Narration — how to report back

Short and scannable, one line per fact:

- **Lead with what changed or what is next**, not with context.
- **Numbered steps** for multi-step work, one action per line.
- **Names, not numbers**, for every map and ticket.
- **End with exactly one concrete next step** — one action, not a menu.
- **Say plainly when something is blocked**, on whom, and since when.

## Anti-patterns

| Anti-pattern | Why it breaks the map |
|---|---|
| Listing open tickets in the map body | They go stale instantly — the tracker query *is* the list. |
| Restating a decision on the map | Two copies drift. The map gists and links; the ticket holds the detail. |
| Referring to tickets as `#42` | Illegible to a human skimming. Use the title. |
| Pre-slicing the fog into tickets | You are inventing questions you cannot yet phrase. Leave them in *Not yet specified*. |
| Answering your own grilling ticket | HITL means the human speaks for themselves. Ask and wait. |
| Resolving three tickets "while I'm here" | Each resolution changes the map; the next choice must be made against the updated map. |
| Building the deliverable inside a ticket | That is execution, not wayfinding. Hand off instead. |
| Working a claimed (assigned) ticket | Another session is on it — you will collide. |
| Charting a plan that fits one session | Pure overhead. Say so and stop. |

## Definition of done

- **Charting done** = the map exists with a stated destination, the specifiable tickets exist and are wired with blocking edges, the rest is written into *Not yet specified*, research sub-agents are away, and the user has the map's name, link, and current frontier.
- **A working session done** = exactly one ticket (research excepted) is resolved with a resolution comment, closed, gisted onto the map; the fog and out-of-scope sections are updated; the new frontier is reported.
- **The map done** = no open tickets and no fog — nothing is left to decide before someone goes and builds the thing. Say so explicitly, and close the map issue.

## Attribution

Adapted from the MIT-licensed `wayfinder` skill in [mattpocock/skills](https://github.com/mattpocock/skills) (Copyright © 2026 Matt Pocock). The wayfinding model — destination, map, decision tickets, fog of war, out of scope — is theirs; this version is tracker-agnostic, self-contained (no companion-skill calls), and carries the orion house rules.
