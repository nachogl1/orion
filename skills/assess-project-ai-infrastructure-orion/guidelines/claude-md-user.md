# Orion guidelines — **user-level** `CLAUDE.md`

The orion layer for assessing a **user-level** agent-instruction file:
`~/.claude/CLAUDE.md`, `~/.claude/CLAUDE.local.md`, `~/.claude/rules/*.md`.
For a project's own file use [`claude-md-repo.md`](claude-md-repo.md); the scope
router is [`claude-md.md`](claude-md.md). Pair this with the consensus baseline in
[`consensus-resources.md`](consensus-resources.md) (section 1), and cross-reference
[`claude-setup-audit.md`](claude-setup-audit.md), which audits this file as part of
the whole `~/.claude/` setup.

These guidelines are **distilled and generalized** from real files. They describe
*behaviours a good user-level file establishes* — the assessor checks whether the file
covers each area appropriately **for this user**, not whether it copies this wording.

---

## What a user-level file is for

It loads into **every session on every repo**. Its job is the user's **cross-project**
preferences: how to communicate, candor, verification posture, generic git/PR
conventions, effort economy, multi-agent safety. Two consequences drive the whole
rubric:

1. **Every line is paid for everywhere.** Leanness is weighted higher here than at repo
   scope — a wasted line costs on every prompt of every project.
2. **Anything project-specific here pollutes every other project.** A stack rule, one
   repo's tracker, one team's naming table, an absolute path — each is a **smell**, not
   a feature. It belongs in that repo's own file.

**Assessment rules:**

- **Assess this file on its own.** Never compare it to a repo's `CLAUDE.md`, and never
  mark a rule "missing" when that rule correctly lives at **repo** scope (stack rules,
  build/test commands, a named tracker, branch tables keyed to an issue ID). Those
  dimensions are **not scored here** — they are absent from this rubric by design.
- **Repo-specific content found here is scored *down* (dimension 1), not up.**

---

## A. Consensus baseline (must hold before orion specifics)

Fail these and the rest barely matters:

- **Concise & signal-dense**, imperative voice, **specific & verifiable** rules,
  scannable structure, no internal contradictions, **~≤200 lines**
  (`consensus-resources.md` §1 — the cap applies in full at user scope; the orion layer
  does *not* relax it here, because this file loads everywhere).
- Uses the correct mechanism for the job: durable behavioural rules in `CLAUDE.md`,
  per-area rules in `~/.claude/rules/` (path-scoped), **hard enforcement in hooks**
  (not prose), repeatable procedures in **skills**.
- Past the budget, the fix is path-scoped rules or a skill — never a longer root file.
  Length spent on rules is earned; length spent on prose is sprawl at any count.

## B. Orion layer — areas a strong user-level file establishes

For each, the assessor notes **present / partial / absent** and whether it's concrete
enough to act on.

### U1. Scope purity & token economy
- **No machine-specific values** — absolute user paths, home-folder names, machine
  names, secrets. Use home-relative (`~/.claude`, `~/Downloads`) forms.
- **No single project's specifics** — stack rules, one repo's tracker/commands, one
  team's naming table, one product's domain vocabulary.
- **Token economy** — it loads on every prompt everywhere; keep it lean. Rules that
  apply to one repo in ten do not belong here.

### U2. Verification posture (generic — no project commands)
- **Code analysis is not verification** — run the real test/build/workflow.
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
- The *commands* stay at repo scope — this file states the **posture**, not `npm test`.

### U3. Git & merge guardrails (generic)
- **Never commit directly to the default branch**; work goes on a feature branch + PR.
- A generic branch-name format (e.g. `feat/<desc>`, `fix/<desc>`) — the tracker-ID
  variant belongs at repo scope.
- **Conventional Commits** (`type(scope): summary`) as the default message format.
- No force-push, no hook bypass (`--no-verify`, `--no-gpg-sign`), no disabling
  safeguards on protected branches.
