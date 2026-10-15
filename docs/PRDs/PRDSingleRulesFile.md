# PRD — one rules file for every project

## Problem

orion shipped two rule files. `ORION.md` was copied into every project and refreshed on update; `BASE_CLAUDE.md` was
a template used only to create a project's `CLAUDE.md` when it had none, and never touched again. Both held generic
rules, so a rule added to the template reached no existing project, and nobody could tell which file a new rule
belonged in.

## Decision

- **`baselines/BASE_CLAUDE.md` is the only rules file.** It holds every mandatory rule for every project, is copied to
  `<project>/.claude/orion/BASE_CLAUDE.md` on `init` and overwritten on every `update`. On a contradiction it wins.
- **`ORION.md` is gone.** `update` deletes the old copy from a project and rewrites the import line in its `CLAUDE.md`.
- **The project's `CLAUDE.md` holds only project-specific facts and rules** and imports the mandatory rules with one
  line. If the project has no `CLAUDE.md`, `init` writes a slot-only starter (tracker, commands, stack, worktrees,
  boundaries, pending questions). An existing `CLAUDE.md` only gets the import line at the top.
- The last section of `BASE_CLAUDE.md` lists what the project's `CLAUDE.md` must state, so the two never drift.

## Out of scope

- Merging the project's `CLAUDE.md` on update. It is the project's own file and is never overwritten.
- Rules that belong to one project only.

## Acceptance

- `orion init` on an empty folder: `.claude/orion/BASE_CLAUDE.md` exists, `CLAUDE.md` is the starter with the import.
- `orion init` on a folder with its own `CLAUDE.md`: only the import line is added at the top.
- `orion update` on a project installed before this change: `ORION.md` is removed, the import line is rewritten, the
  rest of `CLAUDE.md` is untouched.
- `orion uninstall` removes the rules copy and the import line and leaves the project as it started.
