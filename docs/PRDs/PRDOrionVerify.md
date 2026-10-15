# PRD — orion-verify: the post-install consistency check

## Problem

`orion init` is a mechanical copy. It drops skills, a rules file and a session-start hook into a project and adds an
import line to the project's `CLAUDE.md`, but it cannot tell whether the result makes sense as a whole. A rule the
project already had may now contradict the mandatory rules it just started importing. A skill the project already had
may sit in the place of one orion ships (init skips it and says so once, in output nobody reads twice), or may tell the
agent to do what the rules forbid. A line may be missing or doubled after a hand edit. None of this is caught until it
bites, usually mid-session, with no pointer back to the install.

## Decision

- **`orion.sh` gains a `verify` sub-command** that runs every check a script can do deterministically and prints one
  line per finding (`ok` / `WARN` / `FAIL`), exit 1 on any `FAIL`, never a fix: the files orion owns are present,
  `config.json` is valid, `CLAUDE.md` imports `BASE_CLAUDE.md` exactly once and no longer imports the retired file,
  the rules copy matches what is committed, every skill and skill file `BASE_CLAUDE.md` relies on is installed, every
  skill folder (orion's and the project's) has a `SKILL.md` whose `name` matches the folder with no duplicate names and
  no user-level shadow, `.claude/settings.json` parses and carries the orion hook once, and nothing orion installed is
  ignored by git. Unfilled slots in `CLAUDE.md` are a `WARN` with a count, not a failure.
- **A new skill, `orion-verify`, is the whole-picture check.** It runs `verify` first and applies the fix for every
  `FAIL` without asking, because those only repair what orion installed. Then it does what a script cannot: reads the
  project's `CLAUDE.md` against `BASE_CLAUDE.md` for contradictions, duplicates, missing required sections and stale
  references; reads every project-owned skill for instructions that break the mandatory rules and for name clashes;
  reads the settings for a deny rule that would block orion or a status-line entry that would break teammates.
- **Three outcomes, kept apart: fixed, needs a yes, reported.** Anything the project owns (its `CLAUDE.md` rules, its
  own skills, `.gitignore`) is never edited without the user's yes, asked once in one batch of clickable questions with
  the exact rewrite shown. The rules copy is never edited; it is orion's.
- **`init` asks for the check once.** It leaves a per-computer marker in the cache (never in the project, so it is never
  committed) and the `check` hook, on the next session start, consumes the marker and tells Claude Code to run
  `/orion-verify` before anything else, then exits without an update check. `verify` also consumes the marker, so a
  check run right after an in-session `init` does not trigger a second one. `init`'s own closing message names the
  skill for the person at the terminal. `uninstall` removes the marker.
- The skill's report is short and in chat: what is still wrong, what was fixed, what was only noted, one next step.
- **Open to new skills without editing the check.** Neither `verify` nor the skill names a skill: both walk every
  folder under `.claude/skills/` and every skill the rules file refers to. A skill that needs something from the
  project or the machine ships a `VERIFY.md` beside its `SKILL.md` — a table of read-only checks with what to do on
  failure — and `/orion-verify` runs every `VERIFY.md` it finds, orion's and the project's own, within fixed limits
  (read-only, nothing fixed without a yes beyond the mechanical fixes of orion's own files, an unrunnable check is
  unverified, never passed). `verify` lists the skills that carry one. `dev-next` and `issue-map` ship the first two.

## Out of scope

- Running the check after `update`. The rules file already tells the agent to re-read `CLAUDE.md` after an update that
  changed it, and the `orion` skill's `update` row does the same. The user may type `/orion-verify` at any time.
- Judging the quality of the project's own rules or skills beyond their consistency with the mandatory rules.
- Fixing a project skill or a project rule without a yes.

## Acceptance

- `skills/orion-verify/SKILL.md` exists, is self-contained, carries no project, person, company or stack names, and
  names no skill; `verify` on a fresh install lists `dev-next` and `issue-map` under `skill-checks`.
- `bash -n orion.sh` is clean; `./orion.sh init --project <empty tmp dir> --no-statusline` installs `orion-verify`
  beside the other skills and ends by naming it; the first `check` after that prints the single-line
  `hookSpecificOutput` JSON asking for the skill and the second is silent; `verify` on the fresh install exits 0 with
  only the unfilled-slot warning; a `CLAUDE.md` with the import line removed, doubled, or pointing at the retired file
  makes `verify` exit 1 with the matching `FAIL`; `update --force`, `check --force` and `uninstall --yes` leave the tmp
  dir as it started.
