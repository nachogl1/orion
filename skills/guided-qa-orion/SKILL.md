---
name: guided-qa-orion
description: 'Guided, story-by-story QA of a batch of already-developed stories, driven by a QA report (HTML/MD) the user provides — for example one emitted by an automated batch pipeline — with the goal of clearing the batch for production. The agent ingests the report, then QAs ONE story at a time exhaustively against the live app, HALTS after each story with a full verdict + plain-English story summary + the tests it ran + every bug/concern/improvement, and ASKS the user what to do (fix now, log an issue, log to MD/HTML, defer, accept). It never advances to the next story without the user. Bugs get fixed, then the WHOLE test suite + e2e must pass; nothing is committed until the user agrees everything passed and a final pre-commit test run is green. Use when the user says "/guided-qa-orion", "guided QA", "QA this batch with this document", "walk these stories one by one for QA", or hands over a QA report and asks to verify the stories before merge/deploy.'
---

# guided-qa-orion

> [!NOTE]
> **Thinking of editing this skill?** Prefer creating a *new version* — copy it to a new skill name (e.g. bump a `-vN` suffix) — and leave this one as-is. People and automated workflows may rely on the current behaviour, so versioning beats editing in place.

Companion-style QA for a batch of stories that are already built and merged onto a batch branch, where the user hands you a **QA report** (e.g. `qa-report.html`, a markdown report, a list of issues with expected behaviour — often the artifact an automated batch pipeline produces) and wants to certify the batch for production.

The defining rule: **one story at a time, exhaustive QA, then a hard HALT with exhaustive feedback, then the user decides the next move.** You are the user's QA companion — you do the testing, you surface everything, and the two of you decide together whether the batch is safe to ship. You do not race ahead. This makes it a natural fit to run **in parallel with a long-running pipeline**: the pipeline builds, you QA what it has already produced.

This skill is interactive and gated. It is the opposite of a fire-and-forget automation: every story ends in a conversation.

## Operating principles (read first)

1. **Story-by-story, never batched.** QA exactly one story, halt, report, wait. Do not pre-test the next story "to save time" — the user may want to fix/change something that affects later stories.
2. **Exhaustive per story.** Happy path + every action/variant + role/persona gating + localization (if the app is multi-language) + adjacent-area regressions + edge cases + the network/DB side-effects. Verify against the LIVE app, not just unit tests.
3. **Exhaustive feedback, every story.** The halt report is the product. It must let the user decide with full information.
4. **The user decides every transition.** Never advance to the next story, and never commit, without an explicit user decision.
5. **Truth over the document.** The QA report is a guide and a set of claims — verify them. Flag inaccuracies, distinguish real bugs from documented TODOs and from test-environment/seed limitations.
6. **Don't report automation artifacts as product bugs.** UI driving (browser-automation clicks especially) can silently no-op or be refused. Prove a UI bug with DOM-level evidence before calling it (see "The UI-click pitfall").
7. **Nothing ships red.** Fixes trigger a full test suite + e2e run; commits are gated behind green + user approval + a final pre-commit test run.
8. **Branch discipline.** Work on the batch branch. Never commit to the default branch. Commit/push only when the user asks. (Honor any repo ground-rules file, e.g. `CLAUDE.md`.)

## Inputs / pre-conditions

- **A QA report** path from the user (HTML or MD). **This is mandatory — the skill is report-driven. If none was given, stop and ask for it before doing anything else.**
- A git repo on the **batch branch** (not the default branch). Confirm with `git branch --show-current`.
- An app stack that can be started locally (or is already running).
- The project's test commands. **Auto-detect from the repo** rather than assuming a stack — inspect the manifests present and derive the unit/integration and e2e commands:
  - JS/TS: `package.json` scripts (npm/pnpm/yarn/bun); monorepo workspace filters if present.
  - .NET: `*.sln` / `*.csproj` → the test runner.
  - Other ecosystems: `Makefile`, `pyproject.toml`/`tox.ini`, `go.mod`, `Cargo.toml`, `pom.xml`/`build.gradle`, etc.
  - e2e: whatever the repo wires up (a `test:e2e`-style script, a browser-automation runner, a runbook).
  Confirm the detected commands before relying on them.

