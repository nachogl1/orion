---
name: project-status-forecast-orion
description: "Read the current project's backlog (BMAD story docs, GitHub Issues, or Jira — whichever the repo actually uses, detected at runtime), compute real delivery metrics (scope, velocity, trend), and project a phase-aware, multi-speed forecast all the way to a DEPLOY-READY date — not just 'dev done'. Models the full timeline: ramp-up → development → pre-deploy QA → refinement/hardening → deploy. Produces three speed scenarios (conservative / expected / optimistic), graduating to Monte-Carlo P50/P85/P95 confidence bands as run-over-run history accumulates. Appends a dated snapshot each run so forecasts sharpen over time, and emits a single self-contained dark-theme HTML stakeholder deck into the Downloads folder. Invents no numbers. Use when the user says '/project-status-forecast-orion', 'where does the project stand', 'when will we ship / finish', 'forecast the project', 'delivery forecast', 'status deck for stakeholders', or wants a realistic deploy-ready date range to drive decisions."
user_invocable: true
---

# project-status-forecast-orion

> [!NOTE]
> **Editing this skill.** This is a *living, in-place* skill (no `-vN` convention) — it is meant to be refined run-over-run as the owner learns what forecasts actually held up. When you change it, keep changes **backward-tolerant**: never break the on-disk snapshot/config formats below in a way that orphans an existing `forecast-history.jsonl`. If you must change the snapshot schema, add fields, don't rename/remove; bump `schema_version` and read older lines defensively.

Tell the user **where the project really stands and when it will realistically be deploy-ready**, with enough honest, source-backed information that any stakeholder can make a call. The defining idea: **"all dev stories closed" is not "ready to ship."** This skill forecasts the *whole* timeline — including the QA and refinement tail after development — under several speeds, so nobody is surprised by the last mile.

The output is a single self-contained dark-theme HTML deck at `~/Downloads/<project-name>-status-forecast-<YYYY-MM-DD>.html` (Windows: `%USERPROFILE%\Downloads\…`), dated so successive runs can be compared side by side.

## When to invoke

User says `/project-status-forecast-orion`, asks where the project stands, when it will finish or ship, for a delivery forecast, for a stakeholder status deck, or wants a realistic deploy-ready date range.

## Operating principles (read these first)

- **Real information only — invent no numbers.** Every metric must trace to the backlog source (tracker query, BMAD doc, commit history) or to the persisted snapshot history. If something isn't measurable, say "not tracked" and show how to start tracking it — never guess to fill a slide.
- **Forecast to deploy-ready, not dev-complete.** The headline date is when the product can ship, which is `dev-complete + QA + refinement`. Always show the dev-complete date too, clearly labelled, so the gap is visible.
- **Phase-aware.** Model the timeline as phases (ramp-up → development → pre-deploy QA → refinement/hardening → deploy). Each phase has a tunable factor; measure actuals against the project's own history and surface where assumptions came from.
- **Several speeds, never one false-precision date.** Present conservative / expected / optimistic as a *range*. Add Monte-Carlo P50/P85/P95 bands once the snapshot history is long enough. A single hard date is a lie; a range with stated assumptions is a decision tool.
- **Best-effort with whatever exists today; sharper over time.** First run on a fresh project has thin data — say so, lean on defaults, and still produce a useful range. Each run appends a snapshot, so trend, measured phase durations, and Monte-Carlo bands become available as the series grows.
- **Stakeholder-readable.** The audience is mixed (eng + PM + leadership). Lead with a one-glance RAG verdict and the deploy-ready range; put the math behind it. Define any term a non-engineer wouldn't know.
- **Source of truth = the repo's actual tracker.** Detect it; don't assume GitHub. Adapt queries to BMAD docs / GitHub / Jira / GitLab / Linear as found.
- **Single self-contained HTML.** All styles inline, charts as inline SVG (no network, no CDN). Portable file the user can email.

## Workflow

### Step 1 — Detect the backlog source (do not assume)

