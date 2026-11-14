# PRD — orion: skills, rules and an installer for Claude Code projects

**Status: approved by the owner on 2026-10-17; updated on 2026-11-08 with the decisions of the improvement map.**
This is the PRD for orion. It describes orion as it is once the epic
[Improvement list of 2026-11-03: the decided changes](https://github.com/nachogl1/orion/issues/168) is built; until
then, the parts that epic changes describe the decided target, not the code on `main`. Its owner updates it on their
own terms. After this PRD's first map, a later map may record its decisions as ADRs under `docs/ADRs/` instead; each
ADR says whether it is still `pending` or already folded into this file, and `/reconcile` folds the pending ones in
with the owner. This replaces the versioning ADR's rejection (its decision 7) of letting the person choose each time.

## Problem and users

An AI coding assistant left to itself works differently in every session and for every person: it skips tests,
pushes to the main branch, forgets what was decided, files duplicate tickets and leaves branches behind. A team that
wants it to build real software needs the same careful way of working every time, for everyone, without each person
setting it up by hand.

- **Who uses orion:** developers and small teams who build software with Claude Code and track their work on GitHub
  Issues. Many are new to the stack or the domain of the project they work in, so every skill speaks in plain words.
- **Who maintains orion:** the owner of this repository, who changes it only through pull requests.
- **What they get:** a project where the assistant follows one rulebook, runs a known set of skills that hand work to
  each other, and stays up to date with one command — and where a teammate gets all of it with a plain `git clone`.

## What orion is

orion is three things, installed **into one project at a time** and committed there:

1. **The skills** — ready-made, self-contained abilities under `<project>/.claude/skills/<name>/`, each marked as
   orion's with an `.orion-managed` file, refreshed by every update.
2. **The rulebook** — `BASE_CLAUDE.md`, the mandatory rules for every project. The project's own `CLAUDE.md` imports
   it and adds only the project's facts. The two never contradict each other; if they do, `BASE_CLAUDE.md` wins.
3. **The installer** — `orion.sh` (bash), with `orion.ps1` as a Windows launcher that only finds Git Bash and runs it.
   A copy of the script lives in the project, so the project can update itself.

Optional and per computer: a **status line** at `~/.claude/statusline`. Every project carries orion's baseline of it, and each computer's copy is offered the newest one it sees and takes it only on its owner's word, in every update mode.

Optional and per computer: **mods**, Claude Code plugins that change how Claude Code looks and behaves and run with
the person's own permissions. orion's mods live in `mods/`; every project carries orion's copy of each one, as it
carries the status line baseline. Only on the person's yes, orion copies a mod into a folder under `~/.claude/` (a
local marketplace) and installs it from there at user scope with Claude Code's plugin command, so it works offline and
survives a moved or deleted project. A newer mod in a project is offered at session start in every update mode; on a
yes orion replaces the computer's copy and reinstalls it, with no merge (a person who wants their own edits copies
the mod under a new name). `orion uninstall` leaves an installed mod alone; a separate command removes it. The first
mod is **Orion Control Tower**, a pane on the right of Claude Code's fullscreen layout, shown and hidden with Ctrl+X
then P: this session's TLDR and activities, the `/dev-next` runs on this computer with their terminal, step and
sub-agents, and every open pull request. Accepting it also adds that shortcut to the person's own keybindings file,
merged in and never replacing it, with a warning when the chord is already taken.

Offered to each person: **personal rules** for their own user-level `CLAUDE.md` (`~/.claude/CLAUDE.md`), talked
through clause by clause and taken only on their word (see "Personal rules" under Scope).

This repository is the source. orion carries one **version number** in three parts, `major.minor.patch`, starting at
`2.0.0`. Nobody sets it by hand: after a merge that changes what a project receives (`skills/`, `baselines/`,
`orion.sh`), the release job reads the squash commit's Conventional Commit type and tags the next version
`v<major.minor.patch>`: a `!` after the type raises the first part, `feat` the middle part, every other type the last
part. That merge is a release, which every project picks up with `orion update`. The version lives only in the release
tags (the hand-edited `ORION_VERSION` file goes), and a check on every pull request fails when its title has no valid
Conventional Commit type. A version without dots (the old whole numbers) always counts as older than any three-part
one, so old installs are offered the update as usual. This replaces decision 1 of the versioning ADR.

## Vocabulary

