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

## Scope — detect user-level vs repo-level FIRST, then assess each file on its own

A `CLAUDE.md` is judged **differently depending on where it lives**, because the two
scopes do different jobs. Before scoring, determine each file's scope from its path:

- **User-level** — `~/.claude/CLAUDE.md`, `~/.claude/CLAUDE.local.md`,
  `~/.claude/rules/*`. Loaded into **every** session on **every** repo. Its job is the
  user's cross-project preferences (how to communicate, candor, verification posture,
  generic git/PR conventions, effort economy).
- **Repo-level** — `<repo>/CLAUDE.md`, `<repo>/.claude/CLAUDE.md`,
  `<repo>/CLAUDE.local.md`, `<repo>/.claude/rules/*`, an `AGENTS.md` imported by one.
  Loaded **only** for that repo. Its job is this project's specifics (stack, build/test
  commands, architecture, its source-of-truth tracker, its naming rules).

**Rules for the assessor:**

1. **Assess every file independently, against the rubric for its own scope.** Do
   **not** compare two `CLAUDE.md` files against each other, and do **not** mark a rule
   "missing" from one file when that rule correctly lives at the **other** scope.
2. **A user-level file is not penalized for lacking repo-specifics** (a project's stack
   rules, build/test commands, that repo's tracker, its branch/naming tables). Those
   dimensions are **N/A** at user scope — and a user-level file that *hardcodes* one
   project's specifics is a **smell** (it pollutes every other repo's session).
3. **A repo-level file is not penalized for lacking generic cross-project preferences**
   (personal tone, an AI canary, a global default paradigm) — those may sit at user
   scope and be inherited. Note them as *"could hoist to user scope"*, not a repo defect.

**Which rubric dimensions (§D) apply at each scope:**

