# PRD — prd-to-tickets: cut a PRD into epics and stories built for parallel work

## Problem

The mandatory rules say "PRD → epic → story" and that agents implement stories only, but nothing in orion does the
split. A PRD is cut by hand, and hand-cut backlogs show the same faults every time: stories that share a folder and
collide at merge, blockers set in one of the two forms only (so agents and people see different graphs), stories
filed `agent-ready` with a question still open, duplicates of issues that already exist, a chain so deep that only
one developer can work at a time, and front-end stories filed before any screen has been designed, so each agent
invents a layout of its own.

## Decision

- **A new skill, `prd-to-tickets`, reads one PRD under `docs/PRDs/` and files the epics and stories** to
  `dev-next`'s `references/new-issue.md` shape, with the person present until the batch is filed and never after.
- **The cut is shaped for parallel work:** the scaffold story first (one developer on day one, when the project has
  no code yet), then one story per shared contract (type, interface, schema, shared project file), then everything
  fans out. Blockers are set only on real contract dependencies (the consumer of a definition waits for its definer);
  every story names the one folder or module it owns; the chain stays shallow; and a paper check confirms that from
  the contract level on, at least the project's developer count of stories is unblocked at every level.
- **Readiness labels, as the rules define them:** `agent-ready` (nothing left to ask, mutually exclusive with
  `needs-human`), `needs-human` (a person acts or decides first, reason as the last comment, or human-only work for
  good), `outside-change` (lands in a repository the team does not own: never autonomous, always also
  `needs-human`, always with `### External reference`, skipped by `/dev-next`).
- **Blockers in both forms, always read back:** the `### Blocked by` body section agents parse and GitHub's native
  relation people see. Epic → story is a native sub-issue. **Existing open issues become blockers, never duplicates**;
  a closed issue covers nothing.
- **The UX check is the first thing the person hears.** When the PRD describes screens and `docs/ux/prototypes/`
  holds no prototype for them, the skill says so and offers to draft one from the PRD in parallel with the split (a
  sub-agent in its own worktree, a pull request a human merges). A `needs-human` story for the prototype is filed and
  every front-end story is blocked by it, so no agent starts a screen nobody has drawn. `BASE_CLAUDE.md` now names
  `docs/ux/prototypes/` as the place the prototype lives and allows the skill to draft it; before, it only said the
  user provides the designs under `docs/ux/` before the first split.
- **A fresh sub-agent checks the plan against the cut rules before the person sees it**, and the person gets one
  look before anything is filed. The interview asks every question the PRD leaves open, never one the PRD or the
  project's `CLAUDE.md` already answers.
- The skill ships a `VERIFY.md` so `/orion-verify` checks its prerequisites after install, and rebuilds the issue
  map silently at the end when `issue-map` is installed.

## Out of scope

- Any tracker but GitHub Issues (same as `dev-next`).
- Writing or editing the PRD. A PRD update the interview makes necessary is offered once and lands as its own
  `docs(prd)` pull request.
- Building anything: the skill files tickets; `/dev-next` builds them. The prototype is a design document, not code.
- Changing how `/dev-next` reads blockers, labels or the issue body. The shape stays `new-issue.md`'s.

## Acceptance

- `skills/prd-to-tickets/SKILL.md`, `VERIFY.md` and `references/ux-prototype.md` exist, carry the `ORION - `
  description prefix, reference only `.claude/skills/dev-next/references/*` outside the skill, and hold no project,
  person, company, product or stack names.
- The skill's first message to the person, when the PRD describes screens and no prototype exists, says there is no
  UX prototype to lead with and offers to draft one in parallel.
- Every filed story carries `story` plus exactly one readiness label, every `new-issue.md` heading, its blockers in
  both forms read back, and a native sub-issue link to its epic.
- `./orion.sh init --project <empty tmp dir> --no-statusline` installs `prd-to-tickets` beside `dev-next`;
  `update --force`, `check --force` and `uninstall --yes` leave the tmp dir as it started.
