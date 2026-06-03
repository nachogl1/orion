---
name: generate-project-writeup-orion
description: "Generate a single polished Microsoft Word (.docx) PROJECT WRITE-UP / CLOSURE SUMMARY REPORT for the current repository, dropped into the user's Downloads folder, written for LEADERSHIP / COMMERCIAL STAKEHOLDERS to mark a project as delivered/closed. It leads with an economic case — a transparent cost comparison (a defensible traditional team x duration x blended-rate baseline, cross-referenced to the COCOMO II Post-Architecture phase model) against the ACTUAL observed delivery, headlining the savings and time-to-market compression of an AI-assisted build. The contributor count and full-time/part-time FTE split that drive the cost math are ALWAYS confirmed with the user (git author lists over/under-count bots, AI-agent commits, and part-timers). After the financial summary it assembles: project overview (what it is, the problem solved, the solution), scale-of-work quantitative metrics measured from the real repo (LOC split prod vs test, commits, duration, modules, models, endpoints, tests, docs), technical architecture (backend/frontend/infra stack tables with rationale), architecture patterns, security implementation, core features, an 'invisible excellence' section (testing, code quality, design system), a traditional-vs-modern comparison, value delivered (risk reduction + OPEX saving; revenue only if a business case is supplied), and a documentation inventory. Detects the project's stack and conventions from its own files at run time — assumes no stack. Renders the .docx via a bundled zero-dependency Python generator (no pandoc / python-docx / Word install required), with pandoc and HTML fallbacks. INVENTS NO NUMBERS — every metric is measured or marked 'not measured'. STRICTLY READ-ONLY: it reads git + repo files and writes ONE .docx to Downloads; it never edits the repo and never commits. Use when the user says '/generate-project-writeup-orion', 'generate a project write-up', 'write up a project closure / summary report', 'closing report for this project', 'project delivery summary for leadership', 'AI-assisted development summary', or wants a single shareable Word document that closes the project out."
user_invocable: true
---

# generate-project-writeup-orion

> [!NOTE]
> **Editing this skill?** This skill has **no `-vN` convention** — edit it in place
> (like `project-handover-orion` / `guided-qa-orion`). Keep everything in the skill
> files **general** (see the Distribution-safety gate at the bottom) — this repo is
> publicly distributable. The *report* it generates about a user's repo is a local
> artifact in their Downloads and may name their project, people, and figures; the
> **skill files must never hard-code anything project-specific** (no product/codename,
> no company, no real rates, no person names).

Produce a single polished **Microsoft Word (`.docx`) project-closure summary report**
in the user's Downloads folder that lets a delivery lead hand a finished project to
**leadership / commercial stakeholders** — leading with the **economic case** (what it
would traditionally have cost vs. what it actually took) and backing it with measured
scale-of-work, technical depth, and business value.

The output lives at
`~/Downloads/<repo-name>-project-writeup-<YYYY-MM-DD>.docx` (Windows:
`%USERPROFILE%\Downloads\…`) so it's instantly shareable.

## When to invoke

User says `/generate-project-writeup-orion`, asks to **write up / close out a project**,
wants a **delivery or project-summary report for leadership**, an **AI-assisted
development summary**, or a single shareable **Word document that marks the project as
delivered**.

> Not to be confused with `project-handover-orion` (a *technical* handover to a
> successor developer, HTML, dark theme) — **this** skill is an *executive/commercial
> closure write-up*, Word format, economics-first.

## Operating principles (read these first)

- **Audience: leadership & commercial stakeholders.** Sponsors, a business-unit owner, a
  budget holder. Write in **clear, confident, plain business English**. Define a technical
  term the first time it appears, in one phrase, then move on. Lead with outcomes, cost,
  risk, and value; keep the deep technical detail in its own clearly-labelled sections so a
  non-technical reader can skim past it.
- **Economics first, and HONEST.** The headline is a cost/time comparison. Every figure must
  be **defensible and its assumptions shown** — the report states the method, the rate, the
  team assumption, and the source of each number. **Never inflate.** A reader who disagrees
  with an assumption must be able to see exactly which one and re-do the math. (See
  *Economic methodology* below — it is deliberately conservative and transparent.)
- **Invent no numbers.** Every metric is **measured from the real repo** (git, file counts,
  test counts) or marked **"not measured."** Never guess LOC, test counts, velocity, commit
  counts, or revenue. If a section can't be substantiated, shrink or drop it — do not pad.