Inspect the repo and pick the authoritative source of stories/issues. Check in this order; a project may have more than one — prefer the one that is actually maintained (most recent activity):

1. **Local BMAD docs** — `docs/stories/**`, `_bmad-output/**`, `docs/prd/**`, `*.story.md`, story files with status front-matter (`Draft`/`Approved`/`InProgress`/`Done`). If present and current, this is often the truest backlog for a BMAD project.
2. **GitHub Issues** — repo has a GitHub remote (`git remote -v`) and `gh` is authenticated (`gh auth status`). Use `gh issue list`.
3. **Jira** — a project key appears in `CLAUDE.md`/`README`/config, branch names (`PROJ-123`), or commit messages; and the Atlassian tools are available. Use JQL search.
4. **GitLab / Linear / other** — adapt the equivalent CLI/API.
5. **Fallback: git history** — if there is no tracker at all, derive a rough velocity from merged PRs / commits-with-story-refs, and say plainly in the deck that the forecast is commit-derived and weaker.

State the detected source on the cover slide so the reader knows what's authoritative. If two sources disagree, name the discrepancy — that itself is decision-grade information.

### Step 2 — Establish the timeline anchors

A phase forecast needs a start, a now, and (ideally) a target:

- **`today`** — the run date.
- **`start_date`** — earliest of: an explicit `project_start_date.md` memory file (see Config), the first closed story's date, the first issue's created date, or the first commit. If you had to infer it, label it "(inferred)".
- **`target_date`** — read `project_target_date.md` from the project memory dir (same convention `sequential-bmad-github-orion-v3` uses). If absent, omit the target-rate analysis and print one line: *"No target_date configured — to enable target-vs-actual analysis, save `target_date: <YYYY-MM-DD>` to `<project-memory-dir>/project_target_date.md`."*
- **Working calendar** — default Mon–Fri, no holidays. Honor `forecast_phases.md` overrides (`work_days`, `holidays`) if present. Report both calendar-day and work-day figures.

### Step 3 — Measure scope and velocity (from the detected source)

**Scope.** Count the unit the project actually uses — *stories* if there's a story label/structure, else *issues*, else BMAD story files. Compute total / closed / open. If the tracker distinguishes work types (labels like `bug`, `qa`, `chore`, `hardening`, or BMAD epic structure), split **dev work** from **QA/bug/hardening work** — that split feeds the phase model. Don't invent a label that doesn't exist; fall back to undifferentiated "units" and model QA/refine as time phases instead.

Example GitHub queries (adapt for other trackers):

```bash
gh repo view --json name,owner,description
gh issue list --state closed --limit 1000 \
  --json number,title,closedAt,createdAt,assignees,labels \
  -q '.[] | [.number, (.assignees[0].login // "—"), .closedAt, (.labels|map(.name)|join(",")), .title] | @tsv'
gh issue list --state open --limit 1000 \
  --json number,title,createdAt,assignees,labels \
  -q '.[] | [.number, (.assignees[0].login // "—"), (.labels|map(.name)|join(",")), .title] | @tsv'
```

For Jira, use `searchJiraIssuesUsingJql` with the detected project key and pull `status`, `resolutiondate`, `created`, `assignee`, `issuetype`, `labels`. For BMAD docs, parse the status front-matter and any per-story `Done`/closed date (or fall back to file `git log` last-modified-to-Done).

**Velocity** (closed units over time):
- **Raw**: closed ÷ elapsed, expressed per calendar day, per work day, and per 7-day week.
- **Ramp-aware steady-state**: exclude the first `ramp_window` (default 7 calendar days) and recompute. The first week is typically slower; the steady-state rate is the better basis for forecasting remaining work. **Report both** and use steady-state for projection (fall back to raw if the project is younger than the ramp window).
- **Recent vs. cumulative trend** (needs ≥ 3 snapshots): compare the last snapshot interval's rate to the cumulative rate. Flag **accelerating / steady / decelerating** — a decelerating trend is exactly the kind of thing stakeholders must hear early.
- **Per-contributor** counts and current cadence, and the **engineer count** actively closing work (drives per-engineer required-rate math). Identify the current user from `git config user.email` matched to the tracker login.

