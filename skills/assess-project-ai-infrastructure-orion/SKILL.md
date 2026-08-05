---
name: assess-project-ai-infrastructure-orion
description: 'Assess a repository''s AI-development infrastructure — its agent/project documentation, the agent tooling wired into it, and (optionally) the user''s own Claude Code setup — against a two-layer benchmark: an independent CONSENSUS layer (widely-cited, vendor/community best-practice resources, re-validated at run time) and an opinionated ORION layer (guidelines collected from real projects and generalized). Emits a single self-contained HTML report into the Downloads folder. Before assessing, it shows the user the exact list of consensus resources it will benchmark against and asks whether to add more. Per-area assessors cover: the agent instruction file (CLAUDE.md / AGENTS.md / .claude/rules), the README, contributing & governance docs (CONTRIBUTING / CODE_OF_CONDUCT / SECURITY / CI / runbook / ADRs / decision log), the pull-request template, the ISSUE/TICKET template (incl. an agent-ready vs needs-human-decision marker), the project''s MCP servers / plugins / helper tooling (recommending broadly-useful ones that are missing — e.g. browser-automation, container, knowledge-base, and context-compression tooling), and a self-audit of the user''s ~/.claude/ setup (settings.json, hooks, memory, skills/plugins) for what is stale/broken/wasteful. Each area gets 0–5 dimension scores, a consensus checklist (cited), an orion checklist, concrete gap recommendations, and suggested rewrite snippets; a cross-doc pass flags duplication/drift, missing high-value docs, and — if the repo has no issue tracker — proposes adopting GitHub Issues as the single source of truth. Detects the project''s stack, tracker vocabulary, and conventions from its own files at run time — assumes no stack. STRICTLY READ-ONLY towards the target repo and the user''s settings: it reports and recommends only — it never edits the target repo, never writes a PR/issue template into it, never changes the user''s settings, and never commits (its only writes are the HTML report in Downloads and, if the user opts in, new entries in its own guidelines/consensus-resources.md). Use when the user says "/assess-project-ai-infrastructure-orion", "assess my project docs / AI setup", "review/grade my CLAUDE.md", "audit my Claude setup", "what MCPs or plugins should I add", "check my contributing/PR/issue template", or "how good are my docs".'
---

# assess-project-ai-infrastructure-orion

> [!NOTE]
> **Editing this skill?** This skill has **no `-vN` convention** — edit it in place
> (like `guided-qa-orion`). When you add a new assessor, also add its guideline
> file under `guidelines/` and a row to `guidelines/README.md`. Keep everything here
> **general** (see the Distribution-safety gate below) — this repo is publicly
> distributable.

Assess a repository's **AI-development infrastructure** — its **agent/project
documentation**, the **agent tooling** wired into it (MCP servers, plugins, helper
CLIs), and, optionally, the **user's own Claude Code setup** (`~/.claude/`) — and
produce a detailed, self-contained **HTML report** in the user's Downloads folder. The
report scores each area against two benchmark layers and turns every gap into a
concrete recommendation.

This is a **strictly read-and-report** skill. It **never modifies the target repo, the
user's settings, or anything else** — no file edits, no PR/issue template written in,
no MCP/plugin installed, no commits. Its entire output is the report plus an in-chat
summary; any "fix" it proposes lives *in the report* as a recommendation the user can
apply themselves.

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

## Recommendation scope — repo vs user-level (hoisting)

Many recommendations recur across **every repo the same user owns** — generic
conventions and boilerplate templates that aren't project-specific. Rather than have
the user re-apply them repo by repo, the report tags each recommendation with the
**lowest scope it can live at**, so they can apply a common fix **once** at user level
and let every repo inherit it. There are **three** scopes:

- **`repo`** — inherently project-specific; must live in the target repo. README,
  stack/build/test commands, architecture, ADRs/decision log/runbook, and any rule that
  names this project's stack or domain.
- **`user (~/.claude)`** — Claude Code user scope, loaded into **every** session on
  every repo: `~/.claude/CLAUDE.md` (generic rules — commit/PR convention, the
  agent-ready vs needs-human-decision marker, code-style musts), `~/.claude/settings.json`
  (hooks, statusLine, plugin enablement), `~/.claude.json` (MCP servers).
- **`account (.github)`** — GitHub's **default community health files**: a public repo
  named **`<owner>/.github`** supplies defaults to **all repos under that account that
  lack their own copy**. Hoistable here: `PULL_REQUEST_TEMPLATE.md`,
  `ISSUE_TEMPLATE/*`, `CONTRIBUTING`, `CODE_OF_CONDUCT`, `SECURITY`, `SUPPORT`,
  `FUNDING`. A per-repo copy still overrides when one repo needs something special.

