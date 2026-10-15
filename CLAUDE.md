Mandatory rules, owned by this repository and imported straight from the source every project gets a copy of: @baselines/BASE_CLAUDE.md

# CLAUDE.md — working rules for the orion skills repo

This repo is a collection of **general-purpose, publicly distributable** Claude Code skills. Anyone can clone it and run these skills against any user and any repository. That single fact drives the rules below.

## This repo runs on its own rules

- The import line at the top reads `baselines/BASE_CLAUDE.md` **directly from the repo**, not a copy under `.claude/orion/`. A pull request that changes the baseline therefore changes this repo's own rules in the same commit; there is no `orion update` step and nothing to keep in sync. Keep the import pointing at `baselines/`.
- **Never run `orion init` against this checkout.** It would copy `skills/` into `.claude/skills/` and the baseline into `.claude/orion/`, and that copy would go stale on every baseline edit.
- Everything below is what the baseline's last section says the project's `CLAUDE.md` must state, plus the rules that only make sense for this repo. Communication, work tracking, git, definition of done and the working rules live in the baseline and are **not repeated here**: a rule in this file must not contradict it, and on a contradiction the baseline wins.

## Build and test commands

| Purpose | Command |
|---|---|
| Build | `bash -n orion.sh` (a syntax check; there is nothing to compile) |
| **The full suite** | `d=$(mktemp -d) && bash orion.sh init --project "$d" --no-statusline --update-mode ask && bash orion.sh update --project "$d" --force && bash orion.sh check --project "$d" --force && bash orion.sh uninstall --project "$d" --yes && [ ! -e "$d/.claude/orion" ] && [ ! -e "$d/.claude/skills" ] && ! grep -qi orion "$d/CLAUDE.md" "$d/.claude/settings.json"` (the init/update/check/uninstall round trip against an empty folder; uninstall keeps the starter `CLAUDE.md` and an empty `settings.json` on purpose, so the check is that nothing orion owns is left behind) |
| One file | `bash -n orion.sh` · `python3 -m py_compile skills/issue-map/scripts/issue_map.py` (`python` on Windows) |
| Typecheck / static analysis | `powershell -NoProfile -Command "[scriptblock]::Create((Get-Content -Raw orion.ps1)) > \$null"` (parses `orion.ps1` with Windows PowerShell 5.1; Windows only) |
| Lint | `grep -L -E '^description: ["'\'']?ORION - ' skills/*/SKILL.md` (lists every skill whose description lacks the `ORION - ` prefix; must print nothing) |

