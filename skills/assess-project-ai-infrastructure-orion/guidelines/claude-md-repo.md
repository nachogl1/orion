# Orion guidelines — **repo-level** `CLAUDE.md`

The orion layer for assessing a **repo-level** agent-instruction file:
`<repo>/CLAUDE.md`, `<repo>/.claude/CLAUDE.md`, `<repo>/CLAUDE.local.md`,
`<repo>/.claude/rules/*.md`, and an `AGENTS.md` imported by one of them.
For the user's own global file use [`claude-md-user.md`](claude-md-user.md); the scope
router is [`claude-md.md`](claude-md.md). Pair this with the consensus baseline in
[`consensus-resources.md`](consensus-resources.md) (section 1).

These guidelines are **distilled and generalized** from real project files. They
describe *behaviours a good project file establishes* — not any one project's stack.
The assessor checks whether the file covers each area **appropriately for that
project**, detected from its own manifests and source at run time, never against a
preferred technology.

---

## What a repo-level file is for

It loads **only for this repo**. Its job is this project's **specifics**: the stack, the
real build/test commands, the architecture, its named source of truth, its branch and
naming rules, its enforcement mechanisms.

**Assessment rules:**

- **Assess this file on its own.** Never compare it to another repo's `CLAUDE.md` or to
  the user's global file.
- **Do not penalize it for lacking generic cross-project preferences** — personal tone,
  a response shape, an AI canary, a global default paradigm. Those may sit at **user**
  scope and be inherited (see [`claude-md-user.md`](claude-md-user.md)). Note them as
  *"could hoist to user scope"*, never as a repo defect.
- **A repo file that restates the user's global preferences verbatim is not a bug, but
  it is a drift risk** — two copies of one rule diverge. Note it; if the repo is public
  and its contributors may have no user-level file, the duplication is deliberate and
  the file should say so.

---

## A. Consensus baseline (must hold before orion specifics)

Fail these and the rest barely matters:

- **Concise & signal-dense**, imperative voice, **specific & verifiable** rules,
  scannable structure, no internal contradictions, references rather than duplicates the
  README/architecture.
- **Line budget.** The consensus sources put the cap at **~200 lines**
  (`consensus-resources.md` §1). The orion layer allows a repo file up to **~350 lines**,
  because §B asks it to carry things a user file never does: naming tables, Must Always /
  Must Never lists, a change→doc map, the repo's real commands. This is a deliberate
  **orion-layer deviation from the cited consensus number** — score the consensus
  criterion against ~200 as the source states it, and the orion criterion against ~350,
  so the report never hides the disagreement.
- Past the budget, the fix is **path-scoped `.claude/rules/*.md`** (loaded only when the
  agent touches a matching area), not a longer root file. The budget buys *rules*:
  length spent on tables of real project rules is earned, length spent on prose is
  sprawl at any count.
- Uses the correct mechanism for the job: durable behavioural rules in `CLAUDE.md`,
  per-area rules in `.claude/rules/` (path-scoped), **hard enforcement in hooks** (not
  prose), repeatable procedures in **skills**.

## B. Orion layer — areas a strong repo-level file establishes

For each, the assessor notes **present / partial / absent** and whether it's concrete
enough to act on.

### R1. Verification & quality gates — end-to-end, with this repo's real commands
*(highest-value dimension — flag hard if missing)*
- **Code analysis is not verification** — run the real test/build/workflow.
- **The actual commands are named** (test, build, lint, e2e, how to bring the stack up).
  A posture without commands is a user-scope rule that never became a project rule.
- Run the suite after implementing and **before** committing; report pass/fail counts
  without being asked.
- "Run it" means *to completion* (tests/build/e2e), not "generate the code."
- **The suite is green at end of session**, and **pre-existing failures are still the
  agent's responsibility** — fix them or surface them explicitly and get acknowledged;
  never disclaim with "those were already failing."
- If something genuinely can't be run locally (missing infra, wrong OS), **say so
  explicitly** — don't claim success.
- **Root-cause on repeated failure — don't blind-retry.** When the same command, test,
  build, or action fails **again**, stop repeating it and work out *why* before the next
  attempt — read the actual error, check the real state, form a hypothesis, act on the
  cause. Never loop a failing action hoping it passes, and never "fix" a failure by
  masking the symptom (deleting/skipping the test, widening a timeout, swallowing the
  error). A signal that looks like a known failure may have a **different** cause.