- **Surface CI failures**; don't auto-fix-and-re-push without approval; never merge on
  red or still-pending checks.
- **Never auto-merge** — the agent may open, describe, and suggest reviewers for a PR,
  but the **merge decision belongs to a human.**
- Don't run destructive/irreversible operations without confirming; prefer a
  dry-run/preview first.

### U4. Change philosophy & effort economy
- **"Smallest change that works"** — do what was asked, follow existing patterns, **no
  unrequested refactors or speculative abstractions.**
- A default reasoning-effort posture, with explicit "escalate only when stuck."
- **Sub-agent model tiering** — cheap model for simple/mechanical work, top model
  reserved for hard decisions — and a **cap on parallel sub-agents** to avoid rate
  limits.
- **Cap sub-agent *output* in the spawn prompt** — each sub-agent returns a bounded
  result (e.g. *"a verdict + 5 bullets max"*, or a fixed schema), never a free-form
  essay. Uncapped output floods the orchestrator's context and can kill the turn.

### U5. Communication, tone & response shape
This is **prime user-level material** — the single strongest reason to keep a user file
at all, and it costs almost nothing to carry.

- **Summarize and use clear language by default; let the user ask for more detail.**
  Lead with the outcome and the decision, not a blow-by-blow.
- **Functional / business-first explanations** when the reader is unfamiliar with the
  code — explain *what it does for the user* before implementation detail.
- **Plain-language onboarding tone** — an explicit audience/altitude for explanations
  (e.g. *"explain it like I don't know this tech stack or domain"*), rather than leaving
  tone to chance.
- **Emit reports/docs as files**, not inline walls of text, unless inline is asked for.
- **Never guess or fabricate.** Check the *actual* state (code, docs, command output)
  before asserting it; anything unverified is labelled an assumption, not stated as fact.