Run the build, the lint and the typecheck after any edit; the full suite runs before any pull request opens (the baseline's gate) and after every edit to `orion.sh` or `orion.ps1`. "Done" = every edited `.md` renders without parse errors, the lint prints nothing, and the round trip is clean. CI (`.github/workflows/ci.yml`) runs the same commands on every pull request.

## Stack and layout

- Stack: **bash** for `orion.sh` (runs under Git Bash, macOS bash and Linux, so no GNU-only flags), **Windows PowerShell 5.1** for `orion.ps1` (pure ASCII; it only finds Git Bash and runs `orion.sh`), **Python 3.9+, standard library only** for `skills/issue-map/scripts/issue_map.py`, Markdown for every skill. No test framework: the round trip above is the suite. CI runs on GitHub Actions (an Ubuntu job for bash and Python, a Windows job for the PowerShell parse).
- Layout: `skills/<name>/` is the product (one folder per skill), `baselines/` holds `BASE_CLAUDE.md` and the status line, `docs/PRDs/` the PRDs, `docs/CHANGELOG.md` the changelog. There is no separate test code path. Skip-count baseline: 0.

## Worktrees

- Worktree root (outside the project): `../orion-wt/`, a sibling folder of the checkout, one sub-folder per branch. No port rule: orion runs no server.

## Boundaries

- Deploys to: nowhere. The product is this repository on `main`; every project's `orion update` clones `main` with `git clone --depth 1`. A merge to `main` is the release.
- External read-only repositories: none.
- Sensitive data classes that never enter the repository: everything listed under "Distribution safety" below (people, organizations and products, repositories and infrastructure, locale tells, real identifiers from a source project, machine specifics).
- Boundaries an agent must not move: skills are self-contained and never reference orion repo files; work-specific skills never land here; the `check` sub-command stays silent on success and exits 0 on every failure; `update` and `uninstall` touch only what carries the `.orion-managed` marker or sits in `.orion-manifest`.
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
- **CHANGELOGs:** required for the `-vN` skills; optional for in-place skills — an in-place skill *may* keep a `CHANGELOG.md` for notable behaviour changes, and if it has one, keep it updated. `docs/CHANGELOG.md` is the repo-wide one the baseline asks every pull request to add its line to.
- When historical CHANGELOG entries mention the *old* skill name, leave them — they're an accurate record of that version; only operational references point at the current name.

## How the repo is wired

The root `README.md` is a short, non-technical overview and install guide for people — keep it that way; the detailed facts for agents live here:

- orion is installed **into a project**, never at user level. `orion.sh` (bash; `orion.ps1` is only a Windows launcher that finds Git Bash and runs it) has the sub-commands `init | update | check | verify | status | uninstall`. `init` copies each `skills/<name>/` into `<project>/.claude/skills/<name>/` with an `.orion-managed` marker, copies `baselines/BASE_CLAUDE.md` → `<project>/.claude/orion/BASE_CLAUDE.md`, the script itself and a `VERSION` file (commit SHA) into `<project>/.claude/orion/`, creates `<project>/CLAUDE.md` if missing from the slot-only starter embedded in `orion.sh` (otherwise only adds the import line for `.claude/orion/BASE_CLAUDE.md` at the top, replacing the pre-rename `@.claude/orion/ORION.md` line if present), creates `config.json` once (`updateMode`: `ask`/`auto`/`off`, from `--update-mode` or an interactive question when stdin is a TTY, default `ask`), and adds one `SessionStart` hook (`orion.sh check`) to `<project>/.claude/settings.json`. Ownership keys off the marker and the `.orion-manifest` list: `update`/`uninstall` touch only those, never the project's `CLAUDE.md`, `config.json`, unmarked skills, or other settings.
- **Editing the repo does NOT update any project — every project runs `orion update`** (offered at session start by the hook in `ask` mode). The project copy of `orion.sh` fetches orion with `git clone --depth 1` from the `source`/`ref` in its `config.json`; when `orion.sh` runs from inside this checkout it uses the checkout directly (handy for testing: `bash orion.sh init --project <tmp-dir>`).
- The `check` sub-command is a hook: it must stay silent on success, exit 0 on every failure, and print only the single-line `hookSpecificOutput` JSON when an update exists or when the one-shot post-install marker is pending. Settings edits go through `jq` → `python3` → Windows PowerShell fallbacks; keep all three branches in step.
- **`init` asks for one post-install check.** It leaves a per-computer marker in the cache dir (`~/.cache/orion/<hash>.verify-pending`, never in the project); the next `check` consumes it and asks Claude Code to run `/orion-verify` instead of checking for an update. The `verify` sub-command is the mechanical half of that check (one line per finding, `ok`/`WARN`/`FAIL`, exit 1 on a `FAIL`, never a fix, also consumes the marker); the `orion-verify` skill runs it, fixes the `FAIL`s, then reviews `CLAUDE.md`, the project's own skills and the settings against `BASE_CLAUDE.md`, asking before it touches anything the project owns. `uninstall` removes the marker.
- `baselines/` holds `BASE_CLAUDE.md` (**the one rules file**: every mandatory rule for every project, overwritten in projects on update — keep it generic and slot-free; anything project-specific is a slot in the starter `CLAUDE.md` that `orion.sh` writes once, and the last section of `BASE_CLAUDE.md` lists what that starter must state; keep its "this file wins on a contradiction" note) and `statusline/` (per-computer, copied **once** to `~/.claude/statusline` on `init --statusline`, never touched by `update`, no `.orion-managed` marker). Edited in place in the repo. **This repo imports that same file at the top of this `CLAUDE.md`**, so a change to it is read back against this file for new contradictions in the same pull request, exactly as the baseline asks of every project.
- `SKILL.md` (uppercase) is the required entry-point file in every skill folder; longer skills also carry `README.md`, `PREREQUISITES.md`, `CHANGELOG.md`, a `prompts/` folder, or a `references/` folder of files the skill loads on demand (`dev-next`).
- **A skill that needs anything from the project or the machine ships a `VERIFY.md`** beside its `SKILL.md` (`dev-next` and `issue-map` are the worked examples): a short table of read-only checks — what must hold, how to check it, what to do when it fails. `/orion-verify` reads every `VERIFY.md` under `.claude/skills/*/` and runs the checks, so a new skill is covered by the post-install check the moment it ships, with no change to `orion-verify`. Never name a skill inside `orion-verify`; keep it driven by what is on disk.
- `dev-next`, `harvest` and `dev-quick` ship together: `harvest` reads the audit reports `dev-next` writes and follows `dev-next`'s `references/new-issue.md`; `dev-quick` files an issue to that same file's shape and then invokes `dev-next` as its engine (never copies it).
- `prd-to-tickets` is the planning front of that set: it reads one PRD under `docs/PRDs/` and files the epics and stories to `references/new-issue.md`'s shape. Its first message checks `docs/ux/prototypes/` for the screens the PRD describes (the prototype rule is the baseline's; the sub-agent that drafts one is this skill's). It rebuilds `issue-map` silently at the end when installed.
- `harvest-qa` is the QA half of the harvest: `dev-next` writes a `qa-<N>.json` record beside every merged story's run report on the audit branch (the dev agent's `QA checks` blocks and a short user-level story of what changed, per `references/audit.md`), and `harvest-qa` reads only those, dedupes them (superseded by key, obsolete, already tracked, nothing to test — every decision logged and counted as tested), drives the rest against `main` one `qa-<seam>` agent at a time (the product is a shared port and database), files `bug` issues to `references/new-issue.md`'s shape, and keeps its bookmark and log in `docs/harvest-qa-state.json`. `harvest` reads only `issue-<N>.json` and `docs/harvest-state.json`; neither skill touches the other's files. The `QA due` and `Harvest due` counts `dev-next` prints are the baseline's numbers.
- `issue-map` is the fourth of that set: `dev-next` calls it with `--silent` after every claim and merge (when installed), and it reads the same `### Blocked by` section, labels and native links that `references/new-issue.md` defines. Its generator (`scripts/issue_map.py`, Python 3.9+, stdlib only) writes a never-committed snapshot into the main checkout and excludes it through `.git/info/exclude`, so it never dirties a project.
- `reconcile-issue-map` is the fifth: the check that the issues, the PRDs under `docs/PRDs/` and the code on `main` still agree (four lenses: PRD → issues, issues → PRD, map health, product reality). It reads `references/new-issue.md` as the shape, runs `issue-map`'s generator for its footer when installed, and keeps a bookmark in `docs/reconcile-state.json` (last reconciled commit plus accepted findings). The three mechanical drift signs `dev-next` probes in its phase 6 are the ones the baseline lists.
- `clear-git-resources` is the sweep behind all of them: `dev-next` deletes its own worktree and branches when a story merges, but nothing cleans up after a failed run or a human-merged pull request (`harvest`, `reconcile-issue-map`, `prd-to-tickets`, `wayfinder`). Its scanner (`scripts/scan.sh`, portable bash, read-only) lists worktrees, local and remote branches and the worktree root in three kinds — safe (work already on the default branch, pull request merged or closed, remote branch gone, folder that is not a worktree), needs the person's word (commits not on the default branch, uncommitted changes), never offered (the default branch, `audit/*`, open pull requests, `in-flight.json` entries, other repositories' checkouts) — each with the exact delete command; the skill runs only the commands the person agreed to. The `check` hook counts branches (local plus remote-tracking, `HEAD` excluded, no network) once a day with the same expression as the scanner (`branch_count`), only when the skill is installed, and offers it at `branchLimit` (`config.json`, default 20, a number or `off`; `init` writes the key, `status` and `verify` read it). A second message from `check` is joined to the update message, so the hook still prints one JSON line.

