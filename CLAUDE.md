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

- For the **`sequential-bmad-github-orion-vN`** skills: prefer creating a **new version** (copy to a bumped `-vN` suffix) over editing in place — people and automated workflows may depend on the current behaviour. Add a CHANGELOG entry describing the deltas, leave the prior version as-is, and add the new skill's row to the root `README.md`.
- Other skills (e.g. `guided-qa-orion`) have **no `-vN` convention** and are edited in place. Each skill's top-of-file editor note states which applies.
- When historical CHANGELOG entries mention the *old* skill name, leave them — they're an accurate record of that version; only operational references point at the current name.

## How the repo is wired

- Each `skills/<name>/` folder is linked into the user's skills dir (`~/.claude/skills/`) via a junction (Windows) / symlink (macOS/Linux). The link points back at the clone, so the user-level skill **is** the repo file — no copy step.
- **Updates are manual:** `install.ps1 -Update` / `install.sh --update` (git pull + relink). Auto-pull is intentionally off (supply-chain risk). After adding a new skill folder, run the installer (without `-Update`) to create its link.
- Each skill is a directory containing an uppercase `SKILL.md`; longer skills also carry `README.md`, `PREREQUISITES.md`, `CHANGELOG.md`, and a `prompts/` folder.

## Conventions for changes here

- Skills are project-agnostic: detect build/test/stack commands and conventions from the target repo at run time; don't assume a stack.
- Keep `install.ps1` / `install.sh` pure-ASCII and Windows-PowerShell-5.1-compatible.
- Commit/push only when the user asks; branch off `main` for changes; end commit messages with the required `Co-Authored-By` trailer.
