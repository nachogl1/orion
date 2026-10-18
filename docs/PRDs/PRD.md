# PRD — orion: skills, rules and an installer for Claude Code projects

**Status: approved by the owner on 2026-10-17.** This is the PRD for orion.
It describes orion as it is today; it plans no new work. Every later big change gets its own
`docs/PRDs/PRD<SummaryName>.md` and, once shipped, is folded into this file.

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

Optional and per computer: a **status line** at `~/.claude/statusline`. Every project carries orion's baseline of it, and each computer's copy follows the newest one it sees; a copy its owner edited is merged only on their word.

This repository is the source. A merge to `main` is a release; every project picks it up with `orion update`.

## Vocabulary

| Term | Meaning |
|---|---|
| Skill | A folder with a `SKILL.md` that Claude Code runs on request (`/<name>`). orion's carry the `ORION - ` prefix in their description. |
| orion-managed | Carries the `.orion-managed` marker or sits in `.orion-manifest`: owned by orion, overwritten on update, removed on uninstall. |
| Baseline / `BASE_CLAUDE.md` | The one mandatory rules file, generic and slot-free, overwritten in projects on update. |
| Starter `CLAUDE.md` | The slot-only project rules file `init` writes once when the project has none; yours from then on. |
| Slot | A project fact the starter asks for (commands, stack, worktree root, boundaries); `TBD` until filled. |
| PRD | Product requirements document under `docs/PRDs/`: the north star for what a project builds. |
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

## Scope

### The installer

Sub-commands of `orion.sh`, run in the project or with `--project <dir>`:

| Sub-command | Contract |
|---|---|
| `init` | Copies every skill with its marker, the baseline, the script and a `VERSION` file (commit SHA) into the project; creates `CLAUDE.md` from the starter if missing, else only adds the import line at the top (replacing the pre-rename import if present); writes `config.json` once (`updateMode`, `source`, `ref`, `branchLimit`); adds one `SessionStart` hook; optionally installs the status line; leaves a one-shot per-computer marker that asks for `/orion-verify`. |
| `update` | Fetches orion (`git clone --depth 1` from the configured source and ref, or this checkout when run from it) and re-copies only what orion owns, the status line baseline and the commit time (`VERSION` line 4) included; brings an unedited per-computer status line up to date. Never touches the project's `CLAUDE.md`, `config.json`, unmarked skills or other settings. |
| `check` | The session-start hook. Silent on success and exit 0 on every failure. It prints at most one `hookSpecificOutput` JSON line: once after `init`, the request to run `/orion-verify` instead of the update check; otherwise, at most once a day each, an update offer (`ask`) or a note that it updated itself (`auto`, nothing under `off`), and the branch-limit offer of `/clear-git-resources` when that skill is installed. Every session, with no network, it brings an unedited per-computer status line up to the project's newer baseline (never back to an older one) silently, and offers the merge when the copy was edited. Messages are joined into one line. |
| `verify` | The mechanical post-install check: one line per finding (`ok` / `WARN` / `FAIL`), exit 1 on a `FAIL`, never a fix; consumes the post-install marker. |
| `status` | What is installed, at which version, the update mode, the branch limit and the current branch count. |
| `statusline` | `merge`: a three-way merge of the project's newer baseline into an edited per-computer status line, keeping the edits (conflict markers and exit 1 where both changed the same lines; a copy from before the merge base existed is saved to `~/.claude/statusline.bak` and replaced). `skip`: declines that version. |
| `uninstall` | Removes everything orion owns and the hook and marker; keeps everything the project owns, including the starter `CLAUDE.md` minus the import line. |

Settings edits go through `jq`, then `python3`, then Windows PowerShell, so the hook installs on any machine that has
one of the three. The `updateMode` default is `ask`; `branchLimit` defaults to 20 branches (local plus
remote-tracking) or `off`.

### The skill set

The loop, from idea to checked software:

- `wayfinder` — charts work too big for one session as a map of typed decision tickets and settles them one at a time;
  plans, never builds. Works on GitHub Issues, Jira or a local markdown map.
- `prd-to-tickets` — cuts a PRD into epics and stories for parallel work (scaffold → contract stories → fan-out),
  sets both blocker forms, reuses open issues as blockers, and drafts a UX prototype when front-end stories lack one.
- `dev-quick` — turns a change with no ticket into an `agent-ready` issue in the standard shape and hands it to
  `dev-next`. It interviews the person only when something is unclear, and agents offer it whenever someone asks for a
  code change in chat.
- `dev-next` — the engine: picks the next free story, claims it, builds it in a worktree, has a fresh agent review it,
  merges on green CI, closes it, writes the run report and QA record, and counts what is due.
- `issue-map` — draws the blocked-by graph of every issue into a never-committed local HTML snapshot; `dev-next`
  rebuilds it silently after every claim and merge.
- `harvest` — works through the run reports with the person, in waves, and turns what matters into as few tickets
  as possible.
- `harvest-qa` — drives the QA records against `main`, one agent at a time, and files one `bug` per failure reproduced
  twice that no open issue covers.