- **Contributors are always confirmed with the user.** The cost math hinges on headcount and
  the full-time/part-time FTE split. Git author lists mislead (bots, AI-agent commits,
  renamed emails, drive-by contributors). **Always** show the git author list as a hint and
  **ask** the user to confirm the real contributor count and FTE — never silently trust git.
- **Assume no stack.** Detect build/test/run, layout, modules, models, endpoints, and test
  conventions from the project's own manifests and source at run time. Never carry another
  project's stack or vocabulary over.
- **Strictly read-only.** The skill reads git + repo files and writes exactly **one `.docx`
  to Downloads** (plus a sidecar JSON it can clean up). It **never edits the repo, never
  commits, never pushes.**
- **Single self-contained Word file.** No linked images, no external template the recipient
  needs. The bundled generator emits a portable `.docx`.
- **Distribution-safety self-check** before writing (see gate). The generated report is a
  local artifact and may name the user's project/people/figures; the **skill files** stay
  general.

## How the `.docx` gets generated (bundled, zero-dependency)

The skill does **not** hand-write OOXML or depend on Word. It assembles all report content
into a **single JSON file** and renders it with the bundled generator:

```
python <skill-dir>/assets/build_docx.py <report-data.json> <output.docx>
```

`build_docx.py` uses **only the Python standard library** (`zipfile` + OOXML templating) —
no `python-docx`, no `pandoc`, no Word install. The JSON contract (block types:
`title_block`, `toc`, `heading`, `paragraph`, `bullets`, `table`, `page_break`) is
documented in the **header of `build_docx.py`** — read it before authoring the JSON. The
generator handles styling (cover/title block, coloured table headers, zebra rows, an
emphasised total/savings row, a live Word table-of-contents field, headings that populate
that TOC).

**Generation path & fallbacks** (pick the first that works on the machine):

1. **Primary — `build_docx.py`** with any `python3`/`python` on PATH (3.8+). This is the
   default; it needs nothing installed. Verify Python: `python --version` (Windows often
   `py -3 --version`).
2. **Fallback A — pandoc**, *only if* Python is somehow unavailable but `pandoc` is present:
   emit the same content as Markdown and run `pandoc report.md -o output.docx`. Tables and
   headings convert; you lose the coloured cover styling.
3. **Fallback B — Word-openable HTML**, last resort: write a styled `.html` and tell the user
   to open it in Word and "Save As → .docx". Only if neither Python nor pandoc exists.

State in chat which path was used. **Do not install anything** without asking the user first.

## Inputs / pre-conditions

- A **target repository** — default to the current repo (`git rev-parse --show-toplevel`).
- **Report metadata** (for the cover/title block) — gathered from the user, with sensible
  detected defaults: project display name (repo/README), optional **codename**, one-line
  subtitle, **business unit / programme**, report **date** (default today), **project
  owner**, **confidentiality** line, and the **report-type** label (default
  *"AI-Assisted Development — Project Summary Report"*; offer a neutral
  *"Project Delivery Summary"* if the build wasn't AI-assisted).
- **Economic inputs** (prompted — see methodology):
  - **Contributors & FTE** — confirmed with the user (always).
  - **Blended day rate + currency** — the org's internal blended cost per person-day (e.g.
    `650` + `GBP/£`). No default invented; ask.
  - **Working days per month** — default `20` (offer to change).
  - **Assumed traditional team composition** — e.g. *2 developers + 1 QA*; confirm.
  - **Actual calendar duration** — derived from git (first→last commit on the delivery
    branch); user may override (e.g. real elapsed wall-clock differs from commit span).
- **Optional business case** — if the user supplies revenue/RFA figures (a file or pasted
  numbers), populate §Value Delivered → Revenue. **Otherwise mark revenue "not provided"** —
  never fabricate commercial projections.

## Workflow

### Step 1 — Confirm scope & gather report metadata

1. Resolve repo root + name. Read `README.md` / `CLAUDE.md` to propose the project display
   name, subtitle, and (if present) a codename — confirm with the user.
2. Collect cover metadata (business unit/programme, date, owner, confidentiality, report-type
   label). Use `AskUserQuestion` to batch the genuine unknowns; accept sensible defaults for
   the rest and state them.
