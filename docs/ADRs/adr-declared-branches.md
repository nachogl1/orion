# ADR — a project declares its development and release branches at install, and orion sets GitHub's default branch to match

**Status: pending**

## Context

The develop-branch map decided that the shared rules and the skills stop naming `main` for daily work and look up
**the repository's default branch** instead, and that a release branch, if a project has one, is named in the
project's `CLAUDE.md`. Under that plan `orion.sh` does not change: `init` asks nothing about branches, and nothing
orion ships ever touches a project's GitHub settings.

That leaves a project that wants the same split as orion (daily work on one branch, releases from another) to set
it up by hand: create the branch, change GitHub's default branch in the repository settings, and write the release
branch into `CLAUDE.md`. Until all three are done, the skills keep reading the old default branch and merge daily
work into the branch the project releases from. Nothing tells the person which step is missing.

## Decision

1. **`init` asks for two branch names**: the **development branch** (where daily work starts from and merges into)
   and the **release branch** (the branch the project deploys from). It asks when stdin is a terminal, the same way
   it asks for the update mode, and takes them from `--dev-branch <name>` and `--release-branch <name>` otherwise.
   Both default to the repository's current default branch, so an install that answers neither behaves as today.
2. **The same name for both means a one-branch project**: no release branch, no release pull request, nothing
   changed on GitHub.
3. **The names are kept in `.claude/orion/config.json`** as `developBranch` and `releaseBranch`: the person's file,
   written once by `init` and never touched by `update`. The starter `CLAUDE.md` that `init` writes names the release
   branch in its deploy line, and the baseline's list of what a project's `CLAUDE.md` must state gains both names.
4. **`init` makes GitHub match, and only this far**: it creates a declared branch that does not exist yet (from the
   current default branch) and sets the development branch as the repository's default branch
   (`gh repo edit --default-branch <name>`), then runs `git remote set-head origin --auto` in the checkout. It does
   this only when a declared name differs from what GitHub has now. **It never writes branch protection or any other
   repository setting.**
5. **A step that cannot run never fails the install.** Without `gh`, without a GitHub remote, or without the right
   to change the default branch (only a repository admin has it), `init` prints the one step a person must do by
   hand and goes on.
6. **GitHub's default branch stays what the skills read.** They keep looking it up at run time, as the
   develop-branch map decided; the two keys in `config.json` record what the project declared, so a disagreement can
   be seen.
7. **`verify` warns, existing installs included**: one `WARN` when the keys are missing (an install from before
   this decision), one when GitHub's default branch is not the declared development branch (when `gh` can read it),
   and one when this checkout's `origin/HEAD` still points at another branch. `/orion-verify` then asks for the
   names, or offers the same steps as `init`, and acts only on the person's yes.
8. **Only `init`, and `/orion-verify` on the person's yes, change GitHub.** `update`, `check` and `uninstall` never
   do; `uninstall` leaves the branches and the default branch as they are.

## Consequences

- orion changes a repository setting for the first time. It is the one setting the skills depend on, changed only
  on the names the person gave, and it is undone with the same command.
- `init` gains an optional use of `gh` and of the network. The suite stays offline, so its checks run against a
  stand-in `gh`.
- Open pull requests keep their old base: GitHub does not move them when the default branch changes. `init` says so
  and names the command (`gh pr edit <N> --base <development branch>`); it never moves them itself.
- Every other clone of the project keeps reading the old default branch until `git remote set-head origin --auto`
  runs there; the `origin/HEAD` warning in decision 7 is what tells each person.
- A workflow in the project that runs only on a push to the old default branch (CI, a deploy) gets no run for a
  merge into the new development branch until the project adds it. `init` says so; orion never edits a project's
  workflows.
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