**Universality guard.** Only recommend hoisting a rule/template to a user-level scope
when it's plausibly **universal for this user** — true for essentially all their repos,
not just this one. A rule that fits a minority of repos pollutes every session/repo if
hoisted; keep those at `repo` scope. When unsure, tag `repo` and note it *could* hoist
if the user confirms it's universal.

This skill stays **strictly read-only**: hoisting is a *recommendation* in the report
(scope tag + where to put it + paste-ready snippet). The skill never creates a
`.github` repo, never edits `~/.claude/`, and never commits — applying the level-up is
the user's call.

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
9. **Assess each `CLAUDE.md` on its own scope.** Detect whether each agent-instruction
   file is **user-level** (`~/.claude/…`, loaded on every repo) or **repo-level**
   (`<repo>/…`, loaded for one repo) and score it against the scope-appropriate rubric
   in [`guidelines/claude-md.md`](guidelines/claude-md.md) ("Scope" section). Assess each
   file **independently** — never compare two `CLAUDE.md` files, and never mark a rule
   "missing" that correctly lives at the other scope (a user file isn't docked for
   lacking a repo's stack rules; a repo file isn't docked for lacking generic personal
   preferences).

## Inputs / pre-conditions

- A **target repository** — default to the current working directory's repo. Confirm
  with `git rev-parse --show-toplevel` (works fine on a non-git folder too; just note
  it).
- **Which areas to assess** — default to the six repo assessors; let the user narrow.
  The **setup self-audit** is opt-in (it reads `~/.claude/`, outside the repo).
- **Read scope.** Most assessors read the target repo only. The **tooling** assessor
  additionally reads **user-scope** config (`~/.claude.json`, `~/.claude/`) to see what
  the user already has globally; the **setup self-audit** reads `~/.claude/` in full.
  These are **read-only** — never edit the user's config — and their contents may be
  sensitive, so they surface only in the user's **local** report, never in this repo.
- Network access for **consensus-link re-validation** (degrade gracefully if offline:
  cite principles, mark links unverified).

## Phase 0 — Confirm scope

1. Identify the target repo root and its name (for the report filename only — a local
   artifact, not committed).
2. Confirm the **assessor set**, grouped into **three pillars** of a project's AI
   infrastructure. Default = the six repo assessors; the seventh (setup self-audit) is
   **opt-in** because it reads outside the repo:

   **Pillar 1 — Agent instructions & docs**
   - **Agent instructions** — `CLAUDE.md`, `./.claude/CLAUDE.md`, `CLAUDE.local.md`,
     `.claude/rules/*.md`, an `AGENTS.md` imported by CLAUDE.md. These are the
     **repo-level** files by default; the **user-level** `~/.claude/CLAUDE.md` (and
     `~/.claude/rules/*`) is **also** assessed with this rubric — at **user scope** —
     when the user asks to grade it or opts into the self-audit. Each file is scored
     independently on its own scope (Operating principle 9).
   - **README** — root + any per-package READMEs.

   **Pillar 2 — Process & governance**
   - **Contributing & governance** — `CONTRIBUTING(.md)`, `CODE_OF_CONDUCT`,
     `SECURITY`, `SUPPORT`, CI/test docs, runbook/troubleshooting, ADRs + index,
     decision log, and the tracker / source-of-truth.
   - **PR template** — `PULL_REQUEST_TEMPLATE.md`, `.github/PULL_REQUEST_TEMPLATE.md`,
     `docs/…`, or a `PULL_REQUEST_TEMPLATE/` directory.
   - **Issue/ticket template** — `ISSUE_TEMPLATE.md`, `.github/ISSUE_TEMPLATE/*.md|*.yml`
     (issue forms), or the tracker's request-type templates — checking for the
     **agent-ready vs needs-human-decision** marker
     ([`guidelines/issue-template.md`](guidelines/issue-template.md)).

   **Pillar 3 — Tooling & environment**
   - **Agent tooling (MCPs / plugins)** — MCP servers, plugins and helper CLIs wired in
     at **repo scope** (`.mcp.json`, `.claude/`) and **user scope** (`~/.claude.json`,
     `~/.claude/`), recommending broadly-useful tooling that's missing
     ([`guidelines/tooling-mcps-plugins.md`](guidelines/tooling-mcps-plugins.md)).
   - **Claude setup self-audit (opt-in)** — the user's own `~/.claude/` (settings.json,
     hooks, memory, skills/plugins) for what's stale/broken/wasteful
     ([`guidelines/claude-setup-audit.md`](guidelines/claude-setup-audit.md)). Because
     this reads the user's home config (not the target repo), **only run it when the
     user opts in**; findings go in the same local report.

