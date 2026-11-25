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
- **`updateMode: off`**: nothing newer from orion is offered: no update check, no rules check (`/orion-verify`), no
  status line offer, no mod offer and no personal rules offer. Each still runs by hand: `/orion-verify`,
  `bash .claude/orion/orion.sh statusline merge`, `bash .claude/orion/orion.sh mod install <name>`, and asking to go
  through orion's personal rules. Rules that changed while it was `off` are asked about once when it is `ask` or
  `auto` again. Letter case and spaces around the value do not matter (`OFF`, ` off ` are `off`).
- **A value orion does not understand** (`false`, `never`, an empty string), or a `config.json` saved as UTF-16 (as
  Windows PowerShell 5.1 writes it): orion treats it as `off`, and every session start says so in one line, naming
  `ask`, `auto` and `off` (and, for UTF-16, that the file must be saved as UTF-8), until the file is fixed.
- Your own folder is never updated by the session-start hook. If an update reaches it as uncommitted files anyway,
  see the next section.

## When an orion file is missing or damaged

- `bash .claude/orion/orion.sh repair` re-copies every file orion owns from the commit already installed (line 1 of
  `.claude/orion/VERSION`), in every update mode. The installed version, `VERSION` and `config.json` stay as they
  are; only what was missing or changed comes back. `/orion-verify` runs it for the files it finds missing.
- A project skill of your own in an orion skill's place is skipped; `repair --force` replaces it, only on your word.
- When that commit cannot be fetched (no network, or the source no longer has it), nothing changes: one line, exit 1.
  `/orion-verify` then asks whether to update to the newest orion instead.
- After an update by an older orion (16 or earlier) left line 5 of `VERSION` empty, the next session start under
  `ask` or `auto` writes the release number back there without a word; the old script's own
  `ORION_VERSION: No such file or directory` line during that update stays, since only a version set by hand could
  silence it.

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
- Two more questions follow it: the development branch (where daily work starts and merges) and the release branch
  (where the project deploys from). Enter keeps the current default branch for both; the same name for both is a
  one-branch project. Without a terminal, pass `--dev-branch <name>` and `--release-branch <name>`.
- A development branch other than the current default becomes the repository's default branch on GitHub, and a
  declared branch that does not exist yet is created from the current default. orion then says what it left alone:
  open pull requests keep their old base (`gh pr edit <N> --base <development branch>`), a workflow that runs only on
  a push to the old default gets no run, and a workflow started by hand or on a schedule runs on the new one.
- When it cannot make the change (no `gh`, no GitHub remote, no admin right), it prints the one step to do by hand
  and the install still finishes. Change the names later with `bash .claude/orion/orion.sh branches --dev <name>
  --release <name>`.

## At session start: GitHub's default branch is not the declared one

- Every session refreshes this clone's idea of GitHub's default branch (`origin/HEAD`). When it differs from the
  development branch in `.claude/orion/config.json`, the session says so once a day; `/orion-verify` offers the fix
  and runs it only on your yes. Silent when the remote cannot be reached.

## When `/clear-git-resources` lists the branches

- The release branch (the one the project deploys from) is listed as kept, local and remote, with no delete command,
  even when every commit on it is already on the default branch. It is the `releaseBranch` named in
  `.claude/orion/config.json`; an install from before that key counts `main` as the release branch whenever the
  default branch is another one. A one-branch project sees no change.

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
