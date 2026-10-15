# BASE_CLAUDE.md — mandatory rules shipped by orion

> **Owned by orion.** `orion init` copies this file to `.claude/orion/BASE_CLAUDE.md` and every `orion update`
> overwrites it there. Never edit the copy: a change to these rules is a pull request to orion.
>
> **The project's `CLAUDE.md` imports this file and adds the project's own facts and rules** (what it must state is
> listed at the end). **The two must never contradict each other**: before writing or changing a rule in the project's
> `CLAUDE.md`, check it against this file; after every `orion update` that changed this file, re-read the project's
> `CLAUDE.md` for new conflicts and fix them in the same commit. If a contradiction slips through anyway, this file wins.

## Communication

- TLDR first. One-liners. Numbered steps, one action per line. End with exactly one next action.
- Five lines max unless asked for more; several topics become one line each, never casualties.
- Never refer to a thing by its number alone — `issue #12 (parse the dataset section)`, never a bare `#12`.
- No preamble, no recap, no sign-off. Problems (bugs, risks, failures) come first and are never cut for length.
- Never guess. Check the code, the docs or the running command before stating something; label assumptions as such.
- Radical candor: care personally, challenge directly. No flattery, no sugar-coating; a bad idea is called a bad idea,
  with the reason.
- An opinion, a comparison or research asked for in chat is answered in chat. Create a file only when asked for one.

## Work tracking

- **GitHub Issues in the project's own repository are the only source of truth.** PRD → epic → story. Agents
  implement **stories** only, never an epic. (`/dev-next` and `/harvest` drive GitHub Issues and nothing else.)
- **The assignee owns the issue.** Assign yourself *before* writing any code. Never work on, edit or unassign someone
  else's. Two claims can land in the same second, so re-read after claiming: a second assignee, or an earlier
  "claimed by run …" comment from another run, means the earlier claim wins. The later run deletes its claim comment,
  drops its in-flight entry, unassigns itself only when the other assignee is a different login (two of your own
  terminals share one assignee, which stays), and takes the next issue.
- **Blocked means blocked in either place.** An issue waits until every blocker is CLOSED — not "nearly done" —
  whether listed under a `### Blocked by` heading in the body or set as GitHub's native "blocked by" relation.
  Whoever writes a ticket sets **both**: the native relation for people, the body section for agents.
- **Epic → story is a native GitHub sub-issue**, never a plain text list.
- **Every story names the folder or module it owns** under `### Seam`, so two stories on one folder are spotted
  before they collide (merged into one, or one blocks the other).
- **Every new issue, whoever files it, follows `.claude/skills/dev-next/references/new-issue.md`**: body headings,
  labels, the native parent and blocking links with their read-back checks. A person writing a ticket by hand follows
  the same file; there is no separate issue template to keep in step.
- **An issue filed while working on another is tied to where it came from**: the pull request in hand links the new
  issue, and the new issue names that pull request (or the issue, if no pull request is open yet) under
  `### PRD references`.
- **Read an issue only with `gh issue view <N> --json title,body,labels,comments`.** Shorter forms drop the body.
- Labels: `epic` `story` `agent-ready` `needs-human` `in-progress` `outside-change` `bug`, plus the `wayfinder:*` set
  the planning skill owns. `/dev-next` creates any of the seven that are missing in its preflight.
  - `agent-ready`: nothing is left to ask. An agent claims it, builds it, gets a fresh-agent review and merges with no
    human. **An issue with none of `agent-ready`, `needs-human` or `outside-change` is not taken automatically**:
    `/dev-next` stops in preflight and asks the human what it is. A label given then earns one ready-check before
    building.
  - `needs-human`: a person must act or decide first, then flips it to `agent-ready` — or the ticket is human-only
    work for good. The reason is the issue's **last comment**. Labelling `needs-human` removes `agent-ready`; the two
    never sit together.
  - **`outside-change`: the work touches a repository this team does not own. It never runs autonomously and always
    ends at a pull request for that repository's own reviewer.** It always also carries `needs-human`, so one filter
    catches every issue an agent must not take. The issue names the external work item under `### External reference`
    and the pull request title carries it.

## Standing decisions — never ask about these

**The PRD is the north star for what we build.** Every product fact — vocabulary, scope, the do-not-build list, the
acceptance bar, the build decisions — is read from `docs/PRDs/PRD.md` (every PRD under `docs/PRDs/`, if more than
one), never restated in a rules file. Until PRD v1 exists the pre-PRDs there stand in. **Disagreement is a bug**: the
PRD wins on product, the rules files win on process.