| Term | Meaning |
|---|---|
| Skill | A folder with a `SKILL.md` that Claude Code runs on request (`/<name>`). orion's carry the `ORION - ` prefix in their description. |
| orion-managed | Carries the `.orion-managed` marker or sits in `.orion-manifest`: owned by orion, overwritten on update, removed on uninstall. |
| Baseline / `BASE_CLAUDE.md` | The one mandatory rules file, generic and slot-free, overwritten in projects on update. |
| Starter `CLAUDE.md` | The slot-only project rules file `init` writes once when the project has none; yours from then on. |
| Slot | A project fact the starter asks for (commands, including how to pass the test-copies count to the full suite or `none`, stack, worktree root, boundaries); `TBD` until filled. |
| PRD | Product requirements document under `docs/PRDs/`: the north star for what a project builds; written or provided by the person, never drafted by an agent on its own. |
| ADR | A decision record at `docs/ADRs/adr-<change-name>.md` (context, decision, consequences, alternatives) for a hard-to-reverse decision; approved by the person before any ticket or code. Carries a status line, `pending` or `folded into the PRD on <date>`. |
| Version number | `major.minor.patch`, held only in the `v<major.minor.patch>` release tags and on line 5 of a project's `.claude/orion/VERSION`; set by the release job after each merge that changes what a project receives. |
| Mod | A Claude Code plugin that changes how Claude Code looks and behaves, offered per computer and installed at user scope only on the person's word. |
| `owner-merges` | A story label: `/dev-next` builds the story and opens its pull request, then stops; the owner tries the change and merges. Every story that builds or changes a mod carries it. |
| Test copies | How many parallel copies (workers) a run's test suite uses on a shared computer; each run sizes its own. |
| Epic / story | A group of work / one buildable piece of it. Agents build stories only. Epic → story is a native GitHub sub-issue. |
| Blocker | An issue that must be CLOSED first; set both as GitHub's native relation and under `### Blocked by`. |
| Seam | The folder or module a story owns, so two stories on one folder are caught before they collide. |
| Worktree root | A folder outside the project holding one worktree per branch, plus the never-committed `in-flight.json`. |
| Audit branch | `audit/<login>`, a per-developer branch of run reports and QA records; pushed directly, never merged. |
| Run report | The one file each `/dev-next` story leaves: product problems for later, things that slowed it, tips. |
| QA record | The user-level checks a merged story leaves for `/harvest-qa`. |
| Bookmark | A state file on `main` recording what a person-run skill already handled (`docs/*-state.json`). |
| Drift | Any disagreement between the PRDs, the issues and the code on `main`. |
| `VERIFY.md` | A skill's table of read-only checks that `/orion-verify` runs after install. |
| Personal rules / `GLOBAL_CLAUDE.md` | The clauses orion offers for each person's own `~/.claude/CLAUDE.md`; what they accept sits in its ORION GLOBAL section. |

## Scope

### The installer

Sub-commands of `orion.sh`, run in the project or with `--project <dir>`:

| Sub-command | Contract |
|---|---|
| `init` | First shows a short notice that orion's agents claim issues, file tickets and merge their own work on green, and asks to continue (`--yes` skips the question, as for `uninstall`). Copies every skill with its marker, the baseline, the script and a `VERSION` file (commit SHA, commit time, version number) into the project; creates `CLAUDE.md` from the starter if missing, else only adds the import line at the top (replacing the pre-rename import if present); writes `config.json` once (`updateMode`, `source`, `ref`, `branchLimit`, `worktreeLimit`); adds one `SessionStart` hook; optionally installs the status line; warns when git ignores files it installed; leaves a one-shot per-computer marker that asks for `/orion-verify`, and its closing message puts `/orion-verify` before the first commit. |
| `update` | Fetches orion (`git clone --depth 1` from the configured source and ref, or this checkout when run from it) and re-copies only what orion owns, the status line baseline, `GLOBAL_CLAUDE.md`, the commit time (`VERSION` line 4) and the version number (line 5) included; says when the per-computer status line has a newer baseline waiting (one from a higher version number), and never changes it; says to run `/orion-verify` when it changed the rules. `update --skip` records the newest orion as declined on this computer, so the hook stays quiet until a newer one. Removes an orion-managed skill folder that orion renamed (`reconcile-issue-map`, now `reconcile`). Never touches the project's `CLAUDE.md`, `config.json`, unmarked skills or other settings. |
| `check` | The session-start hook. Silent on success and exit 0 on every failure. It prints at most one `hookSpecificOutput` JSON line: once after `init`, the request to run `/orion-verify` instead of the update check; otherwise, every session with no network, the offer of `/orion-verify` once each time orion's rules (`BASE_CLAUDE.md` and every `.md` file of an orion skill) differ from every set on record as checked for this repository on this computer (line endings do not count; one record, of the last 20 sets checked, serves every worktree of a clone; a computer with no record yet, such as a fresh clone, is asked once, worded as orion being new there), seen after an `auto` update or the session-start pull in the same session; every session (an unreachable source costs up to 8 s of the start), an update offer (`ask`, quiet once declined with `update --skip` until a newer one, unless `--force`) or a note that it updated itself (`auto`, nothing under `off`) — only when a release tag is higher than the project's version number (with no number on either side, or a `ref` other than `main`, any new commit counts), and never when the installed version equals the newest (a status line or personal-rules copy missing from the project brings no message: the next update copies it again); and at most once a day each, the branch- or worktree-limit offer of `/clear-git-resources` when that skill is installed. Every session it first runs `git pull --ff-only` on the branch the session opens in (only the fetch is time-limited; silent unless refused, then one line), and, with no network, it offers the project's newer status line baseline (one from a higher version number than the computer's copy last took or skipped, never a lower one): taking it for an unedited copy, merging it into an edited one, never without the person's word, even under `auto`; likewise a newer mod than the one installed on this computer, replaced and reinstalled only on the person's word; and, once per clause version per computer and never under `off`, the offer to go through orion's personal rules while a clause carries a higher version number than the person's ORION GLOBAL section (never a write to their file; it comes back only when a clause carries a higher number than the highest one already offered on that computer, or on `--force`). Messages are joined into one line. |
| `verify` | The mechanical post-install check: one line per finding (`ok` / `WARN` / `FAIL`), exit 1 on a `FAIL`, never a fix; warns about every installed file git ignores (and about a whole ignored folder, which needs `<folder>/*` plus re-includes) and about a folder the baseline names that the project keeps under another path; warns when the `docs/changelog/` folder is missing (`/orion-verify` creates it; an old single-file changelog stays as history); consumes the post-install marker and records the rules it checked on this computer. |
| `status` | What is installed, at which version number and commit, the update mode, the branch and worktree limits and the current counts. |
| `statusline` | `merge`: takes the project's newer baseline; an unedited per-computer status line becomes it, an edited one gets a three-way merge that keeps the edits (conflict markers and exit 1 where both changed the same lines; a copy from before the merge base existed is saved to `~/.claude/statusline.bak` and replaced). `skip`: declines that version. |
| `uninstall` | Removes everything orion owns, the hook, the marker, the rules fingerprint and the declined-update record; keeps everything the project owns, including the starter `CLAUDE.md` minus the import line; never touches the person's `~/.claude/CLAUDE.md`, the per-computer status line or an installed mod. |

Settings edits go through `jq`, then `python3`, then Windows PowerShell, so the hook installs on any machine that has
one of the three. The `updateMode` default is `ask`; `branchLimit` defaults to 20 branches (local plus
remote-tracking) and `worktreeLimit` to 20 worktrees, each a number or `off`.

### Personal rules (`GLOBAL_CLAUDE.md`)

The reply rules, working habits and git habits that make the assistant pleasant to work with belong in each person's
own `~/.claude/CLAUDE.md`, one per computer. orion offers them, never pushes them; whatever a person accepts is theirs.

- **The offer:** `baselines/global/GLOBAL_CLAUDE.md`, copied by `init` and `update` to
  `<project>/.claude/orion/global/` and listed in the manifest. Nothing imports it. It may repeat rules
  `BASE_CLAUDE.md` already makes for projects, and nothing in it names or describes a real person, team, company or
  machine.
- **A clause** is one bullet or numbered item under the file's headings, on one line ending in an invisible version
  note. Because the version is only known after the merge, a changed clause's note names the newest version already
  released plus `+`, for example `<!-- orion:v2.4.1+ -->` ("changed after 2.4.1"); a pull request left open across a
  release refreshes its notes, and the suite flags a stale one. Notes from before three-part versions (such as
  `<!-- orion:v2 -->`) stay as they are and keep comparing with each other; a note without dots is older than any
  note with them.
- **The ORION GLOBAL section** at the end of the person's file holds what they accepted, under the same headings, each
  clause keeping its marker:

  ```markdown
  # ORION GLOBAL — v2
  …accepted clauses…
  <!-- /ORION GLOBAL -->
  ```

  The heading's version number is the only record of what was offered: it holds the version the person last went
  through, and every clause changed after it is offered; the others are not. After every discussion it moves to the highest clause
  number in the file that was offered, whether the person accepted everything, part or nothing; declining everything
  still leaves the heading and the end line. A changed clause the person accepted earlier is shown old and new side
  by side and replaced in place only on a yes. The person may edit the section freely; orion trusts the number. A
  heading in any other form (such as the timestamps orion used before) counts as no section: there is no migration.
