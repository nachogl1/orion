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
| **clear-resources-orion** | Lists and removes the local branches, git worktrees, and remote branches you *created* (anything not the default branch whose first/divergent commit is authored by your `git config user.email` — branches you only contributed a commit to are left alone). Default branch, remote, and identity are all detected at runtime — works in any repo on any platform. Presents three lists for one consolidated confirmation before deleting. |
| **itemize-orion** | Walks through a list of items, concerns, or decisions one at a time, treating you as a junior dev with zero domain knowledge. For each item: restate plainly, present options, give an explicit recommendation, then wait for your pick before continuing. |
| **guided-qa-orion** | Companion-style, story-by-story QA of an already-built batch, driven by a QA report (HTML/MD) you provide. QAs one story at a time against the live app, HALTS with an exhaustive verdict + findings, and asks you what to do (fix / log an issue / defer / accept) before advancing. Nothing commits until the full test suite + e2e are green and you approve. Stack, test commands, auth, and issue tracker are all detected/parameterized — pairs well with a long-running pipeline that emits the report. |
| **assign-issues-orion** | Plans ~2 days of work for *you* and assigns the issues on the host. Asks your username and how many issues (1–6); counts what's already assigned to you toward that target; gathers context epic-first (epic completeness + what teammates are doing) rather than brute-forcing every open issue; and clusters the picks in one feature slice that's isolated from teammates' active lanes, so the work is parallelizable and collision-free. Dependency-checked, feasibility-checked against the 2-day window. |
| **sequential-bmad-github-orion-v2** | Production-ready, strictly one-at-a-time, four-agent per-issue pipeline (create-story → implement → code-review → build/test/PR/CI/merge into batch) against a shared batch branch, with the success bar being code a senior dev would merge to main without follow-up work. After the queue, a two-agent batch-QA pipeline (test-and-fix → PR-author) runs full tests + e2e + a live-stack junior-tester QA gate, writes a `qa-report.html`, and opens a Draft PR batch→main. Instead of long-polling it **pauses for your free-form signal** ("merged" / "closed"); on merge it closes the batched issues and drops a per-run stats HTML in your Downloads. **Assumes [BMAD](https://github.com/bmad-code-org/BMAD-METHOD) + GitHub Issues** (confirmed upfront). Build/test commands auto-detected. |
| **sequential-bmad-github-orion-v3** | Same pipeline as v2, plus three fixes from real-run findings. **Deferral tracking:** every "out of scope" item (pre-existing baseline failures, carry-forward gaps) is filed into a find-or-reuse tracking `#N` and linked back into the PR bodies, so deferred work can't silently leak; a Phase-4 pre-close check and a stats-report scope-ledger panel keep it honest. **Hard CI gate:** a per-issue PR with red or still-pending CI never merges into the batch (pre-merge gate + orchestrator post-merge audit that reverts a slip-through). **Human-like QA:** the live-stack gate drives the app by navigating the real UI rather than deep-linking to known URLs, surfacing the broken-nav/dead-button bugs a real user hits. **Assumes [BMAD](https://github.com/bmad-code-org/BMAD-METHOD) + GitHub Issues** (confirmed upfront). Build/test commands auto-detected. |
| **create-up-to-speed-report-orion** | Generates a single self-contained dark-themed HTML onboarding deck for the current project, dropped into your Downloads folder. Written for a junior dev with zero stack/domain knowledge: product context, the stack with glossaries + ASCII diagrams, architectural patterns, dev-environment boot guide, live status from the issue tracker, a per-epic/story walkthrough with color-coded ownership, and a hands-on QA walkthrough of everything built. Adapts to any repo; invents no numbers; redacts secrets/PII. |
| **project-status-forecast-orion** | Reads the project's backlog from whatever it actually uses (local BMAD story docs, GitHub Issues, Jira, GitLab/Linear — detected at runtime), measures real scope + velocity + trend, and projects a **phase-aware, multi-speed forecast to a deploy-ready date** — not just "dev done." Models the full timeline (ramp-up → development → pre-deploy QA → refinement → deploy) and runs conservative/expected/optimistic scenarios, graduating to Monte-Carlo P50/P85/P95 bands as run-over-run history accumulates. Appends a dated snapshot each run (per-project, local-only) so forecasts sharpen over time, and emits a single self-contained dark-theme HTML stakeholder deck (inline-SVG charts) into your Downloads folder. Invents no numbers; leads with a one-glance RAG verdict + deploy-ready range. |

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