### Step 4 — Run the phase-aware forecast

This is the core. Project the remaining timeline as ordered phases, each ending on a date:

| Phase | Duration model (default) | Notes |
|---|---|---|
| **Ramp-up** | mostly already elapsed | Only material for a project younger than `ramp_window`. Apply `ramp_factor` (default 0.65 × steady-state) to the not-yet-ramped portion. |
| **Development** | `remaining_dev_units ÷ velocity` | The dev-complete date. Uses the scenario's velocity (Step 4 scenarios). |
| **Pre-deploy QA** | `qa_factor × dev_duration` (default 0.25) | If the tracker has measurable QA/bug/hardening work, use the greater of (that work ÷ velocity) and the factor-based estimate. |
| **Refinement / hardening** | `refine_factor × dev_duration` (default 0.15) | Buffer to fix QA-found defects and polish before deploy. |

`deploy_ready_date = dev_complete_date + qa_duration + refine_duration` (advanced over the working calendar). All factors come from `forecast_phases.md` (with the defaults above); **once a phase has actually completed in the history, prefer the measured duration over the factor and say so.**

**Speed scenarios** — compute the full timeline (dev → QA → refine → deploy-ready) under each:

- **Conservative (slow)** — velocity × `conservative_mult` (default 0.7), and the *larger* QA/refine factors (×1.3). Answers "if things go worse than now."
- **Expected (current pace)** — steady-state velocity, default factors. The planning number.
- **Optimistic (fast)** — velocity × `aggressive_mult` (default 1.3), smaller QA/refine factors (×0.8). The "everything breaks our way" floor.

Once `forecast-history.jsonl` has **≥ 6 snapshots** (configurable `mc_min_samples`), also run a **Monte-Carlo simulation**: sample the observed per-interval throughput (the deltas between snapshots, optionally bootstrapped) ~10,000 times to drain the remaining backlog, add the QA+refine tail to each draw, and report **P50 / P85 / P95 deploy-ready dates** with a fan chart. Below the sample threshold, state that bands are not yet available and that N more runs will unlock them. (If you cannot run a real RNG in-session, compute the percentiles analytically from the throughput distribution and label the method.)

**Observed-window scenarios** (when history allows): instead of (or alongside) the multiplier scenarios, derive conservative/expected/optimistic from the **slowest / median / fastest** rolling-window velocity the project has *actually* achieved — real speeds beat invented multipliers. Prefer these once available; keep the multiplier scenarios as the bootstrap.

**Target analysis** (only if `target_date` present): work *backward* from the target — `required_dev_complete = target_date − (qa_duration + refine_duration)` — then `required_dev_velocity = remaining_dev_units ÷ work_days_to_required_dev_complete`. Compare to actual velocity → **gap** (negative = behind). Derive per-engineer required rate (`required_team_rate ÷ engineer_count`). Set a **RAG verdict**: 🟢 on track (expected ≤ target), 🟡 at risk (conservative > target ≥ expected), 🔴 behind (expected > target).

### Step 5 — Persist a snapshot (improve over time)