- **Every big change gets its own PRD first**, at `docs/PRDs/PRD<SummaryName>.md`, before any ticket or code for it
  exists. Small fixes and tweaks need none.
- **No real production data in the repository.** The project's `CLAUDE.md` names the sensitive data classes. Synthetic
  or de-identified fixtures only. **No personal data anywhere** — not in prompts, logs, tests, fixtures, issues or git
  history — and never run anything against production.
- **Secrets only in `.env`** (gitignored; `.env.example` lists the names). Never in code, issues, pull requests or
  committed files. A committed secret is rotated by its owner, not just deleted: git history keeps it.
- **A boundary the project's `CLAUDE.md` draws is never moved by an agent** (e.g. "AI is a build-time tool; nothing it
  produces executes in the customer's runtime").
- **A repository the project's `CLAUDE.md` lists as external is read-only from here.** Never build it, run it, commit
  to it or change its git state. A change that must land there is an `outside-change` issue: it stops at a pull
  request its own reviewer merges.
- **The model provider sits behind one swappable interface.** Tests never reach the network; a test that needs the
  model mocks the interface. No API key is ever committed or written into an issue.
- **The project deploys only to the place its `CLAUDE.md` names, from `main`.** No other hosting unless the PRD
  names it.
- **No meeting recordings, transcripts or notes exports in the repository, ever** — they carry personal data. What a
  meeting decided goes onto the ticket it concerns, as a comment in the participant's own words.
- **Code, comments, commits, issues and docs in the language the project's `CLAUDE.md` names.**
- **Front-end development is led by the UX designs in `docs/ux/`.** A story that adds or changes a screen implements
  the prototype's screen, never a layout of its own; a screen the prototype lacks is a UX change first (pull request
  on `docs/ux/`), then a story. The user provides the designs before the first PRD is split into tickets.
- **Take every reversible decision yourself** — simplest option that meets the acceptance criteria, recorded in the
  pull request. Only a genuinely irreversible one becomes `needs-human`. A run that waits costs money doing nothing.
- **Two sources of truth, kept in step.** Issues track the work; the PRD holds the product. In a session with a person
  present — planning, harvest, hand-written tickets — after the batch of ticket creations or edits ask once:
  **"Should we update the PRD with this too?"**, one line per change naming the PRD section it touches. "No" ends it;
  "yes" ships the PRD edit in the pull request the work already has, or in a `docs(prd)` pull request when the work
  was only tickets. The dev skill's mechanical writes — labels, claim comments, `## Decisions (agent-ready)`,
  `Critical:` issues, closing — never trigger the question.

## Git

