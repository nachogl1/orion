<p align="center">
  <img src="assets/orion-twinkle.gif" alt="orion — a repo-level utility framework for Claude Code projects" width="520"/>
</p>

# orion

> [!CAUTION]
> **Read every skill before you run it. You are responsible for what you execute.**
> These skills instruct an AI agent to run commands, edit files, delete branches, and call external tools on your machine. Before installing or invoking any skill, **open its `SKILL.md` and read it in full** — make sure there are no instructions, commands, or clauses that could be harmful or damaging in *your* context. Treat them like any other code you'd run: review first, trust nothing blindly, and only run what you understand and accept the consequences of.
>
> **These skills are under constant improvement and are provided as-is — errors, unexpected behaviour, and breaking changes can and do occur.** Use them at your own risk, keep your work committed/backed up before running anything that touches your repo, and verify the results.

A **repo-level utility framework** for [Claude Code](https://claude.com/claude-code) projects: a set of general-purpose skills, a baseline of working rules, and an optional status line, installed **into the project** and committed, so a team shares one setup and gets updates by pulling.

Nothing is installed at user level any more (the earlier user-level `install.ps1` / `install.sh` copies are retired by `init`). The only per-computer piece is the optional status line.

> Work-specific skills (anything that references a specific product, team, or internal workflow) live only on the machines that need them — not in this repo. This keeps the repo safely shareable: no product names, no team identifiers, no internal paths.

## Prerequisites

- **Git** — fetches orion and its updates. On Windows this means **Git for Windows**, whose Git Bash runs the script (Claude Code uses it too).
- **Claude Code** — installed and run once in the project.
- **jq** — only if you enable the optional status line. (Settings edits use `jq`, falling back to `python3`, then Windows PowerShell.)

## Install into a project

Run **inside the project folder**, once, from any shell — nothing to clone, the script fetches the latest orion itself:

```sh
# macOS / Linux / Git Bash
curl -fsSL https://raw.githubusercontent.com/nachogl1/orion/main/orion.sh | bash -s -- init
```
```powershell
# Windows PowerShell
irm https://raw.githubusercontent.com/nachogl1/orion/main/orion.ps1 | iex
```

To pass options on PowerShell (e.g. `--statusline`), use the scriptblock form:
`& ([scriptblock]::Create((irm https://raw.githubusercontent.com/nachogl1/orion/main/orion.ps1))) init --statusline`.

Prefer not to pipe a download into a shell? Clone and run it from there — the result is identical:

```sh
git clone -q --depth 1 https://github.com/nachogl1/orion.git /tmp/orion && /tmp/orion/orion.sh init && rm -rf /tmp/orion
```
```powershell
git clone -q --depth 1 https://github.com/nachogl1/orion.git $env:TEMP\orion; & $env:TEMP\orion\orion.ps1 init; Remove-Item -Recurse -Force $env:TEMP\orion
```

Or from a clone of this repo: `./orion.sh init --project <path-to-project>` (Windows: `.\orion.ps1 init --project <path>`). You can also simply tell Claude *"set up orion in this project"* and it runs the same command.

`init` does five things, then tells you to review and commit:

| What | Where it lands | Who owns it afterwards |
|---|---|---|
| Every skill in `skills/` | `.claude/skills/<name>/` with an `.orion-managed` marker | orion (refreshed by `update`) |
| The rules baseline [`baselines/ORION.md`](baselines/ORION.md) | `.claude/orion/ORION.md` | orion (refreshed by `update`) |
| The manager script + version file | `.claude/orion/orion.sh`, `.claude/orion/VERSION` | orion (refreshed by `update`) |
| A project `CLAUDE.md` | created from [`baselines/BASE_CLAUDE.md`](baselines/BASE_CLAUDE.md) if missing; an existing one only gets the import line `@.claude/orion/ORION.md` at the top | **you** — never touched again |
| The update check | one `SessionStart` hook in `.claude/settings.json`, and `.claude/orion/config.json` (`updateMode`) | **you** |

Commit the result on a branch. **Teammates need no install step**: Claude Code reads project skills and `CLAUDE.md` straight from the repo, so a clone or pull is enough.

Options: `--statusline` / `--no-statusline` (otherwise a y/N prompt when interactive; piped installs default to no), `--force` (overwrite a same-named skill that is not an orion copy, and re-seed the status line), `--source <git url|path>` / `--ref <branch>` (use a fork).

### Rules: orion's and yours

`.claude/orion/ORION.md` holds the general working rules orion ships (communication, git guardrails, definition of done). It is overwritten on every update, so **do not edit it**. Your project's rules live in `CLAUDE.md`, which imports it on its first line; **where the two disagree, your `CLAUDE.md` wins** (the baseline says so explicitly). The template `CLAUDE.md` is a starting point for a project run the orion way — fill every `<angle-bracket>` slot, delete the bullets you have no use for.

## How updates work

Each project updates on its own, with one command. Whoever runs it commits, and the team gets it by pulling.

1. **Automatic check.** The `SessionStart` hook runs `orion.sh check`, at most once a day per project, and compares `.claude/orion/VERSION` with the latest commit of orion's `main` (`git ls-remote`, no API, no token). It never blocks or fails a session.
2. **One-click update.** When a newer orion exists, Claude asks at the start of the session whether to update now. Yes runs `orion.sh update`; no is remembered for that session.
3. **Your choice of mode** — `updateMode` in `.claude/orion/config.json`:

| `updateMode` | Behaviour |
|---|---|
| `ask` (default) | Claude offers the update at session start. |
| `auto` | The hook applies the update silently and Claude tells you what changed; you still review and commit. |
| `off` | Never checks. Run `/orion update` (or `bash .claude/orion/orion.sh update`) when you want it. |

`update` re-copies only what orion owns: marked skills (added, refreshed, or removed when orion no longer ships them), `ORION.md`, `orion.sh`, `VERSION`. Skills without the marker, your `CLAUDE.md`, your `config.json` and the rest of `settings.json` are never touched.

The `/orion` skill (shipped with the rest) wraps all of this from inside Claude Code: `/orion status`, `/orion check`, `/orion update`, `/orion uninstall`.

### Why "ask" and not "auto" by default?

Auto-applying executable skill content is a supply-chain risk: anything pushed to orion's `main` would land in your project with no review. `ask` gives you a "did I really want this?" moment; switch to `auto` only for repos where you accept that.

## Skills

Each row is a one-line summary — the full behaviour contract lives in each skill's `SKILL.md`.

| Skill | What it does |
|---|---|
| **project-handover** | Generates a plain-language, code-internals-free HTML handover document for stakeholders and new joiners, with a dated epics-and-stories snapshot. Strictly read-only. |
| **generate-project-writeup** | Generates a leadership-facing Word (`.docx`) project write-up that leads with a transparent traditional-vs-actual cost comparison; every metric measured or marked "not measured." Strictly read-only. |
| **handoff** | Distils the current conversation into a single markdown handoff document a fresh agent can continue from — goal, state, decisions + rationale, dead-ends, open questions, next steps — referencing existing artifacts by path/URL instead of copying them. Saves outside the workspace to a location you pick, redacts secrets/PII, and tailors to what the next session is for. Explicit-invocation only; no git changes. |
| **wayfinder** | Charts a chunk of work too big for one agent session as a shared *map* issue plus typed decision tickets on the repo's tracker (detected at run time) — destination first, sharp questions become tickets, blurry ones stay written-down "fog" until they sharpen, anything past the destination is ruled out of scope. Resolves one ticket per session and records the decision back onto the map. Planning only; it produces decisions, not the deliverable. Adapted from the MIT-licensed [`wayfinder`](https://github.com/mattpocock/skills) skill. |
| **orion** | Manages the orion installation in the current repository: `status`, `check`, `update`, `uninstall`. Thin wrapper around `.claude/orion/orion.sh`. |

## Status line baseline (optional, per computer)

Besides skills, the repo ships a **Claude Code status line** as a baseline (`baselines/statusline/`): install it if you want it, then it is yours to change. One line, live in every session:

> `1h23m` | `ctx: 42.5%` | `[branch] ◆0 ◯1 ●2 ▲1` | `#12 ok` | **`$1.23`** `$345.67` | `Opus` | `effort:high` | `⚑0` | `5h:23% ↻2h14m` | `7d:41% ↻3d5h`

- session alive time, context-usage % (color-coded), git branch + state indicators, PR status for the current branch (cached, background-refreshed), **cost**: API-equivalent USD for the **open session** (green) plus the **current calendar month to date across all projects** (blue, computed from local transcripts via [ccusage](https://github.com/ryoppippi/ccusage)), the **model name**, the **reasoning-effort level** (when the model exposes one), a **jobs flag** (`⚑N` when background agent sessions are running), and — rightmost, each in its own colour — the **subscription usage limits**: how much of the **5-hour** and **7-day** window is used and how long until each refreshes (subscription sessions only).
- **a baseline, not a managed copy**: it is a per-computer setting, so `init` copies the folder **once** to `~/.claude/statusline` and writes the `statusLine` entry into `~/.claude/settings.json`. After that the copy is yours — edit it freely; `update` never touches it. To reset to the baseline, delete the folder or pass `--force` together with `--statusline`.
- installing it is **opt-in**: pass `--statusline` to `init`, or answer the y/N prompt during an interactive install. Each teammate decides for their own computer.

```sh
curl -fsSL https://raw.githubusercontent.com/nachogl1/orion/main/orion.sh | bash -s -- init --statusline
```
```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/nachogl1/orion/main/orion.ps1))) init --statusline
```

Requirements and details (jq required; gh and node optional): see [`baselines/statusline/README.md`](baselines/statusline/README.md).

## Add a new skill

1. Drop the skill folder under `skills/`. Each skill is a directory containing `SKILL.md` (uppercase — case-sensitive filesystems matter).
2. `git add skills/<name> && git commit && git push`.
3. Every project picks it up on its next `orion update` (offered automatically at session start in `ask` mode).

## Uninstall

```sh
bash .claude/orion/orion.sh uninstall        # or: /orion uninstall inside Claude Code
```

Removes everything orion owns from the project: the marked skill copies, `.claude/orion/`, the import line in `CLAUDE.md` (the rest of the file stays), and the `SessionStart` hook entry in `.claude/settings.json`. Your own skills and rules stay. The status line is a per-computer copy and is left alone — delete `~/.claude/statusline` and its `statusLine` entry in `~/.claude/settings.json` by hand if you no longer want it.

## Contributing

The working rules for changes to this repo live in [`CLAUDE.md`](CLAUDE.md) — read it before contributing (it's written for AI agents working in the repo, but the rules bind humans equally). The short version:

- **Distribution safety (highest-priority rule).** Everything here is publicly distributable. Never introduce anything that identifies a specific person, team, company, product, private repo, or machine — in prose, code, examples, placeholders, **and git metadata (commit messages, PR titles, PR bodies)**. Use runtime-resolved placeholders (`<repo-name>`, `<gh-login>`, `#<N>`, `~/.claude`) instead; skills detect everything project-specific from the target repo at run time. Self-check your diff *and* your commit/PR text before pushing.
- **Versioning.** All current skills (and the baselines) are edited in place. Skills carrying a `-vN` suffix are immutable per version — copy to a bumped `-vN` rather than editing in place, add a CHANGELOG entry, and add the new row to this README.
- **Issues.** Before filing one, dedupe first — search open issues *and* the code; never point at a **closed** issue as the reason to skip work.
- **PR/commit hygiene.** Branch off `main`; commit messages follow [Conventional Commits](https://www.conventionalcommits.org/) (`type(scope): description`, e.g. `fix(orion): guard the hook merge`); keep `orion.sh` portable bash and `orion.ps1` pure-ASCII, Windows-PowerShell-5.1-compatible; keep PR bodies as generic as the code they describe.

## License

[MIT](LICENSE) — free to use, modify, and redistribute with attribution.
