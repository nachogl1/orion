# CLAUDE.md — working rules for the orion skills repo

This repo is a collection of **general-purpose, publicly distributable** Claude Code skills. Anyone can clone it and run these skills against any user and any repository. That single fact drives the rules below.

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

**Self-check before every commit or PR:** scan the diff *and* the commit message / PR body for the categories above (a quick `git grep -niE`/`git log`/`gh pr view` pass for likely tells). If you find one, generalize it before pushing. If something already leaked into pushed git metadata, scrub it (amend + `--force-with-lease`; edit the PR body) and tell the user it may persist in the host's unreachable-object storage until GC.

> Work-specific skills (anything referencing a specific product, team, or internal workflow) do **not** belong in this repo — they live only on the machines that need them.

## Versioning convention

- For any skill carrying a **`-vN`** suffix (none at present — the convention is kept for future pipeline-style skills): prefer creating a **new version** (copy to a bumped `-vN` suffix) over editing in place — people and automated workflows may depend on the current behaviour. Add a CHANGELOG entry describing the deltas and leave the prior version as-is.
- All current skills (e.g. `project-handover`) have **no `-vN` convention** and are edited in place. Each skill's top-of-file editor note states which applies.
- **CHANGELOGs:** required for the `-vN` skills; optional for in-place skills — an in-place skill *may* keep a `CHANGELOG.md` for notable behaviour changes, and if it has one, keep it updated.
- When historical CHANGELOG entries mention the *old* skill name, leave them — they're an accurate record of that version; only operational references point at the current name.

## How the repo is wired

The root `README.md` is a short, non-technical overview and install guide for people — keep it that way; the detailed facts for agents live here:

- orion is installed **into a project**, never at user level. `orion.sh` (bash; `orion.ps1` is only a Windows launcher that finds Git Bash and runs it) has the sub-commands `init | update | check | verify | status | uninstall`. `init` copies each `skills/<name>/` into `<project>/.claude/skills/<name>/` with an `.orion-managed` marker, copies `baselines/BASE_CLAUDE.md` → `<project>/.claude/orion/BASE_CLAUDE.md`, the script itself and a `VERSION` file (commit SHA) into `<project>/.claude/orion/`, creates `<project>/CLAUDE.md` if missing from the slot-only starter embedded in `orion.sh` (otherwise only adds the import line for `.claude/orion/BASE_CLAUDE.md` at the top, replacing the pre-rename `@.claude/orion/ORION.md` line if present), creates `config.json` once (`updateMode`: `ask`/`auto`/`off`, from `--update-mode` or an interactive question when stdin is a TTY, default `ask`), and adds one `SessionStart` hook (`orion.sh check`) to `<project>/.claude/settings.json`. Ownership keys off the marker and the `.orion-manifest` list: `update`/`uninstall` touch only those, never the project's `CLAUDE.md`, `config.json`, unmarked skills, or other settings.
- **Editing the repo does NOT update any project — every project runs `orion update`** (offered at session start by the hook in `ask` mode). The project copy of `orion.sh` fetches orion with `git clone --depth 1` from the `source`/`ref` in its `config.json`; when `orion.sh` runs from inside this checkout it uses the checkout directly (handy for testing: `./orion.sh init --project <tmp-dir>`).
- The `check` sub-command is a hook: it must stay silent on success, exit 0 on every failure, and print only the single-line `hookSpecificOutput` JSON when an update exists or when the one-shot post-install marker is pending. Settings edits go through `jq` → `python3` → Windows PowerShell fallbacks; keep all three branches in step.
- **`init` asks for one post-install check.** It leaves a per-computer marker in the cache dir (`~/.cache/orion/<hash>.verify-pending`, never in the project); the next `check` consumes it and asks Claude Code to run `/orion-verify` instead of checking for an update. The `verify` sub-command is the mechanical half of that check (one line per finding, `ok`/`WARN`/`FAIL`, exit 1 on a `FAIL`, never a fix, also consumes the marker); the `orion-verify` skill runs it, fixes the `FAIL`s, then reviews `CLAUDE.md`, the project's own skills and the settings against `BASE_CLAUDE.md`, asking before it touches anything the project owns. `uninstall` removes the marker.
- `baselines/` holds `BASE_CLAUDE.md` (**the one rules file**: every mandatory rule for every project, overwritten in projects on update — keep it generic and slot-free; anything project-specific is a slot in the starter `CLAUDE.md` that `orion.sh` writes once, and the last section of `BASE_CLAUDE.md` lists what that starter must state; keep its "this file wins on a contradiction" note) and `statusline/` (per-computer, copied **once** to `~/.claude/statusline` on `init --statusline`, never touched by `update`, no `.orion-managed` marker). Edited in place in the repo.
- `SKILL.md` (uppercase) is the required entry-point file in every skill folder; longer skills also carry `README.md`, `PREREQUISITES.md`, `CHANGELOG.md`, a `prompts/` folder, or a `references/` folder of files the skill loads on demand (`dev-next`).
- **A skill that needs anything from the project or the machine ships a `VERIFY.md`** beside its `SKILL.md` (`dev-next` and `issue-map` are the worked examples): a short table of read-only checks — what must hold, how to check it, what to do when it fails. `/orion-verify` reads every `VERIFY.md` under `.claude/skills/*/` and runs the checks, so a new skill is covered by the post-install check the moment it ships, with no change to `orion-verify`. Never name a skill inside `orion-verify`; keep it driven by what is on disk.
- `dev-next`, `harvest` and `dev-quick` ship together: `harvest` reads the audit reports `dev-next` writes and follows `dev-next`'s `references/new-issue.md`; `dev-quick` files an issue to that same file's shape and then invokes `dev-next` as its engine (never copies it). All three work with **GitHub Issues only**; `BASE_CLAUDE.md` says the same.
- `prd-to-tickets` is the planning front of that set: it reads one PRD under `docs/PRDs/` and files the epics and stories to `references/new-issue.md`'s shape (scaffold → contract stories → fan-out, one seam per story, both blocker forms, native sub-issues, existing open issues as blockers). Its first message checks `docs/ux/prototypes/` and, when the PRD describes screens that have no prototype, offers to draft one from the PRD in parallel (a sub-agent, its own branch, a human merges) and blocks every front-end story on it. It rebuilds `issue-map` silently at the end when installed.
- `issue-map` is the fourth of that set: `dev-next` calls it with `--silent` after every claim and merge (when installed), and it reads the same `### Blocked by` section, labels and native links that `references/new-issue.md` defines. Its generator (`scripts/issue_map.py`, Python 3.9+, stdlib only) writes a never-committed snapshot into the main checkout and excludes it through `.git/info/exclude`, so it never dirties a project.
- `reconcile-issue-map` is the fifth: a human-run check that the issues, the PRDs under `docs/PRDs/` and the code on `main` still agree (four lenses: PRD → issues, issues → PRD, map health, product reality), fixing drift only on the person's word. It reads `references/new-issue.md` as the shape, runs `issue-map`'s generator for its footer when installed, and keeps a bookmark in `docs/reconcile-state.json` (last reconciled commit plus accepted findings). `dev-next` never runs it; its phase 6 probes three mechanical signs and prints `Drift found: run /reconcile-issue-map`, mirroring `Harvest due`.

## Filing issues — only when needed, dedupe first, and never defer to a dead issue

- **Only file a ticket when the work genuinely needs one.** A deferral is not an automatic ticket. Before filing, ask: is this real, actionable, and worth someone's time later? If yes, file it. If it's small enough to just do, do it now. If it's noise, drop it and say so in the reply. Filing "to be safe" grows a backlog nobody ever drains — every task then ends by producing more tickets instead of ending.
- **Before offering to file any new issue, do a deep dive first.** Search the actual code *and* the open issues to check whether something already covers what you're about to file — an existing open issue, or code that already implements/handles it. Don't propose a new issue until you've confirmed nothing already covers it. This has been gotten wrong repeatedly; treat the dedupe pass as mandatory, not optional.
- **Never defer to a closed issue.** Do not say "I won't do X because it's handled/tracked by issue #<N>" without first checking that #<N> is actually **open**. A closed issue means nobody will pick it up, so the work silently falls through the cracks. Before pointing at an existing issue as the reason to skip work, verify it's open; if it's closed (or doesn't really cover the case), either do the work or file/reopen a tracking issue.

