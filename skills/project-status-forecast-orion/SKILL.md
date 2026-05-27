---
name: project-status-forecast-orion
description: "Read the current project's backlog (BMAD story docs, GitHub Issues, or Jira — whichever the repo actually uses, detected at runtime), compute real delivery metrics (scope, velocity, trend), and project a phase-aware, multi-speed forecast all the way to a DEPLOY-READY date — not just 'dev done'. Models the full timeline: ramp-up → development → pre-deploy QA → refinement/hardening → deploy. Produces three speed scenarios (conservative / expected / optimistic), graduating to Monte-Carlo P50/P85/P95 confidence bands as run-over-run history accumulates. When the project's start/end dates aren't already in its memory, asks the user for them (approximate is fine), stores them, and anchors every prediction to them — and asks whether final QA/refinement is in-scope or happens post-delivery (excluded from the date if so). Forecasts the backlog drain on NET created-vs-closed throughput (not gross), measures velocity over the active window (excluding pre-tracking setup), distinguishes planned vs emergent scope, and flags bot/agent-driven throughput. Appends a dated snapshot each run so forecasts sharpen over time, and emits a single self-contained dark-theme HTML stakeholder deck into the Downloads folder. Invents no numbers. Use when the user says '/project-status-forecast-orion', 'where does the project stand', 'when will we ship / finish', 'forecast the project', 'delivery forecast', 'status deck for stakeholders', or wants a realistic deploy-ready date range to drive decisions."
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
- **Forecast to deploy-ready, not dev-complete — but confirm what "done" includes.** Development finishing is not shipping. The deploy-ready date is `dev-complete + final QA + refinement` **only when that work sits inside the project's timeline**. On some projects QA/hardening happens *after* hand-off, outside the tracked window. So **ask whether the final QA + refinement is in-scope or post-delivery** (Step 2) and add the tail only when it's in-scope. Always show dev-complete separately so the gap is visible either way.
- **Anchor to user-confirmed dates; never invent the start/end.** The project's start and intended ship dates are the spine of the forecast. If they aren't already in the project's memory, **ask the user (approximate is fine) and store them** before forecasting — don't silently assume them. Show each anchor's provenance (user-given vs inferred) so the reader can trust the math.
- **Forecast dates on NET throughput, not gross.** If the team creates new work nearly as fast as it closes it, the gross close-rate produces an absurdly optimistic drain — a high "closed per week" makes the open backlog look like it clears in days, right up until you notice nearly as many new issues landed that same week. Measure **created-vs-closed net burndown** and drain the remaining backlog on the *net* rate; show the gross close-rate only as a capacity figure, never as the basis for a finish date. When net is ~zero or negative, say so loudly — the honest headline is "scope isn't converging yet," not a date.
- **Separate measured facts from scenario judgment.** Numbers pulled from the tracker/history are facts; multipliers and assumed future scope are *judgment*. Label them differently in the deck and expose the assumptions as editable knobs — never let an assumed multiplier masquerade as derived data.
- **Sanity-check the inputs before trusting the output.** Throughput can be inflated by automated/agent accounts; a completion % can swing wildly depending on whether you count planned stories or raw open issues; a "start date" can hide weeks of pre-tracking setup. Detect each and surface it — a confidently wrong forecast is worse than a wide honest one.
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

### Step 2 — Establish the timeline anchors (ASK & STORE if not in memory)

A phase forecast needs a start, a now, and an end. **The start and end dates are mandatory anchors — every prediction is built on them.** You have no reliable way to *know* a project's intended start or ship date, so do not infer-and-proceed silently: read them from the project memory dir first, and **if either is missing, ASK the user, then WRITE the answer to memory before forecasting.**

