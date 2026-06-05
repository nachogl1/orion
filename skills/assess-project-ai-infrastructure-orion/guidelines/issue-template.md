# Orion guidelines — Issue / ticket template

The orion layer for assessing (or recommending) a repository's **issue/ticket body
template** — `ISSUE_TEMPLATE.md`, `.github/ISSUE_TEMPLATE/*.md` or `*.yml`
(GitHub issue forms), or the equivalent template in whatever tracker the project uses
(Jira request types, GitLab description templates, …). Pair with the consensus
baseline in [`consensus-resources.md`](consensus-resources.md) (section 4).

> **Guidelines, not a template.** Like the PR-template assessor, this skill does
> **not** drop an issue template into the target repo. It assesses an existing one —
> or, if none exists, recommends one and offers a *generated* draft built from the
> repo's own conventions, **in the report**. The sections below are the rubric.

The tension mirrors the PR template: an issue template must be **short enough that
people actually fill it in**, yet **structured enough that the resulting ticket is
workable** — and, for repos worked by agents, **clear enough that an agent knows
whether it may take the ticket autonomously.**

---

## A. Consensus baseline

- A clear **title convention** and a **what / why** statement (problem or goal, not
  just a symptom).
- For bugs: **steps to reproduce, expected vs actual, environment.**
- For features: **the outcome wanted** and **acceptance criteria.**
- **Right-sized** — enough structure to be actionable, not so much it's abandoned;
  separate templates per type (bug / feature / chore) where the tracker supports it.
- Labels / type / area so the ticket routes correctly.

## B. Orion layer — the sections that make a ticket workable (and agent-takeable)

### B1. Agent-ready marker — **autonomous vs needs-human-decision**  ← (headline orion rule)
This is the highest-value orion-specific field. **Every issue declares its decision
posture** so an autonomous agent picking it up knows whether it may proceed:

- **🤖 Agent-ready (autonomous)** — an agent can complete it end-to-end without a
  human judgement call. Scope, acceptance criteria, and the "right" approach are
  derivable from the ticket + repo.
- **🧑 Needs human decision / action** — completing it correctly requires a human to
  **decide** something (ambiguous product/UX behaviour, security/privacy trade-off,
  irreversible data call) **or take an action the agent can't** (provision access, a
  business sign-off). The agent **stops and asks** on these rather than guessing.
- **Carry the question with the flag.** A needs-human ticket states *what* decision is
  needed and *what* the options are, so it can be resolved in one pass — and once
  resolved, the answer is written back onto the ticket and it becomes agent-ready.
- **Apply narrowly.** Reserve the needs-human flag for genuine judgement/action calls;
  don't flag work an agent can reasonably infer or look up — over-flagging drags a
  human into routine work and defeats the purpose.
- **Mechanism is project-specific** — a checkbox, a label
  (`agent-ready` / `needs-human-decision`), or a required heading. The assessor checks
  that *some* explicit, consistent mechanism exists. (Mirrors
  [`contributing-and-governance.md`](contributing-and-governance.md) §B4 and the PR
  template's decision-posture surfacing in [`pr-template.md`](pr-template.md) §B9.)

### B2. Outcome & acceptance criteria
- The ticket states the **outcome** (what's true when it's done), with
  **Given/When/Then** acceptance criteria where it fits — the same criteria the PR's
  manual-verification step checks against.

### B3. Context & scope boundary
- Enough context to start without a back-and-forth (links to the relevant area, prior
  tickets, designs/specs), and an explicit **out-of-scope / non-goals** line so the
  work doesn't sprawl. Deferred sub-items get their own linked ticket, not buried prose.

### B4. Work-item / requirement linkage
- If the project tracks epics/stories/requirements, the template prompts for the
  parent link (Epic N / Story X.Y / FR-NFR refs). **Detect the project's tracking
  vocabulary at run time** — don't assume any scheme. N/A if the project has no such
  layer.

### B5. Reproduction / evidence (bug path)
- Bug template prompts for **steps, expected vs actual, environment/version, and
  logs/screenshots** — enough that the bug can be reproduced, not just believed.

### B6. Type / priority / area routing
- Type (bug/feature/chore/spike), area/component, and priority or size, matched to the
  labels the project actually uses — so triage and agent-batching can filter on them.

---

## C. Smells to flag

- **No issue template** in a repo that takes contributions or is worked by agents.
- **No agent-ready / needs-human marker** in a repo worked by agents — agents either
  block on everything or silently guess on risky tickets (§B1).
- A `needs-human-decision` ticket that **doesn't say what the decision is** — the human
  can't resolve it in one pass.
- **Over-flagging** — routine, inferable work marked needs-human, so the convention
  becomes noise.
- Bug template with no reproduction/expected-vs-actual; feature template with no
  acceptance criteria.
- A template so long it's abandoned, or one giant template for every issue type when
  the tracker supports several.
- Leaked specifics (internal URLs, person/team identifiers) baked into a public
  template.

## D. Scoring rubric (per dimension, 0–5; N/A where a section legitimately doesn't
apply to this project)

1. **Exists & is right-sized** — present, per-type where supported, short enough to use
   (§A).
2. **Agent-ready / needs-human-decision marker** (§B1) — *weighted highest for
   agent-worked repos; N/A if the repo is never worked by agents.*
3. **Outcome & acceptance criteria** (§B2).
4. **Context & explicit scope boundary** (§B3).
5. **Work-item / requirement linkage** (§B4) — N/A if the project has no such layer.
6. **Reproduction / evidence on the bug path** (§B5) — N/A if there's no bug template
   path.
7. **Type / priority / area routing** (§B6).

For every dimension under 3 (and not N/A), give a concrete recommendation and a
suggested snippet. When a repo lacks an issue template, **generate the draft from this
rubric + the repo's detected conventions** (including the agent-ready marker) and
include it **in the report** — the skill never writes it into the repo.