- **A declared *response shape*, not just a tone.** Tone says how an answer *sounds*; a
  shape fixes the *form* every answer takes, so the reader never hunts for the point.
  The exact list matters less than that it is stated and checkable:
  - **Action first** — the opening line is the next action or what changed; no warm-up,
    no restatement of the question.
  - **TLDR and one-liners by default** — every point lands as a single plain line; depth
    is deferred until asked for. This governs density, **not substance**: a fact or
    caveat is compressed into a one-liner, never dropped.
  - **Numbered steps** for anything multi-step — one action per line, in order.
  - **Exactly one concrete next step** to close — not a menu, not an open offer to help.
  - **Tangents suppressed** — cut, or parked in one labelled line at the very end.
  - **A one-line state restatement each turn** — done / in progress / blocked and on
    whom. This is *current status*; the file should explicitly distinguish it from a
    recap of already-reported work so it doesn't collide with "no recap".
  - **Concrete time/effort estimates** ("~15 min", "3 commands") instead of "a bit" —
    and, per the no-guessing rule, an explicit *"can't estimate without X"* rather than
    an invented number.
  - **Wins stated plainly and concretely** ("suite green, 42/42") — about the work,
    never flattery of the user (§U6).
  - **Errors reported matter-of-factly** — what broke, why, and the fix; no apologising,
    no self-criticism, no dwelling.
  - **No preamble, no recap, no sign-off.** If the file also mandates an always-on
    marker (an AI canary, below), it must **explicitly exempt** it here — otherwise the
    two rules contradict, which is a §C smell.

  In reality these are **ADHD-support pillars**: answer-first ordering, one idea per
  line, TLDR with detail on demand, visible state, a single next step, no prose walls —
  the structure that keeps a reply followable for a reader who struggles to sustain
  focus. A file that makes the framing explicit (*"talk to me like I have ADHD and
  struggle to focus — these rules are the support pillars"*) is a positive signal that
  the shape is deliberate; its absence is never penalized.
- **An instruction-adherence canary ("AI canary").** A cheap, always-visible marker
  proving the file is still being applied — e.g. every response opens with a fixed
  token. If it disappears, the user knows the instructions dropped out of context.
  Optional: note its presence as a positive signal; don't penalize its absence.

### U6. Directness & discuss-before-doing
- **Radical Candor — care personally *and* challenge directly.** No flattery, no
  agreement-for-its-own-sake; **say the hard thing**. Challenging without care reads as
  obnoxious aggression; caring without challenge collapses into **ruinous empathy** —
  withholding a real objection to avoid friction, which is exactly the sycophancy this
  dimension exists to prevent.
- **Disagree explicitly before executing** when a plan is flawed ("that breaks X because
  Y"), but don't argue for argument's sake and stop relitigating settled decisions.
  Treat the user as a **peer, not a principal.**
- The file should establish **both**: permission to challenge, *and* the expectation
  that challenges are specific and constructive rather than merely blunt.
- **Discuss before doing** — while the user is exploring or asking for an opinion, give
  the opinion or the trade-offs; **don't edit files or run tools until an explicit
  "go."** If permission is unclear, ask rather than assume.

### U7. Multi-agent safety (when the user runs parallel sub-agents)
*N/A if the user never fans out; mark N/A rather than 0.*
- **No `git stash`** in a sub-agent (it corrupts the parent's working tree) — isolate in
  a **worktree** instead.
- **No branch switching** in a sub-agent.
- **Scope commits tightly** — each sub-agent commits only the files it touched; **never
  `git add -A`** in a multi-agent context.
- **Fail clean** — a failing sub-agent reports and stops; it doesn't attempt its own
  recovery.
- **Name every sub-agent for the human watching** — a title saying *what that agent is
  doing* (`review-auth-tests`, not `agent-3`, not an echo of the parent task). The agent
  list is the operator's only window into a fan-out: with generic labels they can't tell
  which agent to stop, inspect, or blame. That's a safety problem, not a cosmetic one.
  Pairs with the output cap in §U4.

### U8. Deferral discipline (generic — no named tracker)
- **Only file a ticket when the work genuinely needs one.** A deferral is not an
  automatic ticket: real, actionable, and worth someone's time later → file it; small
  enough to just do → do it; noise → drop it and say so. Filing "to be safe" grows a
  backlog nobody drains.
- **Dedupe before filing** — check existing open items *and* the code before proposing a
  new one.
- **Every surviving deferral carries an anchor** — any "out of scope / follow-up /
  deferred" note names a tracker item on the same line. Recurring pre-existing failures
  get **one umbrella item**, referenced everywhere, never re-described as fresh prose.
- **Never defer to a closed item** — verify it's open before pointing at it as the
  reason to skip work.
- *Which* tracker is repo-scope information; the discipline is generic and belongs here.

### U9. Global code-quality default *(optional — N/A if left to each repo)*
- A **declared default design paradigm** the agent falls back to when a repo says
  nothing — in whatever terms the user actually works in. Scored on being *declared*,
  never against an orion-preferred paradigm.
- **Clean-code expectations made concrete** — intention-revealing names, small
  single-purpose units, no dead or commented-out code, no magic values — as verifiable
  rules, not "write good code".
- **A default testing workflow** (e.g. TDD: a failing test first, red → green → refactor;
  a bug fix starts with a regression test).
- A user who deliberately leaves all of this to each repo is **N/A here, not 0** — but
  the fallback is then "whatever the agent improvises", which is worth saying out loud.

### U10. Enforcement wiring — a hard rule needs a mechanism, not just prose
A `CLAUDE.md` is a *prompt*, and a prompt is the weakest form of enforcement: it degrades
as context fills, and nothing fails loudly when it is ignored. For every rule this file
states as **hard**, the assessor asks *what actually stops it happening*:

- **The mechanism at user scope is `~/.claude/settings.json` hooks** (plus global git
  hooks / a `core.hooksPath` template if the user has one) — cross-reference
  [`claude-setup-audit.md`](claude-setup-audit.md).
- **Score the fraction of hard rules with real backing**, not the number of hooks. Ten
  hooks enforcing none of the file's stated rules is not a 5.
- **List every prose-only hard rule as a hook candidate**, each with the concrete
  mechanism to add — that list *is* the recommendation for this dimension.
- **Never credit enforcement that isn't there.** A file claiming "the pre-commit hook
  blocks X" with no such hook is worse than silence: it teaches the agent a false safety
  net. Flag the mismatch.
- Soft rules (tone, response shape, change philosophy) are **out of scope here** — they
  can't be mechanised and are scored under §U4–U6.

---

## C. Smells to flag (user scope)

- **Any single project's specifics** — stack rules, one repo's tracker or commands, one
  team's naming table. It pollutes every other repo's session.
- **Machine-specific values** — absolute user paths, home-folder names, secrets.
- Sprawl past ~200 lines; long prose paragraphs instead of rules at any length.
- Vague rules ("write good code", "test properly") that can't be verified.
- Contradictions between the root file and `~/.claude/rules/*`.
- **Response-shape rules that contradict each other** — e.g. "restate the state every
  turn" alongside "never recap" with no stated distinction, or an always-on marker (an
  AI canary) mandated in one rule and banned by a "no preamble" rule. A shape rule that
  can't be followed without breaking another is worse than none.
- "Enforcement" written as prose that should be a **hook** — note it as a hook candidate
  (§U10).
- **Enforcement claimed but absent** — the file names a hook that doesn't exist in
  `~/.claude/settings.json`. A false safety net is worse than no claim.
- No verification posture; no git guardrails.
- Sub-agents spawned with generic, duplicated, or task-echoing labels (`agent-1`, `task`)
  in a file that mandates parallel fan-out — the run can't be observed or attributed.

## D. Scoring rubric (per dimension, 0–5)

**0** absent · **1** mentioned only · **2** partial/vague · **3** present & adequate ·
**4** specific & verifiable · **5** specific, verifiable, and well-scoped (right
mechanism, right length).

1. **Hygiene, leanness & scope purity** (§A, §U1) — concise, imperative, specific,
   scannable, ~≤200 lines, no contradictions, **and free of project- or
   machine-specific content**. *Leanness weighs harder here than at repo scope.*
2. **Verification posture** (§U2) — *weight 2;* includes root-cause discipline on
   repeated failure (no blind-retry, no symptom-masking).
3. **Git & merge guardrails** (§U3).
4. **Change philosophy & effort economy** (§U4) — includes sub-agent tiering, a
   parallel cap, and bounded sub-agent output.
5. **Communication, tone & response shape** (§U5) — includes a declared response shape
   whose rules don't contradict one another.
6. **Directness & discuss-before-doing** (§U6).
7. **Multi-agent safety** (§U7) — *N/A if the user never runs parallel sub-agents; mark
   N/A rather than 0* — includes descriptive sub-agent naming.
8. **Deferral discipline** (§U8).
9. **Global code-quality default** (§U9) — *N/A if the user deliberately leaves this to
   each repo.*
10. **Enforcement wiring** (§U10) — *weight 2;* hard rules backed by `~/.claude`
    hooks rather than prose alone, and the file names the mechanism.

**Roll-up = weighted mean over the applicable dimensions.** Weight **2** on dimension 2
(Verification posture) and dimension 10 (Enforcement wiring); weight **1** on every
other. An **N/A** dimension drops out of *both* numerator and divisor — it is never a 0.
Worked example: dimensions 2 and 10 scored 4 and 2, six other applicable dimensions
averaging 4 → (4×2 + 2×2 + 4×6) ÷ (2 + 2 + 6) = 3.6.

For every dimension under 3, the report must give a **concrete fix** and, where useful,
a **suggested rewrite snippet** the user could paste in.
