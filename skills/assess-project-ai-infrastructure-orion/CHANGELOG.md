# Changelog — assess-project-ai-infrastructure-orion

This skill follows **no `-vN` convention** — it is edited in place. Record notable
changes here.

## Response shape framed as ADHD-support pillars (CLAUDE.md guideline)

- **`guidelines/claude-md.md` §B4** — the "declared response shape" block now names
  what the rules are in reality: **ADHD-support pillars** (answer-first, one idea per
  line, visible state, a single next step, no prose walls — the structure that keeps a
  reply followable for a reader who struggles to sustain focus). A user-level file may
  make the framing explicit (e.g. *"talk to me like I have ADHD and struggle to focus —
  these rules are the support pillars"*); the assessor treats that clause as a positive
  signal of a deliberate shape, never as a requirement — absence is not penalized.

## Response shape & descriptive sub-agent naming (CLAUDE.md guidelines)

- **`guidelines/claude-md.md` §B4 gained "a declared *response shape*".** Tone rules
  say how an answer should *sound*; a response shape fixes the *form* every answer
  takes. The assessor now checks whether the file states one in checkable terms:
  action first, numbered steps for multi-step work, exactly one concrete next step,
  tangents suppressed, a one-line state restatement each turn, concrete time estimates
  (or an explicit "can't estimate without X"), wins stated concretely, errors reported
  matter-of-factly, and no preamble/recap/sign-off — with any always-on marker (an AI
  canary) **explicitly exempted** so the rules don't collide. Flagged as prime
  **user-level** material; a repo-level file that omits it is *"could hoist"*, not a
  defect.
- **§B9 gained "name every sub-agent for the human watching."** Each spawned sub-agent
  needs a title/name/description saying *what it is doing* — the agent list / run graph
  is the operator's only window into a parallel fan-out, and generic or duplicated
  labels make a run impossible to stop, inspect, or attribute. Treated as a safety
  item, not cosmetics; pairs with the §B1 output cap.
- **New §C smells** — response-shape rules that contradict each other (e.g. "restate
  state every turn" alongside "never recap", or a mandated canary banned by a
  "no preamble" rule), and sub-agents spawned with generic/duplicated labels.
- **Rubric (§D)** — dimension 5 now covers the response shape and its internal
  consistency; dimension 6 now covers descriptive sub-agent naming.

## Root-cause-on-repeated-failure discipline (CLAUDE.md guideline)

- **New bullet in `guidelines/claude-md.md` §B3** — a strong CLAUDE.md tells the agent
  that when the same command/test/build/action fails again (e.g. a second time), it must
  **stop retrying and diagnose the root cause** before the next attempt: read the real
  error, check actual state, act on the cause — never blind-loop a failing action, never
  mask a failure (skip/delete the test, widen a timeout, swallow the error). Explicitly
  **applies at both user and repo scope**. Rubric dimension 2 (Verification) and the
  smells list updated to cover it.

## User-level vs repo-level CLAUDE.md — scope-aware, independent assessment

- **`guidelines/claude-md.md` gained a "Scope" section.** The assessor now detects
  whether each `CLAUDE.md` is **user-level** (`~/.claude/…`, loaded on every repo) or
  **repo-level** (`<repo>/…`, loaded for one repo) and scores it against the rubric
  **for its own scope**. A user-level file is no longer penalized for lacking
  repo-specifics (stack rules, a repo's tracker/commands) — those dimensions are **N/A**
  at user scope — and hardcoding one project's specifics into a user file is now flagged
  as a smell. A per-dimension scope-applicability table and user-level-only checks
  (token economy, no machine paths, no single-project specifics) were added.
- **Independent assessment, no comparison.** Every `CLAUDE.md` is assessed on its own
  merits; the skill never scores one file by comparing it to another, and never marks a
  rule "missing" that correctly lives at the other scope.
- **`SKILL.md`** — new operating principle 9; Phase 2 records each file's scope; the
  Phase 3 agent-instructions assessor tags scope and applies the scope-appropriate
  rubric; the user-level `~/.claude/CLAUDE.md` is assessed with this rubric (at user
  scope) when the user asks or opts into the self-audit.

## Read-only claim scoped to the target repo

- The frontmatter description claimed the skill "never edits any file", contradicting
  Phase 1's opt-in append of user-supplied sources to `guidelines/consensus-resources.md`.
  The claim is now scoped: strictly read-only **towards the target repo and the user's
  settings**; its only writes are the HTML report and (opt-in) its own guidelines corpus.

## Code-quality & design standards (CLAUDE.md guideline)

- **New §B13 in `guidelines/claude-md.md`** — a strong CLAUDE.md declares its
  code-quality posture: a stated design paradigm (OOP as the orion default — SOLID,
  encapsulation, composition over inheritance — unless the stack idiomatically calls
  for another), concrete clean-code rules (verifiable, not "write good code"), TDD as
  the default workflow (failing test first; bug fixes start with a regression test),
  and code-smell vigilance (refactor smells in new code, surface pre-existing ones —
  without licensing unrequested refactors).
- **Rubric dimension 10 added** to score §B13.

## AI canary + never-guess evidence discipline (CLAUDE.md guideline)

- **CLAUDE.md guideline additions** (`guidelines/claude-md.md`, §B4):
  - **AI canary** — an instruction-adherence marker (e.g. a fixed salutation token at
    the start of every response) that makes it visible when the instruction file has
    dropped out of context; assessed as a bonus signal, absence not penalised.
  - **Never guess or fabricate** — the "check actual file/config/service state"
    bullet broadened into a general evidence discipline: back every claim with
    something checkable; label unverified statements as assumptions.

## Recommendation scope tags + "Level up to user scope" report section

- **Scope tagging.** Every recommendation is now tagged with the lowest scope it can
  live at — `repo`, `user (~/.claude)`, or `account (.github)` — so commonalities that
  recur across all the user's repos (generic CLAUDE.md rules, PR/issue templates,
  CONTRIBUTING/CODE_OF_CONDUCT/SECURITY) can be applied **once** at user level instead of
  per repo. New "Recommendation scope — repo vs user-level (hoisting)" section defines
  the three scopes, the per-area mapping, and a **universality guard** (only hoist what's
  truly common across the user's repos).
- **New report section — "Level up to user scope":** the consolidated, deduped set of
  user-/account-scope recommendations, grouped by destination (`~/.claude/CLAUDE.md`,
  `~/.claude/settings.json` / `~/.claude.json`, and a public `<owner>/.github` repo),
  each with paste-ready snippet, exact path, the one-time `gh repo create <owner>/.github
  --public` note, and a per-repo-override caveat. Per-area sections carry a scope badge.
- **Still strictly read-only:** hoisting is a recommendation only — the skill never
  creates a `.github` repo, edits `~/.claude/`, or commits.

## Renamed + scope expanded → AI-development infrastructure

- **Renamed** `assess-project-docs-orion` → `assess-project-ai-infrastructure-orion`
  (folder, frontmatter, headings, guideline cross-references, README row).
- **Broadened** from "project documentation" to a project's **AI-development
  infrastructure**: docs **+ agent tooling + the user's own Claude setup.**
- **New assessor — issue/ticket template** (`guidelines/issue-template.md`): mirrors the
  PR-template rubric, headlined by the **agent-ready vs needs-human-decision** marker so
  an autonomous agent knows whether it may take a ticket; generates a draft (with the
  marker) when none exists, in the report.
- **New assessor — agent tooling (MCPs / plugins)**
  (`guidelines/tooling-mcps-plugins.md`): detects MCP servers / plugins / helper CLIs at
  **repo and user scope** and recommends broadly-useful, **relevant** missing tooling by
  capability (browser-automation, container, knowledge-base, output/context-compression,
  token-optimization), with publicly-available examples re-validated at run time.
- **New assessor — Claude setup self-audit (opt-in)**
  (`guidelines/claude-setup-audit.md`): points Claude at the user's own `~/.claude/`
  (settings.json, hooks, memory, skills/plugins) and reports what's **stale / broken /
  wasteful** — read-only, file+line findings, never edits the user's config.
- **Governance:** if the repo has **no tracker at all**, the synthesis now proposes
  adopting one as the single source of truth (**GitHub Issues** for a GitHub-hosted
  repo); required-green-CI-before-merge and a stated **squash-merge** strategy added to
  the merge/protection guidance.
- **CLAUDE.md guideline additions:** cap **sub-agent output** in the spawn prompt
  ("verdict + N bullets max") to protect main context; an explicit **ELI5 / layman**
  audience-altitude preference; default-branch protection with **required green CI** and
  a **squash-merge** default; the directness guideline reframed as **Radical Candor**
  (care personally *and* challenge directly; ruinous empathy as the failure mode).
- Consensus layer extended with §6 (MCP / plugins / tooling) and §7 (Claude Code
  settings / hooks / memory) sources, plus distilled issue-template criteria.
- **Three-pillar framing** of the report and assessor set — *(1) Agent instructions &
  docs, (2) Process & governance, (3) Tooling & environment* — so the expanded scope
  reads as one coherent assessment (Phase 0 list, report header + scorecard grouped by
  pillar; individual guideline files unchanged).
- Still **strictly read-only** across all assessors — including the new user-scope
  reads; nothing is installed, edited, or committed.

## Initial version

- New skill: assess a repository's project documentation against a **two-layer
  benchmark** and emit a self-contained HTML report into the Downloads folder.
- **Consensus layer** (`guidelines/consensus-resources.md`) — independent, widely-cited
  best-practice resources (Claude Code memory & best-practices docs, Make a README /
  Standard Readme, GitHub community-health & PR-template docs, Conventional Commits /
  Keep a Changelog / SemVer / ADR), re-validated at run time.
- **Orion layer** — per-doc guideline files generalized from real projects:
  - `guidelines/claude-md.md` — agent instruction files (effort economy, change
    philosophy, end-to-end verification, communication & directness,
    discuss-before-doing, git guardrails, branch/worktree naming, multi-agent safety,
    source-of-truth & deferral discipline, doc maintenance, stack enforcement). Includes
    the collected guideline: **summarize and use clear language by default; let the
    user ask for more detail.**
  - `guidelines/project-readme.md` — README orientation, runnable quick-start,
    reference-don't-duplicate, status honesty.
  - `guidelines/contributing-and-governance.md` — contribution mechanics, merge/
    protection rules, deferral discipline, decision records, and the collected
    guideline: **agent-safe vs. needs-human-decision issue tagging** (flag the issues
    where an agent must stop and ask a human; apply narrowly).
  - `guidelines/pr-template.md` — PR-template *guidelines* (not a template):
    summary+issue link, work-item refs, out-of-scope **anchoring discipline**, real
    test-evidence, an enforcement checklist **generated from the repo**, human-owned
    merge.
- A **benchmark-confirmation step** (Phase 1): before assessing, the skill shows the
  user the exact consensus resource list it will use (re-validated for reachability)
  and asks whether to add more; user-added sources can optionally be persisted into
  `guidelines/consensus-resources.md` for future runs.
- Per-doc assessor pipeline (parallel, capped) and cross-doc synthesis
  (duplication/drift, coverage gaps, convention consistency).
- **Strictly read-only:** the skill reports and recommends only. It never edits any
  file, never writes a PR template into the repo, never commits, and does not offer to
  apply fixes — every recommendation lives in the HTML report for the user to apply.
