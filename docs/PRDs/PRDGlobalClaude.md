# PRD — GLOBAL_CLAUDE.md: personal rules orion offers

**Status: approved by the owner on 2026-10-18.** The open questions at the end are answered before the first ticket
is cut.
Once shipped, it is folded into `docs/PRDs/PRD.md`.

## Problem and users

orion keeps every project's rules up to date through `BASE_CLAUDE.md`, and since the status line change every
computer's status line follows orion too. A person's own user-level `CLAUDE.md` (`~/.claude/CLAUDE.md`, one per
computer) still gets nothing: the reply rules, working habits and git habits that make the assistant pleasant to
work with have to be copied by hand from someone who already has them, and they go stale.

- **Who uses it:** every person who opens a session in a project with orion installed, including a teammate who
  only cloned the repository.
- **What they get:** an offer, never a push, of orion's recommended personal rules, talked through clause by clause.
  Whatever they accept is theirs.

## What changes

### 1. `GLOBAL_CLAUDE.md`, the offered personal rules

- A new file **`GLOBAL_CLAUDE.md`** lives in `baselines/global/`, a sister folder of `baselines/statusline/`, next
  to `BASE_CLAUDE.md`.
- **Seed:** the owner's own user-level `CLAUDE.md`, rewritten for anyone: "the person" instead of "me", nothing
  that names or describes the owner, and every rule that `BASE_CLAUDE.md` already makes for projects left out.
- **A clause** is one bullet or one numbered item, grouped under the file's headings. Every clause ends with an
  invisible date marker, `<!-- orion:2026-10-18T10:00Z -->` (UTC), the moment it was last added or changed.
- `init` and `update` copy the folder to `<project>/.claude/orion/global/`, listed in `.orion-manifest`, exactly as
  they already copy `statusline/`. The project copy is only the offer; nothing imports it.

### 2. The ORION GLOBAL section in the person's own file

- Everything a person accepts lives in one section **at the top** of their `~/.claude/CLAUDE.md`:

  ```markdown
  # ORION GLOBAL — last updated 2026-10-18T14:05Z
  …accepted clauses, under the same headings as GLOBAL_CLAUDE.md…
  <!-- /ORION GLOBAL -->
  ```

- The timestamp on the heading line is the only record of what was offered. **A clause dated after it is offered;
  a clause dated before it is not.** After every discussion the timestamp moves to "now", whether the person
  accepted everything, part or nothing.
- A person who declines everything still gets the heading, the timestamp and the end line with nothing between,
  so the same clauses are not offered again.
- A changed clause that the person accepted earlier is shown as old and new side by side and replaced in place only
  if they say yes.
- The person may edit the section freely. Editing the timestamp is their own responsibility; orion trusts it.
- `uninstall` never touches the person's file: accepted clauses are theirs.

### 3. The discussion

- The `orion` skill gains an action, **`/orion global`**: it reads the project copy of `GLOBAL_CLAUDE.md` and the
  person's section, lists the clauses dated after the timestamp (or all of them when there is no section), asks
  about them in batches with clickable options (accept, skip, accept with an edit), writes only inside the section,
  and moves the timestamp.
- It never edits anything in the person's file outside the section, and it shows the final section before saving.

### 4. The offer at session start: always asked, never automatic

- The `check` hook (no network, still silent on success, exit 0 on every failure, at most one JSON line, its message
  joined to the others as the status line offer is) reads the project copy of `GLOBAL_CLAUDE.md` and the heading
  line of `~/.claude/CLAUDE.md`. When a clause is newer than the timestamp, or there is no section yet, it asks
  Claude Code to offer `/orion global` with the AskUserQuestion tool, once a day per computer.
- **This offer ignores `updateMode: auto`.** As with the status line, the person's own file changes only on their
  word, here through the discussion. `auto` may refresh the project copy of `GLOBAL_CLAUDE.md`;
  not answering means nothing else changes.
- Right after `init`, the post-install message also asks for the discussion, once `/orion-verify` has run.
- The hook never writes to `~/.claude/CLAUDE.md`.

## Do not build

- **Any automatic write to `~/.claude/CLAUDE.md`**, in any update mode.
- **A per-computer list of declined clauses.** The section timestamp is the only record.
- **Edits outside the ORION GLOBAL section**, or removal of the section by `uninstall`.
- **An import of `GLOBAL_CLAUDE.md`** into the person's file: they get copies of the clauses they chose, not a link.
- **Anything in `GLOBAL_CLAUDE.md` that names or describes a real person**, team, company or machine.

## Acceptance bar

- The CI chain is green with the commands in `CLAUDE.md`, and the full suite adds these checks:
  - `check` offers `/orion global` when there is no section, and when a clause is newer than the timestamp.
  - `check` stays silent about it when every clause is older than the timestamp, and when it already offered today.
  - `check` under `auto` never writes `~/.claude/CLAUDE.md`.
  - `uninstall` leaves `~/.claude/CLAUDE.md` byte for byte as it was.
  - Every clause in `GLOBAL_CLAUDE.md` carries a valid date marker, and a clause changed against `origin/main`
    carries a newer date than before (otherwise the change would never be offered).
- `verify` reports a missing project copy of `GLOBAL_CLAUDE.md` as a `FAIL`.
- `CLAUDE.md` (the boundary on what orion touches outside the project, and the wiring notes), `BASE_CLAUDE.md`'s
  skill list, `PRD.md` (the "Do not build" line about a user-level install), the README and `docs/CHANGELOG.md`
  describe the change.

## Open questions

| Question | Recommended answer | Decides |
|---|---|---|
| Does `updateMode: off` also silence the offer? | Yes: `off` means orion stays quiet. | Owner |
| Is `/orion global` an action of the `orion` skill or a skill of its own? | An action of `orion`: one fewer skill to install and verify. | Owner |
| Is the section at the top of the person's file, or at the end? | The top, as asked. | Owner |