### Standard questions (ask these verbatim — every repo, every run)

So the skill asks the **same** thing in every repo, use the fixed `AskUserQuestion`
set below. Don't paraphrase, reorder, or merge them; only skip a question the user
already answered unprompted in their invocation. The two-question Phase-0 call and the
one-question Phase-1 call are kept **separate** because Phase 1 must be shown *after*
consensus links are re-validated (Phase 1, step 3).

**Phase 0 — one `AskUserQuestion` call, two questions:**

- **Q1 — header `Assessor set`** · question: *"Which of the six repo assessors should
  this run cover? (agent instructions, README, contributing/governance, PR template,
  issue template, agent tooling)"*
  Options, in order — first is the default:
  1. **All six repo assessors**
  2. **Let me narrow the set**

  Q1 is **only** about the repo assessors — it must **not** carry a "+ self-audit"
  option. The self-audit is owned solely by Q2 (this removes the overlap/contradiction
  that earlier phrasings hit).

- **Q2 — header `Self-audit`** · question: *"Run the opt-in Claude setup self-audit? It
  reads your `~/.claude/` (settings, hooks, memory, skills) outside the repo. Read-only;
  findings go only in your local report."*
  Options, in order — first is the default:
  1. **No, repo only**  *(default — opt-in: it reads outside the repo)*
  2. **Yes, include the self-audit**

**Phase 1 — one `AskUserQuestion` call, one question** (asked in Phase 1, step 4, after
the re-validated source list is shown):

- **Q3 — header `Benchmark`** · question: *"These are the consensus sources I'll
  benchmark against (re-validated above). Proceed with this built-in list, or add your
  own first?"*
  Options, in order — first is the default:
  1. **Proceed with built-in list**
  2. **I'll add sources**

If the user narrows in Q1, follow up to learn which assessors to keep (free-form). If
they pick "I'll add sources" in Q3, collect URLs and validate per Phase 1, step 4.

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
4. **Ask whether to add more** — use the pinned **Q3** from Phase 0's "Standard
   questions" block (header `Benchmark`), asked here after the list is shown. If the user
   supplies URLs: validate reachability and include the reachable ones in this run's
   benchmark (note any that didn't resolve). If they decline, proceed with the built-in
   list. Never silently swap or drop a source.
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
   missing, and their paths). Missing high-value docs are findings, not skips. For each
   `CLAUDE.md` found, also record its **scope** — user-level (`~/.claude/…`) vs
   repo-level — so the assessor applies the right rubric (Operating principle 9).
2. **Detect the stack & commands** from manifests actually present — e.g.
   `package.json` scripts (npm/pnpm/yarn/bun; workspaces), `*.sln`/`*.csproj`,
   `Makefile`, `pyproject.toml`/`tox.ini`, `go.mod`, `Cargo.toml`,
   `pom.xml`/`build.gradle`. Derive the unit/integration, type-check, and e2e commands.
3. **Detect tracker vocabulary** — GitHub Issues, Jira keys, BMAD story/epic docs,
   requirement IDs (FR/NFR), etc. The PR/issue-template and governance assessors need
   this to judge work-item linking without assuming a scheme. **If there is no tracker
   at all** (status scattered across a README checklist, TODO comments, or nowhere),
   record it — the governance assessor turns this into a *"propose GitHub Issues as the
   single source of truth"* recommendation (Phase 4), defaulting to the repo's actual
   host's native tracker.
4. **Detect existing conventions** — branch-naming, commit convention (e.g.
   Conventional Commits), the project's own "Must Always / Must Never" rules and
   naming tables (so the PR-template assessor can check the enforcement checklist is
   *generated from this repo*, not canned).
5. **Read the target docs** in full so assessors work from real content.
6. **Detect agent tooling** (for the tooling assessor) — repo-scope `.mcp.json`,
   `.claude/` settings/plugins, and **user-scope** `~/.claude.json` / `~/.claude/`
   (MCP servers, enabled plugins, linked skills). Record what's present at each scope so
   the assessor recommends only genuinely-missing, relevant tooling.
