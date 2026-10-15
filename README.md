<p align="center">
  <img src="assets/orion-twinkle.gif" alt="orion — a collection of general-purpose Claude Code skills" width="520"/>
</p>

# orion

> [!CAUTION]
> **Read every skill before you run it. You are responsible for what you execute.**
> These skills instruct an AI agent to run commands, edit files, delete branches, and call external tools on your machine. Before installing or invoking any skill, **open its `SKILL.md` and read it in full** — make sure there are no instructions, commands, or clauses that could be harmful or damaging in *your* context. Treat them like any other code you'd run: review first, trust nothing blindly, and only run what you understand and accept the consequences of.
>
> **These skills are under constant improvement and are provided as-is — errors, unexpected behaviour, and breaking changes can and do occur.** Use them at your own risk, keep your work committed/backed up before running anything that touches your repo, and verify the results.

A collection of general-purpose [Claude Code](https://claude.com/claude-code) skills.

The installer **copies** each `skills/<name>/` folder into the agent's user skills directory (default `~/.claude/skills/`) and drops an `.orion-managed` marker so later runs can tell its own copies apart from your other skills. Copies are used instead of junctions/symlinks (Windows no longer treats junctioned skill folders reliably), so the user-level skill is a real copy — **`git pull` alone does not propagate; every update re-copies the skill content.** **Updates are manual**: run the installer with `-Update` / `--update` (or just ask Claude to do it for you) to pull *and* re-copy the latest skills. An optional scheduled auto-pull is available but disabled by default — see "How updates work" for the tradeoff.

> Work-specific skills (anything that references a specific product, team, or internal workflow) live only on the machines that need them — not in this repo. This keeps the repo safely shareable: no product names, no team identifiers, no internal paths.

## Prerequisites

- **Git** — to clone the repo.
- **Claude Code** — installed and run once (creates `~/.claude/skills/`).
- **PowerShell 5.1+** (Windows) or **Bash** (macOS / Linux) — for the installers.
- **jq** — only if you enable the optional status line.

## Install

```sh
git clone https://github.com/nachogl1/orion.git
cd orion

# Windows
.\install.ps1

# macOS / Linux
./install.sh
```

The installer:

1. Copies each skill in `./skills/` into the agent's skills directory (default: Claude Code → `~/.claude/skills/`), marking each copy `.orion-managed`.
2. Offers the optional [status line](#status-line-optional) with a y/N prompt (skipped when running with `-Force` / `--force`, or pre-answered with `-StatusLine` / `--statusline`).
3. Registers a scheduled auto-pull **only if you ask for it** via `-Schedule` / `--schedule` (default: **none** — manual updates are recommended).

Non-interactive form (no scheduled task registered):

```powershell
.\install.ps1 -Force                         # Windows
```
```sh
./install.sh --force                          # macOS / Linux
```

### After install

Open any project in Claude Code and type `/handoff` — the skill should start by asking where to save the handoff document.

## How updates work

Updates are manual. The user-level skills are **copies**, so a plain `git pull` is not enough — you must run the installer's update pass, which pulls *and* re-copies:

```powershell
.\install.ps1 -Update          # Windows
```
```sh
./install.sh --update           # macOS / Linux
```

…or just tell Claude something like *"update orion"* / *"pull the latest skills"* — Claude will run the update for you.

That one command handles all four change types:

| Change in the repo | What `-Update` does |
|---|---|
| Edit an existing skill | `git pull`, then re-copies the folder over the managed copy. |
| Add a new skill | `git pull` brings the folder; the copy step adds it to the target dir. |
| Remove a skill | `git pull` deletes the folder; the prune step removes the orphaned managed copy. |
| Rename a skill | Both — prune removes the old-name copy, the copy step creates the new-name one. |

### Why manual instead of scheduled?

Auto-pulling executable skill content is a supply-chain risk: anything pushed to `origin/main` runs as you, on every machine, with no review. Manual updates give you a "did I really want this?" moment and let you choose when to take the change.

If you still want it, register the scheduled task explicitly:

```powershell
.\install.ps1 -Schedule daily          # Windows (09:00 local)
```
```sh
./install.sh --schedule daily           # macOS / Linux (cron 0 9 * * *)
```

## Skills

Each row is a one-line summary — the full behaviour contract lives in each skill's `SKILL.md`.

| Skill | What it does |
|---|---|
| **project-handover** | Generates a plain-language, code-internals-free HTML handover document for stakeholders and new joiners, with a dated epics-and-stories snapshot. Strictly read-only. |
| **generate-project-writeup** | Generates a leadership-facing Word (`.docx`) project write-up that leads with a transparent traditional-vs-actual cost comparison; every metric measured or marked "not measured." Strictly read-only. |
| **handoff** | Distils the current conversation into a single markdown handoff document a fresh agent can continue from — goal, state, decisions + rationale, dead-ends, open questions, next steps — referencing existing artifacts by path/URL instead of copying them. Saves outside the workspace to a location you pick, redacts secrets/PII, and tailors to what the next session is for. Explicit-invocation only; no git changes. |
| **wayfinder** | Charts a chunk of work too big for one agent session as a shared *map* issue plus typed decision tickets on the repo's tracker (detected at run time) — destination first, sharp questions become tickets, blurry ones stay written-down "fog" until they sharpen, anything past the destination is ruled out of scope. Resolves one ticket per session and records the decision back onto the map. Planning only; it produces decisions, not the deliverable. Adapted from the MIT-licensed [`wayfinder`](https://github.com/mattpocock/skills) skill. |

## Base CLAUDE.md baseline

[`baselines/BASE_CLAUDE.md`](baselines/BASE_CLAUDE.md) is a starting `CLAUDE.md` for a new project run the orion way:
tracker-driven stories, worktree-per-issue, fresh-agent review, merge on green, one audit pile harvested with a human.
Copy it to `<repo>/CLAUDE.md` and fill every `<angle-bracket>` slot (tracker, stack, commands, worktree root); delete
the bullets the project has no use for. It is not installed by the installer — it is copied into a project by hand.

## Status line (optional)

Besides skills, the repo ships a shared **Claude Code status line** (`statusline/`) you can opt into. One line, live in every session:

> `1h23m` | `ctx: 42.5%` | `[branch] ◆0 ◯1 ●2 ▲1` | `#12 ok` | **`$1.23`** `$345.67` | `Opus` | `effort:high` | `⚑0` | `5h:23% ↻2h14m` | `7d:41% ↻3d5h`

- session alive time, context-usage % (color-coded), git branch + state indicators, PR status for the current branch (cached, background-refreshed), **cost**: API-equivalent USD for the **open session** (green) plus the **current calendar month to date across all projects** (blue, computed from local transcripts via [ccusage](https://github.com/ryoppippi/ccusage)), the **model name**, the **reasoning-effort level** (when the model exposes one), a **jobs flag** (`⚑N` when background agent sessions are running), and — rightmost, each in its own colour — the **subscription usage limits**: how much of the **5-hour** and **7-day** window is used and how long until each refreshes (subscription sessions only).
- installed with the same copy + `.orion-managed` marker mechanism as skills (`~/.claude/statusline-orion`), so `-Update` / `--update` re-copies status-line improvements too.
- activating it (writing the `statusLine` entry into `~/.claude/settings.json`) is **opt-in**: pass `-StatusLine` / `--statusline` to the installer, or answer the y/N prompt during an interactive install.

```powershell
.\install.ps1 -StatusLine            # Windows
```
```sh
./install.sh --statusline             # macOS / Linux
```

Requirements and details (jq required; gh and node optional): see [`statusline/README.md`](statusline/README.md).

## Add a new skill

1. Drop the skill folder under `skills/`. Each skill is a directory containing `SKILL.md` (uppercase — case-sensitive filesystems matter).
2. `git add skills/<name> && git commit && git push`.
3. On each other machine, run `install.ps1 -Update` / `install.sh --update` (or just ask Claude to update orion) to pick it up.

## Uninstall

```powershell
.\uninstall.ps1                  # Windows
```
```sh
./uninstall.sh                    # macOS / Linux
```

Removes the managed copies (skills and status line — any folder carrying the `.orion-managed` marker), removes the `statusLine` entry from `~/.claude/settings.json` if it points at our copy, and unregisters the scheduled task (if one was registered). The cloned repo itself is left in place — delete the folder if you don't want it.

## Contributing

The working rules for changes to this repo live in [`CLAUDE.md`](CLAUDE.md) — read it before contributing (it's written for AI agents working in the repo, but the rules bind humans equally). The short version:

- **Distribution safety (highest-priority rule).** Everything here is publicly distributable. Never introduce anything that identifies a specific person, team, company, product, private repo, or machine — in prose, code, examples, placeholders, **and git metadata (commit messages, PR titles, PR bodies)**. Use runtime-resolved placeholders (`<repo-name>`, `<gh-login>`, `#<N>`, `~/.claude`) instead; skills detect everything project-specific from the target repo at run time. Self-check your diff *and* your commit/PR text before pushing.
- **Versioning.** All current skills (and the status line) are edited in place. Skills carrying a `-vN` suffix are immutable per version — copy to a bumped `-vN` rather than editing in place, add a CHANGELOG entry, and add the new row to this README.
- **Issues.** Before filing one, dedupe first — search open issues *and* the code; never point at a **closed** issue as the reason to skip work.
- **PR/commit hygiene.** Branch off `main`; commit messages follow [Conventional Commits](https://www.conventionalcommits.org/) (`type(scope): description`, e.g. `fix(installer): guard junction delete`); keep installer scripts pure-ASCII and Windows-PowerShell-5.1-compatible; keep PR bodies as generic as the code they describe.

## License

[MIT](LICENSE) — free to use, modify, and redistribute with attribution.
