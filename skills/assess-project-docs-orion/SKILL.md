---
name: assess-project-docs-orion
description: 'Assess a repository''s project documentation against a two-layer benchmark — an independent CONSENSUS layer (widely-cited, vendor/community best-practice resources, re-validated at run time) and an opinionated ORION layer (guidelines collected from real projects and generalized) — then emit a single self-contained HTML report into the Downloads folder. Before assessing, it shows the user the exact list of consensus resources it will benchmark against and asks whether to add more. Runs a per-doc assessor pipeline covering the agent instruction file (CLAUDE.md / AGENTS.md / .claude/rules), the README, contributing & governance docs (CONTRIBUTING / CODE_OF_CONDUCT / SECURITY / CI / runbook / ADRs / decision log), and the pull-request template. Each doc gets 0–5 dimension scores, a consensus checklist (cited), an orion checklist, concrete gap recommendations, and suggested rewrite snippets; a cross-doc pass flags duplication/drift and missing high-value docs. Detects the project''s stack, tracker vocabulary, and conventions from its own files at run time — assumes no stack. STRICTLY READ-ONLY: it reports and recommends only — it never edits any file, never writes a PR template into the repo, and never commits. Use when the user says "/assess-project-docs-orion", "assess my project docs", "review/grade my CLAUDE.md", "grade my README", "check my contributing/PR template", or "how good are my docs".'
---

# assess-project-docs-orion

> [!NOTE]
> **Editing this skill?** This skill has **no `-vN` convention** — edit it in place
> (like `guided-qa-orion`). When you add a new doc-assessor, also add its guideline
> file under `guidelines/` and a row to `guidelines/README.md`. Keep everything here
> **general** (see the Distribution-safety gate below) — this repo is publicly
> distributable.

Assess a repository's **project documentation** and produce a detailed, self-contained
**HTML report** in the user's Downloads folder. The report scores each doc against two
benchmark layers and turns every gap into a concrete recommendation.

This is a **strictly read-and-report** skill. It **never modifies the target repo** —
no file edits, no PR template written in, no commits. Its entire output is the report
plus an in-chat summary; any "fix" it proposes lives *in the report* as a
recommendation the user can apply themselves.

## The two benchmark layers (read this first)

Every doc is judged against the **union** of:

1. **Consensus layer** — independent, widely-cited best-practice resources listed in
   [`guidelines/consensus-resources.md`](guidelines/consensus-resources.md). None are
   owned by the skill author. The skill **re-validates each cited link at run time**
   before putting it in the report (dead link → cite the principle, note it's
   currently unreachable).
2. **Orion layer** — opinionated guidelines collected from real projects and
   generalized, one file per doc type under [`guidelines/`](guidelines/README.md).
   Stricter than consensus; never contradicts it.

The report keeps the two **scored separately** so the reader sees the industry
baseline gap distinctly from the orion-recommended gap.

## Operating principles

1. **Strictly read-only — never modify the target repo.** Do **not** apply fixes, edit
   files, write a PR template into the repo, or otherwise change anything. Every
   recommendation lives *in the report*; applying it is the user's job. Do not even
   offer to apply fixes.
2. **Never commit, push, or merge.**
3. **Confirm the benchmark before assessing.** Show the user the consensus resources
   this run will use and ask if they want to add more (Phase 1). Don't silently pick
   the sources.
4. **Assume no stack.** Detect the project's stack, test/build commands, tracker
   vocabulary, and conventions from its own files at run time. Score docs against what
   the project *actually* is, not a presumed technology.
5. **Score honestly; recommendations must be concrete.** Every dimension under 3/5 gets
   an actionable recommendation and, where useful, a paste-ready rewrite snippet — in
   the report. No vague "improve this."
6. **Cite real, reachable sources.** Re-validate consensus links (Phase 1); don't emit
   broken URLs; never invent a source.
7. **Distribution-safety self-check** before writing the report (see gate).
8. **Summarize in chat; the report holds the detail.** Tell the user the headline
   scores and the top gaps in clear language; point them to the HTML for depth.

## Inputs / pre-conditions

- A **target repository** — default to the current working directory's repo. Confirm
  with `git rev-parse --show-toplevel` (works fine on a non-git folder too; just note
  it).
