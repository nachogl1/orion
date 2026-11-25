# Runbook

What a person sees orion do in a project, and what to do about it.

## At session start: an orion update

- **`updateMode: ask`** (the default): when a higher orion version exists, the session asks "Update now" or "Not now".
  A yes makes the agent ship the update through its own pull request: a worktree on `feat/orion-update-v<new>` from
  the default branch, `orion.sh update` there, the project's gate, a pull request titled
  `chore(orion): update orion from <old> to <new>` merged once its checks are green, then a pull into your folder.
  "Not now" keeps quiet until the next version.
- **`updateMode: auto`**: the same, without asking. Until the pull request merges, every session start asks again.
  A run that stopped (red checks, checks still pending, a person merges) is picked up by the next one from its
  branch, which reports the waiting pull request's link instead of starting over.
- **`updateMode: off`**: no check.
- Your own folder is never updated by the session-start hook. If an update reaches it as uncommitted files anyway,
  see the next section.

## At session start: orion's files left uncommitted

- When an orion skill (a folder under `.claude/skills/` with an `.orion-managed` marker) or a file
  `.claude/orion/.orion-manifest` lists differs from the last commit in the main checkout, the session says so and
  asks "Ship them" or "Not now". It never discards them: they may hold edits of your own.
- A yes ships them through their own pull request the same way. A first install nobody committed also brings
  `.claude/orion/config.json`, `.claude/settings.json` and `CLAUDE.md`; since it changes `CLAUDE.md`, a person merges
  that pull request.
- "Not now" asks again at the next session start while the files still differ. Commit them yourself, on a branch, to
  stop it.
- Silent in a linked worktree, outside a git repository, and for files that are the project's own
  (`.claude/orion/config.json`, skills without the marker).

## During install

- The update-mode question now reads `auto - an agent ships it through its own pull request without asking`.

## When `/orion-verify` checks the commands table

- `orion.sh verify` prints one `WARN  claude-md-row` line for each commands-table row the rules rely on that your
  `CLAUDE.md` lacks (build, full suite, one file, one test, typecheck, lint). A row counts as present when
  its label holds the row's key word in any case (`lint` for the lint row), so a reworded label still counts.
- `/orion-verify` then works out the command from your CI workflow, build files or README and proposes the row with
  its source; it adds the row only on your yes. When the row is there under a label the key word misses, it offers to
  rename that label to orion's wording and keeps your command.
- orion no longer sizes a test run's parallel workers ("test copies"): the full suite runs exactly as your
  `CLAUDE.md` lists it. A "Test copies" row an older orion wrote is read by nothing; `/orion-verify` offers once to
  delete it and never asks you to fill it.