## Conventions for changes here

- Skills are project-agnostic: detect build/test/stack commands and conventions from the target repo at run time; don't assume a stack.
- A new skill with prerequisites (a tool, a sign-in, a `CLAUDE.md` slot) ships a `VERIFY.md` so `/orion-verify` checks them after install (see "How the repo is wired").
- **Every skill's `description` starts with `ORION - `** (the word, a space, a hyphen, a space), e.g. `description: ORION - Pick up the next GitHub issue …`. The prefix marks the skill as orion-managed in the user's skill list, so it is told apart from the project's own skills at a glance. Every new skill added to `skills/` must carry it, keep it when rewording a description, and the lint above checks it.
- **Skills are self-contained by design** — they're copied standalone into the project's `.claude/skills/`, so they can't reference orion repo files. Shared boilerplate (the Windows BOM workaround, the mandatory dedupe deep-dive text, palette values shared across report skills, …) is therefore *intentionally duplicated*; when correcting such a block, `git grep` for every copy and fix all of them, never "factor it out."
- Keep `orion.ps1` pure-ASCII and Windows-PowerShell-5.1-compatible; keep `orion.sh` free of GNU-only flags (it runs under Git Bash, macOS bash and Linux).
- Commit/push only when the user asks; commit messages end with the required `Co-Authored-By` trailer.

## Asking the user questions

- When you need to ask the user something, **list the questions** and use the clickable-options format (the AskUserQuestion tool): offer distinct options per question, mark your recommendation, and let the user pick by clicking.
- Phrase every question and option **for a junior developer with zero knowledge of the tech stack or the company domain** — plain language, no unexplained technical concepts, define any jargon or acronym on first use.
