@.claude/orion/ORION.md

# CLAUDE.md — <project name>

This file is configuration. Changing a rule is a pull request with a reason.

> Every `<angle-bracket>` value is a slot the project fills in. A bullet the project has no use for is deleted.
> The first line imports the rules orion ships (`.claude/orion/ORION.md`, refreshed by `orion update`); everything
> below is the project's own. **The two must never contradict each other**: check a new or changed rule here against
> the orion rules first, and after an `orion update` that changed them, re-read this file for conflicts and fix them in
> the same commit. If a contradiction slips through, this file wins — a safety net, not a licence to override.

## 1 · Work tracking

- **<tracker> is the only source of truth.** PRD → epic → story. Agents implement **stories** only, never an epic.
- **The assignee owns the issue.** Assign yourself *before* writing any code. Never work on, edit or unassign someone
  else's. Two claims can land in the same second, so re-read after claiming: a second assignee, or an earlier
  "claimed by run …" comment from another run, means the earlier claim wins. The later run deletes its claim comment,
  drops its in-flight entry, unassigns itself only when the other assignee is a different login (two of your own
  terminals share one assignee, which stays), and takes the next issue.
- **Blocked means blocked in either place.** An issue waits until every blocker is CLOSED — not "nearly done" —
  whether listed under a `### Blocked by` heading in the body or set as the tracker's native blocking relation.
  Whoever writes a ticket sets **both**: the native relation for people, the body section for agents.
- **Epic → story is the tracker's native parent/child link**, never a plain text list.
- **Every story names the folder or module it owns** under `### Seam`, so two stories on one folder are spotted
  before they collide (merged into one, or one blocks the other).
- **Every new issue, whoever files it, follows `.claude/skills/dev-next/references/new-issue.md`**: body headings,
  labels, the native parent and blocking links with their read-back checks. A person starts from the tracker's story
  template, which pre-fills the same shape.
- **An issue filed while working on another is tied to where it came from**: the pull request in hand links the new
  issue, and the new issue names that pull request (or the issue, if no pull request is open yet) under
  `### PRD references`.
- The one sanctioned read: `<the tracker command that returns title, body, labels and comments>`. Shorter forms drop
  the body.
- Labels: `epic` `story` `agent-ready` `needs-human` `in-progress` `outside-change` `bug`, plus the `wayfinder:*` set
  the planning skill owns.
  - `agent-ready`: nothing is left to ask. An agent claims it, builds it, gets a fresh-agent review and merges with no
    human. **An issue with none of `agent-ready`, `needs-human` or `outside-change` is not taken automatically**:
    `/dev-next` stops in preflight and asks the human what it is. A label given then earns one ready-check before
    building.
  - `needs-human`: a person must act or decide first, then flips it to `agent-ready` — or the ticket is human-only
    work for good. The reason is the issue's **last comment**. Labelling `needs-human` removes `agent-ready`; the two
    never sit together.
  - **`outside-change`: the work touches a repository this team does not own. It never runs autonomously and always
    ends at a pull request for that repository's own reviewer** (§2). It always also carries `needs-human`, so one
    filter catches every issue an agent must not take. The issue names the external work item under
    `### External reference` (<the other team's key format>), and the pull request title carries it.

## 2 · Standing decisions — never ask about these

**The PRD is the north star for what we build.** Every product fact — vocabulary, scope, the do-not-build list, the
acceptance bar, the build decisions — is read from `docs/PRDs/PRD.md` (every PRD under `docs/PRDs/`, if more than
one), never restated here. Until PRD v1 exists the pre-PRDs there stand in. **Disagreement is a bug**: the PRD wins
on product, this file wins on process.

- **Every big change gets its own PRD first**, at `docs/PRDs/PRD<SummaryName>.md`, before any ticket or code for it
  exists. Small fixes and tweaks need none.
- **No real production data in this repository.** <Name the sensitive data classes: customer records, partner-owned
  schemas, corpus extracts, database dumps.> Synthetic or de-identified fixtures only. **No personal data anywhere**
  — not in prompts, logs, tests, fixtures, issues or git history — and never run anything against production.
- **Secrets only in `.env`** (gitignored; `.env.example` lists the names). Never in code, issues, pull requests or
  committed files. A committed secret is rotated by its owner, not just deleted: git history keeps it.
- <**Any boundary an agent must not move** — e.g. "AI is a build-time tool; nothing it produces executes in the
  customer's runtime." Stating it here stops an agent re-deciding it.>
- **<External repository> is read-only from here.** Never build it, run it, commit to it or change its git state.
  A change that must land there is an `outside-change` issue: it stops at a pull request its own reviewer merges.
- **The model provider sits behind one swappable interface.** Tests never reach the network; a test that needs the
  model mocks the interface. No API key is ever committed or written into an issue.
- **The project deploys to one place only: <environment>, from `main`.** No other hosting unless the PRD names it.
- **No meeting recordings, transcripts or notes exports in this repository, ever** — they carry personal data. What a
  meeting decided goes onto the ticket it concerns, as a comment in the participant's own words.
- **Code, comments, commits, issues and docs in <language>.**
- **Front-end development is led by the UX designs in `docs/ux/`.** A story that adds or changes a screen implements
  the prototype's screen, never a layout of its own; a screen the prototype lacks is a UX change first (pull request
  on `docs/ux/`), then a story. The user provides the designs before the first PRD is split into tickets.
