# Orion guidelines — `CLAUDE.md` (agent instruction files)

The orion layer for assessing a repository's agent-instruction file(s):
`CLAUDE.md`, `./.claude/CLAUDE.md`, `CLAUDE.local.md`, `.claude/rules/*.md`, and an
`AGENTS.md` imported by a `CLAUDE.md`. Pair this with the consensus baseline in
[`consensus-resources.md`](consensus-resources.md) (section 1).

These guidelines are **distilled and generalized** from real project CLAUDE.md files.
They describe *behaviours a good agent-instruction file establishes* — not any one
project's stack. The assessor checks whether the target file covers each area
**appropriately for that project**, not whether it copies this wording.

---

## A. Consensus baseline (must hold before orion specifics)

Fail these and the rest barely matters:

- **Concise & signal-dense**, imperative voice, **specific & verifiable** rules,
  scannable structure, no internal contradictions, references rather than duplicates
  the README/architecture, **right-sized (~≤200 lines)** and right-scoped.
- Uses the correct mechanism for the job: durable behavioural rules in `CLAUDE.md`,
  per-area rules in `.claude/rules/` (path-scoped), hard enforcement in **hooks**
  (not prose), repeatable procedures in **skills**.

## B. Orion layer — areas a strong CLAUDE.md establishes

Grouped by theme. For each, the assessor notes **present / partial / absent** and
whether it's concrete enough to act on.

### B1. Effort & resource economy
- A default reasoning-effort posture, with explicit "escalate only when stuck."
- Sub-agent model tiering (cheap model for simple work, top model reserved for hard
  decisions) and a **cap on parallel sub-agents** to avoid rate limits.

### B2. Change philosophy
- "Smallest change that works"; follow existing patterns; **no unrequested
  refactors or speculative abstractions.**

### B3. Verification is end-to-end (high value — flag hard if missing)
- **Code analysis is not verification** — run the real test/build/workflow.
- Auto-run the suite after implementing and **before** committing; report pass/fail
  counts without being asked.
- "Run it" means *to completion* (tests/build/e2e), not "generate the code."
- **The suite must be green at end of session**, and **pre-existing failures are
  still the agent's responsibility** — fix them or surface them explicitly and get
  acknowledged; never disclaim with "those were already failing."
- If something genuinely can't be run locally (missing infra, OS-specific), **say so
  explicitly** — don't claim success.

### B4. Communication & tone
- **Summarize and use clear language by default; let the user ask for more detail.**
  Lead with the outcome and the decision, not a blow-by-blow; expand only on request.
- **Functional / business-first explanations** when the reader is unfamiliar with the
  code — explain *what it does for the user* before implementation detail.
- **Plain-language onboarding tone** — assume the reader is new to the stack and
  tooling; gloss domain terms and tool steps on first use.
- **Emit reports/docs as files**, not inline walls of text, unless inline is asked for.
- Check the *actual* state of files/configs/services before asserting it.