7. **(If the self-audit is opted in)** read the user's `~/.claude/` setup — settings
   files, hooks and the scripts they reference, user `CLAUDE.md`/rules, skills/plugins —
   resolving every referenced path so broken/dangling references are caught.

## Phase 3 — Per-doc assessment (parallel assessor pipeline)

Spawn one **assessor sub-agent per in-scope doc**, in parallel, **capped at 4 at a
time** (orion effort-economy). Use a mid-tier model (e.g. Sonnet) for assessors;
reserve the top model for the cross-doc synthesis and report if needed.

Give each assessor:
- its **orion guideline file** (`guidelines/<area>.md`) and the **confirmed consensus
  list** from Phase 1 (the relevant `consensus-resources.md` section + any
  user-added sources),
- the **actual target content** — the doc(s) for doc assessors; the detected tooling /
  `~/.claude/` config for the **tooling** and **self-audit** assessors,
- the **Phase-2 detection results** (stack, commands, tracker vocab, conventions,
  tooling-by-scope, setup config),
- this instruction set.

**Cap each assessor's return** (orion effort-economy): instruct sub-agents to return
the structured result only — scores + findings + snippets — not a free-form essay, so
the orchestrator's context survives the fan-out.

Each assessor returns a structured result:
- **Consensus-layer findings** — per consensus criterion: met / partial / missing,
  with the cited source (re-validated).
- **Orion-layer findings** — the guideline's 0–5 rubric, each dimension scored, with a
  one-line justification; mark **N/A** where a dimension legitimately doesn't apply
  (e.g. multi-agent safety in a repo that never runs parallel agents).
