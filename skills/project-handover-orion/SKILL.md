---
name: project-handover-orion
description: "Generate a single self-contained dark-themed HTML PROJECT HANDOVER document for the current repository, dropped into the user's Downloads folder, written for a BRAND-NEW JUNIOR DEVELOPER who just joined and is taking the project over — assume zero knowledge of the tech stack and zero knowledge of the domain, explained in plain language, summarised and clear (every stack/domain term defined on first use, concrete examples from the actual repo). Tuned for OFFBOARDING: it captures the whole-project context plus the departing engineer's footprint (the areas they owned, their open branches/PRs, their WIP) — i.e. the in-their-head context a diff alone won't show. The doc is a scrolling reference page with a sticky table-of-contents: TL;DR, product & domain context, architecture & mental model WITH general-level ASCII diagrams of the project's components and how they interconnect plus a request/data-flow diagram (drawn from the real repo), repo & dev environment (auto-detected build/test/run), current state (live from GitHub when a remote + gh are available, else local git), git-history footprint & ownership, prioritized open threads & next steps, known issues/gotchas/traps, open questions/decisions pending, resources & contacts, and a glossary. Detects the project's stack and conventions from its own files at run time — assumes no stack; uses gh when present and degrades gracefully to local-only. STRICTLY READ-ONLY: it reads git + repo files + GitHub and writes ONE HTML file to Downloads; it never edits the repo and never commits. Use when the user says '/project-handover-orion', 'create a handover', 'I'm leaving the project / offboarding', 'hand this project over', or wants a single HTML file a successor can read to take over."
user_invocable: true
---

# project-handover-orion

> [!NOTE]
> **Editing this skill?** This skill has **no `-vN` convention** — edit it in place
> (like `guided-qa-orion` / `assess-project-docs-orion`). Keep everything here
> **general** (see the Distribution-safety gate below) — this repo is publicly
> distributable. The *report* it generates about a user's repo is a local artifact
> and may name their repo; the skill files must never hard-code anything
> project-specific.

Produce a single self-contained dark-themed **HTML handover document** in the user's
Downloads folder that gets a successor from "I've never seen this project" to "I know
what it is, how it's built, where it stands, what the departing engineer owned, and
exactly what I should pick up first."

The output is a **scrolling reference page with a sticky table-of-contents** (not a
slide deck) — a successor will search it and return to it repeatedly, so anchored,
scannable sections beat one-pass slides. It lives at
`~/Downloads/<repo-name>-handover-<YYYY-MM-DD>.html` (Windows:
`%USERPROFILE%\Downloads\…`) so it's instantly shareable.

## When to invoke

User says `/project-handover-orion`, says they're **offboarding / leaving the project**,
asks to **hand the project over**, or wants a single HTML file a successor can read to
take ownership.

## Operating principles (read these first)

- **Audience: a brand-new junior developer who just joined the company** and is taking the
  project over — assume **zero knowledge of this project's tech stack and zero knowledge of
  the domain.** Write in **plain, friendly language**; define **every** stack term, library,
  acronym, and domain word on first use; reach for a simple analogy when it helps (a recipe
  for a template, a bouncer for auth — pick one that fits the actual code). Never assume they
  know a framework, tool, or business concept the way a senior would.
- **Summarised and clear — not a wall of text.** The goal is *fast comprehension*, not
  exhaustiveness. Prefer short paragraphs, bullets, small tables, and one concrete example
  over long prose. Each concept gets: a one-line plain definition → *why it exists here* → a
  **concrete example pulled from this actual repo** (a real file/entity/endpoint, with its
  path so they can go look). Cut anything that doesn't help a newcomer act.
- **Explain intent and trade-offs, not just facts.** A junior can read the code; what they
  can't recover is *why* it's built this way and what to be careful of — make that explicit.
- **This is offboarding, not a branch hand-off.** Cover the **whole project** as the
  thing being inherited — and additionally surface the **departing engineer's footprint**
  (areas owned, WIP, open branches/PRs) so the successor knows what was "in their head."
- **Source of truth = the repo + git history + GitHub.** Read files for architecture and
  conventions; read **git history** for the footprint; use `gh` for live issue/PR/CI data
  **when a GitHub remote and authenticated `gh` are present**, and **degrade gracefully to
  local-git-only** otherwise (say which mode the doc reflects on the cover). **Do not
  invent numbers** — mark anything not tracked as "not tracked."