### B5. Directness (anti-sycophancy)
- No flattery or agreement-for-its-own-sake; **say the hard thing**.
- **Disagree explicitly before executing** when a plan is flawed ("that breaks X
  because Y"), but don't argue for argument's sake, and stop relitigating settled
  decisions. Treat the user as a **peer, not a principal.**

### B6. Discuss-before-doing
- While the user is exploring / asking for an opinion, give the opinion or trade-offs;
  **don't edit files or run tools until an explicit "go."** If permission is unclear,
  ask — don't assume it.

### B7. Git & GitHub guardrails
- **Never commit directly to the default branch**; all work goes through a feature
  branch + PR.
- No force-push, no hook bypass (`--no-verify`, `--no-gpg-sign`), no disabling
  safeguards on protected branches.
- **Surface CI failures to the user**; don't auto-fix-and-re-push without approval.
- **Never auto-merge** — the agent may open and describe a PR and suggest reviewers,
  but the **merge decision belongs to a human.**
- Don't run destructive/irreversible operations without confirming; prefer
  dry-run/preview first.

### B8. Branch & worktree naming conventions
- A documented branch format, e.g. `<action>/(#<id>)-<short-description>` where
  `<action>` ∈ {feat, fix, chore, refactor, docs, test} and `<id>` is the tracker ID.
- Worktree directory names kept **short** (e.g. keyed by issue id) so Windows
  `MAX_PATH` doesn't bite, while the branch keeps the descriptive name.
- "Soft migration" framing for new conventions (apply to new branches; don't rewrite
  in-flight history).

### B9. Multi-agent safety (when sub-agents run in parallel)
- **No `git stash`** in sub-agents (corrupts the parent's working tree) — use
  worktrees to isolate.
- **No branch switching** in sub-agents.
- **Scope commits tightly** — each sub-agent commits only the files it touched;
  **never `git add -A`** in a multi-agent context.
- **Fail clean** — a failing sub-agent reports and stops; it doesn't attempt recovery
  that conflicts with the parent.

### B10. Source-of-truth & deferral discipline
- A single, named **source of truth for status** (e.g. the issue tracker), and a rule
  to comment progress at milestones.
- **Every deferral carries an anchor** — any "out of scope / follow-up / deferred"
  note must reference a linked tracker item (file it first) or a work-item ID on the
  same line. Recurring pre-existing failures get **one umbrella item**, referenced
  everywhere, never re-described as fresh prose.
- **Agent-safe vs. needs-human-decision tagging.** Issues/stories should declare
  whether they are safe for an agent to complete autonomously or **require a human
  decision** — so when an agent picks the work up, it knows to pause and ask the
  human to validate or answer before proceeding. Apply this **only** where a genuine
  human judgement call is needed (ambiguous product/UX/security/data trade-offs); do
  **not** gate work the agent can reasonably infer or determine itself. (This is
  primarily an *issue-authoring* rule — see
  [`contributing-and-governance.md`](contributing-and-governance.md) — but a good
  CLAUDE.md tells the agent to **honour the tag**: stop and ask on a flagged item.)

### B11. Documentation maintenance
- A **change-X → update-doc-Y map** (a small table) so docs don't rot.
- A lightweight **decision log** and/or **ADR** convention for architectural choices,
  with an index.
- **Governed documents** (PRD, architecture, the CLAUDE.md itself, …) require explicit
  human approval to edit — **propose, don't silently apply.**

### B12. Stack & architecture enforcement
- **"Must Always / Must Never"** lists and **naming-convention tables** that capture
  the project's real rules — *but detected from the project*, never hardcoded to a
  stack. (The assessor checks these exist and are specific/verifiable; it does **not**
  expect any particular technology.)
- A short **dev-environment** section: how to bring the stack up, common pitfalls,
  port/credential checks before starting servers.

---

## C. Smells to flag

- Over-200-line sprawl; long prose paragraphs instead of rules.
- Vague rules ("write good code", "test properly") that can't be verified.
- Duplicates the README / architecture doc instead of linking it.
- Contradictions between the root file and nested/`rules/` files.
- "Enforcement" written as prose that should be a **hook** (e.g. "always run lint
  before commit") — note it as a hook candidate.
- Secrets, absolute user paths, or machine-specific values committed into the file.
- No verification/green-suite rule; no git guardrails; no source-of-truth statement.
- Stack rules hardcoded as copy-paste from another project (mismatch with the repo's
  actual manifests).

## D. Scoring rubric (per dimension, 0–5)

Score each, then roll up. **0** absent · **1** mentioned only · **2** partial/vague ·
**3** present & adequate · **4** specific & verifiable · **5** specific, verifiable,
and well-scoped (right mechanism, right length).

1. **Hygiene & form** — concise, imperative, specific, scannable, ≤~200 lines, no
   contradictions, references not duplicates (consensus baseline, §A).
2. **Verification & quality gates** (§B3) — *weighted highest.*
3. **Git/GitHub & merge guardrails** (§B7).
4. **Change philosophy & effort economy** (§B1–B2).
5. **Communication & directness** (§B4–B6).
6. **Multi-agent safety** (§B9) — *N/A if the project never uses parallel sub-agents;
   mark N/A rather than 0.*
7. **Source-of-truth, deferral & agent-safe tagging** (§B10).
8. **Doc maintenance & governance** (§B11).
9. **Stack/architecture enforcement specificity** (§B12).

For every dimension under 3, the report must give a **concrete fix** and, where
useful, a **suggested rewrite snippet** the user could paste in.
