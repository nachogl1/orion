# Orion guidelines — Contributing & governance docs

The orion layer for the docs that tell people (and agents) **how work flows through
the project**: `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, CI/test docs,
a troubleshooting/runbook, an ADR index, and a decision log. Pair with the consensus
baseline in [`consensus-resources.md`](consensus-resources.md) (sections 3 & 5).

The assessor evaluates whatever of these exist, **and flags the high-value ones that
are missing** — it does not demand every file in every repo (a tiny solo repo needs
less than a multi-team one). Judge proportionally to the project.

---

## A. Consensus baseline

- Concrete steps for **filing a good issue** and **opening a good PR** (not "be nice").
- Branch / commit / review conventions, and **what CI gates**.
- How to set up the dev environment and run the tests.
- Behavioural expectations — link a **code of conduct**.
- A **security** contact / disclosure path if the project warrants one.
- Pointers to deeper docs (architecture, ADRs, runbook).

## B. Orion layer

### B1. Branch, commit & PR conventions are written down
- The branch-naming format (e.g. `<action>/(#<id>)-<desc>`), the commit convention
  (e.g. Conventional Commits if used), and the PR expectations live here or are
  linked. These should **match** what the CLAUDE.md tells the agent (see
  [`claude-md.md`](claude-md.md) §B8) — flag drift between human docs and agent rules.
  The **issue and PR templates** encode these conventions at filing time (see
  [`issue-template.md`](issue-template.md) and [`pr-template.md`](pr-template.md)).

### B2. Merge & protection rules are explicit
- Never commit to the default branch; **a human owns the merge decision**; protected
  branches and required checks are documented. (Mirrors CLAUDE.md §B7.)
- **Required CI must be green before a merge**, and the **merge strategy is stated**
  (a **squash merge** to keep the default branch linear is the common orion default) —
  so contributors and agents land changes the same way and nothing merges on red or
  pending CI.

### B3. Deferral & follow-up discipline
- The contribution rules state that **out-of-scope / follow-up items must be tracked
  and linked** (a real issue, filed first), and that recurring pre-existing failures
  get **one umbrella issue** referenced everywhere — not re-described each time.
  (Mirrors CLAUDE.md §B10; the PR template enforces it per-PR — see
  [`pr-template.md`](pr-template.md).)

### B4. Agent-safe vs. needs-human-decision issue tagging  ← (collected guideline)
This is a first-class governance rule for repos worked by both humans and agents.

- **Every issue / story declares its decision posture:** either
  - **agent-safe** — an autonomous agent can complete it end-to-end without a human
    judgement call; or
  - **needs-human-decision** — completing it correctly requires a human to validate
    something or answer a question first.
- **When an agent picks up a `needs-human-decision` item, it stops and asks** the
  human to validate / decide before proceeding — rather than guessing and
  potentially committing the wrong call.
- **Apply the flag narrowly.** Reserve `needs-human-decision` for genuine judgement
  calls: ambiguous product/UX behaviour, security or privacy trade-offs, irreversible
  data decisions, anything where being wrong is costly and the "right" answer isn't
  derivable from the repo. **Do not** flag work the agent can reasonably infer,
  look up, or determine itself — over-flagging defeats the purpose by dragging a human
  into routine work.
- **Carry the question with the flag.** A `needs-human-decision` issue should state
  *what* decision is needed and *what* options exist, so the human can answer in one
  pass instead of a back-and-forth.
- **Mechanism is project-specific** — a label (`needs-human-decision` / `agent-safe`),
  a checkbox in the issue template, or a heading in the issue body. The assessor
  checks that *some* explicit, consistent mechanism exists, not which one.

> Why it matters: it lets autonomous/batch agent pipelines run unattended on the safe
> work while cleanly **halting and escalating** exactly the items that need a person —
> instead of either blocking on everything or silently guessing on the risky ones.

### B5. Source of truth & status
- A single named **source of truth for project status** (typically the issue tracker)
  and the rule to comment progress at milestones (start / in-review / merged).
  Conflicting status systems (e.g. tracker *and* a stale status file) is a smell.
- **If the project has no tracker at all** — no GitHub/GitLab Issues, no Jira, status
  scattered across a README checklist, TODO comments, or a chat thread — that's a
  finding, not an N/A. **Recommend adopting a single tracker as the source of truth;**
  for a repo already hosted on GitHub, **propose GitHub Issues** (zero extra infra,
  native PR/`Closes #N` linking, label-based agent-ready tagging per §B4). For another
  host, propose its native tracker. The point is *one* named home for status that
  issues, PRs, and agents all reference.

### B6. Decision records & doc-maintenance
- A **decision log** and/or **ADR** convention with an **index**, and the
  change-X → update-doc-Y expectation (mirrors CLAUDE.md §B11).
- **Governed documents** require explicit human approval to change.

### B7. Multi-agent / parallel-work hygiene
- If the project runs parallel agents/worktrees, the contributor docs (or CLAUDE.md)
  spell out the worktree/branch isolation rules (no stash, no branch-switching,
  tightly-scoped commits — mirrors CLAUDE.md §B9).

---

## C. Smells to flag

- A `CONTRIBUTING` that's all etiquette and no *mechanics* (no branch/test/PR steps).
- Human contribution rules that contradict the agent's CLAUDE.md rules.
- No code of conduct / no security path on a project that clearly needs one.
- Two competing "sources of truth" for status.
- Issue/PR process described but **no agent-safe / needs-human convention** in a repo
  that is worked by agents.
- ADRs/decision log mentioned but no index, or stale and abandoned.
- Internal team names, private URLs, or person identifiers leaked into a public
  CONTRIBUTING.

## D. Scoring rubric (per dimension, 0–5; mark N/A where a file legitimately isn't
needed for this project's size)

1. **Issue & PR mechanics** — concrete steps to file/contribute (§A).
2. **Branch/commit/review conventions written & consistent** with CLAUDE.md (§B1).
3. **Merge & protection rules explicit** (§B2).
4. **Deferral / follow-up discipline** (§B3).
5. **Agent-safe vs. needs-human-decision tagging** (§B4).
6. **Source of truth & status** single and clear (§B5).
7. **Decision records & doc-maintenance** (§B6).
8. **Code of conduct / security path** present where warranted (§A).
9. **Multi-agent hygiene** documented where relevant (§B7) — N/A otherwise.

For every dimension under 3 (and not N/A), give a concrete fix and a suggested
snippet where useful.