- **A repo with no test suite is not exempt** — it states what "verified" means here
  instead (the file renders, the installer runs clean, the container builds).

### R2. Git/GitHub & merge guardrails (this repo's actual rules)
- **Never commit directly to the default branch**; all work lands via a feature branch
  + PR.
- No force-push, no hook bypass (`--no-verify`, `--no-gpg-sign`), no disabling
  safeguards on protected branches.
- **Surface CI failures to the user**; don't auto-fix-and-re-push without approval.
- **Never auto-merge** — the agent may open and describe a PR and suggest reviewers, but
  the **merge decision belongs to a human.**
- **Default branch is protected, and the rule says so:** all changes land via PR;
  **required CI checks must be green before merge** (no merging red or still-pending
  CI); and the project's **merge strategy is stated** — squash, merge commit, or rebase,
  whichever the repo has chosen. **The assessor scores that a strategy is declared and
  that it matches the repo's actual settings — never that it matches a preferred one**
  (a merge-commit repo running release trains or stacked PRs is not a lower score than a
  squash repo). The agent never merges around a failing/pending check.
- **Commit-message convention stated** (e.g. Conventional Commits `type(scope): summary`)
  with this repo's real scope vocabulary, plus any required trailer.
- Don't run destructive/irreversible operations without confirming; prefer a
  dry-run/preview first.

### R3. Branch & worktree naming conventions
- A documented branch format, e.g. `<action>/(#<id>)-<short-description>` where
  `<action>` ∈ {feat, fix, chore, refactor, docs, test} and `<id>` is **this repo's**
  tracker ID.
- Worktree directory names kept **short** (e.g. keyed by issue id) so Windows
  `MAX_PATH` doesn't bite, while the branch keeps the descriptive name.
- "Soft migration" framing for new conventions (apply to new branches; don't rewrite
  in-flight history).
- The convention should match what the repo's own tooling generates — a file describing
  `feat/<desc>` while the project's automation creates issue-numbered branches is behind
  its own tooling.

### R4. Change philosophy & effort economy
- **"Smallest change that works"** — follow the patterns already in the file, **no
  unrequested refactors or speculative abstractions.**
- Any repo-specific effort rules: what's expensive to run here, what to avoid touching,
  which directories are generated.
- If the project runs sub-agents: model tiering, a **cap on parallel sub-agents**, and
  **bounded sub-agent output** in the spawn prompt (a verdict + N bullets, or a fixed
  schema) — uncapped output floods the orchestrator's context.

### R5. Repo-specific communication & reporting
*Score only what is genuinely project-specific; generic tone and response-shape rules
belong at user scope and are **N/A** here (note "could hoist"), not a defect.*
- **Where output goes** — e.g. reports/docs emitted as files in a stated location rather
  than inline; the artifacts this repo expects a run to leave behind.
- **Audience** — who reads this project's output (contributors, stakeholders, a public
  audience) and at what altitude to explain it.
- **Never guess or fabricate** about *this* project — check the actual state of files,
  configs, and services before asserting it; label anything unverified as an assumption.
- **Radical Candor and discuss-before-doing** — if not inherited from a user file, the
  repo may state them: challenge a flawed plan explicitly before executing, and don't
  edit or run tools while the user is still exploring.

