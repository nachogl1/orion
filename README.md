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

1. Asks which agent these skills are for (default: Claude Code → `~/.claude/skills/`).
2. Copies each skill in `./skills/` into the target dir (marking each copy `.orion-managed`).
3. Asks whether to register a scheduled auto-pull (default: **none** — manual updates are recommended).

Non-interactive form (no scheduled task registered):

```powershell
.\install.ps1 -Force                         # Windows
```
```sh
./install.sh --force                          # macOS / Linux
```

### After install

Open any project in Claude Code and type `/clear-resources-orion` — you should see a list of branches/worktrees you created, ready for one-confirmation removal.

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

| Skill | What it does |
|---|---|
| **clear-resources-orion** | Lists and removes the local branches, git worktrees, and remote branches you *created* (anything not the default branch whose first/divergent commit is authored by your `git config user.email` — branches you only contributed a commit to are left alone). Default branch, remote, and identity are all detected at runtime — works in any repo on any platform. Presents three lists for one consolidated confirmation before deleting. |
| **itemize-orion** | Walks through a list of items, concerns, or decisions one at a time, treating you as a junior dev with zero domain knowledge. For each item: restate plainly, present options, give an explicit recommendation, then wait for your pick before continuing. |
| **guided-qa-orion** | Companion-style, story-by-story QA of an already-built batch, driven by a QA report (HTML/MD) you provide. QAs one story at a time against the live app, HALTS with an exhaustive verdict + findings, and asks you what to do (fix / log an issue / defer / accept) before advancing. Throughout the run it maintains **one consolidated `qa-findings.md`** — every story's verdict, the tests run, and all findings (with each filed/deferred `#N`) — written beside the input report (for a `sequential-bmad-github-orion-v4` run, that's the batch session folder under `~/Downloads/`), so you're left with a single actionable document. Nothing commits until the full test suite + e2e are green and you approve. Stack, test commands, auth, and issue tracker are all detected/parameterized — pairs well with a long-running pipeline that emits the report. |
| **assign-gh-issue-orion** | Picks *N* issues for *you* (the number you ask for, **2 by default**) and assigns them on the host. Every pick must be **agent-ready** — an autonomous coding agent can take it and ship without a human decision mid-flight; when a promising issue hides an open decision (ambiguous scope, design/product question, missing spec), the skill **HALTS, asks you to resolve it, records the answer onto the issue**, and only then counts it eligible. Asks your username and the count; counts what's already assigned to you toward the target; gathers context epic-first (epic completeness + what teammates are doing) rather than brute-forcing every open issue; clusters the picks in one feature slice isolated from teammates' active lanes, so the work is parallelizable and collision-free. Dependency-checked; no time budget — driven by the issue count. |
| **sequential-bmad-github-orion-v4** | Production-ready, strictly one-at-a-time, four-agent per-issue pipeline (create-story → implement → code-review → build/test/PR/CI/merge into batch) against a shared batch branch, then a two-agent batch-QA pipeline (test-and-fix → PR-author). Plus three improvements. **Run from any base branch:** the batch forks from — and the Draft PR targets — whatever branch you invoke it from (a feature/integration branch, or a separate worktree), so you can keep working on `main` untouched while a batch runs; running from `main` behaves as before. **TODOs to lessons-learned:** a TODO/FIXME left during development is recorded in `lessons-learned.md` (file:line + what/why) so a deferred feature/gap isn't forgotten. **Neutral, exhaustive QA report:** `qa-report.html` is now a test plan for an independent full-round QA agent — claims phrased as things to verify (not "we're green"), with per-story error/empty/persistence angles, a "most likely to be broken" risks section, and a "what automation did NOT cover" gap map. Keeps the deferral tracking (find-or-reuse `#N`s linked back into PR bodies), hard CI-green merge gate, and human-like live-stack QA. **Assumes [BMAD](https://github.com/bmad-code-org/BMAD-METHOD) + GitHub Issues** (confirmed upfront). Build/test commands auto-detected. |
| **fable-sequential-gh-orion-v1** | The **BMAD-free successor** of the `sequential-bmad-github-orion` family (which stays available as the fallback), built on Fable-5-era primitives. Same production-ready bar and hard CI-green merge gate, but per issue a **Workflow** runs: strong-model **spec agent** (grounds the issue against live code, posts the spec as an issue comment — no story files) → implementer in a worktree forked from the batch tip → **3 parallel adversarial reviewers** + fix agent → finalize to PR-open; the orchestrator owns CI-watch + squash-merge into the batch. Designed for **overnight unattended runs**: failures **park-and-continue** (full diagnosis record, branch preserved; the queue never blocks on a human), and the pipeline **never merges to the base branch** — it ends with a neutral `qa-report.html` (input for `fable-guided-qa-orion`), a Draft PR batch→base, ultrareview flags for risky PRs, and a steering report; you merge after your own QA. Every run closes with a **retro agent** proposing project-knowledge updates and generalized skill improvements. GitHub Issues as source of truth; build/test auto-detected. |
| **fable-project-updates-orion** | Turns a raw pasted list of updates/corrections/bugs for an **existing** project into an agent-ready GitHub backlog while consuming minimal user attention: a parallel **grounding fan-out** (one read-only agent per item) verifies each item against the live code and either auto-drafts a complete issue or flags the specific human decision it needs; only the flagged pile is discussed — one item at a time, itemize-style, options + one recommendation. Feature-sized items get an in-session epic/story breakdown reviewed before filing. Mandatory dedupe deep-dive before anything is filed; reuse over create. |
| **fable-prd-orion** | Greenfield project inception at analyst depth without BMAD: interview-driven elicitation in rounds at a **user-chosen depth** (quick / standard / exhaustive), optional **market-research fan-out** (parallel researchers, claims verified and cited), the PRD (optionally via a judge panel over independent scoping drafts), an architecture overview, and a **UX prototypes decision** — your references become canon, or X distinct design-direction flavours are generated in parallel as clickable self-contained HTML prototypes in Downloads for you to choose or mix. Docs committed to the repo, then the epic/story breakdown is built and **reviewed with you in-session before anything is filed** as GitHub epics + stories, each agent-ready for `fable-sequential-gh-orion-v1`. |
| **fable-guided-qa-orion** | Fable-5-era sibling of `guided-qa-orion` (which stays untouched): the same supervised story-by-story live-app QA loop — record-and-continue, one consolidated decision session, fix-first/file-rarely, triple commit gate — upgraded with **full test + e2e suites running as background tasks** while live clicking continues, a **per-story code-level finder fan-out** that pre-reads each story's diff so the walkthrough starts with a target list, first-class handling of the fable pipeline's report contract (DO-NOT-CHASE `#N`s; **Parked-issues** section — absent features are not bugs), and a retro block feeding the pipeline's self-improvement loop. |
| **create-up-to-speed-report-orion** | Generates a single self-contained dark-themed HTML onboarding deck for the current project, dropped into your Downloads folder. Written for a junior dev with zero stack/domain knowledge: product context, the stack with glossaries + ASCII diagrams, architectural patterns, dev-environment boot guide, live status from the issue tracker, a per-epic/story walkthrough with color-coded ownership, and a hands-on QA walkthrough of everything built. Adapts to any repo; invents no numbers; redacts secrets/PII. |
| **project-status-forecast-orion** | Reads the project's backlog from whatever it actually uses (local BMAD story docs, GitHub Issues, Jira, GitLab/Linear — detected at runtime), measures real scope + velocity + trend, and projects a **phase-aware, multi-speed forecast to a deploy-ready date** — not just "dev done." Models the full timeline (ramp-up → development → pre-deploy QA → refinement → deploy) and runs conservative/expected/optimistic scenarios, graduating to Monte-Carlo P50/P85/P95 bands as run-over-run history accumulates. Appends a dated snapshot each run (per-project, local-only) so forecasts sharpen over time, and emits a single self-contained dark-theme HTML stakeholder deck (inline-SVG charts) into your Downloads folder. Invents no numbers; leads with a one-glance RAG verdict + deploy-ready range. |
| **project-handover-orion** | Generates a single self-contained dark-themed **HTML project-handover** document into your Downloads folder (`~/Downloads/<repo>-handover-<date>.html`), written for a **broad audience including clients and stakeholders** as well as new joiners — assumes **zero tech-stack and zero domain knowledge**, explained in plain language with every term defined on first use. **Neutral tone — addressed to nobody, by nobody:** no author, no successor, no offboarding/ownership framing. **No code internals:** describes the project at **general product-behaviour / module / feature** level (the code is often agent-generated, so class names and wiring aren't known or stable) — diagrams use generic component names only. **No stale-prone content:** omits open PRs/branches/WIP and "what to pick up next." The one status it carries is a **dated epics-and-stories snapshot** — every epic and story listed with a short description and a **done/not-done badge** (green = done, red = not done), status read from the project's actual backlog (BMAD story docs / GitHub Issues / Jira, detected at runtime). Scrolling reference page with a **sticky table-of-contents**: cover, TL;DR/overview, product & domain context, architecture & mental model (conceptual diagrams built as styled HTML/CSS boxes + arrows, never ASCII art), how it's built & run (auto-detected setup/build/test/run), the full epics & stories listing, and a glossary. For real **product depth**, the product & domain section can lean on the companion **create-up-to-speed-report-orion** skill's discovery, distilled back into the handover's neutral, no-code-internals voice. Detects stack/commands/conventions from the repo itself; invents no numbers. **Strictly read-only** — reads git + files + tracker, writes one handover HTML file (any onboarding deck used to enrich it is a separate by-product), never edits the repo or commits. |
| **generate-project-writeup-orion** | Generates a single polished **Microsoft Word (`.docx`) project write-up / closure summary report** into your Downloads folder (`~/Downloads/<repo>-project-writeup-<date>.docx`), written for **leadership / commercial stakeholders** to mark a project delivered. **Economics-first:** it leads with a transparent cost comparison — a defensible *traditional team × duration × blended-rate* baseline (cross-referenced to the COCOMO II Post-Architecture phase split, with an honest over-estimation caveat) against the **actual observed delivery**, headlining the money and time-to-market saved by an AI-assisted build. The **contributor count and full-time/part-time FTE split** that drive the math are **always confirmed with you** (git author lists miscount bots, AI-agent commits, and part-timers). It then assembles project overview, **scale-of-work metrics measured from the real repo** (LOC split prod-vs-test, commits, duration, modules, models, endpoints, tests, docs), backend/frontend/infra stack tables, architecture patterns, security, core features, an "invisible excellence" section (testing, code quality, design system), a traditional-vs-modern comparison, value delivered (risk + OPEX; revenue only if you supply a business case), and a documentation inventory. Renders via a **bundled zero-dependency Python generator** (no pandoc / `python-docx` / Word install needed), with pandoc and HTML fallbacks. **Invents no numbers** — every metric is measured or marked "not measured." Detects stack/conventions from the repo itself. **Strictly read-only** — reads git + files, writes one `.docx`, never edits the repo or commits. |
| **assess-project-ai-infrastructure-orion** | Grades a repo's **AI-development infrastructure** — docs, agent tooling, and (opt-in) your own Claude setup — against a **two-layer benchmark**: an independent *consensus* layer (widely-cited best-practice resources, re-validated at runtime) and an opinionated *orion* layer (generalized from real projects). Assessors cover the **agent instruction file** (`CLAUDE.md` / `AGENTS.md` / `.claude/rules`), the **README**, **contributing & governance** docs, the **PR template**, the **issue/ticket template** (with an **agent-ready vs needs-human-decision** marker), the project's **MCP servers / plugins / tooling** (recommending broadly-useful missing ones — browser-automation, container, knowledge-base, context-compression), and an opt-in **self-audit of your `~/.claude/` setup** (settings/hooks/memory/skills) for what's stale/broken/wasteful — the self-audit also tips you toward the opt-in [**orion status line**](#status-line-optional) when you have no status line or no cost visibility. Each area gets 0–5 dimension scores, a cited consensus checklist, an orion checklist, concrete gap fixes, and paste-ready snippets; a cross-cutting pass flags duplication/drift, missing high-value docs, and — if there's no tracker — proposes **GitHub Issues** as the single source of truth. Detects stack, tracker vocabulary, and conventions from the repo itself; emits a single self-contained dark-theme HTML report into your Downloads folder. **Strictly read-only** — reports and recommends only (every fix lives in the report), never edits the repo or your settings and never commits. |

## Status line (optional)

Besides skills, the repo ships a shared **Claude Code status line** (`statusline/`) you can opt into. One line, live in every session:

> `1h23m` | `ctx: 42.5%` | `[branch] ◆0 ◯1 ●2 ▲1` | `#12 ok` | **`$1.23`** `$345.67`

- session alive time, context-usage % (color-coded), git branch + state indicators, PR status for the current branch (cached, background-refreshed), and **cost**: API-equivalent USD for the **open session** (green) plus the **rolling last 30 days across all projects** (blue, computed from local transcripts via [ccusage](https://github.com/ryoppippi/ccusage)).
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
- **Versioning.** `sequential-bmad-github-orion-vN` skills are immutable per version — copy to a bumped `-vN` rather than editing in place, add a CHANGELOG entry, and add the new row to this README. Other skills (and the status line) are edited in place.
- **Issues.** Before filing one, dedupe first — search open issues *and* the code; never point at a **closed** issue as the reason to skip work.
- **PR/commit hygiene.** Branch off `main`; keep installer scripts pure-ASCII and Windows-PowerShell-5.1-compatible; keep PR bodies as generic as the code they describe.
