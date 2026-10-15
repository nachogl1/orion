# PRD — reconcile-issue-map: keep the issues and the PRD saying the same thing

## Problem

The mandatory rules name two sources of truth — the PRD holds the product, the issues track the work — and say a
disagreement between them is a bug. Nothing in orion checks for one. `prd-to-tickets` cuts a PRD once; from then on
people and the repository move: a PRD section is rewritten after its stories were filed, a story is filed from a
conversation and names no PRD section, a closed story's decision never reaches the PRD, an epic is closed with
children still open, a folder is renamed under the story that owns it, a blocker is set in one of the two forms only.
`issue-map` draws the graph but judges nothing beyond the mechanics its footer reports. An agent building from a
stale story builds the wrong thing, and nobody finds out until review.

## Decision

- **A new skill, `reconcile-issue-map`, reads the PRDs under `docs/PRDs/`, every issue (open and closed, with the
  native sub-issue and blocked-by links) and the code on `main`, and lists every way they disagree**, through four
  lenses: the PRD asks for something no story covers (including a PRD section changed after its stories were cut);
  a story the PRD does not ask for, or a closed story's outcome the PRD never absorbed; the issue map is broken (no
  epic, blocker forms that disagree, cycles, built out of order, impossible label pairs, two open stories on one
  seam, a seam missing from `main`, a chain too deep); and the product does not match the issues (a closed story
  whose work is not on `main`, an open story whose work already is, a do-not-build item in the code).
- **A person runs it, and decides every finding.** The three checks run as sub-agents with bounded briefs; this
  session confirms every line against the PRD and the issue before it is shown, groups findings by PRD section, epic
  or folder, rates each (fix before the next run / fix some day / probably fine as it is), explains each in plain
  words as to someone with no context, and asks in waves with clickable options. Destinations: fix the issues,
  update the PRD, file a story, close a story, accept as fine, not this time.
- **The PRD wins on what to build; `main` wins on what is done.** A story that contradicts its PRD section is fixed,
  not the PRD, unless the person says the PRD is stale. Issue edits go straight to GitHub under the ownership rules
  (never someone else's, never an in-flight issue, never the last comment of a `needs-human` issue, never
  `needs-human` → `agent-ready`); PRD edits and the bookmark land in one pull request a human merges.
- **A bookmark, `docs/reconcile-state.json`**, records the `main` commit the last run read at and the findings the
  person accepted as fine, so a run only re-raises what changed.
- **`/dev-next` probes, never reconciles.** At the end of its run, from data it already holds, it checks three cheap
  signs — the issue-map footer reports a disagreement or a dropped link, an open issue carries an impossible label
  pair or no parent epic, or `docs/PRDs/` changed on `main` since the bookmark — and ends with
  `Drift found: run /reconcile-issue-map`, exactly as it ends with `Harvest due: run /harvest`.
- The skill ships a `VERIFY.md` so `/orion-verify` checks its prerequisites after install, and rebuilds the issue
  map silently at the end when `issue-map` is installed.

## Out of scope

- Any tracker but GitHub Issues (same as `dev-next`).
- Running the full reconciliation inside `/dev-next`: it needs a person for every decision and would cost every run
  a large read of the PRDs and the backlog.
- Writing a PRD from scratch (`/wayfinder`), or cutting one into tickets (`/prd-to-tickets`).
- Judging code quality or product fit beyond "is what the PRD and the issues claim actually on `main`".

## Acceptance

- `skills/reconcile-issue-map/SKILL.md` and `VERIFY.md` exist, carry the `ORION - ` description prefix, reference
  only `.claude/skills/dev-next/references/*` and `.claude/skills/issue-map/scripts/*` outside the skill, and hold no
  project, person, company, product or stack names.
- Every finding the person sees names its lens in the first words and carries a one-line "how much it matters, and
  why"; nothing is edited, filed, closed, accepted or dropped without an answer given in a wave.
- `/dev-next`'s phase 6 probes the three signs and prints `Drift found: run /reconcile-issue-map` when any holds;
  `BASE_CLAUDE.md` names the skill and the probe.
- `./orion.sh init --project <empty tmp dir> --no-statusline` installs `reconcile-issue-map` beside `dev-next`;
  `update --force`, `check --force` and `uninstall --yes` leave the tmp dir as it started.
