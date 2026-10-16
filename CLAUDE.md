Mandatory rules, owned by this repository and imported straight from the source every project gets a copy of: @baselines/BASE_CLAUDE.md

# CLAUDE.md — working rules for the orion skills repo

This repo is a collection of **general-purpose, publicly distributable** Claude Code skills. Anyone can clone it and run these skills against any user and any repository. That single fact drives the rules below.

## This repo runs on its own rules

- The import line at the top reads `baselines/BASE_CLAUDE.md` **directly from the repo**, not a copy under `.claude/orion/`. A pull request that changes the baseline therefore changes this repo's own rules in the same commit (so that pull request also re-reads this file for new contradictions); there is no `orion update` step and nothing to keep in sync. Keep the import pointing at `baselines/`.
- **Never run `orion init` against this checkout.** It would copy `skills/` into `.claude/skills/` and the baseline into `.claude/orion/`, and that copy would go stale on every baseline edit.
- Everything below is what the baseline's last section says the project's `CLAUDE.md` must state, plus the rules that only make sense for this repo. Communication, work tracking, git, definition of done and the working rules live in the baseline and are **not repeated here**.

## Build and test commands

| Purpose | Command |
|---|---|
| Build | `bash -n orion.sh` (a syntax check; there is nothing to compile) |
| **The full suite** | `bash tests/run.sh` (syntax checks, then `orion.sh` end to end against throw-away projects in a sandbox: the init/update/check/uninstall round trip, every settings editor (jq, python, PowerShell where present) on a settings file with a byte-order mark, the `check` hook (silent or one JSON line, always exit 0, a failing and a working auto-update), the post-install marker, `verify`, `status`, the branch counter against `scan.sh`, config escaping and the manifest; no network, nothing left behind; prints one line per check and exits 1 on any failure) |
| One file | `bash -n orion.sh` · `bash -n skills/clear-git-resources/scripts/scan.sh` · `python3 -m py_compile skills/issue-map/scripts/issue_map.py skills/generate-project-writeup/assets/build_docx.py` (`python` on Windows) |
| Typecheck / static analysis | `powershell -NoProfile -Command "[scriptblock]::Create((Get-Content -Raw orion.ps1)) > \$null"` (parses `orion.ps1` with Windows PowerShell 5.1; Windows only) |
| Lint | `grep -L -E '^description: ["'\'']?ORION - ' skills/*/SKILL.md` (lists every skill whose description lacks the `ORION - ` prefix; must print nothing) |

Run the build, the lint and the typecheck after any edit, and the full suite after every edit to `orion.sh`, `orion.ps1`, `scan.sh` or `tests/run.sh`, and always before a pull request opens; every edited `.md` must still render without parse errors. CI (`.github/workflows/ci.yml`) runs the same chain on every pull request. Commits carry an empty email or a GitHub no-reply address (`*@users.noreply.github.com`, `noreply@github.com`), so no real email address enters the public history; check with `git config user.email` before committing. CI's `commit-emails` job rejects any other email on a pull request's commits and on every push to `main`.

## Stack and layout

- Stack: **bash** for `orion.sh` (runs under Git Bash, macOS bash and Linux, so no GNU-only flags), **Windows PowerShell 5.1** for `orion.ps1` (pure ASCII; it only finds Git Bash and runs `orion.sh`), **Python 3.9+, standard library only** for `skills/issue-map/scripts/issue_map.py`, Markdown for every skill. No test framework: `tests/run.sh` (plain bash) is the suite. CI runs on GitHub Actions: an Ubuntu job for bash and Python, a Windows job for the PowerShell parse and the suite under Git Bash, and a job that checks commit emails.
- Layout: `skills/<name>/` is the product (one folder per skill), `baselines/` holds `BASE_CLAUDE.md` and the status line, `docs/PRDs/` the PRDs, `docs/CHANGELOG.md` the changelog. The suite lives in `tests/`. Skip-count baseline: 0.

