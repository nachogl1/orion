---
name: create-up-to-speed-report-orion
description: "Generate a comprehensive junior-developer onboarding HTML presentation for the current project, dropped into the user's Downloads folder. The deck covers product context, the stack with glossaries and diagrams, architectural ideas, the dev environment, current status (live from GitHub), per-epic + per-story walkthrough with color-coded ownership, optional governance summary, and a hands-on QA walkthrough exercising every closed unit of work. Tone: junior dev with zero stack or domain knowledge. Use when the user says '/create-up-to-speed-report-orion', 'generate onboarding deck', 'get-me-up-to-speed presentation', or wants a single HTML file they can read to ramp on a new project."
user_invocable: true
---

# create-up-to-speed-report-orion

Produce a single self-contained dark-themed HTML presentation that gets the reader from "I know nothing about this project" to "I can spin the stack up, click through every working feature, and tell you what shipped this week."

The output lives at `~/Downloads/<repo-name>-up-to-speed.html` (Windows: `%USERPROFILE%\Downloads\…`) so it's instantly shareable.

## When to invoke

User says `/create-up-to-speed-report-orion`, asks for an onboarding deck, asks to get up to speed on a project, or otherwise wants a comprehensive ramp-up document for the current repo.

## Operating principles (read these first)

- **Audience**: junior dev, no prior knowledge of the project's tech stack or domain. Always define jargon on first use. Use analogies (nightclub bouncer for auth, recipe for templates, etc.) — the right analogy depends on the project; pick one that fits the actual code you're reading.
- **Be exhaustive about the domain and what this repository does.** This is the whole point of the deck — the reader should finish knowing, in plain language, **what problem the project solves, the domain vocabulary, what this specific repository is responsible for within the wider system, and how each major feature works end-to-end.** Bias toward over-explaining the domain rather than under-explaining it. Every concept gets: a plain-English definition, *why it exists here*, and a **concrete example pulled from the actual repo** (a real entity, a real endpoint, a real screen, a real user journey — with the file path so the reader can go look). Abstract description without a concrete example from this codebase is a miss. When a domain term has a real-world meaning, give that first, then how this project uses it.
- **Tone**: friendly, concrete, example-driven. Short paragraphs. Tables and code blocks over prose. Never assume the reader knows any acronym, library, framework, or domain term — define every one inline on first use. **Which terms need defining depends entirely on this repo's stack** — they are whatever actually appears in the code you read in Step 1. It might be DLLs / OIDC / SignalR in one project; goroutines / gRPC in a Go service; hooks / hydration / SSR in a React app; coroutines / DI containers in Kotlin; CRDTs / WebRTC in a realtime tool. Do **not** carry a fixed term list (including these examples) over from another project — define the terms this repository genuinely uses, and skip the ones it doesn't.
- **Source of truth = the repo + GitHub**. Read files for architecture. Use `gh` CLI for live issue / story / contributor data. **Do not invent numbers.**
- **Output is a single HTML file**. No external assets, no CSS frameworks loaded over the network. All styles inline. Use a `<template id="slides">` + JS clone pattern for navigation so the file is portable.
- **Color-code ownership** on the per-story slides: blue = current user shipped, green = teammate shipped, red = pending.
- **Diagrams are ASCII art inside `<pre><code>` blocks**. Keep them readable on a projector; ≤ 100 chars per line.
- **Naming**: throughout the deck, use the actual project name (read from `gh repo view` or `package.json`), not a placeholder. Lower-case the repo name for the filename, title-case it for headings.

## Workflow

### Step 1 — Discover the project

Read these in order; some won't exist:

1. `CLAUDE.md` at repo root → ground rules, must-always / must-never, conventions
2. `README.md` at repo root → project elevator pitch
3. Architecture / spec docs in any of these locations:
   - `architecture.md`, `ARCHITECTURE.md`
   - `prd.md`, `PRD.md`, `product-brief*.md`
   - `docs/architecture/**`, `docs/prd/**`, `docs/design/**`
   - `_bmad-output/planning-artifacts/**` (if the team uses BMAD)
   - `.github/CONTRIBUTING.md`, `CONTRIBUTING.md`