Append exactly one JSON line to `<project-memory-dir>/forecast-history.jsonl` where `<project-memory-dir>` is `~/.claude/projects/<harness-project-key>/memory/` (the harness key is derived from the project's absolute path; this is the same dir Step 2 reads config from). **Create the dir if missing; never commit it; it is local-only.** Append — never rewrite — so the series is preserved.

```jsonc
{
  "schema_version": 1,
  "date": "<YYYY-MM-DD>",                 // run date (one snapshot per run; if same-day re-run, append anyway)
  "source": "bmad|github|jira|gitlab|git",
  "unit": "stories|issues|units",
  "scope": { "total": 0, "closed": 0, "open": 0, "dev_open": 0, "qa_open": 0 },
  "velocity": { "per_cal_day": 0.0, "per_work_day": 0.0, "per_week": 0.0, "steady_state_per_work_day": 0.0 },
  "engineers": 0,
  "phase_factors": { "ramp": 0.65, "qa": 0.25, "refine": 0.15 },
  "scenarios": {
    "conservative": { "dev_complete": "YYYY-MM-DD", "deploy_ready": "YYYY-MM-DD" },
    "expected":     { "dev_complete": "YYYY-MM-DD", "deploy_ready": "YYYY-MM-DD" },
    "optimistic":   { "dev_complete": "YYYY-MM-DD", "deploy_ready": "YYYY-MM-DD" }
  },
  "target_date": "YYYY-MM-DD|null",
  "rag": "green|amber|red",
  "notes": "<one-line: what changed vs last snapshot, or 'first run'>"
}
```

On every run, **read the prior lines first** so you can: show "what changed since last run" (Δ scope, Δ velocity, did the deploy-ready date move?), compute trend, measure completed-phase actuals, and feed Monte-Carlo. Tolerate older `schema_version` lines (read defensively, fill missing fields with nulls).

### Step 6 — Generate the HTML deck

Single self-contained file, dark theme, inline-SVG charts, keyboard-navigable. Reuse the visual conventions of `create-up-to-speed-report-orion` (same palette, `<template id="slides">` + JS-clone navigation, footer progress bar) — but charts here are **inline SVG**, not ASCII, because the forecast *is* the chart.

**Slide outline** (adapt to the data you actually have):

1. **Cover** — project name, "Status & Forecast", run date, the detected backlog source + unit, nav hints (← / → / Space / F).
2. **Executive summary (one glance)** — the RAG pill; the **deploy-ready range** (conservative → optimistic) with the expected date bold; dev-complete date; target date + gap if set; the 3 biggest risks; "what changed since last run." A stakeholder who reads only this slide should still be able to decide.
3. **Where we stand** — totals (closed / open / %), elapsed (calendar + work days, with the actual start date and method), the scope split (dev vs QA/bug) if available.
4. **Velocity** — raw vs steady-state (per cal day / work day / week); the trend verdict (accelerating / steady / decelerating); a **velocity-over-time line chart** from the snapshot series (or "first run — no series yet").
5. **Burndown / burnup** — remaining units over time with the projected trend lines for each scenario (the "fan").
6. **The phase model explained** — a horizontal timeline (ramp → dev → QA → refine → deploy) with each phase's dates and the factor/measured-duration it used; make the QA+refine tail visually obvious.
7. **Scenarios** — a table: Scenario · Velocity used · Dev-complete · +QA · +Refine · **Deploy-ready**. Rows: Conservative / Expected / Optimistic (+ Monte-Carlo P50/P85/P95 if unlocked). A fan chart of deploy-ready dates.
8. **Target analysis** (only if target_date) — required vs actual velocity, the gap (colored ±), per-engineer required rate, and what would have to change to hit the date.
9. **Contributors** (if multi-dev) — per-engineer closed counts, share, cadence.
10. **Risks & assumptions** — every assumption the forecast rests on (start-date inference, phase factors used, whether QA work is tracked or estimated, sample size for bands), and the top risks to the date. Honesty here is the product.
11. **Methodology & data provenance** — exactly which queries/files produced the numbers, the snapshot count and date range, and "invents no numbers" stated plainly so stakeholders trust it.

### Step 7 — Write the file and report

Path: `~/Downloads/<project-name>-status-forecast-<YYYY-MM-DD>.html` (Windows: `${env:USERPROFILE}\Downloads\…`). `<project-name>` = repo name from `gh repo view --json name` / manifest / folder name; lowercase-hyphenated.

After writing, report to the user:
- Absolute path to the HTML file and the snapshot file.
- The **headline**: RAG verdict + expected deploy-ready date + the conservative→optimistic range.
- Snapshot count now in the series and, if bands aren't unlocked yet, how many more runs until Monte-Carlo bands appear.
- A 2–3 line "what changed since last run" (or "first run — baseline established").

### Step 8 — Verify before declaring success

- Read the file back briefly: valid HTML, the slide count matches what the JS navigates, every `<svg>` chart closes, no raw markdown leaked (`**bold**`, `# heading`).
- Confirm UTF-8 survived (accents, em dashes, arrows render).
- Confirm a new line was actually appended to `forecast-history.jsonl` and it parses as JSON.
- On Windows, if the writing tool used PowerShell `Set-Content`, re-encode without BOM:
  ```powershell
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
  ```

## Config files (project memory dir)

All optional, all in `~/.claude/projects/<harness-project-key>/memory/`, all local-only:

- **`project_target_date.md`** — `target_date: <YYYY-MM-DD>` (reuses the v3 convention). Unlocks target analysis.
- **`project_start_date.md`** — `start_date: <YYYY-MM-DD>` to override inferred start.
- **`forecast_phases.md`** — tunables (YAML/front-matter); any omitted key uses the default:
  ```yaml
  ramp_window_days: 7
  ramp_factor: 0.65
  qa_factor: 0.25
  refine_factor: 0.15
  conservative_mult: 0.7
  aggressive_mult: 1.3
  mc_min_samples: 6
  work_days: [Mon, Tue, Wed, Thu, Fri]
  holidays: []          # ["YYYY-MM-DD", ...]
  ```
- **`forecast-history.jsonl`** — the append-only snapshot series (Step 5). Never edit by hand unless correcting a bad run.

## What to NOT include

- **No fabricated numbers.** If it's not in the tracker/docs/history, mark it "not tracked."
- **No single false-precision date** presented as certainty — always a range with assumptions.
- **No credentials, secrets, internal IPs, hostnames, license keys, or PII** even if read from config or surfaced by the tracker — replace with `<placeholder>` or omit.
- **No customer/person identifiers** beyond the tracker login needed for the contributor slide.
- **No verbatim CLAUDE.md / CONTRIBUTING.md** — summarize.
- **No prescriptive "do these tasks next" to-do list** — this deck informs decisions; the call belongs to the stakeholders. (Risks and what-would-have-to-change are fine; assignments are not.)

## Failure modes to watch

- **No tracker at all** → fall back to git-history velocity; state clearly the forecast is commit-derived and weaker.
- **Brand-new project (younger than `ramp_window`)** → not enough steady-state data; use raw velocity, widen the scenario range, and say bands/trend need more runs.
- **QA work not tracked** → model QA/refine purely as time phases from the factors; flag in Risks & assumptions that the tail is estimated, not measured.
- **Tracker doesn't distinguish stories from bugs/chores** → count undifferentiated units; don't invent a label.
- **`gh`/Jira returning truncated lists** → pass `--limit 1000`+ (GitHub) / page JQL fully (Jira).
- **Inferred start date is wrong** → tell the user to set `project_start_date.md`; show the inference method so they can sanity-check.
- **Same-day re-run** → still append a snapshot (the series is event-based, not one-per-day); "what changed" compares to the immediately prior line.
- **PowerShell `Set-Content -Encoding utf8` adds a BOM / double-encodes** → use `[System.IO.File]::WriteAllText` with `New-Object System.Text.UTF8Encoding $false`.
- **Velocity is zero (nothing closed yet)** → don't divide by zero; report "no completions yet — forecast is planning-state only" and base the range on backlog size + the configured factors with an explicit caveat.

## How to adapt to a project you've never seen before

1. **Spend the first effort on Step 1** — getting the authoritative backlog source right matters more than any chart. A beautiful forecast off the wrong source is worse than no forecast.
2. **Lead with honesty about data quality.** First runs are thin; say so on the cover and let the range be wide. Stakeholders trust a humble range over a confident guess.
3. **Prefer measured over assumed** the moment history allows it — swap factor-based phase durations for actuals, multiplier scenarios for observed-window scenarios, point estimates for Monte-Carlo bands. The skill is designed to get sharper every run; let it.
4. **Make the QA+refine tail impossible to miss.** The single most valuable thing this deck does is stop teams from celebrating "dev done" and then slipping the real ship date. Keep that gap visually loud on the executive and phase slides.