## Conventions for changes here

- Skills are project-agnostic: detect build/test/stack commands and conventions from the target repo at run time; don't assume a stack.
- A new skill with prerequisites (a tool, a sign-in, a `CLAUDE.md` slot) ships a `VERIFY.md` so `/orion-verify` checks them after install (see "How the repo is wired").
- **Every skill's `description` starts with `ORION - `** (the word, a space, a hyphen, a space), e.g. `description: ORION - Pick up the next GitHub issue …`. The prefix marks the skill as orion-managed in the user's skill list, so it is told apart from the project's own skills at a glance. Every new skill added to `skills/` must carry it, keep it when rewording a description, and the verification pass below checks it.
- **Skills are self-contained by design** — they're copied standalone into the project's `.claude/skills/`, so they can't reference orion repo files. Shared boilerplate (the Windows BOM workaround, the mandatory dedupe deep-dive text, palette values shared across report skills, …) is therefore *intentionally duplicated*; when correcting such a block, `git grep` for every copy and fix all of them, never "factor it out."
- Keep `orion.ps1` pure-ASCII and Windows-PowerShell-5.1-compatible; keep `orion.sh` free of GNU-only flags (it runs under Git Bash, macOS bash and Linux).
- Commit/push only when the user asks; branch off `main` for changes; commit messages follow **Conventional Commits** (`type(scope): imperative summary`) and end with the required `Co-Authored-By` trailer.

## Planning & ticket creation

- When designing or planning a project and when producing tickets (GitHub issues, Jira, or any other tracker), **prioritise parallelism**: split the work into tasks and divide the domain according to the number of developers on the project, so every developer can work in parallel without clashing with the others (minimise shared files/modules per ticket and cross-ticket dependencies; when a dependency is unavoidable, state it explicitly on the ticket).

## Answering the user — short by default

- **Five lines max unless the user asks for more.** A chat reply defaults to at most five lines. The user asks for detail when they want it.
- **Multiple relevant topics become one-liners, never casualties.** If several things are worth the user knowing, give each as a single plain line rather than dropping it or expanding it. Goal: the user learns everything we could tell them in the shortest possible form, and expands whatever they choose.
- Applies to chat replies only — files a skill emits (reports, docs, HTML decks) keep their own format.

## Asking the user questions

- When you need to ask the user something, **list the questions** and use the clickable-options format (the AskUserQuestion tool): offer distinct options per question, mark your recommendation, and let the user pick by clicking.
- Phrase every question and option **for a junior developer with zero knowledge of the tech stack or the company domain** — plain language, no unexplained technical concepts, define any jargon or acronym on first use.

## Git guardrails

- Never commit directly to `main`; changes land via a `feat/<desc>` / `fix/<desc>` branch + PR.
- Never force-push, bypass hooks (`--no-verify`), or merge a PR with failing/pending CI.
- Never auto-merge — the merge decision belongs to a human.

## Verification (no build/test suite)

- After editing a `.md` skill file, confirm it renders without parse errors.
- After adding or editing a skill, confirm every description still starts with the `ORION - ` prefix: `grep -L -E '^description: ["'\'']?ORION - ' skills/*/SKILL.md` must print nothing (it lists the files that lack it).
- After editing `orion.sh` / `orion.ps1`, run `bash -n orion.sh`, parse `orion.ps1` with PS 5.1, then run `./orion.sh init --project <empty tmp dir> --no-statusline`, `update --force`, `check --force` and `uninstall --yes` against it and confirm the tmp dir ends up as it started.
- "Done" = the edited file is valid and that init/update/uninstall round trip is clean.