If the working branch is the default branch, or no QA report is available, stop and ask before doing anything.

## Phase 0 — Ingest the QA report & build the story map

1. **Read the entire QA report.** Extract and write down (in your working notes / a task list):
   - Branch name and the **ordered list of stories/issues** (use the report's merge/QA order).
   - Per story: a one-line plain-English summary, the expected behaviours / acceptance criteria, and the **explicit click-through / verification steps**.
   - **Known TODOs / acknowledged limitations** per story (e.g. "route doesn't exist yet → 404 by design", "no seed data", "sublabels stay in language X"). Keep this list separate — these are NOT bugs.
   - Any **claims** the report makes (test counts, "verified live", deep-link params, storage keys). These are to be *verified*, not trusted.
   - The accounts / personas and their permissions, and the **stack start instructions**.
2. **Create a task list** — one task per story, in order, plus a "stack up" task and a "batch wrap-up" task. This is the spine of the run.
3. **Confirm scope with the user** only if the order, personas, or which-report is ambiguous. Otherwise state your plan briefly and proceed.

## Phase 1 — Bring up the stack (and confirm true readiness)

4. **Check if it's already running** (probe the app port / health). If not, start it with the project's command (from the report or detected).
5. **Wait for *true* readiness, not just the dev server.** A live SPA port ≠ a ready stack. Wait for the auth provider (OIDC/SSO/session), the DB/migrations, and the API health/ready marker. Poll until the real "ready" signal appears (log line, health 200, dashboard green), with a sane timeout.
6. **If startup fails, diagnose before nuking.** Common failure modes: orphaned containers, stuck DB/migration locks, migration-history drift. Surgical fixes beat a full volume wipe. Surface the diagnosis if you can't recover quickly.
7. **Confirm you can log in** as each persona you'll need. Note the default UI language; if the user can't read it, offer to switch the UI to their language for the walkthrough (do this once, early).

## Phase 2 — Per-story exhaustive QA loop (THE CORE)

Repeat this whole block for each story, **in order, one at a time.**

### 2A — Understand the story
- Restate, in plain English, what the story does and who it's for. Pull from the report; read the code if the report is thin or you need the real contract (e.g. how an action builds a URL, how a permission is computed, what a query scopes by).
- List its acceptance criteria / expected behaviours **and** its known TODOs (from Phase 0). You'll judge findings against both.

### 2B — Exhaustive live QA
Pick the right tool for the story type:
- **UI stories** → drive the real browser with a browser-automation tool (e.g. Playwright, including via an MCP server): navigate, type, click, snapshot. Walk the actual user journey end-to-end.
- **Backend/API stories** → real HTTP calls against the running API (authenticated), inspect responses, DB rows, audit/activity logs.
- **Background/job stories** → trigger the job, observe the dashboard + DB state.

Cover, at minimum:
- **Happy path** for every action/variant the story adds.
- **Permission / role gating** — re-login as each relevant persona and confirm what each can and cannot see/do. Server-computed permissions must be checked with a real session, not assumed.
- **Localization** (only if the app supports multiple languages) — toggle every supported language; confirm no raw keys leak, locale files have matching entries, and verify any persistence claim (storage key, survives reload).
- **Network/side-effects** — confirm the expected endpoints actually fire (and with the right status), and that DB/audit/activity rows are written where the AC implies persistence.
- **Adjacent-area regressions** — smoke-test screens/endpoints that share the changed component or slice.
- **Edge cases** — empty/ambiguous queries, mixed-result orderings, boundary inputs, deep-link params.
- **Cross-check the report's claims** against what you observe. Note every inaccuracy.

For each observation, classify it:
- **Real bug / error** (with severity), **Concern / risk**, **Improvement**, **Doc inaccuracy**, **Documented TODO confirmed**, or **Environment/seed limitation** (e.g. a "missing" result that's actually correct role-scoping or absent seed data — verify against the scoping logic / seed before calling it).

Capture evidence: network results, accessibility/DOM snapshots, DOM reads. Use real screenshots only when visual proof is needed (dark mode, layout), saved to a scratch dir.

#### The UI-click pitfall (CRITICAL — do not skip)
Browser-automation clicks can **silently no-op** or be **refused by the hit-test**, and that can look exactly like a product bug (or hide one). Before you declare a click/interaction broken — or pass it — verify at the DOM level:
- Read `getComputedStyle(el).pointerEvents`, and use `document.elementFromPoint(cx, cy)` at the element's centre to see what a real cursor would actually hit (overlays, `pointer-events:none`, ancestors intercepting).
- Run a **negative + positive control**: dispatch a faithful pointer/mouse event sequence on the topmost element a cursor would hit (replicates the real click) vs. directly on the target element. If only the latter works, the handler is sound but unreachable → a real bug. If neither does anything but the unit test passes, suspect a CSS/overlay issue the test env can't see (a headless DOM like jsdom ignores layout & `pointer-events`).
- Only then conclude. Many "the click did nothing" results are the tool, not the app — and some "looks fine" results hide a CSS bug that only manifests in a real browser. Prove it either way.

### 2C — HALT and give exhaustive feedback (the deliverable)
Stop. Present a complete per-story report:
1. **Verdict** — one of: ✅ PASS · 🟡 PASS-with-notes · 🔴 FAIL · ⛔ BLOCKER.
2. **What the story does** — plain English, 2-4 lines.
3. **Tests I ran** — concrete steps and their results (a table works well: action → expected → observed → ✓/✗). Include personas, localization, endpoints fired, edge cases.
4. **Findings** — every bug / error / concern / improvement / doc inaccuracy / confirmed-TODO, each with: severity, evidence, root cause (if known), and a concrete suggested fix. Explicitly separate **real bugs** from **documented TODOs / env-limitations** so the user isn't alarmed by by-design behaviour.

Keep it exhaustive but scannable — this report is what the user uses to decide.

### 2D — Ask the user what to do (do not advance unsupervised)
Use `AskUserQuestion` (multi-select) to let the user choose what to do with this story's findings. Typical options:
- **Fix now** (apply fixes on the batch branch),
- **Log an issue** (in the project's tracker, for out-of-scope / deferred items),
- **Log to MD/HTML report** (append findings to a running QA log),
- **Accept & continue** (notes only),
- **Defer / out-of-scope**.

Then ask whether to **proceed to the next story**. **Do not move on until the user decides.** This is the heart of the skill — the two of you decide together, story by story.

## Phase 3 — Carry out the chosen actions

- **Fix now**: find the real **root cause** (don't patch symptoms), keep the fix **narrowly scoped**, and match the surrounding code's conventions. After each fix:
  - Re-verify the fix **live** (and, for UI, with the DOM-level proof from 2B).
  - Run the **affected unit tests** to confirm nothing local broke.
  - If a fix is more invasive than a one-liner (new dependency, shared component, test-infra/config change), **surface the trade-off** before committing to it; don't silently expand scope. (For example: introducing a UI component that depends on a context provider from a component library can require the test runner to dedupe/inline that package so a single context instance is used — that's a config change worth flagging.)
  - **Do not commit yet** — commits are gated by Phase 5.
- **Log an issue**: title + repro steps + expected/actual + scope/impact + suggested fix; apply sensible existing labels; **no assignee unless asked**. Use the project's issue tracker (e.g. GitHub via `gh issue create`, or whatever the repo uses). Confirm the issue URL back to the user.
- **Log to MD/HTML**: append to the agreed findings file. If the file is a "status" artifact the user treats as canonical, follow their update rules (update in place, append-only history, preserve content verbatim).
- **Defer / accept**: record it in your notes and the per-story verdict; move on.

## Phase 4 — Advance only on the user's say-so

After the chosen actions are handled, confirm with the user whether to continue. Then return to **Phase 2** for the next story. Repeat until every story has a verdict and the user is satisfied with each.

## Phase 5 — Batch wrap-up: full suite + e2e BEFORE any commit

This phase runs once all stories are QA'd and all agreed fixes are applied. The user's hard requirement:

> If bugs were found and fixed, the **whole test suite (e2e included)** must run; only when everything is green and the user — with your help — agrees it all passed do we run the tests once more as the pre-commit gate, and *then* commit.

Steps:
1. **Run the WHOLE test suite** — every unit/integration suite the repo has (backend + frontend), not just the ones touched.
2. **Run the e2e suite** against the live stack (start/keep the stack up; honor any project-specific e2e/runbook quirks).
3. **If anything is red**: fix it (root cause, scoped), then **re-run the WHOLE suite + e2e again** — not just the failing test. Loop until fully green. Cap retries on a single stubborn failure and surface it rather than thrashing.
4. **Joint go/no-go**: present the green results and your assessment; the user decides "all passed."
5. **Pre-commit gate**: once the user agrees, run the tests **one more time** as the final gate immediately before committing. Only on green do you proceed.
6. **Commit** (only now): scoped staging (never `git add -A`), Conventional Commits, on the **batch branch**. One commit per logical fix or a tidy grouping. Use the repo's commit conventions (incl. any required `Co-Authored-By` trailer). **Push / open a PR only when the user explicitly asks.** Never commit or push to the default branch.

## Hard rules — what this skill never does

- Never advances to the next story without the user's explicit decision.
- Never commits anything before the **full suite + e2e are green** AND the user has approved AND a final pre-commit test run passed.
- Never commits or pushes to the default branch; batch branch only; push/PR only on request.
- Never reports a browser-automation artifact (silent no-op / hit-test refusal) as a product bug without DOM-level proof (`pointer-events`, `elementFromPoint`, dispatched-event control).
- Never labels a documented TODO, by-design 404, role-scoped empty result, or absent-seed result as a bug — classify it correctly and say so.
- Never overstates a verdict: if a test was skipped or only partially verifiable in the environment, say exactly that.

## Field notes & recurring pitfalls (from real runs)

- **Unit / headless-DOM tests can't see CSS or layout.** A green unit suite says nothing about real-browser rendering — a headless DOM (e.g. jsdom) ignores layout, stacking, overlays, and `pointer-events`, so a CSS bug that makes an element unclickable (or an overlay that swallows clicks) sails right through. Any interaction an AC depends on must be confirmed in a real browser, not inferred from passing tests. (One real instance: a CSS attribute-*presence* selector matched far more elements than intended and disabled pointer events on all of them — invisible to the headless DOM, broken in the real browser.)
- **Don't judge an async-triggering action by its first frame.** When a click kicks off a fetch (a deep-linked dialog, a lazy panel, a late-rendered list), "nothing happened" immediately afterwards is often just the load not having finished. Re-check after the data settles before concluding it failed.
- **Role scoping vs. bugs**: an empty result for a non-admin persona is often correct scoping (verify against the query/permission logic), and an empty list for a seeded-but-unassigned entity is a seed limitation — not a defect.
- **Doc claims drift from reality**: deep-link params, persistence storage keys, and "verified live" claims are frequently slightly wrong. Verify each; report the delta as a doc inaccuracy, not necessarily a product bug.
- **Stack readiness**: SPA port up ≠ ready. Wait for auth + DB + API health. On restart trouble, check orphaned containers / DB locks / migration drift before wiping volumes.
- **Test-env module/context mismatches**: adding a component that relies on a library's shared context (e.g. a dialog/title from a component library) can throw "must be used within X" in the test runner even though it works at runtime — because the runner resolves two module instances. Fix via the runner's dedupe/inline config, and flag it as a config change.

## Cleanup checklist (every run)

- [ ] Scratch artifacts (screenshots, temp files) are outside the committed tree or removed.
- [ ] No marker/scratch files staged.
- [ ] Stack left in the state the user expects (running if they want to keep testing; stopped if asked).
- [ ] Every story has a recorded verdict; deferred items are logged where the user chose (issue / MD / HTML).
- [ ] Nothing committed unless the full suite + e2e were green and the user approved.