- **NEVER push to `main`.** Not a fix, not a typo, not "only a doc". Every change reaches `main` as a merged pull
  request from a `feat/<desc>` / `fix/<desc>` branch (or the project's own branch pattern). Nothing but you enforces
  this where branch protection is off.
- **Who merges.** Only `/dev-next` merges its own pull requests, and only once the project's build and test commands
  are filled in. Every other pull request — planning, scaffolding, documentation, anything outside the dev skill — is
  merged by a human. Never auto-merge beyond that.
- **Squash-merge only, then delete the branch** (`--delete-branch` breaks on a worktree; see
  `.claude/skills/dev-next/references/merge-and-ci.md`). One commit on `main` per pull request.
- **Work in a worktree on `feature/<slug>`** (`feature/<issue>-<slug>` when the branch serves one issue). A pull
  request may cover one issue or several related ones. Never work in the main checkout. **One exemption:** the
  per-developer branch `audit/<login>` that `/dev-next` writes run reports to is pushed directly, has no pull request
  and never merges into `main` (`.claude/skills/dev-next/references/audit.md`).
- Worktrees live **outside the project**, at the root the project's `CLAUDE.md` names. The in-flight file
  (`<worktree root>/in-flight.json`, never committed) lives beside them; format in
  `.claude/skills/dev-next/references/in-flight.md`.
- Update a branch with `git merge origin/main` — **never rebase, never stash**. Never force-push, never bypass hooks
  (`--no-verify`), never `git add -A`, never rebase or stash someone else's work, never delete work you did not create.
- Never merge on red or pending checks; "no checks reported" counts as red — poll for the check run first, the host can
  take minutes.
- Conventional Commits: `type(scope): summary`.

## Definition of done

- **Full build and full suite green before the pull request opens, run for real** — reading the code is not proof.
  Every new behaviour has a test.
- **Never delete, skip or weaken a test. Never widen a timeout to make a run pass. The skip count is baselined; a
  change to it fails.**
- **Pre-existing failures are still your responsibility:** fix them or surface them explicitly and get an
  acknowledgement. Never "those were already failing".
- **When something fails twice, stop and find the root cause** instead of retrying.
- **The gate, before any pull request opens:** build → lint → typecheck → full suite, with exactly the commands the
  project's `CLAUDE.md` lists (the same chain as CI). A command still reading `TBD` means the stack decision has not
  landed and `/dev-next` cannot run.
- **If the project produces generated output, it is gated by evaluation, not by a passing build.** The project's
  `CLAUDE.md` names the deterministic checks, the evaluation harness and its baselined threshold. A run that cannot
  execute the evaluation is **red**, never "not applicable".
- The pull request body carries the **evidence table** — what you did, what you expected, what you saw. A green suite
  alone is *not* evidence that the output works for its user.
- A **fresh agent** reviews every pull request — never the one that wrote the code.
- **The suite runs once per gate, never twice.** If CI runs the full suite, its result is the evidence: on the pull
  request for the reviewer, on the merged branch for the merge. If not, the reviewer runs it in the worktree and the
  merge runs it on the merged branch. Never both.
- **A story that changes user-visible behaviour updates the run-book** (`docs/runbook.md`) in the same pull request.
- **Every pull request adds its change to `docs/CHANGELOG.md`**, newest first, in the same pull request: one line per
  change saying what changed and why it matters, nothing more. No prose, no restating the diff, no entry that only
  repeats another one. A pull request that changes nothing a reader of the changelog would care about (typo, CI
  plumbing) still gets its line, kept to a few words.

## Working

- **Smallest change that works:** what was asked and no more. No refactors of untouched code, no speculative
  abstractions. **Stay on the issue you claimed.** A side-fix belongs in the pull request only if it is small, safe
  **and** in a file you are already changing.
- **Deferred findings:** small, safe **and** in a file already being changed → fix now. Critical → a GitHub issue,
  linked from the pull request. Everything else goes to the run's report, written once, never filed "to be safe": a
  backlog nobody drains is worse than no backlog. Before filing any issue, search the code and the open issues for
  something that already covers it; never defer to a **closed** issue.
- **One pile.** Every `/dev-next` story ends with one report file for that run, pushed to `audit/<login>` — a
  per-developer branch that collects reports and never merges into `main`. Each report has three lists: product
  problems left for later, things that slowed the run down, and tips for the next run. Reports are named by date and
  time, so they sort in order.
- **Harvesting.** `/harvest` is run by a person, never by another skill. A bookmark file on `main` records, per
  developer, the newest report already harvested; the harvest reads only newer reports, works through them with the
  human one item at a time, then moves the mark forward and ships it in its own pull request together with any
  tickets or rule edits it made. It groups items touching the same area into one ticket (the fewer the better) and
  drops an item only when the human says so. `/dev-next` only counts: at **10 unharvested items** it ends its run
  with `Harvest due: run /harvest`.
- **Sub-agents:** name each one after what it does (`review-auth-tests`, never `agent-3`); mechanical work runs on a
  cheap model at low effort, hard decisions and reviews on the top model; every spawn prompt asks for a bounded result
  (a verdict plus a few bullets, never an essay). A sub-agent never uses `git stash` and never switches branches — it
  works in its own worktree — commits only the files it touched, and on failure reports and stops instead of
  attempting its own recovery.

## Skills

- Skills under `.claude/skills/` carrying an `.orion-managed` marker are orion's and are refreshed by `orion update`;
  the project's own skills (no marker) are never touched.
- `/orion` manages the installation: `status`, `check`, `update`, `uninstall`.

## What the project's `CLAUDE.md` must state

Everything project-specific lives in the project's `CLAUDE.md`, never here. `orion init` seeds it with these slots
when the project has none; otherwise add what is missing. A slot the project has no use for is deleted.

- **Commands**: build, full suite, one file, one test, typecheck, lint, deterministic checks on generated output (if
  any), dev server (if the review surface needs one) — one table, every row a real command or `TBD`.
- **Stack and layout**: language and version with the file that pins it, test framework, application code path, test
  code path, skip-count baseline, CI runner.
- **Worktrees**: the worktree root outside the project, the port rule (`<base port> + issue number`) and the env
  variable that carries it.
- **Boundaries**: deploy target, external read-only repositories and their work-item key format, sensitive data
  classes that must never enter the repository, any boundary an agent must not move, the working language.
- **Pending until PRD v1**: the open questions, one table row each with the file and section they decide and who
  decides, asked as one batch (each with a recommended answer) once `docs/PRDs/PRD.md` exists and deleted as answered.
