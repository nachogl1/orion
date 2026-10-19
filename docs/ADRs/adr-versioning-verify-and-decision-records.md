# ADR — a version number for orion, a stronger post-install check, and decision records instead of per-change PRDs

**Status: approved by the owner on 2026-10-19.**

## Context

Using orion in real projects showed seven problems:

1. **Update offers that are not real.** The session-start check compares the commit on orion's `main` with the commit
   the project installed. About one merge in three changes nothing a project receives (the README, the guide page,
   tests, CI), yet every one of them makes the check say "a newer orion is available".
2. **`/orion-verify` checks files, not where they live.** The rules and skills assume fixed folders (`docs/PRDs/`,
   `docs/ux/prototypes/`, `docs/runbook.md`, …). A project that keeps its PRDs somewhere else is never told, and the
   skills silently miss them.
3. **Blank commands block the dev skills.** The starter `CLAUDE.md` leaves every command as `TBD`; `/orion-verify` only
   reports them as homework, so `/dev-next` cannot run until a person fills them by hand.
4. **Git-ignored orion files.** `verify` checks four paths only, and its advice ("un-ignore them") fails when the whole
   `.claude/` folder is ignored: git cannot re-include a file inside an ignored folder.
5. **The install's closing message says to commit first and verify second,** although verify fixes things the first
   commit should carry.
6. **The guide page does not explain what orion installs** — the base rules, the personal rules, the skills and the
   status line — where each lives, who owns it and how each one is updated.
7. **"Every big change gets its own PRD first" fires too often.** "Big" is undefined, so agents ask for a new PRD for
   changes that only need a recorded decision, and a PRD per change is far heavier than the decision it records.

## Decision

1. **orion carries one version number** — a plain whole number (orion 1, 2, 3 …) in `ORION_VERSION` at the
   repository root.
   Every pull request that changes a file `init` or `update` copies into a project (the skills, the baselines,
   `orion.sh`) raises it by one; the suite fails a change to those files that does not. After a merge that raised it,
   a GitHub job tags the commit `v<N>`. Each project records the number it installed. The session-start check reads
   the tags in the same single quick call it makes today and offers an update only when a higher number exists; a
   source without such tags falls back to today's commit comparison. The status line and the personal rules keep
   their own timestamps.
2. **`/orion-verify` checks folder locations.** It collects every folder path the base rules and the installed skills
   assume, and flags each one the project keeps somewhere else (a folder that does not exist yet stays quiet: the
   skills create it later). For each, it offers to **move** the folder to the expected place with a git move, on the
   person's yes. No path override slot: the skills keep one fixed layout.
3. **`/orion-verify` fills the blank commands.** For every `TBD` command it proposes a real one, worked out from the
   project's own files (CI workflow first, then the package or build files), naming where it found it, and fills the
   ones the person accepts. It does not run them.
4. **Git-ignored orion files.** `verify` checks every file orion installed; `/orion-verify` proposes the exact
   `.gitignore` lines that work (for an ignored `.claude/`, rewriting it as `.claude/*` plus the re-includes, while
   personal files such as `settings.local.json` stay ignored) and applies them on the person's yes. `init` prints one
   warning line when it finds the problem.
5. **The install's closing message puts `/orion-verify` first**, before the first commit.
6. **The guide page gains a "What orion installs" section**: one box each for the base rules, the personal rules, the
   skills and the status line — where it lives, who owns it, and how it is updated (version number, timestamps,
   merge). The page and its exported graph also show the new decision-record process.
7. **Decision records replace per-change PRDs.** Three sizes of change:
   - **A fix or a tweak:** no document.
   - **A hard-to-reverse decision** (a new mechanism, a format, a dependency, a change of scope): the agent proposes
     an ADR, the person confirms one is needed, and the person approves it before any ticket or code. It lives at
     `docs/ADRs/adr-<change-name>.md`.
   - **A big change or a product update:** the agent only asks whether the person wants a PRD. Creating or updating a
     PRD is the person's process, on their terms: planned with `/wayfinder`, then written or provided by the person.
     No agent drafts a PRD on its own.

   `docs/PRDs/PRD.md` stays the north star for what the product is. orion's own PRD is updated in this bundle to
   describe the new behaviour.

## Consequences

- **Accepted gap:** an approved ADR that changes the product does not update the PRD. `/prd-to-tickets` and
  `/reconcile-issue-map` keep reading only the PRDs, so they may work from a PRD that is behind until the person
  updates it.
- **Version clashes:** two pull requests open at the same time both raise the number; the second must merge `main`
  and raise it again. The suite catches it.
- **A new GitHub job** needs permission to push tags. A copy of orion hosted without it keeps today's behaviour.
- **Moving a folder** changes the project's layout; links to the old place in other documents may break. The move
  only happens on the person's yes.
- **A proposed command may be wrong;** since verify does not run it, the error shows up when a skill first uses it.
- **Until `/orion-verify` runs,** a teammate's clone can still miss git-ignored orion files.
- Existing `docs/PRDs/PRD<SummaryName>.md` files in projects stay where they are; the skills still read every PRD
  under `docs/PRDs/`.

## Alternatives considered

- **Updates:** a release timestamp bumped by the author (needs a file download at every session start, GitHub only);
  comparing files at session start (too slow for the hook's time limit); a three-part version number (every change
  must judge which part to raise).
- **Misplaced folders:** a path override slot every skill reads (about ten skills to teach, more drift).
- **Blank commands:** fill and run each to prove it (the full suite can take minutes at install time).
- **Per-change PRDs:** a sharper definition of "big" with a PRD edit in the same pull request; letting the person
  decide every time; a size threshold by number of epics.