- `reconcile-issue-map` — finds drift between the PRDs, the issues and `main`, and fixes each item with the person.
- `clear-git-resources` — lists stale worktrees, branches and leftover files in three kinds (safe, needs your word,
  never offered) and deletes only what the person agrees to.

Around the loop:

- `orion` — status, check, update and uninstall from inside a session.
- `orion-verify` — runs `verify`, fixes the `FAIL`s in orion's own files, reviews the project's `CLAUDE.md`, skills and
  settings against the baseline, runs every `VERIFY.md`, and asks before touching anything the project owns.
- `handoff` — packs a conversation into a handoff document saved outside the workspace, secrets redacted.
- `project-handover` — a read-only, self-contained HTML handover of the project for newcomers and stakeholders.
- `generate-project-writeup` — a read-only Word write-up of the delivered work for leadership, numbers measured or
  marked "not measured".

### The work-tracking model (shipped as rules in the baseline)

- GitHub Issues in the project's own repository are the only source of truth. PRD → epic → story.
- Labels: `epic`, `story`, `agent-ready`, `needs-human`, `in-progress`, `outside-change`, `bug`, plus the
  `wayfinder:*` set. `agent-ready` and `needs-human` never sit together; `outside-change` always carries
  `needs-human` and ends at a pull request for the other repository's reviewer. An issue with no readiness label is
  never taken automatically.
- The assignee owns the issue; claims are re-read, and the earlier claim wins.
- Every new issue follows `dev-next`'s `references/new-issue.md`; every skill that files or reads issues uses it.
- A big change gets a PRD first, drafted only on request and counted only once approved.

### The audit, harvest, QA and reconcile loop

- Every `dev-next` story pushes one run report and one QA record to `audit/<login>`.
- `dev-next` only counts: 10 unharvested items → `Harvest due: run /harvest`; 5 untested records →
  `QA due: run /harvest-qa`; a sign of drift → `Drift found: run /reconcile-issue-map`.
- `harvest`, `harvest-qa` and `reconcile-issue-map` are run by a person, never by another skill. Each keeps its
  bookmark on `main` and ships it in its own pull request. `harvest` and `harvest-qa` never read each other's files.

## Do not build

- **A user-level install.** orion lives in a project and is committed there; the status line is the only
  per-computer piece.
- **Work-specific skills** — anything tied to one product, team or internal workflow. Those stay on the machines
  that need them.
- **Anything that names a person, company, product, private repository, machine path, locale set or a real
  identifier from a source project** — in files, examples, branch names or git metadata.
- **Skills that reference orion repo files** or share code through a common library. Each skill stands alone.
- **A skill named inside `orion-verify`.** The check is driven by what is on disk and by each skill's `VERIFY.md`.
- **Issue trackers other than GitHub Issues** for the build loop (`wayfinder` alone stays tracker-agnostic).
- **A `check` that prints on success, fails a session start, or edits anything the project owns.**
- **Updates that touch** the project's `CLAUDE.md`, `config.json`, unmarked skills or unrelated settings.
- **Auto-merge beyond `dev-next`'s own pull requests**, rebasing, stashing or force-pushing in any skill.
- **A hosted service, server or deploy target.** orion runs nothing; it deploys nowhere.
- **Running `orion init` against this checkout.** This repository imports `baselines/BASE_CLAUDE.md` directly.

## Acceptance bar

A change to orion is done when all of these hold:

- **The CI chain is green** on the pull request, with exactly the commands in `CLAUDE.md`: build (`bash -n orion.sh`),
  lint (every `SKILL.md` description starts with `ORION - `), Python compile of the issue-map generator, the Windows
  PowerShell 5.1 parse of `orion.ps1`, and the full suite.
- **The full suite** is the round trip against an empty folder: `init` → `update --force` → `check --force` →
  `uninstall --yes`, after which nothing orion owns is left (`.claude/orion` and `.claude/skills` gone, no mention of
  orion in `CLAUDE.md` or `settings.json`). It runs after every edit to `orion.sh` or `orion.ps1`.
- **The `check` contract holds:** silent on success, exit 0 on every failure, at most one JSON line.
- **`verify` on a fresh install** exits 0 with only the unfilled-slot warning.
- **Distribution safety holds:** the diff, the commit message and the pull request text carry no sensitive data
  (the categories under "Do not build"); a leak in pushed history is reported to the owner, never force-pushed away.
- **Every pull request adds a line to `docs/CHANGELOG.md`**, and every edited Markdown file still renders.
- **A shared block corrected in one skill is corrected in every copy** (`git grep` for each).
- **Only `/dev-next` merges its own pull requests**; every other pull request to this repository is merged by a human.

## Build decisions

- **Bash for the installer**, portable across Git Bash, macOS bash and Linux: no GNU-only flags.
- **Windows PowerShell 5.1 for the launcher only**, pure ASCII; it finds Git Bash and runs `orion.sh`.
- **Python 3.9+, standard library only**, for the one script that needs it (the issue-map generator). No third-party
  packages anywhere.
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
- **Merge to `main` is the release.** Squash-merge only; projects pull it with `orion update`.
- **Skills are edited in place**, never copied to a new version.
- **English** for code, comments, commits, issues and docs.
