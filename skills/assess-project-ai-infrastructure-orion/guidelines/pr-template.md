# Orion guidelines — Pull-request template

The orion layer for assessing (or recommending) a repository's PR template
(`PULL_REQUEST_TEMPLATE.md` / `.github/PULL_REQUEST_TEMPLATE.md` / a
`PULL_REQUEST_TEMPLATE/` directory). Pair with the consensus baseline in
[`consensus-resources.md`](consensus-resources.md) (section 4).

> **Guidelines, not a template.** This skill does **not** drop a PR template into the
> target repo. It assesses an existing one — or, if none exists, recommends one and
> offers a *generated* draft built from the repo's own conventions. The sections below
> are the rubric, not boilerplate to paste verbatim.

The guiding tension from consensus: a PR template must be **short enough that
contributors actually use it**, yet **structured enough to drive a good PR**. The
orion additions are about *driving the PR correctly* — especially making deferrals
and test evidence impossible to hand-wave.

---

## A. Consensus baseline

- A **summary** + a link to the issue it closes (`Closes #<issue>`).
- A **type-of-change** indicator.
- A **concrete test-evidence** section — *which* tests, in *which* environment, not a
  bare "ran tests."
- Checklists for things reviewers otherwise forget.
- Encourage screenshots / logs / links for UI or hard-to-describe changes.
- Kept short; lives in root, `docs/`, or `.github/`.

## B. Orion layer — the sections that drive a PR correctly

### B1. Summary + issue link
- One-line "what changed and why" + `Closes #<issue>`. A PR with no linked work item
  is a smell.

### B2. Linked work item / requirement refs
- If the project tracks stories/epics/requirements, the template prompts for them
  (e.g. *Story X.Y*, *Epic N*, *FR/NFR refs*). **Detect the project's tracking
  vocabulary at run time** — don't assume BMAD, Jira, or any specific scheme. If the
  project has no such layer, this section is N/A.

### B3. Type of change
- A short checkbox list (e.g. requirements / architecture-or-ADR / design / code /
  tooling-or-CI / docs / other), matched to the kinds of change the project actually
  produces.

### B4. Out-of-scope / Follow-ups — **every line carries an anchor**  ← (key discipline)
This is the highest-value orion-specific section.

- Every deferred / out-of-scope / follow-up item **must carry an anchor on the same
  line** — a linked `#N` (file the issue *first*, then link it), or the project's
  work-item ID (Story X.Y / Epic N / requirement id).
- **Deferral prose with no anchor is a dropped commitment**, not a note — the template
  should say so, and a reviewer should reject unanchored deferrals.
- **Recurring pre-existing failures** reference **one umbrella issue** by `#N`
  everywhere — never re-described as fresh "out of scope" text each PR.
- A good template encodes this as a checkbox the author must affirm, e.g.
  *"No open out-of-scope items, **or** every one is listed below and linked to a #N."*

### B5. Test evidence — real commands, real results
- Checkboxes for the project's **actual** quality gates, **detected at run time** from
  its manifests — unit/integration, type-check, and e2e as applicable — plus
  "**green locally and in CI**."
- **Manual verification against the issue's acceptance criteria** (Given/When/Then).
- **Screenshots / recording for UI** changes.
- Do **not** hardcode a stack's test runner names into the rubric — the template
  should reflect *this* repo's commands (e.g. derived from `package.json` scripts,
  `*.sln`, `Makefile`, `pyproject.toml`, …).

### B6. Project enforcement checklist — generated, not canned
- The strongest PR templates include a checklist of the project's own **"Must Always /
  Must Never"** rules and naming/architecture conventions — so reviewers verify them
  every time.
- **These must be generated from the repo's own CLAUDE.md / architecture doc /
  conventions at run time**, never copied from another project. (A template that
  hardcodes another stack's rules — a result type, a tenancy filter, a logging
  framework, a specific i18n locale set — is a leak/mismatch smell; flag it.)
- Include the commit-format checkbox **only if** the repo uses that convention
  (e.g. Conventional Commits).

### B7. Documentation updates
- Prompts to update governed docs / ADRs / status columns **when relevant** (mirrors
  CLAUDE.md §B11 and the governance guideline).

### B8. Review & human-owned merge
- At least one reviewer requested; dependencies / follow-up issues linked; and the
  template reflects that **a human owns the merge** (no self-merge). (Mirrors
  CLAUDE.md §B7.)

### B9. Decision-posture surfacing (ties to agent-safe / needs-human)
- For repos using the agent-safe / needs-human-decision convention
  ([`contributing-and-governance.md`](contributing-and-governance.md) §B4), the PR
  template should prompt the author to **flag any decision in the change that still
  needs human sign-off**, so a reviewer knows where judgement (not just correctness)
  is being requested.

---

## C. Smells to flag

- No PR template at all in a collaborative repo.
- A template so long it's clearly ignored (huge canned checklists irrelevant to most
  PRs) — *or* so thin it's just "Summary:".
- An **unanchored** out-of-scope section (or none) — deferrals will leak (§B4).
- "Ran tests ✅" with no specifics; no acceptance-criteria check; no CI gate.
- A **hardcoded enforcement checklist copied from another project** (stack mismatch,
  or worse, leaked internal rules) instead of one generated from this repo (§B6).
- Encourages self-merge / omits a reviewer step.

## D. Scoring rubric (per dimension, 0–5; N/A where a section legitimately doesn't
apply to this project)

1. **Exists & is right-sized** — present, short enough to be used (§A).
2. **Summary + issue link** (§B1).
3. **Work-item / requirement refs** (§B2) — N/A if the project has no such layer.
4. **Type of change** (§B3).
5. **Out-of-scope anchoring discipline** (§B4) — *weighted highest.*
6. **Test evidence with real commands + acceptance-criteria check** (§B5).
7. **Enforcement checklist generated from the repo** (§B6).
8. **Docs-update prompt** (§B7).
9. **Reviewer / human-owned-merge** (§B8).
10. **Decision-posture surfacing** (§B9) — N/A if the repo doesn't use the convention.

For every dimension under 3 (and not N/A), give a concrete recommendation and a
suggested snippet. When a repo lacks a template, **generate the draft from this rubric
+ the repo's detected conventions** and include it **in the report** as a
recommendation — the skill never writes it into the repo.
