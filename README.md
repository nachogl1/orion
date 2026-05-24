# orion

A collection of general-purpose, **non-work** user-level [Claude Code](https://claude.com/claude-code) skills, kept in one repo and shared across every machine I work on.

The installer links each `skills/<name>/` folder into the agent's user skills directory (default `~/.claude/skills/`) using **directory junctions on Windows** and **symlinks on macOS/Linux**. The link points back at the cloned repo, so `git pull` *is* the update mechanism — no copy step, no re-install, no "apply" action. **Updates are manual**: run the installer with `-Update` / `--update` (or just ask Claude to do it for you) when you want to pull the latest skills. An optional scheduled auto-pull is available but disabled by default — see "How updates work" for the tradeoff.

> Work-specific skills (anything that references a specific product, team, or internal workflow) live only on the machines that need them — not in this repo. This keeps the repo safely shareable: no product names, no team identifiers, no internal paths.

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

1. Asks which agent these skills are for (default: Claude Code → `~/.claude/skills/`).
2. Creates a junction / symlink for each skill in `./skills/`.
3. Asks whether to register a scheduled auto-pull (default: **none** — manual updates are recommended).

Non-interactive form (no scheduled task registered):

```powershell
.\install.ps1 -Force                         # Windows
```
```sh
./install.sh --force                          # macOS / Linux
```

## How updates work

Updates are manual. After install, the user-level skill **is** the file in the repo (via the link), so a single `git pull` + relink pass propagates everything:

```powershell
.\install.ps1 -Update          # Windows
```
```sh
./install.sh --update           # macOS / Linux
```

…or just tell Claude something like *"update orion"* / *"pull the latest skills"* — Claude will run the update for you.

That one command handles all three change types:

| Change in the repo | What `-Update` does |
|---|---|
| Edit an existing skill | `git pull` updates the file the junction already points at. |
| Add a new skill | `git pull` brings the folder; the link step adds a junction for it. |
| Remove a skill | `git pull` deletes the folder; the prune step kills the dangling junction. |
| Rename a skill | Both — prune kills the old-name junction, link creates the new-name one. |

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

| Skill | What it does |
|---|---|
| **clear-resources-orion** | Lists and removes all your local branches, git worktrees, and remote branches (anything not the default branch with at least one commit by your `git config user.email`). Default branch, remote, and identity are all detected at runtime — works in any repo on any platform. Presents three lists for one consolidated confirmation before deleting. |
| **itemize-nacho-orion** | Walks through a list of items, concerns, or decisions one at a time, treating you as a junior dev with zero domain knowledge. For each item: restate plainly, present options, give an explicit recommendation, then wait for your pick before continuing. |

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

Removes the junctions / symlinks pointing into this repo and unregisters the scheduled task (if one was registered). The cloned repo itself is left in place — delete the folder if you don't want it.