### R6. Multi-agent safety (when the repo's workflows run parallel sub-agents)
*N/A if the project never fans out; mark N/A rather than 0.*
- **No `git stash`** in a sub-agent (it corrupts the parent's working tree) — isolate in
  a **worktree** instead.
- **No branch switching** in a sub-agent.
- **Scope commits tightly** — each sub-agent commits only the files it touched; **never
  `git add -A`** in a multi-agent context.
- **Fail clean** — a failing sub-agent reports and stops; it doesn't attempt its own
  recovery.
- **Name every sub-agent for the human watching, not for the code** — a title saying
  *what that agent is doing* (`review-auth-tests`, not `agent-3`). The agent list is the
  operator's only window into a fan-out: with generic or duplicated labels they cannot
  tell which agent to stop, re-run, inspect, or blame. That's a safety problem, not a
  cosmetic one. Pairs with the output cap in §R4.

### R7. Source-of-truth, deferral & agent-safe tagging
- A single, **named** source of truth for status (this repo's issue tracker, board, or
  story docs), and a rule to comment progress at milestones. *Naming it is the point —
  this is the dimension a user-level file cannot cover.*
- **Only file a ticket when the work genuinely needs one** — real, actionable, worth
  someone's time later. Small enough to just do → do it. Noise → drop it and say so.
  Filing "to be safe" grows a backlog nobody drains.
- **Dedupe before filing** — search the code *and* the open items to confirm nothing
  already covers it.
- **Every deferral carries an anchor** — any "out of scope / follow-up / deferred" note
  references a linked tracker item (file it first) on the same line. Recurring
  pre-existing failures get **one umbrella item**, referenced everywhere, never
  re-described as fresh prose.
- **Never defer to a closed item** — verify it's open before pointing at it as the
  reason to skip work.
- **Agent-safe vs. needs-human-decision tagging.** Issues/stories declare whether they
  are safe for an agent to complete autonomously or **require a human decision** — so an
  agent picking the work up knows to pause and ask. Apply it **only** where a genuine
  judgement call exists (ambiguous product/UX/security/data trade-offs); don't gate work
  the agent can reasonably determine itself. (Primarily an *issue-authoring* rule — see
  [`contributing-and-governance.md`](contributing-and-governance.md) — but a good
  `CLAUDE.md` tells the agent to **honour the tag**.)

### R8. Documentation maintenance & governance
- A **change-X → update-doc-Y map** (a small table) so docs don't rot.
- A lightweight **decision log** and/or **ADR** convention for architectural choices,
  with an index.
- **Governed documents** (PRD, architecture, the `CLAUDE.md` itself, …) require explicit
  human approval to edit — **propose, don't silently apply.**
- **AGENTS.md interop** — if the repo carries both a `CLAUDE.md` and an `AGENTS.md` (or
  other tool-specific rule files), one is the source and the others import or point to
  it. Two hand-maintained copies drift, and the agent then has a contradiction.

### R9. Stack & architecture enforcement specificity
- **"Must Always / Must Never"** lists and **naming-convention tables** that capture the
  project's real rules — *detected from the project*, never hardcoded to a stack. The
  assessor checks these exist and are specific/verifiable; it does **not** expect any
  particular technology.
- A short **dev-environment** section: how to bring the stack up, common pitfalls,
  port/credential checks before starting servers.
- Rules must match the repo's actual manifests — stack rules copy-pasted from another
  project are a §C smell.

### R10. Code-quality & design standards
- **A stated design paradigm — declared, not improvised.** The file says how code is
  organised, in whatever terms the project actually works in: object-oriented (SOLID,
  strong encapsulation, composition over inheritance), functional/data-oriented,
  procedural, component-and-hooks, actor-based — the stack's own idiom. **The assessor
  scores that a paradigm is declared and that it matches the repo's real idiom, detected
  from its manifests and source layout — never that it matches an orion-preferred one.**
  Undeclared, the agent improvises a different style each session and the codebase
  drifts. Only where nothing is declared *and* nothing is detectable does the
  recommendation become "pick one and write it down."
- **Clean-code expectations made concrete** — intention-revealing names, small
  single-purpose functions/classes, no dead or commented-out code, no magic values —
  phrased as verifiable rules, not "write good code" (that's a §C smell).
- **A stated testing workflow** — e.g. TDD as the default (new behaviour starts with a
  failing test; red → green → refactor; a bug fix starts with a regression test that
  reproduces the bug). Tests are written with the code, not bolted on after.
- **Code-smell vigilance** — watch for classic smells (long methods, god classes,
  duplicated logic, feature envy, shotgun surgery) in code the agent writes *and* code it
  touches: refactor smells in new code before committing; **surface** pre-existing ones
  rather than silently extending them. (Compatible with §R4 — surfacing a smell is not a
  licence for an unrequested refactor.)

### R11. Enforcement wiring — a hard rule needs a mechanism, not just prose
A `CLAUDE.md` is a *prompt*, and a prompt is the weakest form of enforcement: it degrades
as context fills, and nothing fails loudly when it is ignored. So for every rule the file
states as **hard** — the suite is green before commit, never commit to the default
branch, never `--no-verify`, never commit a secret, lint/format before push — the
assessor asks *what actually stops it happening*, and scores the answer:

- **A mechanism exists and the file names it.** A hook (`.claude/settings.json` hooks,
  git hooks, `pre-commit`), a **required CI check**, **branch protection**, or a template
  that forces the field. Naming it matters twice over: the agent learns the rule is real,
  and it learns not to route around it.
- **Where to look**: `.claude/settings.json`, `.git/hooks/`, `.pre-commit-config.yaml`,
  `.husky/`, CI workflow files, `.github/*template*`, and branch-protection settings if
  they're visible.
- **Score the fraction of hard rules with real backing**, not the number of hooks. Ten
  hooks that enforce none of the file's stated rules is not a 5.
- **List every prose-only hard rule as a hook/CI candidate**, each with the concrete
  mechanism to add — that list *is* the recommendation for this dimension.
- **Never credit enforcement that isn't there.** A file claiming "the pre-commit hook
  blocks X" with no such hook is worse than silence: it teaches the agent a false safety
  net. Flag the mismatch.
- Soft rules (tone, change philosophy) are **out of scope here** — they can't be
  mechanised and are scored under §R4–R5.

---

## C. Smells to flag (repo scope)

- Sprawl past ~350 lines; long prose paragraphs instead of rules at *any* length.
  Overflow belongs in path-scoped `.claude/rules/*`, not a longer root file.
- Vague rules ("write good code", "test properly") that can't be verified.
- Duplicates the README / architecture doc instead of linking it.
- Contradictions between the root file and nested / `.claude/rules/` files, or between
  `CLAUDE.md` and an `AGENTS.md` maintained in parallel.
- "Enforcement" written as prose that should be a **hook** (e.g. "always run lint before
  commit") — note it as a hook candidate (§R11).
- **Enforcement claimed but absent** — the file names a hook, check, or protection that
  doesn't exist in the repo. A false safety net is worse than no claim.
- Secrets, absolute user paths, or machine-specific values committed into the file.
- No verification rule; no git guardrails; no named source of truth.
- Blind-retrying a failing command/test/action instead of diagnosing the root cause; or
  "fixing" a failure by masking it (skip/delete the test, widen the timeout, swallow the
  error).
- Stack rules hardcoded as copy-paste from another project (mismatch with this repo's
  actual manifests).
- Conventions that lag the repo's own tooling (a branch format the project's automation
  doesn't produce).
- Sub-agents spawned with generic, duplicated, or task-echoing labels (`agent-1`, `task`,
  `subagent`) in a file that mandates parallel fan-out — the run can't be observed,
  stopped, or attributed from the agent list.

## D. Scoring rubric (per dimension, 0–5)

**0** absent · **1** mentioned only · **2** partial/vague · **3** present & adequate ·
**4** specific & verifiable · **5** specific, verifiable, and well-scoped (right
mechanism, right length).

1. **Hygiene & form** (§A) — concise, imperative, specific, scannable, within the ~350
   line budget, no contradictions, references not duplicates.
2. **Verification & quality gates** (§R1) — *weight 2;* includes this repo's real
   commands and root-cause discipline on repeated failure.
3. **Git/GitHub & merge guardrails** (§R2).
4. **Branch & worktree naming conventions** (§R3).
5. **Change philosophy & effort economy** (§R4).
6. **Repo-specific communication & reporting** (§R5) — *N/A if the project genuinely has
   no repo-specific output/audience rules and inherits tone from user scope.*
7. **Multi-agent safety** (§R6) — *N/A if the project never uses parallel sub-agents;
   mark N/A rather than 0.*
8. **Source-of-truth, deferral & agent-safe tagging** (§R7).
9. **Doc maintenance & governance** (§R8) — includes AGENTS.md single-sourcing.
10. **Stack/architecture enforcement specificity** (§R9).
11. **Code-quality & design standards** (§R10) — paradigm declared, clean-code rules
    verifiable, testing workflow, code-smell vigilance.
12. **Enforcement wiring** (§R11) — *weight 2;* hard rules backed by hooks / required CI
    checks / branch protection / templates rather than prose alone, and the file names
    the mechanism.

**Roll-up = weighted mean over the applicable dimensions.** Weight **2** on dimension 2
(Verification & quality gates) and dimension 12 (Enforcement wiring); weight **1** on
every other. An **N/A** dimension drops out of *both* numerator and divisor — it is never
a 0. Worked example: dimensions 2 and 12 scored 4 and 2, six other applicable dimensions
averaging 4 → (4×2 + 2×2 + 4×6) ÷ (2 + 2 + 6) = 3.6.

For every dimension under 3, the report must give a **concrete fix** and, where useful, a
**suggested rewrite snippet** the user could paste in.
