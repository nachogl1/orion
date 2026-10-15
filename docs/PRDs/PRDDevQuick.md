# PRD — dev-quick: a front door for changes that have no ticket yet

## Problem

`/dev-next` ships an issue that already exists and is `agent-ready`. A change a person wants right now — a fix they
just spotted, a small feature a conversation produced — has no issue, so it is either built by hand in the chat
(no worktree, no fresh review, no evidence table, no audit) or it waits for a planning session it is too small for.
Writing the issue by hand to the `new-issue.md` shape is slow enough that people skip it.

## Decision

- **A new skill, `dev-quick`, turns a free-text request into an `agent-ready` GitHub issue and hands it to
  `/dev-next`.** It is a front door, not a second engine: every step from the claim onwards (worktree, dev agent,
  fresh-agent review, merge on green CI, close, audit, close-out) is `/dev-next`'s, invoked as a sub-skill with the
  exact-claim argument `#<N>`. Nothing of that pipeline is copied into `dev-quick`.
- **The human is present until the issue is filed, and never after.** The skill interviews them until it has no
  question left (as many rounds as it takes, clickable options, recommended answers first), lists the ground
  preparation only a person can do (a secret in `.env`, a service, a design, a decision from someone else) and
  verifies each item, shows the drafted issue once for approval, then files it. From the hand-over on, the run is
  `/dev-next`'s autonomous run.
- **The issue is filed to `dev-next`'s `references/new-issue.md` shape**, with the interview's answers under
  `## Decisions (agent-ready)` so `/dev-next`'s own Q&A phase asks nothing. An interview answer of "ask someone
  else", or a preparation item that cannot be done now, files the issue `needs-human` and ends the run without a
  hand-over.
- **Dedupe before filing is mandatory**: an open issue that already covers the change is interviewed and handed over
  instead of a duplicate; an issue someone is already on stops the run; code that already does it stops the run.
- **Quick means one story** — one seam, one pull request, no PRD. A change that needs more is said to be not quick,
  and the skill points at a PRD, `/wayfinder` or planning, offering at most to file the first stand-alone story.
- `dev-next`, `harvest` and `dev-quick` ship together; `BASE_CLAUDE.md` and the repo's `CLAUDE.md` name all three.

## Out of scope

- Any tracker but GitHub Issues (same as `dev-next`).
- Changing how `/dev-next` claims, develops, reviews or merges. A change there is a change to `dev-next`.
- Running without a person present. The interview is the point; an unattended `dev-quick` is `/dev-next`.

## Acceptance

- `skills/dev-quick/SKILL.md` exists, is self-contained apart from references into `.claude/skills/dev-next/`, and
  carries no project, person, company or stack names.
- The skill files an issue with every `new-issue.md` heading, `story` + exactly one readiness label, the native epic
  and blocker links read back, and a `## Decisions (agent-ready)` section, then invokes `dev-next` with `#<N>`.
- `./orion.sh init --project <empty tmp dir> --no-statusline` installs `dev-quick` beside `dev-next` and `harvest`;
  `update --force`, `check --force` and `uninstall --yes` leave the tmp dir as it started.