- **`today`** — the run date.
- **`start_date`** — read `project_start_date.md` from the project memory dir. **If absent, ask the user:** *"When did this project start (roughly)? An approximate date is fine."* Offer your best inference as the suggested default (earliest closed story / first issue created / first commit) so they can accept or correct it. Then **write the chosen value to `project_start_date.md`** (see Config) so future runs don't re-ask.
- **`target_date`** (the intended end / ship date) — read `project_target_date.md` (same convention `sequential-bmad-github-orion-v3` uses). **If absent, ask the user:** *"When is this expected to be done / shipped (roughly)? An approximate date is fine — the forecast will refine against actual velocity each run."* Then **write the chosen value to `project_target_date.md`**.
- **QA + refinement scope and duration** — read the `qa_refine` block from `forecast_phases.md`. **If absent, ask the user two things and store the answers** before forecasting:
  1. *"Is the final QA + refinement included in the project timeline (i.e. it happens before your target ship date), or does it happen after delivery?"* — if **after delivery, do NOT factor it into the forecast**: the headline delivery date = dev-complete (+ any in-scope buffer only), and the QA/refine effort is shown as a separate *post-delivery* note, never folded into the date.
  2. *"Roughly how long will the final QA + refinement take?"* — a span like "2 weeks" / "10 work days"; approximate is fine.
  Write both to `forecast_phases.md` as `qa_refine.included: true|false` and `qa_refine.duration_work_days: <N>`. A user-given duration **overrides** the factor-based QA/refine estimate; the `qa_factor`/`refine_factor` defaults are only the fallback when no duration is known.
- **Approximate is fine — say so when asking.** Rough dates are acceptable; the deck states them as assumptions, not facts, and the forecast sharpens against measured velocity every run. Record whether each date was **user-given or inferred** and show that provenance on the assumptions slide.
- **Re-confirm on demand.** If the user says the stored dates are wrong (or passes new ones), overwrite the memory files and recompute. The stored values are a convenience, not a lock.
- **Working calendar** — default Mon–Fri, no holidays. Honor `forecast_phases.md` overrides (`work_days`, `holidays`) if present. Report both calendar-day and work-day figures.

Because the end date is now always established, the **target analysis (Step 4) always runs** — comparing the forecast deploy-ready range against the user's intended ship date is the core decision the deck supports.

### Step 3 — Measure scope and velocity (from the detected source)

**Scope.** Count the unit the project actually uses — *stories* if there's a story label/structure, else *issues*, else BMAD story files. Compute total / closed / open. If the tracker distinguishes work types (labels like `bug`, `qa`, `chore`, `hardening`, or BMAD epic structure), split **dev work** from **QA/bug/hardening work** — that split feeds the phase model. Labels are often missing or inconsistently applied; when they are, fall back to undifferentiated "units" — don't invent a label that doesn't exist.

