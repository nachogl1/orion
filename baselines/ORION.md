# ORION.md — standing rules shipped by orion

> **Owned by orion.** This file is copied into `.claude/orion/ORION.md` by `orion init` and **overwritten on every
> `orion update`**. Do not edit it here: put the project's own rules in the project's `CLAUDE.md`, which imports this
> file.
>
> **The two files must never contradict each other.** Before writing or changing a rule in the project's `CLAUDE.md`,
> check it against this file: if it conflicts, drop it or rewrite it so both agree. After every `orion update` that
> changed this file, re-read the project's `CLAUDE.md` for new conflicts and fix them in the same commit. If a
> contradiction slips through anyway, the project's `CLAUDE.md` wins — a safety net, not a licence to override.

## Communication

- TLDR first. One-liners. Numbered steps, one action per line. End with exactly one next action.
- Five lines max unless asked for more; several topics become one line each, never casualties.
- Never refer to a thing by its number alone — `issue #12 (parse the dataset section)`, never a bare `#12`.
- No preamble, no recap, no sign-off. Problems (bugs, risks, failures) come first and are never cut for length.
- Never guess. Check the code, the docs or the running command before stating something; label assumptions as such.

## Git

- **Never push to `main`.** Every change reaches `main` as a merged pull request from a `feat/<desc>` / `fix/<desc>`
  branch (or the project's own branch pattern).
- Never force-push, never bypass hooks (`--no-verify`), never `git add -A`, never rebase or stash someone else's work,
  never delete work you did not create.
- Never merge on red or pending checks; "no checks reported" counts as red — poll for the check run first, the host can
  take minutes. Never auto-merge unless the project's `CLAUDE.md` says who may.
- Conventional Commits: `type(scope): summary`.

## Definition of done

- Full build and full test suite green before the pull request opens, run for real — reading the code is not proof.
- Never delete, skip or weaken a test. Never widen a timeout to make a run pass.
- Pre-existing failures are still your responsibility: fix them or surface them explicitly and get an acknowledgement.
- When something fails twice, stop and find the root cause instead of retrying.

## Working

- Smallest change that works: what was asked and no more. No refactors of untouched code, no speculative abstractions.
- Take every reversible decision yourself, simplest option that meets the acceptance criteria, recorded in the pull
  request. Only a genuinely irreversible decision goes back to a human.
- Deferred findings: small, safe **and** in a file already being changed → fix now. Critical → a tracker issue.
  Everything else is written down once, never filed "to be safe". Before filing any issue, search the code and the open
  issues for something that already covers it; never defer to a **closed** issue.
- Sub-agents: name each one after what it does (`review-auth-tests`, never `agent-3`); mechanical work runs on a
  cheap model at low effort, hard decisions and reviews on the top model; every spawn prompt asks for a bounded result
  (a verdict plus a few bullets, never an essay). A sub-agent never uses `git stash` and never switches branches — it
  works in its own worktree — commits only the files it touched, and on failure reports and stops instead of
  attempting its own recovery.
- Secrets live only in gitignored env files; never in code, issues, pull requests or committed files. No personal or
  production data anywhere in the repository.

## Skills

- Skills under `.claude/skills/` carrying an `.orion-managed` marker are orion's and are refreshed by `orion update`;
  the project's own skills (no marker) are never touched.
- `/orion` manages the installation: `status`, `check`, `update`, `uninstall`.