- **Take every reversible decision yourself** — simplest option that meets the acceptance criteria, recorded in the
  pull request. Only a genuinely irreversible one becomes `needs-human`. A run that waits costs money doing nothing.
- **Stay on the issue you claimed.** No refactor of code the issue does not touch, no speculative abstraction.
  Anything else you notice goes to the run's audit report (§6). A side-fix belongs in the pull request only if it is
  small, safe **and** in a file you are already changing.
- **Two sources of truth, kept in step.** Issues track the work; the PRD holds the product. In a session with a person
  present — planning, harvest, hand-written tickets — after the batch of ticket creations or edits ask once:
  **"Should we update the PRD with this too?"**, one line per change naming the PRD section it touches. "No" ends it;
  "yes" ships the PRD edit in the pull request the work already has, or in a `docs(prd)` pull request when the work
  was only tickets. The dev skill's mechanical writes — labels, claim comments, `## Decisions (agent-ready)`,
  `Critical:` issues, closing — never trigger the question.

## 3 · Git

- **NEVER push to `main`.** Not a fix, not a typo, not "only a doc". Every change reaches `main` as a merged pull
  request. <If branch protection is off:> Nothing enforces this; it holds because you do.
- **Who merges.** Only `/dev-next` merges its own pull requests, and only once §5 is filled in. Every other pull
  request — planning, scaffolding, documentation, anything outside the dev skill — is merged by a human.
- **Squash-merge only, then delete the branch** (`--delete-branch` breaks on a worktree; see
  `.claude/skills/dev-next/references/merge-and-ci.md`). One commit on `main` per pull request.
- **Work in a worktree on `feature/<slug>`** (`feature/<issue>-<slug>` when the branch serves one issue). A pull
  request may cover one issue or several related ones. Never work in the main checkout. **One exemption:** the
  per-developer branch `audit/<login>` that `/dev-next` writes run reports to is pushed directly, has no pull request
  and never merges into `main` (`.claude/skills/dev-next/references/audit.md`).
- Worktrees live **outside the project**: `<worktree root>`. The in-flight file (`<worktree root>/in-flight.json`,
  never committed) lives beside them; format in `.claude/skills/dev-next/references/in-flight.md`.
- Update a branch with `git merge origin/main` — **never rebase, never stash**.

## 4 · Definition of done