- **Planned vs emergent scope — compute both completion numbers.** "Open issue count" is not "remaining planned scope." Cross-reference the project's own plan — epic/story breakdowns in a planning doc, epic-issue body checklists (`- [ ] #NN …`), a roadmap file — to derive a **planned-completion %** (planned items done ÷ planned items), and report it next to the **raw-issue %** (closed ÷ total). When they diverge (nearly done by plan, yet many open emergent follow-ups), that gap is itself decision-grade: show both and say which open items are planned vs emergent.
- **Backlog stability — is total scope even known yet?** Plot issue *creation* over time. Detect **recent creation bursts** (a large block of issues created in the last few days) and **un-enumerated planned work** (an epic/area defined in the plan but with no/few child issues yet). If scope is still being written, lead with a loud **"backlog not yet stable — total scope uncertain"** banner and frame the headline as that uncertainty, not a precise date.

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
- **Active-window start, not first commit.** Compute velocity from when *tracked work actually started flowing*, not from repo creation. If `(first_closed_unit_date − start_date)` exceeds `active_window_gap_days` (default 14), there was a pre-tracking setup period (scaffolding / PRD / architecture, zero closed work) — **switch the velocity denominator to the active window** (from the first closed unit) and surface a one-line note: *"tracked development began on `<date>`; `<N>` days of pre-tracking setup excluded from velocity."* Never let the setup gap halve the rate and push every date out.
- **Gross close-rate**: closed ÷ active-window elapsed, per calendar day / work day / 7-day week. This is the **capacity** figure — report it, but it does *not* drive finish dates (see net, below).
- **Net burndown — this drives the dates.** Compute **created vs closed per week** across the window; the net rate is `closed − created`. Drain the remaining backlog on the **net** rate. If net is ~zero or negative, report "scope not converging" instead of a finish date.
- **Ramp-aware steady-state** (optional): exclude the first `ramp_window` (default 7 calendar days) and recompute; report both. Use steady-state over the active window for projection.
- **Recent vs. cumulative trend** (needs ≥ 3 snapshots): compare the last snapshot interval's rate to the cumulative rate. Flag **accelerating / steady / decelerating** — a decelerating trend is exactly the kind of thing stakeholders must hear early.
- **Contributors — flag non-human accounts.** Count per-contributor close rates and the active engineer count, but **identify bot / agent / pipeline accounts** (automation logins, names matching the project's own tooling, superhuman close rates) and exclude or separately label them. Don't use a contributor count inflated by agents as human headcount for per-engineer required-rate math; note when throughput is **pipeline-driven** (it can swing sharply if the pipeline config changes). Identify the current user from `git config user.email` matched to the tracker login.

### Step 4 — Run the phase-aware forecast

This is the core. Project the remaining timeline as ordered phases, each ending on a date:

| Phase | Duration model (default) | Notes |
|---|---|---|
| **Ramp-up** | mostly already elapsed | Only material for a project younger than `ramp_window`. Apply `ramp_factor` (default 0.65 × steady-state) to the not-yet-ramped portion. |
| **Development** | `remaining_dev_units ÷ velocity` | The dev-complete date. Uses the scenario's velocity (Step 4 scenarios). |
| **Pre-deploy QA** | `qa_factor × dev_duration` (default 0.25) | If the tracker has measurable QA/bug/hardening work, use the greater of (that work ÷ velocity) and the factor-based estimate. |
| **Refinement / hardening** | `refine_factor × dev_duration` (default 0.15) | Buffer to fix QA-found defects and polish before deploy. |

`delivery_date = dev_complete_date + qa_duration + refine_duration` (advanced over the working calendar). All factors come from `forecast_phases.md` (with the defaults above); **once a phase has actually completed in the history, prefer the measured duration over the factor and say so.**

**QA + refinement inclusion (from Step 2).** If `qa_refine.included` is **false** (QA/hardening happens after hand-off, outside the tracked window), the headline **delivery date = dev-complete** (+ any in-scope buffer only); present the QA/refine duration as a separate *post-delivery* note, explicitly **not** added to the forecast date. If **true**, add the tail using the most grounded estimate available: the user-given `qa_refine.duration_work_days` (it overrides the factors), else `qa_factor`/`refine_factor × dev_duration`, else — if QA work is tracked as issues — `that work ÷ velocity`.

**Drain the open backlog on the NET rate, not gross.** Dev-complete for *planned* work = remaining planned dev units ÷ dev velocity. But the remaining-*backlog* drain (which includes emergent follow-ups) must use the **net** created-vs-closed rate from Step 3 — if the team keeps adding scope, gross velocity will lie. Show both, and let the net-based date drive the headline when emergent scope is significant. If net ≤ 0, replace the finish date with a "scope not converging" verdict.

**Speed scenarios** — compute the full timeline (dev → QA → refine → deploy-ready) under each:

- **Conservative (slow)** — velocity × `conservative_mult` (default 0.7), and the *larger* QA/refine factors (×1.3). Answers "if things go worse than now."
- **Expected (current pace)** — steady-state velocity, default factors. The planning number.
- **Optimistic (fast)** — velocity × `aggressive_mult` (default 1.3), smaller QA/refine factors (×0.8). The "everything breaks our way" floor.

Once `forecast-history.jsonl` has **≥ 6 snapshots** (configurable `mc_min_samples`), also run a **Monte-Carlo simulation**: sample the observed per-interval throughput (the deltas between snapshots, optionally bootstrapped) ~10,000 times to drain the remaining backlog, add the QA+refine tail to each draw, and report **P50 / P85 / P95 deploy-ready dates** with a fan chart. Below the sample threshold, state that bands are not yet available and that N more runs will unlock them. (If you cannot run a real RNG in-session, compute the percentiles analytically from the throughput distribution and label the method.)

**Observed-window scenarios** (when history allows): instead of (or alongside) the multiplier scenarios, derive conservative/expected/optimistic from the **slowest / median / fastest** rolling-window velocity the project has *actually* achieved — real speeds beat invented multipliers. Prefer these once available; keep the multiplier scenarios as the bootstrap.

**Target analysis** (normally — `target_date` is established in Step 2): work *backward* from the target — `required_dev_complete = target_date − (qa_duration + refine_duration if in-scope)` — then `required_dev_velocity = remaining_dev_units ÷ work_days_to_required_dev_complete`. Compare to actual velocity → **gap** (negative = behind). Derive per-engineer required rate (`required_team_rate ÷ human_engineer_count` — humans only, per the bot-flagging in Step 3). Set a **target-RAG verdict**: 🟢 on track (expected ≤ target), 🟡 at risk (conservative > target ≥ expected), 🔴 behind (expected > target).

**Health verdict when there's no usable target.** Step 2 normally secures a target, but the user may genuinely have none (or answer "unknown"). The one-glance pill must still be defensible: derive a **delivery-health** verdict (not a target-RAG) from net-burndown sign + trend + scope stability — 🟢 strong (net positive, stable scope, dev ~done), 🟡 watch (flat net or churning scope), 🔴 at-risk (negative net or exploding scope) — and label it explicitly as "health," distinct from a target-based RAG.

**Keep measured and assumed visibly separate.** In the scenarios, mark which inputs are *measured* (velocities, counts, dates from the tracker/history) and which are *assumptions* (multipliers, assumed future scope additions). State assumed extra-scope per scenario as an explicit, editable number — never fold it silently into a "derived" date.

### Step 5 — Persist a snapshot (improve over time)

Append exactly one JSON line to `<project-memory-dir>/forecast-history.jsonl` where `<project-memory-dir>` is `~/.claude/projects/<harness-project-key>/memory/` (the harness key is derived from the project's absolute path; this is the same dir Step 2 reads config from). **Create the dir if missing; never commit it; it is local-only.** Append — never rewrite — so the series is preserved.

```jsonc
{
  "schema_version": 2,
  "date": "<YYYY-MM-DD>",                 // run date (one snapshot per run; if same-day re-run, append anyway)
  "source": "bmad|github|jira|gitlab|git",
  "unit": "stories|issues|units",
  "start_date": "YYYY-MM-DD",             // project start anchor (Step 2)
  "active_start": "YYYY-MM-DD",           // first closed unit; the velocity denominator
  "scope": {
    "total": 0, "closed": 0, "open": 0, "dev_open": 0, "qa_open": 0,
    "planned_total": 0, "planned_done": 0, "emergent_open": 0   // null if no plan to cross-reference
  },
  "velocity": {
    "gross_per_work_day": 0.0, "gross_per_week": 0.0,
    "net_per_week": 0.0,                  // created-vs-closed; this drives the dates
    "steady_state_per_work_day": 0.0
  },
  "engineers": { "total": 0, "human": 0, "bot": 0 },
  "scope_stability": "stable|churning|unknown",
  "phase_factors": { "ramp": 0.65, "qa": 0.25, "refine": 0.15 },
  "qa_refine": { "included": true, "duration_work_days": null },
  "scenarios": {
    "conservative": { "dev_complete": "YYYY-MM-DD", "delivery": "YYYY-MM-DD", "assumed_extra_units": 0 },
    "expected":     { "dev_complete": "YYYY-MM-DD", "delivery": "YYYY-MM-DD", "assumed_extra_units": 0 },
    "optimistic":   { "dev_complete": "YYYY-MM-DD", "delivery": "YYYY-MM-DD", "assumed_extra_units": 0 }
  },
  "target_date": "YYYY-MM-DD|null",
  "verdict": { "kind": "target-rag|health", "value": "green|amber|red" },
  "notes": "<one-line: what changed vs last snapshot, or 'first run'>"
}
```

On every run, **read the prior lines first** so you can: show "what changed since last run" (Δ scope, Δ net rate, did the delivery date move?), compute trend, measure completed-phase actuals, and feed Monte-Carlo. **Read older lines defensively** — `schema_version: 1` snapshots used `velocity.per_work_day`, `engineers` (a bare int), `scenarios[*].deploy_ready`, and `rag`; map them onto the v2 fields and fill anything missing with null rather than erroring.

### Step 6 — Generate the HTML deck

Single self-contained file, dark theme, inline-SVG charts, keyboard-navigable. Reuse the visual conventions of `create-up-to-speed-report-orion` (same palette, `<template id="slides">` + JS-clone navigation, footer progress bar) — but charts here are **inline SVG**, not ASCII, because the forecast *is* the chart.

**Slide outline** (adapt to the data you actually have):

1. **Cover** — project name, "Status & Forecast", run date, the detected backlog source + unit, nav hints (← / → / Space / F). If scope is churning, a "backlog not yet stable" badge here too.
2. **Executive summary (one glance)** — the verdict pill (target-RAG if a target exists, else delivery-**health**, clearly labelled which); the **delivery date range** (conservative → optimistic) with the expected date bold; dev-complete shown separately; whether QA/refinement is **in-scope or post-delivery**; target date + gap; a net-burndown one-liner ("closing ~N/wk, creating ~M/wk → net ~K/wk"); the 3 biggest risks; "what changed since last run." Decidable on this slide alone.
3. **Where we stand** — totals (closed / open / %); **two completion numbers — planned-% and raw-issue-%** — with the gap explained; elapsed over the **active window** (with the pre-tracking setup gap called out and the method shown); dev-vs-QA split if available.
4. **Scope stability** — issue *creation* over time; recent-burst detection; any un-enumerated planned epic/area; the "is total scope known?" verdict. (Drop this slide if scope is clearly stable.)
5. **Velocity & capacity** — gross close-rate (capacity) vs **net burndown (drives the dates)**; the trend verdict (accelerating / steady / decelerating); a velocity-over-time line chart from the snapshot series (or "first run — no series yet"); flag if throughput is pipeline/agent-driven.
6. **Burndown / burnup** — remaining backlog over time with the **net-rate** projection per scenario (the "fan").
7. **The phase model explained** — a horizontal timeline (active-start → dev → [QA → refine if in-scope] → delivery) with each phase's dates and the factor/measured/user-given duration it used; show the QA+refine tail either inside the timeline or as a separate post-delivery note, per the Step 2 answer.
8. **Scenarios** — a table: Scenario · basis (**measured**) · assumed extra-scope (**judgment**) · net rate used · Dev-complete · +QA/refine (if in-scope) · **Delivery**. Rows: Conservative / Expected / Optimistic (+ Monte-Carlo P50/P85/P95 if unlocked). Visually distinguish measured columns from assumption columns. A fan chart of delivery dates.
9. **Target analysis** — the user's intended ship date vs the forecast range; required vs actual (net) velocity; the gap (colored ±); per-engineer required rate over **human** headcount; what would have to change. (If no target: this slide becomes the health-heuristic explanation instead.)
10. **Contributors** (if multi-dev) — per-contributor closed counts, share, cadence, with **human vs bot/agent accounts clearly separated**.
11. **Risks & assumptions** — every assumption the forecast rests on (date provenance, active-window exclusion of setup time, phase factors vs user-given QA/refine duration, QA/refine in- vs post-delivery, assumed extra-scope per scenario, scope-stability, bot-driven throughput, sample size for bands) and the top risks. Honesty here is the product.
12. **Methodology & data provenance** — exactly which queries/files produced the numbers, the snapshot count and date range, the measured-vs-assumed legend, and "invents no numbers" stated plainly so stakeholders trust it.

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

- **`project_target_date.md`** — `target_date: <YYYY-MM-DD>` (reuses the v3 convention). The intended ship/end date. **If missing, Step 2 asks the user and writes this file**; approximate dates are fine.
- **`project_start_date.md`** — `start_date: <YYYY-MM-DD>`. The project start anchor. **If missing, Step 2 asks the user (offering an inferred default) and writes this file.** Edit/delete it to re-anchor.
- **`forecast_phases.md`** — tunables (YAML/front-matter); any omitted key uses the default. **If the `qa_refine` block is missing, Step 2 asks the user (scope + duration) and writes it here.**
  ```yaml
  ramp_window_days: 7
  ramp_factor: 0.65
  qa_factor: 0.25            # fallback only — used when no explicit qa_refine.duration is known
  refine_factor: 0.15        # fallback only (as above)
  qa_refine:
    included: true           # false = QA/hardening happens AFTER delivery; not added to the date
    duration_work_days: null # user-given span; overrides the factor-based estimate when set
  conservative_mult: 0.7
  aggressive_mult: 1.3
  active_window_gap_days: 14 # if first-close lags start by more than this, velocity uses the active window
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

**Forecast-logic traps (these will silently produce a *wrong* date):**

- **Start date hides pre-tracking setup** → if the first closed unit lags the start date by more than `active_window_gap_days`, compute velocity over the **active window** (from first close) and note the excluded setup days. Using repo creation / first commit as the denominator can halve the rate and push every date out by weeks.
- **Scope is churning (team creates ≈ as fast as it closes)** → this is a first-class input, not a footnote: forecast the backlog drain on **net** created-vs-closed, and if net ≤ 0, report "scope not converging" instead of a date.
- **Two completion numbers disagree** → planned-% (by the project's own story/epic plan) and raw-issue-% (closed ÷ total) can differ a lot when there's emergent work. Show **both**; the gap is the story, not a bug to hide.
- **Throughput is automation-driven** → flag bot / agent / pipeline accounts; don't count them as human headcount for per-engineer required-rate, and warn the rate can swing if the pipeline config changes.
- **No usable target** → don't leave the executive pill undefined; fall back to the **delivery-health** heuristic (net sign + trend + scope stability), labelled as health, not target-RAG.
- **Assumed multipliers masquerading as data** → keep measured inputs and scenario assumptions visually separate; state assumed extra-scope per scenario as an explicit, editable number.

**Source / data traps:**

- **No tracker at all** → fall back to git-history velocity; state clearly the forecast is commit-derived and weaker.
- **Brand-new project (younger than `ramp_window`)** → not enough steady-state data; use raw velocity, widen the scenario range, and say bands/trend need more runs.
- **QA work not tracked** → model QA/refine from the user-given duration or the factors; flag in Risks & assumptions that the tail is estimated, not measured.
- **Tracker doesn't distinguish stories from bugs/chores** → count undifferentiated units; don't invent a label.
- **`gh`/Jira returning truncated lists** → pass `--limit 1000`+ (GitHub) / page JQL fully (Jira).
- **Start/end dates not in memory** → ask the user for both (approximate is fine), offering an inferred start as the suggested default, then write `project_start_date.md` / `project_target_date.md` before forecasting. Never silently invent these anchors.
- **Stored date is wrong** → overwrite the memory file with the user's correction and recompute; show each date's provenance (user-given vs inferred) on the assumptions slide so it can be sanity-checked.
- **Same-day re-run** → still append a snapshot (the series is event-based, not one-per-day); "what changed" compares to the immediately prior line.
- **Velocity is zero (nothing closed yet)** → don't divide by zero; report "no completions yet — forecast is planning-state only" and base the range on backlog size + the configured factors with an explicit caveat.

**Windows / cross-shell tooling traps (cost retries on a real run):**

- **`/tmp` is not shared between git-bash and Windows-native Python** → files written from the Bash tool may land in `%LOCALAPPDATA%\Temp`, which a Windows `python` can't resolve as `/tmp/...`. Pick **one explicit absolute path** and use it from both, rather than assuming `/tmp` resolves.
- **Windows console is cp1252 — printing non-ASCII (→, em-dash) raises `UnicodeEncodeError`** → write analysis output to **UTF-8 files**; never `print()` non-ASCII to the console.
- **Heredocs through the Bash tool break on embedded quotes/apostrophes** → write generator scripts with the **Write tool**, then run them — far more robust than `cat > f << 'EOF' … EOF`.
- **PowerShell `Set-Content -Encoding utf8` adds a BOM / double-encodes** → use `[System.IO.File]::WriteAllText` with `New-Object System.Text.UTF8Encoding $false`, or just write the file with Python `open(path, "w", encoding="utf-8")` (clean, no BOM).

## How to adapt to a project you've never seen before

1. **Spend the first effort on Step 1** — getting the authoritative backlog source right matters more than any chart. A beautiful forecast off the wrong source is worse than no forecast.
2. **Lead with honesty about data quality.** First runs are thin; say so on the cover and let the range be wide. Stakeholders trust a humble range over a confident guess.
3. **Prefer measured over assumed** the moment history allows it — swap factor-based phase durations for actuals, multiplier scenarios for observed-window scenarios, point estimates for Monte-Carlo bands. The skill is designed to get sharper every run; let it.
4. **Make the QA+refine tail impossible to miss** — when it's in-scope. The single most valuable thing this deck does is stop teams from celebrating "dev done" and then slipping the real ship date. Keep that gap loud on the executive and phase slides; when QA/refine is post-delivery, label it so nobody double-counts it.
5. **Get the two highest-leverage defaults right first: the active-window start and the net rate.** More than any chart, these two decide whether the first-run forecast is roughly right or wildly off. A velocity measured from repo-creation through a long setup gap, drained on gross close-rate, can be off by 2× in both directions at once — fix the denominator (active window) and the numerator basis (net created-vs-closed) before polishing anything else.