- **The discussion** needs no skill: the agent follows the steps at the top of `GLOBAL_CLAUDE.md` (not a clause,
  never copied) when the session-start offer asks for it or whenever the person asks — read both files, list the
  clauses above the heading's number (all of them without a section), ask in batches with clickable options (accept,
  skip, accept with an edit), write only inside the section, move the number, show the final section before
  saving.
- **The offer at session start:** `check` reads the project copy and the heading line of `~/.claude/CLAUDE.md`, with
  no network, and while a clause carries a higher number than the heading (or there is no section) asks Claude Code to offer the
  discussion with the AskUserQuestion tool, once per clause version per computer (it comes back only when orion adds
  or changes a clause), its message joined to the others. It ignores
  `updateMode: auto` (the person's file changes only through the discussion) and is silenced by `off`. Right after
  `init` the post-install message asks for it too, after `/orion-verify`, unless the mode is `off`.
- **Never:** an automatic write to `~/.claude/CLAUDE.md` in any mode, an edit outside the section, a per-computer list
  of declined clauses, an import of `GLOBAL_CLAUDE.md` into the person's file, or `uninstall` touching that file.

### The skill set

The loop, from idea to checked software:

- `wayfinder` — charts work too big for one session as a map of typed decision tickets and settles them one at a time;
  plans, never builds. Works on GitHub Issues only. A map ends in a PRD, in filed stories (after the planning
  interview), or, after a project's first map, in ADRs only (recommended when the map changes no scope, vocabulary
  or acceptance bar).
- `prd-to-tickets` — cuts a PRD (with its pending ADRs) into epics and stories for parallel work (scaffold → contract
  stories → fan-out), sets both blocker forms, reuses open issues as blockers, chains the tiers (every later-tier
  story waits for the final stories of the tier before), and settles open questions with the planning interview
  shared with `wayfinder`. The UX prototype is merged before it cuts: finding a screen the PRD names but the
  prototype lacks, it drafts the missing screens in a pull request that adds one PRD line pointing at the prototype,
  and stops until that pull request is merged.
- `dev-quick` — turns a change with no ticket into an `agent-ready` issue in the standard shape and hands it to
  `dev-next`. It interviews the person only when something is unclear, and agents offer it whenever someone asks for a
  code change in chat.
- `dev-next` — the engine: picks the next free story, claims it, builds it in a worktree, has a fresh agent review it,
  merges on green CI, closes it, writes the run report and QA record, and counts what is due. It merges `origin/main`
  before its gate and checks it is not behind right before merging; before each local test run it sizes its test
  copies (physical cores ÷ live runs, at most half the cores, at least 1, and 1 when under 2 GB of memory is free);
  it names every sub-agent with the issue number and writes its terminal, step and sub-agents into its in-flight
  entry. An `owner-merges` story stops at its open pull request. A run that gives up keeps its assignee: a technical
  failure stays `agent-ready`, a real question becomes `needs-human`, and the runner resumes with `/dev-next #<N>`.
- `issue-map` — draws the blocked-by graph of every issue into a never-committed local HTML snapshot, rebuilt only
  when a person asks for it. Two opt-in options map only the issues a GitHub search matches (a blocker the search
  left out is drawn faded) or another repository's issues.
- `harvest` — works through the run reports with the person and turns what matters into as few tickets as possible:
  each note rated high, medium or low by fixed tests, high and medium groups first with one three-line question each,
  then every low note in one closing question.
- `harvest-qa` — drives the QA records against `main`, one agent at a time, shows the person each failure reproduced
  twice with its importance, and files a `bug` only for the ones the person chooses.
- `reconcile` — finds drift between the PRDs, their pending ADRs, the issues and `main` (a later-tier story free
  while an earlier tier is open included), fixes each item with the person, and folds pending ADRs into the PRD.
- `clear-git-resources` — lists stale worktrees, branches and leftover files, deletes the person's own stale ones whose
  work cannot be lost, asks before deleting anyone else's, and never touches unmerged work or the audit and QA resources.

Around the loop:

- `orion` — status, check, update and uninstall from inside a session.
- `orion-verify` — runs `verify`, fixes the `FAIL`s in orion's own files, reviews the project's `CLAUDE.md`, skills,
  settings and the person's own rules file against the baseline, runs every `VERIFY.md`, and asks before touching anything the project owns:
  filling each `TBD` command from the project's own files (CI first; never run to test it), moving a folder the
  baseline names to where it expects it (no path override), and the `.gitignore` lines that let orion reach the team.
- `handoff` — packs a conversation into a handoff document saved outside the workspace, secrets redacted.
- `project-handover` — a read-only, self-contained HTML handover of the project for newcomers and stakeholders.
- `generate-project-writeup` — a read-only Word write-up of the delivered work for leadership, numbers measured or
  marked "not measured", opening with a one-page Executive Summary before the table of contents.

### The work-tracking model (shipped as rules in the baseline)

- GitHub Issues in the project's own repository are the only source of truth. PRD → epic → story.
- Labels: `epic`, `story`, `agent-ready`, `needs-human`, `in-progress`, `outside-change`, `bug`, `owner-merges`,
  plus the `wayfinder:*` and `tier:*` sets. A PRD's tiers set the build order through real blocks: every story of a
  later tier is blocked by the final stories of the tier before, and whoever files a story later links it the same
  way; tiers outside the PRD (`tier:bug`, `tier:dev-quick`, …) are outside the chain. `agent-ready` and `needs-human` never sit together; `outside-change` always carries
  `needs-human` and ends at a pull request for the other repository's reviewer. An issue with no readiness label is
  never taken automatically.
- The assignee owns the issue; claims are re-read, and the earlier claim wins.
- Every new issue follows `dev-next`'s `references/new-issue.md`; every skill that files or reads issues uses it.
- Three sizes of change: a fix or a tweak needs no document; a hard-to-reverse decision gets an ADR the person
  confirms is needed and approves before any ticket or code; a big change only gets the question whether the person
  wants a PRD, which they write or provide on their terms (after `/wayfinder`). An agent never drafts a PRD on its own.
  After a project's first map, a map may end in ADRs only. An approved ADR does not update the PRD by itself: it
  stays `pending`, the PRD plus its pending ADRs are the product truth, and `/reconcile` folds them in with the person.
  Decisions taken during a PRD split still go to the PRD.
