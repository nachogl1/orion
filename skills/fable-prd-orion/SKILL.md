---
name: fable-prd-orion
description: |
  Greenfield project inception at BMAD-analyst depth without BMAD: an interview-driven
  planning session that produces a PRD, an architecture overview, a chosen UX direction, and
  an agent-ready GitHub Issues backlog — going to AS MUCH DETAIL AS THE USER WANTS, not a few
  questions. Stages: (1) elicitation in rounds at a user-chosen depth (quick / standard /
  exhaustive), covering problem, users, scope, constraints, success metrics; (2) optional
  MARKET RESEARCH via a parallel web-research Workflow fan-out (competitors, prior art,
  pricing/positioning), adversarially verified and cited, folded into the PRD; (3) PRD drafted
  and iterated with the user (optionally via a judge panel over 2-3 independent scoping
  drafts); (4) architecture overview derived from the PRD; (5) UX PROTOTYPES DECISION — if the
  user provides UX references they become canon; otherwise X different design-direction
  flavours (default 3) are generated IN PARALLEL as self-contained clickable HTML prototypes
  in the Downloads folder for the user to choose or mix; (6) docs committed to the repo;
  (7) epic/story breakdown built and reviewed IN-SESSION with the user (no cloud planning
  tools); (8) breakdown filed as GitHub epics + stories, each agent-ready for a downstream
  pipeline like /fable-sequential-gh-orion-v1. Use when the user says "/fable-prd-orion",
  "let's plan a new project", "create a PRD", "project inception", or has an idea and wants
  the full planning treatment.
---

# fable-prd-orion

> [!NOTE]
> This skill has **no `-vN` convention** — it's edited in place.

You run the inception of a **new** project (or a new major module): from an idea in the user's
head to a committed PRD + architecture + UX direction + agent-ready GitHub backlog. The user
controls depth at every stage; your job is to ask the questions a great product analyst would,
ground everything you can in research, and never file a breakdown the user hasn't reviewed.

Plain-language rule throughout: the user may be deeply technical or not — mirror their
vocabulary, define terms on first use, and present options with a single defended
recommendation (never a hedge).

---

## Stage 0 — Setup & depth contract

1. Confirm the working repo (new/empty repos are fine; `git init` + first push if needed —
   GitHub is required for the backlog stage: `gh auth status` must pass).
2. ONE AskUserQuestion: **depth** — `quick` (one elicitation round, no research, 1 UX flavour,
   compact PRD) / `standard` (2–3 rounds, optional research, 3 UX flavours) / `exhaustive`
   (rounds until the user says stop, full research fan-out, judge panel on the PRD, 3–5 UX
   flavours). Also ask: do they have **UX references** (links, screenshots, an existing design
   system, files) and any **existing material** (notes, business case, competitor list) to
   ingest first.

## Stage 1 — Elicitation (rounds, not a questionnaire)

Interview in rounds; each round goes deeper based on the previous answers — problem & users →
jobs-to-be-done & core flows → scope boundaries & non-goals → constraints (platform, stack
preferences, compliance, budget/time) → success metrics & risks. Use AskUserQuestion for
genuine either/or decisions; free conversation for open questions. After each round, play back
a tightening summary ("here's what I believe so far — corrections?"). Stop when the depth
contract is met AND the user has nothing to correct. Record every decision — the PRD cites
them.

## Stage 2 — Market research (optional; standard+ depth, user consents)

Ultracode Workflow fan-out: parallel researchers each on a different angle — direct
competitors / adjacent & prior art / positioning & pricing models / domain pitfalls and
regulations (angles adapted to the project). Each claim verified by a second agent before it
may enter the PRD (drop or mark unverified otherwise); every kept claim carries its source.
Synthesize into a research brief; review it with the user before it shapes scope.

## Stage 3 — PRD

- `standard`: draft the PRD directly from stages 1–2; iterate sections with the user.
- `exhaustive`: **judge panel** — 2–3 agents independently draft the scoping core (problem
  framing, MVP cut, phasing) from different angles (MVP-first / risk-first / user-experience-
  first); judge agents score them; synthesize from the winner, grafting the best of the
  runners-up; show the user the synthesis AND the losing angles' best ideas.
- PRD contents: problem & evidence · users/personas · jobs & core flows · scope (MVP vs later
  phases) & explicit non-goals · functional requirements per flow · non-functional requirements
  (performance, security, accessibility, localization if applicable) · success metrics ·
  risks & open questions · decision log (from elicitation). Every requirement gets a stable ID
  (`FR-12`) so stories can trace back.

## Stage 4 — Architecture overview

Derived from the PRD, at module level (components, responsibilities, data flow, key
technology choices each with a one-line rationale and rejected alternative). Present options
where real choices exist (stack, hosting, data store) with ONE recommendation each. This is an
overview to make the backlog buildable — not a big-design-up-front document.

## Stage 5 — UX prototypes decision

- **User provided references** (Stage 0): treat them as canon; restate the implied direction
  in one paragraph; confirm; skip generation.
- **No references**: generate **X flavours** (depth default; user may override X). One
  Workflow agent per flavour IN PARALLEL, each given a deliberately distinct design direction
  (e.g. dense-professional / friendly-consumer / minimal-utilitarian — pick directions that
  make sense for the product). Each flavour: ONE self-contained clickable HTML file in
  `~/Downloads/<project>-ux-flavour-<k>.html` covering the 2–3 core flows from the PRD —
  navigable screens, realistic placeholder content, no external assets. (If a connected design
  tool is available and the user prefers it, use it instead; HTML is the universal fallback.)
- User opens them side by side and picks one — or mixes ("flavour 2's layout, flavour 1's
  navigation"). Record the chosen direction + rationale as the PRD's UX section, with the
  winning file kept as reference.

## Stage 6 — Commit the planning docs

`docs/` (or the repo's existing docs convention): `prd.md`, `architecture.md`, the UX decision
(inside the PRD or `ux-direction.md` + the chosen flavour file). One commit on a branch; PR or
direct push per the user's preference. The docs are now the durable spec the backlog traces to.

## Stage 7 — Breakdown, reviewed in-session

Build the epic/story tree from the PRD: epics ≈ deliverable slices (not layers); stories
independently shippable, each carrying plain description, acceptance criteria (traced to
`FR-x`), edge cases, and size (S/M/L). Apply the agent-ready six-point bar (concrete bounded
scope; no open human decision; inputs present; verifiable done-state; no human-only step;
dependencies satisfiable in-order). Present the FULL tree in the conversation — review it with
the user, iterate (split/merge/recut/reorder) until they approve. **Nothing is filed before
this approval.** No cloud planning tools — the review happens here.

## Stage 8 — File the backlog

Epics first, then stories referencing their epic (use the repo's epic convention if one exists;
otherwise label `epic` + tracking-issue checklists, created tolerantly). Each story body is
self-contained — a downstream agent must never need this conversation. Dedupe pass first if
the repo already has issues. Confirm every URL back. Close by suggesting the natural next
step: `/assign-issues-orion` to pick a first slice, or `/fable-sequential-gh-orion-v1` to run it.

## Rails

- The user can stop/resume at any stage boundary; play back where you are and what's pending.
- Research claims never enter the PRD unverified; UX flavours never overwrite each other;
  generated files are write-once.
- This skill plans and files — it does not implement.