- **Strictly read-only.** The skill reads git, repo files, and GitHub, and writes exactly
  **one HTML file to Downloads**. It **never edits the repo, never commits, never pushes.**
- **Assume no stack.** Detect build/test/run commands, layout, and conventions from the
  project's own manifests at run time. Never carry another project's stack or vocabulary
  over.
- **Output is a single HTML file.** No external assets, no network-loaded CSS. All styles
  and scripts inline so the file is portable and shareable.
- **Distribution-safety self-check** before writing (see gate). The generated report is a
  local artifact and may name the user's repo/people; the **skill files** must stay general.

## Inputs / pre-conditions

- A **target repository** — default to the current working directory's repo
  (`git rev-parse --show-toplevel`).
- **Departing-engineer identity** — default to `git config user.email`; confirm with the
  user (they may be handing over on someone else's behalf, or use multiple emails).
- **Optional successor name** — if the user gives one, address the doc to them on the cover.
- **GitHub** — optional. Detect `git remote -v` + `gh auth status`; if absent, run
  local-only and note it.

## Workflow

### Step 1 — Confirm scope (brief)

1. Resolve the repo root and name (filename + headings only — a local artifact).
2. Confirm the **departing engineer's identity** (default `git config user.email`; the doc
   colors the footprint section around this). Ask for a **successor name** only if not
   already given — optional.
3. Detect **data mode**: GitHub-available (remote + `gh auth status` OK) vs. local-only.
   State the mode you'll use and proceed. Use `AskUserQuestion` only if something's
   genuinely ambiguous; otherwise state the plan in one line and continue.

### Step 2 — Discover the project