- An agent merges every pull request it makes once its checks are green (never on red or pending, "no checks
  reported" counts as red, squash, delete the branch), except one touching the PRD, an ADR, the UX prototype or the
  project's `CLAUDE.md`, an `outside-change` one, or an `owner-merges` story: a person merges those.

### The audit, harvest, QA and reconcile loop

- Every `dev-next` story pushes one run report and one QA record to `audit/<login>`.
- `dev-next` only counts: 10 unharvested items → `Harvest due: run /harvest`; 5 untested records →
  `QA due: run /harvest-qa`; a sign of drift → `Drift found: run /reconcile`. Kept low-rated notes still count
  towards the ten.
- `harvest`, `harvest-qa` and `reconcile` are run by a person, never by another skill. Each keeps its
  bookmark on `main` and ships it in its own pull request. `harvest` and `harvest-qa` never read each other's files.

## Do not build

- **A user-level install.** orion lives in a project and is committed there; the status line and the mods are the
  only per-computer pieces orion installs, each only on the person's word, and the person's own `~/.claude/CLAUDE.md`
  changes only through the personal rules discussion, on their word.
- **A mod written into committed project settings**, which would switch code on for teammates without their word.
- **Any automatic write to `~/.claude/CLAUDE.md`**, in any update mode, or an edit outside its ORION GLOBAL section.
- **Work-specific skills** — anything tied to one product, team or internal workflow. Those stay on the machines
  that need them.
- **Anything that names a person, company, product, private repository, machine path, locale set or a real
  identifier from a source project** — in files, examples, branch names or git metadata. One written exception: the
  owner's name in the guide page footer.
- **Skills that reference orion repo files** or share code through a common library. Each skill stands alone.
- **A skill named inside `orion-verify`.** The check is driven by what is on disk and by each skill's `VERIFY.md`.
- **Issue trackers other than GitHub Issues** for the build loop or for `wayfinder`. Whether to support others is a
  later map of its own.
- **A `check` that prints on success, fails a session start, or edits anything the project owns.**
- **Updates that touch** the project's `CLAUDE.md`, `config.json`, unmarked skills or unrelated settings.
- **An agent merging** a pull request that touches the PRD, an ADR, the UX prototype or the project's `CLAUDE.md`,
  an `outside-change` one or an `owner-merges` story; rebasing, stashing or force-pushing in any skill.
- **A hosted service, server or deploy target.** orion runs nothing; it deploys nowhere.
- **Running `orion init` against this checkout.** This repository imports `baselines/BASE_CLAUDE.md` directly.

## Acceptance bar

A change to orion is done when all of these hold:

- **The CI chain is green** on the pull request, with exactly the commands in `CLAUDE.md`: build (`bash -n orion.sh`),
  lint (every `SKILL.md` description starts with `ORION - `), Python compile of the issue-map generator, the Windows
  PowerShell 5.1 parse of `orion.ps1`, and the full suite.
- **The full suite** is the round trip against an empty folder: `init --yes` → `update --force` → `check --force` →
  `uninstall --yes`, after which nothing orion owns is left (`.claude/orion` and `.claude/skills` gone, no mention of
  orion in `CLAUDE.md` or `settings.json`). It runs after every edit to `orion.sh` or `orion.ps1`.
- **The `check` contract holds:** silent on success, exit 0 on every failure, at most one JSON line.
- **The personal rules hold:** every clause of `GLOBAL_CLAUDE.md` carries a valid version note, and one changed
  against `origin/main` names the newest released version plus `+`; `check` offers the discussion without a
  section or with a newer clause, never under `off`, at most once a day, and never writes `~/.claude/CLAUDE.md`
  (not under `auto`, not on `uninstall`); `verify` reports a missing project copy as a `FAIL`.
- **`verify` on a fresh install** exits 0 with only the unfilled-slot warning.
- **The version number holds:** it has three parts, `init` records it, a newer commit with no higher release tag is
  not offered, a higher tag is, a version without dots counts as older than any with them, nothing is offered when
  the installed version equals the newest, and every pull request title carries a valid Conventional Commit type.
- **Distribution safety holds:** the diff, the commit message and the pull request text carry no sensitive data
  (the categories under "Do not build"); a leak in pushed history is reported to the owner, never force-pushed away.
- **Every pull request adds its own one-line file to `docs/changelog/`** (never a shared file, so parallel pull
  requests never conflict), and every edited Markdown file still renders.
- **A shared block corrected in one skill is corrected in every copy** (`git grep` for each).
- **Agents merge their own pull requests on green**, except one touching the PRD, an ADR, the UX prototype or
  `CLAUDE.md`, or an `owner-merges` story (every mod story is one): a human merges those.
- **A mod is checked by hand** with `claude plugin validate`, `claude plugin test` and `tsc`, since they need Claude
  Code and do not run in CI.

## Build decisions

- **Bash for the installer**, portable across Git Bash, macOS bash and Linux: no GNU-only flags.
- **Windows PowerShell 5.1 for the launcher only**, pure ASCII; it finds Git Bash and runs `orion.sh`.
- **Python 3.9+, standard library only**, for the one script that needs it (the issue-map generator). No third-party
  packages anywhere.
- **TypeScript for mods**, each a Claude Code plugin under `mods/<name>/`, installed at user scope from a local
  marketplace under `~/.claude/`; the mod interface is early access and may change between Claude Code releases, so
  orion offers one mod at a time.
- **Test copies sized per run, per computer**: each run reads the computer's physical cores, the live runs in the
  in-flight file and the free memory before every local test run, so the rule needs no setup or measuring.
- **No test framework.** The init/update/check/uninstall round trip is the suite; CI runs it on Ubuntu, and the
  PowerShell parse on Windows.
- **Markdown for every skill**, `SKILL.md` as the entry point; longer skills add `references/`, `prompts/`,
  `README.md`, `PREREQUISITES.md`, `CHANGELOG.md` or `VERIFY.md`.
- **Self-contained skills with intentional duplication.** A skill is copied standalone into a project, so shared
  boilerplate is duplicated on purpose and never factored out.
- **Everything project-specific is detected at run time** from the target project's own files, never hard-coded.
- **One rules file.** The baseline holds every mandatory rule; the project's `CLAUDE.md` holds only its facts.
- **Ownership by marker and manifest.** `update` and `uninstall` act only on what carries `.orion-managed` or sits in
  `.orion-manifest`.
- **A merge that changes what projects receive is the release.** Squash-merge only; the `release` workflow tags the
  next `v<major.minor.patch>` on `main` from the squash commit's type, the session-start check reads the tags in its
  one `ls-remote` call, and projects pull the release with `orion update`.
- **Skills are edited in place**, never copied to a new version.
- **English** for code, comments, commits, issues and docs.