3. Decide the **delivery branch / commit range** the report measures (default: the repo's
   default branch full history; allow a date range or a base..head range if the user scopes
   the project to a window).

### Step 2 — Discover the project (for the narrative sections)

Read these where present and synthesize, citing nothing project-specific into the skill but
freely into the report:

1. `README.md` (root + per-package) → elevator pitch, what it is.
2. `CLAUDE.md` / `AGENTS.md` / `.claude/rules/*` → conventions, workflow (summarize, don't quote).
3. Architecture/spec docs: `ARCHITECTURE.md`, `docs/architecture/**`, ADRs / decision logs,
   `PROJECT_NOTES.md`, design specs, RFAs/business-case docs.
4. **Manifests for the exact stack** (detect, don't assume): `*.sln`/`*.csproj`, `pom.xml`,
   `build.gradle`, `Cargo.toml`, `go.mod`, `pyproject.toml`/`requirements.txt`,
   `package.json` + lockfile, `Dockerfile*`, `docker-compose*`, CI under
   `.github/workflows/**` / `.gitlab-ci.yml`. Derive the stack tables (component → technology
   → why), infra, and CI/CD shape from what's actually present.
5. Top-level layout → the real module/app boundaries, for §Architecture patterns and
   §Core features.

### Step 3 — Measure the scale of work (NUMBERS — measure, never guess)

Use read-only git + file scans. Prefer a real counter when available, else fall back. Mark
anything you can't measure as **"not measured"** in the report rather than estimating.

- **Commits & cadence** — `git rev-list --count <range>`; `git shortlog -sne <range>` (also
  feeds Step 4); first/last commit dates → **calendar duration**.
- **Lines of code, split production vs test** — prefer `cloc` or `tokei` if installed
  (`cloc --vcs=git` / `tokei`). Else use `git ls-files` filtered by extension with `wc -l`,
  and **explicitly separate** production code from **tests, migrations, generated artefacts,
  vendored deps, lockfiles** (exclude the latter from the "production SLOC" used for the cost
  model; report test LOC separately as a quality signal). Split backend vs frontend by
  directory/extension.
- **Backend structure** (stack-adaptive examples — adapt to the real stack):
  modules/apps, domain models/entities, API endpoints/routes, controllers/serializers,
  background jobs, DB migrations. Detect by grepping the real source (e.g. Django: `models.py`
  classes, `path()`/`re_path()` routes, DRF serializers; .NET: `[ApiController]`/`[Http*]`;
  Express/Nest: route decorators/`router.*`; Rails: `resources`/models). Count only what you
  can see.
- **Frontend structure** (if any): pages/views, components, routes, i18n locales, design-system
  primitives, accessibility attributes (`aria-*`/`role=`), build tool.
- **Tests** — files and **cases**: backend (`def test_` / `[Fact]`/`[Test]` / `func Test`),
  component (`it(`/`test(`), e2e (Playwright/Cypress spec counts). Compute the
  **test-to-production LOC ratio** as a quality indicator.
- **Docs** — count markdown docs + total lines; ADRs; design specs. Feeds the Appendix
  inventory (document → lines → purpose).

Record every measured value with the command/source so the report is reproducible. Put the
big set into §Scale of Work (metric → value → industry context); the "industry context"
column is a neutral one-line characterisation, **not** a fabricated benchmark.

### Step 4 — Establish contributors & FTE (ALWAYS ASK)

1. Show the user the git author list: `git shortlog -sne <range>` (counts + names/emails).
2. Flag obvious non-humans (bot accounts, `*-bot`, CI users, AI-agent commit signatures /
   `Co-Authored-By` agent trailers) as candidates to **exclude** from headcount.
3. **Ask the user to confirm**, via `AskUserQuestion` or a short prompt:
   - the real **number of human contributors**;
   - the **full-time vs part-time split** (e.g. *2 full-time + 2 part-time occasional*);
   - how to translate part-timers into **FTE** (default: each part-timer ≈ 0.25 FTE unless
     told otherwise) → compute total **FTE** (e.g. `2 + 2×0.25 = 2.5 FTE`).
   - whether to **exclude AI-agent/bot commits** from the human contributor count (default:
     yes — they are the tooling, not headcount).
4. Carry the confirmed **FTE** and **contributor count** into the economic model and the
   cover/metrics. Record the assumption explicitly in the report (e.g. a footnote:
   "2.5 FTE = 2 full-time + 2 part-time at 0.25 FTE each").

### Step 5 — Build the economic model (centerpiece — transparent & conservative)

Gather the remaining economic inputs (Step "Inputs"): **blended day rate + currency**,
**working days/month** (default 20), **assumed traditional team**, **actual calendar months**
(from git, user may override).

**Economic methodology (state this method, and its assumptions, in the report).**

- **Person-month (PM) unit cost** = `day_rate × working_days_per_month`
  (e.g. £650 × 20 = £13,000 / PM). One rate held constant across scenarios for comparability.
- **Actual (delivered) effort & cost** = `FTE × actual_calendar_months` PM × PM-cost.
  This is observed delivery — the FTE from Step 4, the months from git.
- **Traditional baseline effort & cost** = `assumed_team_size × assumed_calendar_months` PM
  × PM-cost. The assumed team and duration are the **org's own pre-AI estimate** (ask the
  user; if they have no figure, derive a *defensible* duration from a stated productivity
  assumption and show it). This is the headline "what it would have cost."
- **Savings** = traditional − actual, in money, in calendar time, and as a %.

**COCOMO II — use as a cross-check and for the phase split, with a caveat.** The COCOMO II
Post-Architecture *phase distribution* (Boehm's nominal split — Plans&Reqs / Product Design /
Programming / Integration&Test roughly **7 / 17 / 25 / 22 / 22 / 7** across
requirements, design, code, test, …) is a sound, citable way to break the timeline into
**Table 2 (time by phase)** for both the traditional and the actual columns. You **may** also
present a full COCOMO II effort estimate
(`PM = 2.94 × KSLOC^E`, `E ≈ 1.10` at nominal scale factors;
`schedule = 3.67 × PM^0.32`) **only if** you add the honest caveat that COCOMO II's
constants are calibrated to older, lower-productivity baselines and tend to **overestimate**
modern framework-based delivery — so treat it as a conservative upper bound, not as
corroboration of the simpler team×duration figure. **Do not force the two methods to agree;
if they diverge, say so.** Prefer the transparent team×duration figure as the headline.

Produce **Table 1 (cost comparison)** — Traditional / AI-Assisted (Actual) / Savings rows —
and **Table 2 (time by phase)**. Every number traces back to a stated input.

### Step 6 — Assemble the report content (mirror these sections)

Build the JSON `blocks` array (see `build_docx.py` header for the schema). Adapt/drop
sections the project can't substantiate rather than padding. Default structure:

1. **Title block** — banner (org / programme), project name (+ codename), subtitle, fields
   (business unit, date, owner), report-type label, confidentiality line.
2. **Table of contents** (`toc` block) + a page break.
3. **Financial Summary** — a one-line method note; **Table 1 — Cost Comparison**; a
   "showing the working" paragraph (production SLOC measured, team & rate assumptions, the
   arithmetic); **Table 2 — Time Investment by Phase** with the Boehm-distribution note.
4. **Part 1 — Project Overview** — *What is `<project>`?* (plain-language description +
   architecture in a sentence or two); *The problem we solved* (the gap/market/compliance
   need, drawn from README/RFA — only what's documented); *Our solution* (bulleted highlights).
5. **Part 2 — Scale of Work** — the quantitative metrics table (metric → value → context),
   from Step 3. Everything measured.
6. **Part 3 — Technical Architecture** — Backend / Frontend / Infrastructure stack tables
   (component → technology → why this choice), from the real manifests.
7. **Part 4 — Architecture Patterns** — the 3–5 load-bearing patterns (named heading +
   2–4 sentences each: what it is, why, the trade-off), from the real layout.
8. **Part 5 — Security Implementation** — identity/auth, transport/cookies, middleware,
   any high-risk boundary, audit trail, tenancy/isolation — only what the code actually does.
9. **Part 6 — Core Features** — a lifecycle/stages table if the domain has one, then a short
   per-module breakdown (module → what it owns → key capabilities as bullets).
10. **Part 7 — The Invisible Excellence** — Comprehensive Testing (counts + ratio), Code
    Quality (linters/formatters/CI gates), Design System / Accessibility (if frontend).
11. **Part 8 — Comparison with Traditional Approach** — a "manual/legacy vs `<project>`"
    aspect table, and an "operational efficiencies" (process → before → after → improvement)
    table. Keep "improvement" qualitative unless a real number exists.
12. **Part 9 — Value Delivered** — **Revenue opportunity** (ONLY if a business case was
    supplied; else a short "not provided — supply the business case to populate" note);
    **Risk reduction** (bulleted, grounded in the actual security/compliance/audit features);
    **OPEX / time-to-market saving** (from the economic model — restate the saving cleanly).
13. **Appendix — Documentation Inventory** — document → lines → purpose, from Step 3.

Write the JSON to a sidecar (e.g. `<output-dir>/<repo>-writeup-data.json`).

### Step 7 — Render the `.docx`

Run the primary generator (or the first working fallback):

```bash
python "<skill-dir>/assets/build_docx.py" "<data.json>" \
       "<Downloads>/<repo-name>-project-writeup-<YYYY-MM-DD>.docx"
```

- `<repo-name>` = repo name (lowercase, hyphenated) from `gh repo view --json name -q .name`
  when available, else the toplevel folder name. `<YYYY-MM-DD>` = today.
- On Windows the Python launcher is often `py -3`; the Downloads path is
  `${env:USERPROFILE}\Downloads`.

### Step 8 — Verify, then report

- Confirm the file exists and is a valid package: it's a zip whose `word/document.xml`,
  `styles.xml`, etc. parse as XML. (`build_docx.py` only emits well-formed parts, but verify
  the file was written and is non-trivial in size.)
- If Word/LibreOffice is available you may open it headless to sanity-check (optional); the
  TOC is a field — Word offers to update it on open (the bundled `settings.xml` requests it).
- Confirm UTF-8 survived (em dashes, currency symbols, accents) by reading a slice of
  `document.xml` back.
- **Report in chat:** the absolute file path, the **generation path** used (build_docx /
  pandoc / HTML), the **economic headline** (traditional vs actual vs saving, with the FTE and
  rate assumptions named), the section count, and a one-line note of anything marked
  "not measured" or "not provided." The skill ends here — it does **not** edit the repo,
  commit, or offer to. Optionally offer to delete the sidecar JSON.

## What to NOT include

- **No fabricated numbers.** Not measurable from git/files → "not measured." No invented
  revenue, ROI, benchmarks, velocity, or COCOMO figures presented as fact. No forcing two
  estimation methods to agree.
- **No credentials, secrets, internal IPs, tokens, hostnames, or customer names** — even if
  read from config or docs. Replace with `<placeholder>` or omit.
- **No verbatim CLAUDE.md / internal-doc dumps** — summarize.
- **No repo edits, commits, or "I'll fix it" offers** — the document is the deliverable.

## Failure modes to watch

- **Python not on PATH** — try `py -3`, `python3`, `python`; if truly absent, fall back to
  pandoc, then Word-openable HTML. Don't silently produce nothing.
- **Shallow / squashed clone** — commit count and duration are degraded; note the limitation
  and lean on file-based metrics. Don't present a squashed history as the real cadence.
- **Bot / AI-agent commits inflate authors** — this is exactly why Step 4 always asks. Never
  let `git shortlog` alone set headcount.
- **No business case** — leave Revenue as "not provided"; never invent projections.
- **Monorepo / multiple stacks** — scope LOC and module counts per package and say so; don't
  blend a backend and an unrelated tool into one SLOC figure used for cost.
- **Generated/vendored code dwarfs hand-written** — exclude it from production SLOC or the
  cost model is meaningless; state the exclusions.
- **PowerShell encoding** — if you ever write text parts yourself (HTML fallback), avoid a
  BOM: use `[System.IO.File]::WriteAllText($path,$content, (New-Object System.Text.UTF8Encoding $false))`.
  `build_docx.py` already writes UTF-8 without BOM.

---

## Distribution-safety gate (this repo is publicly distributable)

This skill ships publicly. Before generating, confirm **nothing project-specific leaked into
the skill files** — no person/org/product/codename/repo/stack/rate/locale/path specifics in
prose, examples, or the generator. The **generated report** about a user's repo is a **local
artifact** (in their Downloads) and may name their project, people, business unit, rates, and
figures — that's expected; it is never committed back into this repo. What must stay general
is everything under `skills/generate-project-writeup-orion/` itself (including any example JSON
or rates in `build_docx.py` — keep them neutral placeholders).