Read these in order (some won't exist) and synthesize, citing file paths:

1. `CLAUDE.md` / `AGENTS.md` / `.claude/rules/*.md` → ground rules, must-always/never,
   conventions.
2. `README.md` (root + per-package) → elevator pitch, what the repo is.
3. Architecture / spec docs: `ARCHITECTURE.md`, `architecture.md`, `prd.md`,
   `product-brief*.md`, `docs/architecture/**`, `docs/prd/**`, `docs/design/**`,
   `_bmad-output/**`, ADRs / decision logs.
4. Top-level layout → the real organizing principle (`apps/`, `src/`, `packages/`,
   `services/`, `cmd/`, modules, …).
5. **Manifests for the exact stack & commands** (detect, don't assume): `*.sln`/`*.csproj`,
   `pom.xml`, `build.gradle`, `Cargo.toml`, `go.mod`, `pyproject.toml`/`requirements.txt`,
   `package.json`+lockfile (npm/pnpm/yarn/bun; workspaces), `Makefile`, `Taskfile`. Derive
   **build / test / run / lint** commands from what's actually present.
6. `.claude/skills/**/SKILL.md` → team workflows in use (BMAD, sequential pipelines, etc.).
7. CI: `.github/workflows/**`, `.gitlab-ci.yml`, `azure-pipelines.yml` → how it ships.

Synthesize: **product & domain** (what problem it solves, who uses it, vocabulary), the
**architectural mental model** (the 3–5 load-bearing patterns + data flow), the **dev
environment** (boot/build/test/run, conventions), and the **key-files map** (where things
live, with paths).

### Step 3 — Derive the departing engineer's footprint from git history

Use the confirmed identity. **Read-only git** only:

- **Contribution span & volume** — `git log --author=<email> --pretty=…` (first/last commit
  dates, commit count). Note if they're effectively the sole author (footprint == whole
  project) vs. one of many.
- **Hot areas owned** — aggregate `git log --author=<email> --name-only` (or
  `git log --author=<email> --numstat`) into the directories/files they touched most. These
  are the areas where their context is densest — call them out by path with a one-line "why
  this matters."
- **Open WIP** — `git status` (uncommitted changes), `git stash list` (stashes that would be
  lost), local branches they authored (`git for-each-ref --format=… refs/heads` + author
  filter) with `git log <base>..<branch>` to summarize each branch's intent and whether it's
  ahead/stale.
- **Open PRs (if GitHub)** — `gh pr list --author @me --state open --json number,title,…`
  (or by the resolved login). Summarize each: what it does, review state, what's blocking.

Turn this into the **"My footprint & ownership"** narrative: *what the successor is
inheriting that isn't obvious from the current code* — the half-finished branch, the area
only this person understands, the stash worth recovering.

### Step 4 — Capture current project state

- **Branch/working-tree state** — current branch, ahead/behind base, uncommitted/untracked,
  stashes.
- **Open work (if GitHub)** — `gh issue list --state open --limit 500 --json …`,
  `gh pr list --state open --limit 500 --json …`; CI health via `gh run list`/`gh pr checks`.
  Compute closed/open counts only from real data. **If local-only:** report what git can
  show (recent activity, open branches) and clearly mark tracker/CI status as "not available
  in local-only mode."
- **Next-steps raw material** — pull open issues/PRs, `TODO`/`FIXME` markers
  (`git grep -nE "TODO|FIXME"`), and any `lessons-learned.md` / backlog docs into a
  prioritized list for §Open threads.

### Step 5 — Generate the HTML (sections)

One self-contained scrolling page with a **sticky left/▾top table-of-contents** linking to
each `<section id="…">`. Adapt sections to the project (drop what doesn't apply rather than
fabricate). Default sections:

1. **Cover / header** — project name, "Project Handover", date, departing engineer, optional
   successor, and a **data-mode badge** (GitHub-live vs. local-only).
2. **TL;DR** — 3–5 sentences: what the project is, its current state, and the **top 3 things
   the successor must pick up first** (linked to §Open threads).
3. **Product & domain context (explain like the reader joined today)** — in plain language:
   what the product *does*, who uses it, the problem it solves, and the handful of domain
   words a newcomer would stumble on — each defined in one line with a real example from the
   repo. Assume they know nothing about the business; teach the minimum that makes the rest
   of the doc make sense. (The fuller term list lives in §12.)
4. **Architecture & mental model (lead with diagrams)** — the stack named and **each piece
   explained in plain English** (what it is → what it does for us → a real file that uses it),
   the 3–5 major components, and the load-bearing design decisions (the *why* + trade-offs).
   **Include general-level diagrams** so a newcomer sees the shape before the words:
   - a **top-level system / component diagram** — the major pieces (frontend, API, worker,
     database, cache, queue, external services, …) drawn as **boxes with labelled arrows
     showing how they interconnect** and which way data/calls flow;
   - a **request / data-flow diagram** for one core user action — "user clicks X → hits
     `<file/endpoint>` → does Y → reads/writes Z → returns" — tracing one real path end to end.
   Draw them as **ASCII art in `<pre><code>`** (≤100 chars/line, with a tiny legend), derived
   from the **actual** repo (real component and file names, not a generic template). Add a
   third diagram (auth flow, deployment topology, or module boundaries) only if it genuinely
   clarifies. Keep each diagram simple and general — orient, don't exhaustively map every
   class. Follow each with 2–3 plain-English sentences explaining what it shows.
5. **Repo & dev environment** — a **step-by-step "get it running" guide** a newcomer can
   follow: auto-detected **setup / build / test / run** commands with a one-line note on what
   each does; conventions (branching, commits, CI) in plain terms; a **key-files map**
   (path → what lives there) so they know where to look.
6. **Current state** — done / in flight; open PRs & branches; CI health; counts from real
   data. Marks anything unavailable in local-only mode.
7. **My footprint & ownership** — from Step 3: areas owned (by path), open WIP (branches,
   stashes, uncommitted), open PRs — the "in my head" context. Visually distinguish this
   engineer's footprint (accent color) from general project state.
8. **Open threads & next steps** — **prioritized**: in-progress → planned → backlog, each
   actionable enough that the successor needn't reverse-engineer intent. Lead with the top 3
   from §TL;DR.
9. **Known issues, gotchas & traps** — tribal knowledge: flaky tests, workarounds, sharp
   edges, "don't touch X without Y," surprising couplings.
10. **Open questions / decisions pending** — unresolved design/product calls the successor
    inherits, with the options/context known so far.
11. **Resources & contacts** — links to issues/PRs/docs/dashboards and key people/teams (in
    the **local** report only — see safety gate). Mark anything you couldn't verify.
12. **Glossary** — every stack term, library, acronym, and domain word a newcomer would not
    already know, each with a one-line plain-English definition and (where possible) the code
    artifact it maps to. Err toward including a term rather than assuming it's obvious.

### Step 6 — Visual + technical conventions

- **Dark theme** (match the other orion report skills):
  - `--bg: #0b1020`, `--bg-2: #121933`, radial-gradient background
  - `--accent: #5cc8ff`, `--accent-2: #b08cff`, `--good: #4ade80`, `--warn: #fbbf24`,
    `--danger: #f87171`
  - Font: system sans-serif; code: JetBrains Mono / `ui-monospace` fallback
- **Layout: scrolling page, not a deck.** A **sticky table-of-contents** (sidebar on wide
  screens, collapsing to a top bar on narrow) with anchor links to each `<section id>`.
  Implement **scroll-spy** in inline JS to highlight the current section in the TOC. Smooth
  in-page anchor scrolling. No keyboard slide navigation — it's a document.
- **Footprint accent** — the departing engineer's footprint/ownership content uses
  `--accent-2` so it's visually separable from general project state.
- **Priority pills** for §Open threads — e.g. `.pri-now` / `.pri-next` / `.pri-later`
  using `--danger`/`--warn`/`--good`.
- **ASCII diagrams** in `<pre><code>` blocks; ≤100 chars/line, each with a tiny legend and a
  2–3 sentence plain-English caption. §4 must carry at least a **top-level interconnection
  diagram** and a **request/data-flow diagram**, drawn from the real repo (real names).
- **Language = English** regardless of the project's doc language; gloss native terms on
  first use as `<native term> (English gloss)`.

### Step 7 — Write the file

Output path:
- Linux/macOS: `~/Downloads/<repo-name>-handover-<YYYY-MM-DD>.html`
- Windows: `${env:USERPROFILE}\Downloads\<repo-name>-handover-<YYYY-MM-DD>.html`

`<repo-name>` = repo name (lowercase, hyphenated), from `gh repo view --json name -q .name`
when available, else the toplevel folder name. `<YYYY-MM-DD>` = today.

### Step 8 — Verify, then report

- Read the file back briefly: valid HTML, every TOC link resolves to a real `<section id>`,
  scroll-spy script present.
- Confirm no markdown escapes leaked into HTML (no raw `**bold**`, `# headings`).
- Confirm UTF-8 survived — accents, em dashes, arrows render when read back.
- On Windows, if a PowerShell write added a BOM / double-encoded, re-encode without BOM:
  ```powershell
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
  ```
- **Report in chat:** absolute file path, the **data mode** used (GitHub-live / local-only),
  the section count, and a 3-bullet summary — what the doc covers, what the top-3 pick-up
  items are, and what date/snapshot it reflects. The skill ends here — it does **not** edit
  the repo, commit, or offer to.

## What to NOT include

- **No fabricated numbers / status.** Not in `gh`/git/manifests → mark "not tracked" or "not
  available (local-only)." Never guess velocity, counts, or CI state.
- **No credentials, secrets, internal IPs, tokens, VPN configs, or production hostnames** —
  even if read from config. Replace with `<placeholder>` or omit.
- **No verbatim CLAUDE.md / CONTRIBUTING content** — summarize.
- **No repo edits, commits, or "I'll fix it" offers** — the doc is the deliverable.

## Failure modes to watch

- **PowerShell `Set-Content -Encoding utf8` adds a BOM / may double-encode.** Use
  `[System.IO.File]::WriteAllText` with `New-Object System.Text.UTF8Encoding $false`.
- **No GitHub remote or `gh` not authed** — run local-only; clearly badge it on the cover and
  mark tracker/CI sections unavailable. Don't fabricate a tracker.
- **`gh` lists truncated** — always pass `--limit 500` (or higher).
- **Departing engineer is the sole/dominant author** — §My footprint effectively *is* the
  whole project; say so and lean the doc toward exhaustive whole-project coverage.
- **Multiple author emails** — confirm the set with the user; union them in the
  `--author` filters so the footprint isn't undercounted.
- **Shallow clone / squashed history** — git-history footprint is degraded; note the limit
  and lean on file-ownership + current state instead of commit counts.
- **No architecture/PRD docs** — build §Architecture by reading entry points and tracing
  dependencies; cite file paths so the successor can verify.
- **Multi-language docs** — translate to English on first use, keep the original term in
  parentheses so the successor can grep later.

---

## Distribution-safety gate (this repo is publicly distributable)

This skill ships publicly. Before writing the report, confirm **nothing project-specific
leaked into the skill files** — no person/org/product/repo/stack/locale/path specifics in
prose or examples. The **generated report** about a user's repo is a **local artifact** (in
their Downloads) and may name their repo, people, and dashboards — that's fine; it is never
committed back into this repo. What must stay general is everything under
`skills/project-handover-orion/` itself.