- **Gaps → concrete recommendations**, and a **paste-ready rewrite snippet** for each
  dimension under 3. **Tag each recommendation with its scope** — `repo`,
  `user (~/.claude)`, or `account (.github)` (see "Recommendation scope — repo vs
  user-level"). Default to `repo`; tag a user-level scope only when the fix is generic
  boilerplate or a plausibly-universal rule (apply the universality guard), and name the
  exact destination (e.g. `~/.claude/CLAUDE.md`, `<owner>/.github/PULL_REQUEST_TEMPLATE.md`).
- **Smells caught** (from the guideline's "Smells to flag" list), including any
  **leaked specifics** (person/org/product/path) if the doc is meant to be public.
- A **per-doc roll-up score** (mean of applicable dimensions) and a one-paragraph
  plain-English verdict.

The **PR-template and issue-template assessors** additionally: if no template exists,
*generate a draft* from the Phase-2 conventions + the rubric (the issue draft includes
the **agent-ready vs needs-human-decision** marker) and include it **in the report** as
a recommendation. It is **not** written to the repo — the report shows it for the user
to copy if they choose.

The **tooling assessor** recommends only **relevant, genuinely-missing** tooling
(matched to the project's actual workflow), names a concrete publicly-available example
per gap with the scope to add it at, and **re-validates** that each named tool still
exists/reachable at run time. The **self-audit assessor** names the exact file + line
for every broken/stale/wasteful finding. Neither installs or edits anything.

The **agent-instructions assessor** tags each `CLAUDE.md` it assesses with its **scope**
(user-level vs repo-level) and applies the scope-appropriate rubric per
[`guidelines/claude-md.md`](guidelines/claude-md.md) ("Scope" section), scoring each file
**independently** — repo-only dimensions are marked **N/A** (not 0) for a user-level
file, and it never scores one file by comparison to another.

## Phase 4 — Cross-doc synthesis

After assessors return, the orchestrator (or a top-tier synthesis sub-agent):
- **Duplication / drift** — README vs CLAUDE.md vs architecture restating each other;
  branch/commit/PR conventions that disagree between human docs and the CLAUDE.md;
  documented commands that don't match detected manifests.
- **Coverage gaps** — high-value docs missing for a project of this size/shape
  (proportional judgement, not a checklist demand).
- **Consistency of the agent-safe / needs-human-decision convention** across the
  issue template, CLAUDE.md, and PR template (if the repo works with agents).
- **No source of truth** — if Phase 2 found no tracker, raise a top recommendation to
  **adopt one as the single source of truth** (propose **GitHub Issues** for a
  GitHub-hosted repo; otherwise the host's native tracker), and note what it unlocks
  (PR `Closes #N` linking, label-based agent-ready tagging, status in one place).
- **Tooling coverage** — relevant capability gaps (verification/browser, container,
  knowledge-base, context-compression) the project would benefit from, and any
  configured-but-unused tooling.
- **Hoist / level-up pass** — collect every recommendation the assessors tagged
  `user (~/.claude)` or `account (.github)` into one consolidated list, deduped across
  assessors (the same convention may surface in CLAUDE.md *and* the PR template). This
  is the user's "apply once, inherit everywhere" set — surfaced as its own report
  section so they can level up commonalities instead of re-doing them per repo. Apply
  the **universality guard**: anything that only fits this repo stays at `repo` scope.
- **Overall scorecard** — per-area roll-ups + an AI-infrastructure health summary, with
  the 3–5 highest-leverage recommendations ranked first.

## Phase 5 — Emit the HTML report

Write **one self-contained HTML file** (inline CSS/JS, no external assets) to the
user's Downloads folder, e.g.
`~/Downloads/assess-project-ai-infra-<repo>-<YYYY_MM_DD-HH_MM>.html`. Structure:

1. **Header** — repo name, date, assessor set, and a one-line framing: the assessment
   covers **three pillars of AI infrastructure** — *(1) Agent instructions & docs,
   (2) Process & governance, (3) Tooling & environment* — each scored against the
   two-layer (consensus + orion) benchmark.
2. **Overall scorecard** — per-area roll-up scores (visual, e.g. 0–5 bars) **grouped
   under the three pillars**, a per-pillar headline plus the overall AI-infrastructure
   health verdict, and the top ranked recommendations.
3. **Per-area sections, organized under the three pillars** (Pillar 1: agent
   instructions, README · Pillar 2: contributing/governance, PR template, issue
   template · Pillar 3: tooling, setup self-audit), each with:
   - the **consensus checklist** (met/partial/missing) with **cited, re-validated**
     source links,
   - the **orion rubric** with each dimension's 0–5 score + justification,
   - **gaps → recommendations**, with **suggested rewrite snippets** (or the tooling
     config / generated template draft) in copy-friendly code blocks the user can lift,
     each carrying a **scope badge** (`repo` / `user` / `account`),
   - **smells caught**.
   The **tooling** section lists recommended-but-missing tooling by capability with the
   scope to add it at; the **setup self-audit** section (if run) lists each
   broken/stale/wasteful finding with its `~/.claude/` file + line.
4. **Cross-cutting findings** (duplication/drift, coverage gaps, convention
   consistency, no-source-of-truth → propose a tracker, tooling-coverage gaps).
5. **Level up to user scope** — the consolidated, deduped set of recommendations tagged
   `user (~/.claude)` or `account (.github)`: the commonalities this user can apply
   **once** and have every repo inherit, instead of redoing them per repo. Group by
   destination — `~/.claude/CLAUDE.md` (generic rules), `~/.claude/settings.json` /
   `~/.claude.json` (hooks/statusLine/MCP), and a public **`<owner>/.github`** repo
   (PR/issue templates, CONTRIBUTING/CODE_OF_CONDUCT/SECURITY/SUPPORT) — each with its
   paste-ready snippet and the exact path/filename to place it at. Include a one-line
   **universality caveat** (only hoist what's truly common across the user's repos; a
   per-repo copy still overrides an account default) and, for the `.github` route, the
   one-time `gh repo create <owner>/.github --public` setup note. Read-only: the skill
   places nothing — it shows the user what to lift and where.
6. **Sources** — the consensus resources actually cited (including any the user added
   in Phase 1), with their re-validation status.
7. **Footer** — a note that everything here is a **recommendation only**; the skill
   changed nothing in the repo or the user's settings and committed nothing — applying
   any change is the user's call.

Keep the styling clean and dark-theme-friendly to match the other orion report skills.
Then **summarize the headline in chat** (scores + top gaps, and call out the
**level-up set** — what's worth hoisting to user scope) and give the file path.
The skill ends here — it does **not** offer to apply fixes.

---

## Distribution-safety gate (this repo is publicly distributable)

This skill and its guidelines ship publicly. Before writing the report or any
guideline edit, confirm **nothing project-specific leaked into the skill or guideline
files** — no person/org/product/repo/stack/locale/path specifics in prose, examples,
or rubric items. The *report* about a user's repo is a **local artifact** (in their
Downloads) and may name their repo and quote their docs — that's fine; it is never
committed back into this repo. What must stay general is everything under
`skills/assess-project-ai-infrastructure-orion/` itself.

When the orion guidelines flag that the *target* repo's public docs leak specifics,
report it as a finding — but do not copy those specifics into anything under this
skill folder.