4. Top-level folder listing → identify the actual layout (`apps/`, `src/`, `packages/`, `services/`, `cmd/`, etc. — varies by ecosystem)
5. Manifest files for the exact stack versions:
   - Backend: `.sln`, `.slnx`, `*.csproj`, `pom.xml`, `build.gradle`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `requirements.txt`
   - Frontend: `package.json`, `bun.lock`, `pnpm-lock.yaml`, `yarn.lock`
6. `.claude/skills/**/SKILL.md` files → which workflows the team uses (BMAD, sequential, dev-ticket, etc.)
7. CI configuration → `.github/workflows/`, `.gitlab-ci.yml`, `azure-pipelines.yml`

Synthesize:
- **Product**: what problem it solves, who uses it, market context, what came before (if it's a rewrite)
- **Stack**: exact backend + frontend versions, infra/auth, testing libraries — pulled from the manifest files, not invented
- **Architectural ideas**: the 3-5 patterns that shape every story (read the architecture doc or, if missing, infer from the code: layering, dependency direction, data flow, error handling convention, async/job pattern)
- **Dev workflow**: how to boot, what runs as container vs. native, dashboards

### Step 2 — Pull live data from the issue tracker

The skill assumes GitHub. If the project uses another tracker (Jira, Linear, GitLab), substitute the equivalent CLI and adapt the queries — surface this in the cover slide so the reader knows what's authoritative.

```bash
# Repo identity
gh repo view --json owner,name,description

# All closed issues with author + close date + labels
gh issue list --state closed --limit 500 \
  --json number,title,closedAt,assignees,author,labels \
  -q '.[] | [.number, (.assignees[0].login // "—"), .closedAt, (.labels | map(.name) | join(",")), .title] | @tsv'

# All open issues
gh issue list --state open --limit 500 \
  --json number,title,assignees,labels \
  -q '.[] | [.number, (.assignees[0].login // "—"), (.labels | map(.name) | join(",")), .title] | @tsv'

# If the team distinguishes "stories" from "bugs/chores/docs" via a label, fetch those separately
gh issue list --state closed --label story --limit 500 \
  --json number,title,closedAt,assignees
```

If the team doesn't use a `story` label, look for the actual labeling convention (`feat`, `feature`, `epic`, `task`, etc.) and use that. **Never invent a label that doesn't exist.**

Compute:
- Total issues / closed / open + same for stories/features if the project uses a distinguishing label
- First closure date → calendar + work days elapsed since
- Per-day, per-work-day, per-week rates
- Forecast at current pace
- Per-contributor counts (stories + non-story issues + total)
- Identify the current user from `git config user.email` → match to GitHub login via `gh api user` or by grepping recent commit authors

### Step 3 — Generate the HTML

Each chapter is one divider slide + N content slides. Adapt the chapter list to the project — if there's no client-agent, drop that section; if it's pre-launch, the status chapter reports planning state.

**Default chapter outline:**

1. **Cover** — project name, "Junior onboarding · merged deck", nav hints (← / → / Space / F for fullscreen)
2. **The Product & this repo's role** (~8–12 slides — be generous here; this is the chapter that orients everything else)
   - One-paragraph elevator pitch
   - **What this specific repository is responsible for** — its slice of the larger system (is it the API? the web client? a worker? the whole monolith?), what it owns vs. what it delegates to other services/repos, and where it sits in the overall topology. Cite the entry points.
   - Foundational domain concepts the reader needs **specific to this project's domain** — figure them out by reading the docs/code. Don't reuse another project's domain primitives. Each concept: plain definition → why it exists → a concrete instance from this repo (file path).
   - **The core workflows / user journeys**, narrated step by step in plain English — e.g. "a user does X → the request hits `<file>` → this happens → they see Y." One per major feature. This is where the reader learns what the thing actually *does*.
   - Competitors / alternatives and how this product differs
   - Legacy / predecessor (if it's a rewrite) and why
   - User personas (named, with what each cares about, and which features serve them)
   - **Domain vocabulary glossary** — exhaustive: every domain noun a newcomer would stumble on, each with a one-line plain definition and (where possible) the code artifact it maps to. Err on the side of including more terms.
3. **Big Architectural Ideas** (3–5 slides)
   - The 3–5 patterns that shape every story
   - One concrete walkthrough per pattern — a timeline of what happens when a real scenario plays out
4. **The Stack** (~6–10 slides)
   - Overview cards (Backend / Frontend / Infra+Auth / Testing)
   - Backend glossary table (every library, what it is, what it does for us)
   - Frontend glossary table (same format)
   - **System diagrams** (3–6) — top-level architecture, then per-area diagrams (auth flow, data flow, deployment topology, integration points). ASCII art in `<pre>` blocks
   - Repo / monorepo layout
   - Project structure (module boundaries / DLL boundaries / package boundaries — whatever the language calls it)
   - Architecture patterns (Vertical Slice, Hexagonal, Clean, MVC, etc. — whichever applies)
   - Cross-cutting concerns the framework handles automatically (auth, tenancy, logging, error handling)
   - Naming + format conventions (lifted from CLAUDE.md / CONTRIBUTING.md / equivalent)
   - Forbidden patterns
5. **Dev Environment & Workflow** (~6–10 slides)
   - How to boot the stack (one command + what happens)
   - Container vs. native split
   - Local dashboards / observability tools
   - Whether the dev tooling ships to prod (almost always no — explain why)
   - HTTPS / certs in dev (the classic "why didn't my dashboard render" trap, if applicable)
   - Service modes / environment switches (mock/prod/bridge pattern, if applicable)
   - Remote dev infrastructure (VPN, VMs, dev sandboxes) if the project has any
   - Identity / SSO architecture explained with a timeline (if applicable)
   - The team's spec-driven workflow (BMAD, RFC, ADR, design-docs — whatever they use)
   - Testing conventions
6. **The Domain** (~3–5 slides) — purely conceptual, no stories/epics
   - Vision in one paragraph + the product's promise
   - The N problems the product solves
   - Product principles
   - Key features at a high level (4–6 cards)
   - Architectural spine in one slide (the 5–7 rules that summarize how it's built)
7. **Where We Stand** (1–3 slides)
   - Totals (epics if any, stories if labelled, all issues — closed / open / share)
   - Elapsed time (calendar + work days, with the actual dates listed so the reader can verify)
   - Rates per day / per work day / per week
   - Forecast at current pace
   - If the user has a target deadline, target rate to hit it; per-engineer breakdown
8. **Contributor Breakdown** (1 slide between status and per-epic walkthrough)
   - Per-engineer story + issue counts as a table
   - Share of total team output
   - Each person's current cadence
9. **Every Epic, Every Story** (1 chapter divider + 1 slide per epic, or per area/module if no epic structure)
   - Each slide: title, brief, progress pill (`X / Y closed · Z%`), every story as a color-coded row with `#issue · ID · title · assignee`
   - Color legend on the divider: 🔵 mine · 🟢 team · 🔴 pending
   - Append a "My deliveries — concerns & takeaways" slide summarizing what the current user shipped + any QA-time bugs / known concerns
10. **Governance proposal summary** (optional, 1 slide) — if the project has proposed changes to its conventions (`CLAUDE.proposed.md`, draft RFC, open style-guide PR), summarize as a single-slide table
11. **QA Walkthrough — Everything Built So Far** (~6–12 slides)
    - One stack boot, one login (or one entry point), then a logical flow through every working feature
    - Each step cites the Epic.Story / Module.Feature / RFC it verifies
    - Tag steps the current user shipped with `<span class="tag-mine">MINE</span>`
    - End with a "What's NOT built yet" slide

### Step 4 — Visual + technical conventions

- **Dark theme**:
  - `--bg: #0b1020`, `--bg-2: #121933`, radial gradient background
  - `--accent: #5cc8ff`, `--accent-2: #b08cff`, `--good: #4ade80`, `--warn: #fbbf24`, `--danger: #f87171`
  - Font: system sans-serif; code: JetBrains Mono / `ui-monospace` fallback
- **Slide pattern**: `<section class="slide">` inside a `<template id="slides">`; JS clones them into the active deck
- **Keyboard nav**: arrow keys + Space (forward) + Home/End + F for fullscreen
- **Footer**: progress bar + slide counter + slide title
- **Color classes** for story rows: `.story-row.mine`, `.story-row.team`, `.story-row.pending`
- **QA-step blocks**: `.qa-step` with `.label` + `.refs` + `.tag-mine` for user-shipped steps
- **Language of the deck = English** regardless of the project's doc language — the deck is for the reader, not the docs. If the project's docs are in another language, translate domain terms on first use (e.g. `<native term> (English gloss)`).
- **ASCII diagrams** in `<pre><code>` blocks; keep lines ≤ 100 chars

### Step 5 — Write the file

Output path:
- Linux/macOS: `~/Downloads/<repo-name>-up-to-speed.html`
- Windows: `${env:USERPROFILE}\Downloads\<repo-name>-up-to-speed.html`

`<repo-name>` = the repository name from `gh repo view --json name -q .name`. Lowercase, hyphenated.

After writing, report:
- Absolute path to the file
- Total slide count
- A 3-bullet summary: what chapters were generated, what GitHub data was used, what date the snapshot reflects

### Step 6 — Verify before reporting success

- Read the file back briefly to confirm valid HTML and the slide count matches what the JS will navigate
- Confirm no markdown escapes leaked into HTML (e.g. raw `**bold**`, `# headings`)
- Confirm UTF-8 encoding survived — non-ASCII characters (accents, em dashes, arrows) render correctly when read back
- If on Windows and the writing tool used PowerShell `Set-Content`, re-encode without BOM:
  ```powershell
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
  ```

## What to NOT include

- **No fabricated numbers.** If a count isn't in `gh issue list` or the manifest files, mark it "not tracked" — don't guess.
- **No credentials, secrets, internal IPs, VPN configs, or production hostnames** — even if you read them in config files. Replace with `<placeholder>` or omit.
- **No customer names, license keys, or PII** — even if surfaced by the issue tracker or commit history.
- **No verbatim CLAUDE.md / CONTRIBUTING.md content** — summarize.
- **No per-story "PR review report" pages** — those are excessive for onboarding. Compress to the per-epic walkthrough.
- **No "next steps for me" / actionable to-do list** — the deck is informational. Wrap-up is "what's NOT built yet" instead.

## Failure modes to watch

- **PowerShell `Set-Content -Encoding utf8` adds a BOM and may double-encode**. Use `[System.IO.File]::WriteAllText` with `New-Object System.Text.UTF8Encoding $false`.
- **gh CLI returning truncated lists** — always pass `--limit 500` (or higher if needed).
- **Project doesn't distinguish stories from other issues** — fall back to all-issues counting; call them "issues" throughout the deck; don't invent a label.
- **No epic structure** — replace the per-epic walkthrough with a per-component, per-module, or per-area walkthrough using the repo's actual organizing principle.
- **Solo-developer repos** — the contributor breakdown slide becomes trivial; replace with "commit cadence" or skip the slide.
- **Pre-launch / no closed issues yet** — the "Where We Stand" slide reports planning state; the QA walkthrough becomes "what's been spec'd vs. what's been built".
- **Multi-language documentation** — translate to English on first use in the deck; keep the original term in parentheses so readers can grep the docs later.
- **No CI / no observability stack** — drop those sections rather than fabricate.

## How to adapt to a project you've never seen before

1. **Spend 5 minutes** on Step 1's discovery before writing any slide content. The single biggest failure mode is writing slides about a generic project rather than the actual one.
2. **Use the project's own analogies and metaphors** where you can find them (often in README headlines, marketing copy, or comments at the top of key files).
3. **If you can't find a concept in the project, don't bring it in from elsewhere.** Better to have 30 honest slides than 60 with imported scaffolding.
4. **For pre-architectural projects** (no CLAUDE.md, no PRD, just code), build the architecture chapter by reading the actual entry points and tracing dependencies. Cite file paths so readers can verify.