## Worktrees

- Worktree root (outside the project): `../orion-wt/`, a sibling folder of the checkout, one sub-folder per branch. No port rule: orion runs no server.

## Boundaries

- Deploys to: nowhere. The product is this repository on `main`; a merge to `main` is the release, and every project's `orion update` fetches it from there.
- External read-only repositories: none.
- Sensitive data classes that never enter the repository: everything listed under "Distribution safety" below (people, organizations and products, repositories and infrastructure, locale tells, real identifiers from a source project, machine specifics).
- Boundaries an agent must not move: skills are self-contained and never reference orion repo files; work-specific skills never land here; the `check` sub-command stays silent on success and exits 0 on every failure; `update` and `uninstall` touch only what carries the `.orion-managed` marker or sits in `.orion-manifest` (never the project's `CLAUDE.md`, `config.json`, unmarked skills or other settings).
- Working language for code, comments, commits, issues and docs: English.

## Distribution safety — never leak sensitive or specific data (highest-priority rule)

When creating or editing **anything** in this repo, do not introduce data that identifies a specific person, team, company, product, repository, or environment. This is non-negotiable and applies **in any shape or form** — prose, examples, code, comments, placeholders, file or branch names, and **git metadata** (commit messages, PR titles, PR bodies).

Treat the following as sensitive and keep them OUT:

- **People** — names, usernames/handles, emails, initials, org/employee IDs.
- **Organizations & products** — company names, team names, product/project names, internal codenames, customer names.
- **Repositories & infrastructure** — private repo/org slugs, internal URLs, hostnames, service names, bucket/DB/table names, queue/topic names.
- **Locale / region tells** — a specific human language or country set used as an example (e.g. naming the exact languages a product supports, locale-specific persona names, region codes). Say "the project's supported locales / the user's language" instead.
- **Real identifiers from a source project** — actual issue/PR numbers, story/ticket IDs, storage keys, file paths, test-file names, commit SHAs.
- **Machine specifics** — absolute user paths (`C:\Users\<name>\…`, `/home/<name>/…`), home folder names, machine names. Use home-relative (`~/.claude`, `~/Downloads`) or `<placeholder>` forms.

Instead, **use generic placeholders** the skill resolves at runtime: `<repo-name>`, `<gh-login>`, `<N>` / `#<N>`, `<test-file>`, `<locale-key>`, `<lang>`, `<role-1>`, etc. Skills must detect everything project-specific from the target repo's own files (`package.json`, `*.csproj`, `CLAUDE.md`, `README.md`, …) at run time — never hard-code it here.

This applies even when a task's source material (a handoff note, a report, a transcript, an existing private repo) contains such specifics: extract the **general** lesson or behavior, and leave the identifying details behind. If two repos are involved in a task, name only the one this repo *is*; refer to any other as "the downstream/application repo" without its real slug.

**Self-check before every commit or PR:** scan the diff *and* the commit message / PR body for the categories above (a quick `git grep -niE`/`git log`/`gh pr view` pass for likely tells). If you find one, generalize it before pushing. If something already leaked into pushed git metadata, edit the PR body yourself, but scrubbing a commit message needs a force-push, which the baseline forbids: stop and ask the user, and tell them the leak may persist in the host's unreachable-object storage until GC even after a scrub.

> Work-specific skills (anything referencing a specific product, team, or internal workflow) do **not** belong in this repo — they live only on the machines that need them.

## Versioning convention

- For any skill carrying a **`-vN`** suffix (none at present — the convention is kept for future pipeline-style skills): prefer creating a **new version** (copy to a bumped `-vN` suffix) over editing in place — people and automated workflows may depend on the current behaviour. Add a CHANGELOG entry describing the deltas and leave the prior version as-is.
- All current skills (e.g. `project-handover`) have **no `-vN` convention** and are edited in place. Each skill's top-of-file editor note states which applies.
- **CHANGELOGs:** required for the `-vN` skills; optional for in-place skills — an in-place skill *may* keep a `CHANGELOG.md` for notable behaviour changes, and if it has one, keep it updated. `docs/CHANGELOG.md` is the repo-wide one.
- When historical CHANGELOG entries mention the *old* skill name, leave them — they're an accurate record of that version; only operational references point at the current name.

## How the repo is wired

The root `README.md` is a short, non-technical overview and install guide for people — keep it that way; the detailed facts for agents live here:

- orion is installed **into a project**, never at user level. `orion.sh` (bash; `orion.ps1` is only a Windows launcher that finds Git Bash and runs it) has the sub-commands `init | update | check | verify | status | uninstall`. `init` copies each `skills/<name>/` into `<project>/.claude/skills/<name>/` with an `.orion-managed` marker, copies `baselines/BASE_CLAUDE.md` → `<project>/.claude/orion/BASE_CLAUDE.md`, the script itself and a `VERSION` file (commit SHA) into `<project>/.claude/orion/`, creates `<project>/CLAUDE.md` if missing from the slot-only starter embedded in `orion.sh` (otherwise only adds the import line for `.claude/orion/BASE_CLAUDE.md` at the top, replacing the pre-rename `@.claude/orion/ORION.md` line if present), creates `config.json` once (`updateMode`: `ask`/`auto`/`off`, from `--update-mode` or an interactive question when stdin is a TTY, default `ask`), and adds one `SessionStart` hook (`orion.sh check`) to `<project>/.claude/settings.json`.
- **Editing the repo does NOT update any project — every project runs `orion update`** (offered at session start by the hook in `ask` mode). The project copy of `orion.sh` fetches orion with `git clone --depth 1` from the `source`/`ref` in its `config.json`; when `orion.sh` runs from inside this checkout it uses the checkout directly (handy for testing: `bash orion.sh init --project <tmp-dir>`).
- The `check` sub-command is a hook (its silent-on-success, exit-0 contract is under Boundaries): it prints only the single-line `hookSpecificOutput` JSON when an update exists or when the one-shot post-install marker is pending. Settings edits go through `jq` → `python3` → Windows PowerShell fallbacks; keep all three branches in step.
- **`init` asks for one post-install check.** It leaves a per-computer marker in the cache dir (`~/.cache/orion/<hash>.verify-pending`, never in the project); the next `check` consumes it and asks Claude Code to run `/orion-verify` instead of checking for an update. The `verify` sub-command is the mechanical half of that check (one line per finding, `ok`/`WARN`/`FAIL`, exit 1 on a `FAIL`, never a fix, also consumes the marker); the `orion-verify` skill runs it, fixes the `FAIL`s, then reviews `CLAUDE.md`, the project's own skills and the settings against `BASE_CLAUDE.md`, asking before it touches anything the project owns. `uninstall` removes the marker.
- `baselines/` holds `BASE_CLAUDE.md` (**the one rules file**: every mandatory rule for every project, overwritten in projects on update — keep it generic and slot-free; anything project-specific is a slot in the starter `CLAUDE.md` that `orion.sh` writes once, and the last section of `BASE_CLAUDE.md` lists what that starter must state; keep its "this file wins on a contradiction" note) and `statusline/` (per-computer, copied **once** to `~/.claude/statusline` on `init --statusline`, never touched by `update`, no `.orion-managed` marker). Edited in place in the repo.
- `SKILL.md` (uppercase) is the required entry-point file in every skill folder; longer skills also carry `README.md`, `PREREQUISITES.md`, `CHANGELOG.md`, a `prompts/` folder, or a `references/` folder of files the skill loads on demand (`dev-next`).
- **A skill that needs anything from the project or the machine ships a `VERIFY.md`** beside its `SKILL.md` (`dev-next` and `issue-map` are the worked examples): a short table of read-only checks — what must hold, how to check it, what to do when it fails. `/orion-verify` reads every `VERIFY.md` under `.claude/skills/*/` and runs the checks, so a new skill is covered by the post-install check the moment it ships, with no change to `orion-verify`. Never name a skill inside `orion-verify`; keep it driven by what is on disk.
- `dev-next` is the engine of the set and the others are wired to its files: `dev-quick` invokes it (never copies it); `harvest` reads the `issue-<N>.json` reports it writes and keeps its bookmark in `docs/harvest-state.json`; `harvest-qa` reads the `qa-<N>.json` records it writes beside those reports (shape in `references/audit.md`) and keeps its bookmark and log in `docs/harvest-qa-state.json`; `prd-to-tickets` owns the sub-agent that drafts a UX prototype (the rule itself is the baseline's) and rebuilds `issue-map` silently at the end when installed; `reconcile-issue-map` keeps its bookmark in `docs/reconcile-state.json` and runs `issue-map`'s generator for its footer when installed.
- Every skill that files or reads issues (`dev-quick`, `prd-to-tickets`, `harvest`, `harvest-qa`, `issue-map`, `reconcile-issue-map`) takes the body headings, labels and link forms from `dev-next`'s `references/new-issue.md`, so an edit there is an edit to all of them. The `Harvest due` and `QA due` thresholds `dev-next` counts and the three drift signs it probes in its phase 6 are the baseline's: change them in both places together.
- `issue-map` is what `dev-next` calls with `--silent` after every claim and merge (when installed); its generator (`scripts/issue_map.py`) writes the never-committed snapshot into the main checkout and excludes it through `.git/info/exclude`, so it never dirties a project.
- `clear-git-resources` is the sweep behind all of them: `dev-next` deletes its own worktree and branches when a story merges, but nothing cleans up after a failed run or a human-merged pull request (`harvest`, `reconcile-issue-map`, `prd-to-tickets`, `wayfinder`). Its scanner (`scripts/scan.sh`, portable bash, read-only) lists worktrees, local and remote branches and the worktree root in three kinds — safe (work already on the default branch, pull request merged or closed, remote branch gone, folder that is not a worktree), needs the person's word (commits not on the default branch, uncommitted changes), never offered (the default branch, `audit/*`, open pull requests, `in-flight.json` entries, other repositories' checkouts) — each with the exact delete command; the skill runs only the commands the person agreed to. The `check` hook counts branches (local plus remote-tracking, `HEAD` excluded, no network) once a day with the same expression as the scanner (`branch_count`), only when the skill is installed, and offers it at `branchLimit` (`config.json`, default 20, a number or `off`; `init` writes the key, `status` and `verify` read it). A second message from `check` is joined to the update message, so the hook still prints one JSON line.

## Conventions for changes here

- **Every skill's `description` starts with `ORION - `** (the word, a space, a hyphen, a space), e.g. `description: ORION - Pick up the next GitHub issue …`. The prefix marks the skill as orion-managed in the user's skill list, so it is told apart from the project's own skills at a glance. Every new skill added to `skills/` must carry it, keep it when rewording a description, and the lint above checks it.
- **Skills are self-contained by design** (see Boundaries): they're copied standalone into the project's `.claude/skills/`, so shared boilerplate (the Windows BOM workaround, the mandatory dedupe deep-dive text, palette values shared across report skills, …) is *intentionally duplicated*; when correcting such a block, `git grep` for every copy and fix all of them, never "factor it out."
- Commit/push only when the user asks; commit messages end with the required `Co-Authored-By` trailer.

## Asking the user questions

- When you need to ask the user something, **list the questions** and use the clickable-options format (the AskUserQuestion tool): offer distinct options per question, mark your recommendation, and let the user pick by clicking.
- Phrase every question and option **for a junior developer with zero knowledge of the tech stack or the company domain** — plain language, no unexplained technical concepts, define any jargon or acronym on first use.