- **Full build and full suite green before the pull request opens.** Every new behaviour has a test.
- **The skip count is baselined; a change to it fails.**
- <**If the project produces generated output:** it is gated by evaluation, not by a passing build. Name the
  deterministic checks that must be green on every artefact, the evaluation harness, the file holding its baselined
  pass-rate threshold, and any record every artefact must carry. A run that cannot execute the evaluation is **red**,
  never "not applicable".>
- The pull request body carries the **evidence table** — what you did, what you expected, what you saw. A green suite
  alone is *not* evidence that the output works for its user.
- A **fresh agent** reviews every pull request — never the one that wrote the code.
- **The suite runs once per gate, never twice.** If CI runs the full suite, its result is the evidence: on the pull
  request for the reviewer, on the merged branch for the merge. If not, the reviewer runs it in the worktree and the
  merge runs it on the merged branch. Never both.
- **Never merge on red or pending.** "No checks reported" is red. Poll for the check run first: the host can take minutes.
- **A story that changes user-visible behaviour updates the run-book** (`docs/runbook.md`) in the same pull request.

## 5 · Build and test commands

Written down because there is nothing to auto-detect. Every agent uses exactly these. A row still reading `TBD`
means the stack decision has not landed and `/dev-next` cannot run.

| Purpose | Command |
|---|---|
| Build | `TBD` |
| **The full suite** | `TBD` |
| One file | `TBD` |
| One test | `TBD` |
| Typecheck / static analysis | `TBD` |
| Lint | `TBD` |
| Deterministic checks on generated output (if any) | `TBD` |
| Dev server (if the review surface needs one) | `TBD` |

**The gate, before any pull request opens:** build → lint → typecheck → full suite (the same chain as CI).

- **Layout:** `<application code path>` and `<test code path>`; a story adds its code and its tests under the
  matching area.
- **Skip-count baseline: <N>.** Any other number fails the gate.
- Stack: **<language and version, pinned in <pin file>>**, **<test framework>**; every machine runs the same versions.
- **Per worktree:** everything an issue needs lives inside its own worktree; tests run on synthetic fixtures.
  **Port = `<base port> + issue number`**, written into the worktree's `.env` as `<port variable>`, so agents run in
  parallel without colliding.
- Secrets in a gitignored `.env` beside a committed `.env.example`. **Never commit a secret.**
- CI: one workflow, one job named `ci`, running install → lint → build → typecheck → test on every pull request and
  every push to `main`, on `<runner>`, with the pins above.

## 6 · Deferred findings and harvesting

Small, safe **and in a file you are already changing** → fix it in the same pull request. Critical → a tracker issue,
linked from the pull request. Everything else → the run's audit report. Never open an issue "to be safe"; a backlog
nobody drains is worse than no backlog.

**One pile.** Every `/dev-next` story ends with one report file for that run, pushed to `audit/<login>` — a
per-developer branch that collects reports and never merges into `main`. Each report has three lists: product
problems left for later, things that slowed the run down, and tips for the next run. Reports are named by date and
time, so they sort in order.

**Harvesting.** `/harvest` is run by a person, never by another skill. A bookmark file on `main` records, per
developer, the newest report already harvested; the harvest reads only newer reports, works through them with the
human one item at a time, then moves the mark forward and ships it in its own pull request together with any tickets
or rule edits it made. It groups items touching the same area into one ticket (the fewer the better) and drops an
item only when the human says so. `/dev-next` only counts: at **10 unharvested items** it ends its run with
`Harvest due: run /harvest`.

## 7 · Pending until PRD v1

Once `docs/PRDs/PRD.md` exists and this table is not empty, ask the human every open row as one batch (each with a
recommended answer) before any other work, apply the answers to the files named, and delete the rows in the same pull
request. A row marked parked or waiting for a named person is skipped and does not block work.

| # | File and section | Question | Decided by |
|---|---|---|---|
| P1 | `CLAUDE.md` §5 | <e.g. Which stack, and so which build/test/lint commands?> | <role> |
