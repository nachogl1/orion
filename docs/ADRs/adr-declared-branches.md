# ADR — a project declares its development and release branches at install, and orion sets GitHub's default branch to match

**Status: pending**

## Context

The develop-branch map decided that the shared rules and the skills stop naming `main` for daily work and look up
**the repository's default branch** instead, and that a release branch, if a project has one, is named in the
project's `CLAUDE.md`. That is decided but not built yet: it is the open story #236 (Default branch: the rules and
skills say the default branch for daily work), and until it merges the baseline and the skills still name `main`.
Under that plan `orion.sh` does not change:
`init` asks nothing about branches, and nothing orion ships ever touches a project's GitHub settings.

That leaves a project that wants the same split as orion (daily work on one branch, releases from another) to set
it up by hand: create the branch, change GitHub's default branch in the repository settings, and write the release
branch into `CLAUDE.md`. Until all three are done, the skills keep reading the old default branch and merge daily
work into the branch the project releases from. Nothing tells the person which step is missing.

## Decision

1. **`init` asks for two branch names**: the **development branch** (where daily work starts from and merges into)
   and the **release branch** (the branch the project deploys from). It asks when stdin is a terminal, the same way
   it asks for the update mode, and takes them from `--dev-branch <name>` and `--release-branch <name>` otherwise.
   Both default to the repository's current default branch, so an install that answers neither behaves as today.
2. **The same name for both means a one-branch project**: no release branch and no release pull request. Decision 4
   still applies to that one branch, so with the defaults nothing changes on GitHub.
3. **The names are kept in `.claude/orion/config.json`** as `developBranch` and `releaseBranch`, a file the project
   commits, so every teammate's clone reads the same two names. **One sub-command writes them**,
   `orion.sh branches --dev <name> --release <name>`: it stores the two keys and does the GitHub step of decision 4.
   `init` runs it on a first install; on an existing install, `init --dev-branch` or `--release-branch` runs the
   same sub-command, GitHub step included; `/orion-verify` runs it on the person's yes. It adds a key that is
   missing, which the setter behind `--source` and `--ref` cannot do (that one only rewrites a key already in the
   file), so an install from before this decision gets its keys the same way. `update` never touches them. The starter `CLAUDE.md` that `init` writes names the release branch in its deploy line, and the
   baseline's list of what a project's `CLAUDE.md` must state gains both names.
4. **orion makes GitHub match, and only this far**: it creates a declared branch that does not exist yet (from the
   current default branch) and sets the development branch as the repository's default branch
   (`gh repo edit --default-branch <name>`), then runs `git remote set-head origin --auto` in the checkout. It does
   this only when a declared name differs from what GitHub has now. **It never writes branch protection or any other
   repository setting.**
5. **A step that cannot run never fails the install.** Without `gh`, without a GitHub remote, or without the right
   to change the default branch (only a repository admin has it), orion prints the one step a person must do by
   hand and goes on.
6. **GitHub's default branch stays what the skills read.** They keep looking it up at run time, as the
   develop-branch map decided; the two keys in `config.json` record what the project declared, so a disagreement can
   be seen.
7. **`check` keeps every clone in step, every session.** A clone made before the switch keeps pointing its
   `origin/HEAD` at the old default branch, so its skills would merge daily work into the release branch. At every
   session start `check` runs `git remote set-head origin --auto` as a time-limited step of its own: whatever
   `config.json` says (a clone still on the old default branch may not have the two keys yet), and also when the
   session is on no branch or on a branch with no remote copy, the two cases in which its pull step does nothing.
   Then, when this clone has `developBranch` and it differs from `origin/HEAD` (GitHub's default branch is not the
   declared one), it says so in its one message, at most once a day. It stays silent otherwise and still exits 0
   on every failure.
8. **`verify` warns, existing installs included**: one `WARN` when the keys are missing (an install from before
   this decision), one when GitHub's default branch is not the declared development branch (when `gh` can read it),
   and one when this checkout's `origin/HEAD` points at another branch. `/orion-verify` then asks for the names and
   runs the sub-command of decision 3, only on the person's yes.
9. **Only the `branches` sub-command changes GitHub**, reached through `init` or through `/orion-verify` on the
   person's yes. `check` moves nothing but this clone's own `origin/HEAD` pointer. `update` and `uninstall` never
   touch GitHub; `uninstall` leaves the branches and the default branch as they are.
10. **This ships only after the default-branch story (#236) has merged.** Built first, `init` would switch a
    project's default branch while every skill still merged into `main`. The story for this decision is blocked by
    it.

## Consequences

- orion changes a repository setting for the first time. It is the one setting the skills depend on, changed only
  on the names the person gave, and it is undone with the same command.
- `orion.sh` reaches the network in three new places. The `branches` sub-command calls `gh` and pushes a declared
  branch that does not exist yet, the first push `orion.sh` ever makes (a new branch, never a commit onto an
  existing one). `check` makes one more time-limited call at every session start. `verify`, which has no network
  call today, reads GitHub's default branch through `gh` and skips that one comparison when it cannot. The suite
  stays offline, so its checks run against a stand-in `gh` and a local remote.
- A session that is already open when the default branch changes keeps the old `origin/HEAD` until its next start;
  whoever makes the switch tells the people and agents working at that moment.
- Open pull requests keep their old base: GitHub does not move them when the default branch changes. orion says so
  and names the command (`gh pr edit <N> --base <development branch>`); it never moves them itself.
- A workflow in the project that runs only on a push to the old default branch (CI, a deploy) gets no run for a
  merge into the new development branch until the project adds it. A workflow started by hand or on a schedule
  with no branch named runs on the new default branch from then on, and a deploy environment that allows only the
  old branch rejects it. orion says both when it switches the default; it never edits a project's workflows or
  environments.
- The release branch is written in two places (`config.json` for the check, `CLAUDE.md` for the agents).
  `/orion-verify` reads both and reports a disagreement.
- The product description changes: the PRD's "Default branch" and "Release" entries say the skills only look the
  branch up and that a release branch is named only in `CLAUDE.md`; this record adds the question at install and the
  GitHub step.

## Alternatives

- **Also write branch protection** (GitHub rules that block a direct push and require a pull request) on both
  branches. It would enforce "never push to the release branch" on the server, but GitHub does not offer it for
  private repositories on every plan, teams usually keep their own protection rules, and a wrong rule blocks a
  team's work. Rejected by the owner for now.
- **Record the names only** and let `verify` warn until a person changes GitHub by hand. No new reach for orion, but
  it keeps the manual step this decision exists to remove.
- **Keep the plan as it was** (look the default branch up, ask nothing). Nothing to build, but a project that wants
  the split gets no help and no warning when it is half set up.