- **Which docs to assess** — default to all four assessors; let the user narrow.
- Network access for **consensus-link re-validation** (degrade gracefully if offline:
  cite principles, mark links unverified).

## Phase 0 — Confirm scope

1. Identify the target repo root and its name (for the report filename only — a local
   artifact, not committed).
2. Confirm the **assessor set**. Default = all four:
   - **Agent instructions** — `CLAUDE.md`, `./.claude/CLAUDE.md`, `CLAUDE.local.md`,
     `.claude/rules/*.md`, an `AGENTS.md` imported by CLAUDE.md.
   - **README** — root + any per-package READMEs.
   - **Contributing & governance** — `CONTRIBUTING(.md)`, `CODE_OF_CONDUCT`,
     `SECURITY`, `SUPPORT`, CI/test docs, runbook/troubleshooting, ADRs + index,
     decision log.
   - **PR template** — `PULL_REQUEST_TEMPLATE.md`, `.github/PULL_REQUEST_TEMPLATE.md`,
     `docs/…`, or a `PULL_REQUEST_TEMPLATE/` directory.
   Use `AskUserQuestion` only if the user hasn't already said; otherwise state the plan
   briefly and proceed.

## Phase 1 — Confirm the benchmark resources (consensus layer)

Lock in *which external sources* this run benchmarks against, and let the user shape
that list **before** any assessment runs:

1. **Gather the candidate list.** Read
   [`guidelines/consensus-resources.md`](guidelines/consensus-resources.md) and select
   the sections matching the docs in scope (e.g. skip the PR-template sources if the PR
   template isn't being assessed).
2. **Re-validate reachability.** Probe each URL (a `WebFetch`/HEAD-style check) and mark
   it **✓ reachable** / **✗ unreachable**. Offline → mark all *unverified* and proceed.
3. **Show the user the exact list** that will be used, grouped by doc, with reachability
   status — so they can see what the consensus layer is grounded on. Keep it a clean,
   scannable list (clear language; the detail is in the file if they want it).
4. **Ask whether to add more** (`AskUserQuestion`). If the user supplies URLs: validate
   reachability and include the reachable ones in this run's benchmark (note any that
   didn't resolve). If they decline, proceed with the built-in list. Never silently
   swap or drop a source.
5. **Optional persistence (only if asked).** If the user wants their additions reused in
   future runs, offer to append them to `guidelines/consensus-resources.md` under the
   right section — with a one-line "what to take from it" note, marked **✓** only after
   it resolved. This edits the **skill's own corpus**, never the target repo, and only
   on explicit request. (They can also edit that file directly any time — it's the
   single source of the consensus list.)

The confirmed, validated list is passed to every assessor and is exactly what the
report's **Sources** section cites.

## Phase 2 — Discover docs & detect project conventions

Do this once, up front, and pass the results to every assessor so they judge against
the *real* project:

1. **Locate the docs** for each assessor in scope (record which exist, which are
   missing, and their paths). Missing high-value docs are findings, not skips.
2. **Detect the stack & commands** from manifests actually present — e.g.
   `package.json` scripts (npm/pnpm/yarn/bun; workspaces), `*.sln`/`*.csproj`,
   `Makefile`, `pyproject.toml`/`tox.ini`, `go.mod`, `Cargo.toml`,
   `pom.xml`/`build.gradle`. Derive the unit/integration, type-check, and e2e commands.
3. **Detect tracker vocabulary** — GitHub Issues, Jira keys, BMAD story/epic docs,
   requirement IDs (FR/NFR), etc. The PR-template and governance assessors need this
   to judge work-item linking without assuming a scheme.
4. **Detect existing conventions** — branch-naming, commit convention (e.g.
   Conventional Commits), the project's own "Must Always / Must Never" rules and
   naming tables (so the PR-template assessor can check the enforcement checklist is
   *generated from this repo*, not canned).
5. **Read the target docs** in full so assessors work from real content.

## Phase 3 — Per-doc assessment (parallel assessor pipeline)

Spawn one **assessor sub-agent per in-scope doc**, in parallel, **capped at 4 at a
time** (orion effort-economy). Use a mid-tier model (e.g. Sonnet) for assessors;
reserve the top model for the cross-doc synthesis and report if needed.

Give each assessor:
- its **orion guideline file** (`guidelines/<doc>.md`) and the **confirmed consensus
  list** from Phase 1 (the relevant `consensus-resources.md` section + any
  user-added sources),
- the **actual target doc(s)** content,
- the **Phase-2 detection results** (stack, commands, tracker vocab, conventions),
- this instruction set.

Each assessor returns a structured result:
- **Consensus-layer findings** — per consensus criterion: met / partial / missing,
  with the cited source (re-validated).
- **Orion-layer findings** — the guideline's 0–5 rubric, each dimension scored, with a
  one-line justification; mark **N/A** where a dimension legitimately doesn't apply
  (e.g. multi-agent safety in a repo that never runs parallel agents).
- **Gaps → concrete recommendations**, and a **paste-ready rewrite snippet** for each
  dimension under 3.
- **Smells caught** (from the guideline's "Smells to flag" list), including any
  **leaked specifics** (person/org/product/path) if the doc is meant to be public.
- A **per-doc roll-up score** (mean of applicable dimensions) and a one-paragraph
  plain-English verdict.

The **PR-template assessor** additionally: if no template exists, *generates a draft*
from the Phase-2 conventions + the rubric and includes it **in the report** as a
recommendation. It is **not** written to the repo — the report shows it for the user
to copy if they choose.

## Phase 4 — Cross-doc synthesis

After assessors return, the orchestrator (or a top-tier synthesis sub-agent):
- **Duplication / drift** — README vs CLAUDE.md vs architecture restating each other;
  branch/commit/PR conventions that disagree between human docs and the CLAUDE.md;
  documented commands that don't match detected manifests.
- **Coverage gaps** — high-value docs missing for a project of this size/shape
  (proportional judgement, not a checklist demand).
- **Consistency of the agent-safe / needs-human-decision convention** across the
  issue process, CLAUDE.md, and PR template (if the repo works with agents).
- **Overall scorecard** — per-doc roll-ups + a project-docs health summary, with the
  3–5 highest-leverage recommendations ranked first.

## Phase 5 — Emit the HTML report

Write **one self-contained HTML file** (inline CSS/JS, no external assets) to the
user's Downloads folder, e.g.
`~/Downloads/assess-project-docs-<repo>-<YYYY_MM_DD-HH_MM>.html`. Structure:

1. **Header** — repo name, date, assessor set, the two-layer model explained in a line.
2. **Overall scorecard** — per-doc roll-up scores (visual, e.g. 0–5 bars), the
   project-docs health headline, and the top ranked recommendations.
3. **Per-doc sections**, each with:
   - the **consensus checklist** (met/partial/missing) with **cited, re-validated**
     source links,
   - the **orion rubric** with each dimension's 0–5 score + justification,
   - **gaps → recommendations**, with **suggested rewrite snippets** in copy-friendly
     code blocks the user can lift,
   - **smells caught**.
4. **Cross-doc findings** (duplication/drift, coverage gaps, convention consistency).
5. **Sources** — the consensus resources actually cited (including any the user added
   in Phase 1), with their re-validation status.
6. **Footer** — a note that everything here is a **recommendation only**; the skill
   changed nothing and committed nothing — applying any change is the user's call.

Keep the styling clean and dark-theme-friendly to match the other orion report skills.
Then **summarize the headline in chat** (scores + top gaps) and give the file path.
The skill ends here — it does **not** offer to apply fixes.

---

## Distribution-safety gate (this repo is publicly distributable)

This skill and its guidelines ship publicly. Before writing the report or any
guideline edit, confirm **nothing project-specific leaked into the skill or guideline
files** — no person/org/product/repo/stack/locale/path specifics in prose, examples,
or rubric items. The *report* about a user's repo is a **local artifact** (in their
Downloads) and may name their repo and quote their docs — that's fine; it is never
committed back into this repo. What must stay general is everything under
`skills/assess-project-docs-orion/` itself.

When the orion guidelines flag that the *target* repo's public docs leak specifics,
report it as a finding — but do not copy those specifics into anything under this
skill folder.