| §D dimension | User-level | Repo-level |
|---|---|---|
| 1 Hygiene & form | ✅ (leanness weighted **higher** — loads every prompt) | ✅ |
| 2 Verification & quality gates | ✅ generic posture ("run the real thing; green before commit; root-cause on repeated failure") | ✅ + this repo's actual commands |
| 3 Git/GitHub & merge guardrails | ✅ generic (never commit to default branch, Conventional Commits, no force-push) | ✅ + this repo's merge strategy / CI gates |
| 4 Change philosophy & effort economy | ✅ | ✅ |
| 5 Communication & directness | ✅ (prime user-level material) | ✅ (or inherited) |
| 6 Multi-agent safety | ✅ if the user runs parallel agents, else N/A | ✅ if the repo does, else N/A |
| 7 Source-of-truth, deferral & agent-safe tagging | generic convention only; the **named tracker is N/A** | ✅ (names this repo's tracker) |
| 8 Doc maintenance & governance | usually **N/A** (change→doc maps, ADRs are project-specific) | ✅ |
| 9 Stack/architecture enforcement | **N/A** (and hardcoding a stack here is a smell) | ✅ |
| 10 Code-quality & design standards | ✅ if the user sets a global default, else "could hoist" | ✅ |

**Extra checks that apply only to a user-level file** (a bloated or leaky user file
costs on every prompt of every project — cross-reference
[`claude-setup-audit.md`](claude-setup-audit.md), which audits it as part of the whole
`~/.claude/` setup):

- **Token economy** — it loads on every prompt everywhere; keep it lean.
- **No machine-specific values** — absolute user paths, home-folder names, secrets.
- **No single project's specifics** — stack rules, one repo's tracker/commands, one
  team's naming table. Those belong in that repo's file, not here.

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
- **Cap sub-agent *output* in the spawn prompt** — instruct each sub-agent to return a
  bounded result (e.g. *"return a verdict + 5 bullets max"*, or a fixed schema), not a
  free-form essay. Uncapped sub-agent output floods the orchestrator's context and can
  kill the turn; the instruction to bound the return belongs in the prompt that spawns
  the agent.

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
- **Root-cause on repeated failure — don't blind-retry.** When the same command, test,
  build, or action fails **again** (e.g. a second time), **stop repeating it** and work
  out *why* before the next attempt — read the actual error, check the real state, form
  a hypothesis, then act on the cause. Never loop the same failing action hoping it
  passes, and never "fix" a failure by masking the symptom (deleting/skipping the test,
  widening a timeout, swallowing the error). A signal that looks like a known failure
  may have a **different** cause — confirm the cause before acting on it. *(Applies at
  both user and repo scope.)*

### B4. Communication & tone
- **Summarize and use clear language by default; let the user ask for more detail.**
  Lead with the outcome and the decision, not a blow-by-blow; expand only on request.
- **Functional / business-first explanations** when the reader is unfamiliar with the
  code — explain *what it does for the user* before implementation detail.
- **Plain-language onboarding tone** — assume the reader is new to the stack and
  tooling; gloss domain terms and tool steps on first use. A common, strong user-level
  preference is an explicit *"explain it like I don't know this tech stack or domain —
  layman terms, no assumed knowledge"* instruction (an ELI5 posture). The assessor
  checks whether the file sets an explicit audience/altitude for explanations, rather
  than leaving tone to chance.
- **Emit reports/docs as files**, not inline walls of text, unless inline is asked for.
- **Never guess or fabricate.** Check the *actual* state of files/configs/services
  (code, docs, command output) before asserting it. Every claim should be backed by
  something checkable; anything unverified is explicitly labelled an assumption or
  uncertainty rather than stated as fact.
- **A declared *response shape*, not just a tone.** Tone rules say how an answer
  should *sound*; a response shape fixes the *form* every answer takes, so the reader
  never hunts for the point. The assessor checks whether the file pins this down in
  some checkable form — the exact list matters less than that it is stated:
  - **Action first** — the opening line is the next action or what changed, not
    context-setting, not a restatement of the question, not a warm-up.
  - **TLDR and one-liners by default** — every point lands as a single plain-and-simple
    line (a TLDR-style statement); depth is deferred until the reader asks for it.
    This governs density, not substance: a fact or caveat gets compressed into a
    one-liner, never dropped.
  - **Numbered steps** for anything multi-step — one action per line, in the order
    they happen.
  - **Exactly one concrete next step** to close — a single action, not a menu of
    options and not an open-ended offer to help.
  - **Tangents suppressed** — an unasked observation is cut, or parked in one
    labelled line at the very end; never dropped mid-answer.
  - **A one-line state restatement each turn** — what is done, in progress, and
    blocked (and on whom). This is *current status*; a good file explicitly
    distinguishes it from a recap of already-reported work, so it doesn't collide
    with the "no recap" rule below.
  - **Concrete time/effort estimates** ("~15 min", "3 commands") instead of "a bit" /
    "shortly" — and, per the no-guessing rule above, an explicit *"can't estimate
    without X"* rather than an invented number.
  - **Wins stated plainly and concretely** ("suite green, 42/42") — about the work,
    never flattery of the user (§B5).
  - **Errors reported matter-of-factly** — what broke, why, and the fix; no
    apologising, no self-criticism, no dwelling.
  - **No preamble, no recap, no sign-off.** If the file also mandates an always-on
    marker (an AI canary, below), it must **explicitly exempt** it here — otherwise
    the two rules contradict, which is a §C smell.

  In reality these shape rules are **ADHD-support pillars**: answer-first ordering,
  one idea per line, TLDR summaries with detail on demand, visible state, a single
  next step, and no prose walls are what keep a reply followable for a reader who
  struggles to sustain focus. A strong
  user-level file may make that framing explicit with a clause like *"talk to me
  like I have ADHD and struggle to focus — these rules are the support pillars"* —
  the assessor treats such a clause as a positive signal that the shape is
  deliberate, not incidental (never as a requirement; its absence is not penalized).

  This is prime **user-level** material: it is a cross-project preference and costs
  almost nothing to carry. A repo-level file that omits it is not defective (§Scope,
  rule 3) — note it as *"could hoist to user scope"*.
- **An instruction-adherence canary ("AI canary").** A cheap, always-visible marker
  that proves the instruction file is being applied — e.g. every response starts with
  a fixed token (a name, a tag). If the marker disappears, the user knows the
  instructions have dropped out of context or stopped being honoured. Optional: the
  assessor notes its presence as a positive signal of a deliberately maintained file
  rather than penalising its absence.

### B5. Directness (anti-sycophancy) — *Radical Candor*
- No flattery or agreement-for-its-own-sake; **say the hard thing**.
- **Disagree explicitly before executing** when a plan is flawed ("that breaks X
  because Y"), but don't argue for argument's sake, and stop relitigating settled
  decisions. Treat the user as a **peer, not a principal.**
- The orion posture here is **Radical Candor** — *care personally **and** challenge
  directly*. Both axes matter: challenging without care reads as obnoxious aggression;
  caring without challenge collapses into **ruinous empathy** (the sycophancy this
  section exists to prevent) — withholding a real objection to avoid friction. A strong
  CLAUDE.md asks for the candid, well-reasoned pushback, not deference. The assessor
  checks the file establishes *both*: permission to challenge **and** the expectation
  that challenges are specific and constructive, not just blunt.

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
- **Default branch is protected, and the rule says so:** all changes land via PR;
  **required CI checks must be green before merge** (no merging red or still-pending
  CI); and the project's **merge strategy is stated** — a **squash merge** to keep the
  default branch's history linear and one-commit-per-change is the common orion
  default. The agent never merges around a failing/pending check.
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
- **Name every sub-agent for the human watching, not for the code.** Each spawned
  sub-agent gets a title/name/description saying **what that agent is doing**
  (`review-auth-tests`, not `agent-3`, not a repeat of the parent task). The agent
  list / run graph is the operator's only window into a parallel fan-out: with
  generic or duplicated labels they cannot tell which agent to stop, re-run, inspect,
  or blame for a bad result — the run becomes unobservable, which is a safety
  problem, not a cosmetic one. Pairs with the output cap in §B1: a bounded return
  *and* a descriptive label make a fan-out readable.

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

### B13. Code-quality & design standards
- **A stated design paradigm, with OOP as the orion default.** The file declares how
  code is organised — the orion default is object-oriented design (SOLID, strong
  encapsulation, composition over inheritance, polymorphism over type-switching) —
  unless the project's stack idiomatically calls for another paradigm. The point is
  that the default is *declared*, not left to whatever the agent improvises.
- **Clean-code expectations made concrete** — intention-revealing names, small
  single-purpose functions/classes, no dead or commented-out code, no magic values —
  phrased as verifiable rules, not "write good code" (that's a §C smell).
- **TDD as the default workflow** — new behaviour starts with a failing test
  (red → green → refactor); tests are written with the code, not bolted on after; a
  bug fix starts with a regression test that reproduces the bug.
- **Code-smell vigilance** — watch for classic smells (long methods, god classes,
  duplicated logic, feature envy, shotgun surgery) in code the agent writes *and*
  code it touches: refactor smells in new code before committing; **surface**
  pre-existing ones rather than silently extending them. (Compatible with §B2 —
  surfacing a smell is not a licence for an unrequested refactor.)

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
- Blind-retrying a failing command/test/action instead of diagnosing the root cause; or
  "fixing" a failure by masking it (skip/delete the test, widen the timeout, swallow the
  error).
- Stack rules hardcoded as copy-paste from another project (mismatch with the repo's
  actual manifests).
- **Response-shape rules that contradict each other** — e.g. "restate the state every
  turn" alongside "never recap" with no stated distinction, or an always-on marker (an
  AI canary) mandated in one rule and banned by a "no preamble" rule. A shape rule that
  can't be followed without breaking another is worse than none.
- Sub-agents spawned with generic, duplicated, or task-echoing labels (`agent-1`,
  `task`, `subagent`) in a file that mandates parallel fan-out — the run can't be
  observed, stopped, or attributed from the agent list.
- **(User-level file)** hardcodes a single project's stack, tracker, commands, or
  absolute paths — it pollutes every other repo's session; those belong in that repo's
  own file.

## D. Scoring rubric (per dimension, 0–5)

Score each, then roll up. **0** absent · **1** mentioned only · **2** partial/vague ·
**3** present & adequate · **4** specific & verifiable · **5** specific, verifiable,
and well-scoped (right mechanism, right length).

**Apply the "Scope" section first.** For a **user-level** file, mark the repo-only
dimensions **N/A** (don't score them 0) and add the user-level extra checks; for a
**repo-level** file, score the full set. Roll up over the **applicable** dimensions
only, and assess the file on its own — never by comparison to another `CLAUDE.md`.

1. **Hygiene & form** — concise, imperative, specific, scannable, ≤~200 lines, no
   contradictions, references not duplicates (consensus baseline, §A).
2. **Verification & quality gates** (§B3) — *weighted highest;* includes root-cause
   discipline on repeated failure (no blind-retry, no symptom-masking).
3. **Git/GitHub & merge guardrails** (§B7).
4. **Change philosophy & effort economy** (§B1–B2).
5. **Communication & directness** (§B4–B6) — includes a declared **response shape**
   (action first, numbered steps, one concrete next step, no preamble/recap) whose
   rules don't contradict one another.
6. **Multi-agent safety** (§B9) — *N/A if the project never uses parallel sub-agents;
   mark N/A rather than 0* — includes **descriptive sub-agent naming** so a fan-out is
   observable from the agent list/graph.
7. **Source-of-truth, deferral & agent-safe tagging** (§B10).
8. **Doc maintenance & governance** (§B11).
9. **Stack/architecture enforcement specificity** (§B12).
10. **Code-quality & design standards** (§B13) — paradigm declared, clean-code rules
    verifiable, TDD workflow, code-smell vigilance.

For every dimension under 3, the report must give a **concrete fix** and, where
useful, a **suggested rewrite snippet** the user could paste in.
