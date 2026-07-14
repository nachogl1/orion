---
name: guided-qa-orion
description: 'Story-by-story QA of a batch of already-developed stories, driven by a QA report (HTML/MD) the user provides — for example one emitted by an automated batch pipeline — with the goal of clearing the batch for production. The agent ingests the report, then QAs ONE story at a time exhaustively against the live app, but DOES NOT halt or surface problems one by one: as long as a story is QA-able it records every bug/concern/risk into a consolidated findings file and keeps going, holding a single consolidated decision session at the END. Throughout the run it maintains ONE QA findings markdown — focused on concerns/errors/bugs/risks to act on (not praise) — every story''s verdict, the tests it ran, and all bugs/concerns/improvements/doc-inaccuracies/deferred-#Ns — written into the batch session folder next to the input report (for a sequential-bmad-github-orion-v4 run, that''s `~/Downloads/batch-<repo>-<timestamp>-<issues>/qa-findings.md`), so the user is left with a single actionable document. The aim is to leave the batch with as FEW open issues as possible: fix what can be fixed in-session (small fixes are just done, no issue/note), and file an issue only when a fix is genuinely too big — and only after a deep dive confirms no existing open issue or code already covers it. Bugs get fixed, then the WHOLE test suite + e2e must pass; nothing is committed until the user agrees everything passed and a final pre-commit test run is green. Use when the user says "/guided-qa-orion", "guided QA", "QA this batch with this document", "walk these stories one by one for QA", or hands over a QA report and asks to verify the stories before merge/deploy.'
---

# guided-qa-orion

> [!NOTE]
> **Editing this skill?** `guided-qa-orion` has **no `-vN` versioning** — edit it **in place** (per the repo's `CLAUDE.md`). Keep changes backward-compatible where you reasonably can, since other workflows may rely on the current behaviour.

Companion-style QA for a batch of stories that are already built and merged onto a batch branch, where the user hands you a **QA report** (e.g. `qa-report.html`, a markdown report, a list of issues with expected behaviour — often the artifact an automated batch pipeline produces) and wants to certify the batch for production.

The defining rule: **QA each story exhaustively, record every concern/bug/risk into one consolidated findings file, and keep going — then hold ONE consolidated decision session at the end.** You do **not** surface problems one at a time or halt after every story. As long as a story is QA-able, you accumulate its findings and move straight to the next; nothing in the per-story loop waits on the user. The two of you decide together what to *do* about everything at the end. This makes it a natural fit to run **in parallel with a long-running pipeline**: the pipeline builds, you QA what it has already produced.

**The aim is to leave the batch with as few open issues as possible.** Prefer fixing in-session over filing. Small, obvious fixes are just *done* — don't stop to file an issue or write the user a note for something you can fix in a couple of minutes. File an issue **only** when a fix is genuinely too big for this session — and **only after a deep dive** into the code and the existing open issues confirms nothing already covers it (this dedup step is mandatory; see Phase 3).

This skill is gated at the **end**, not per story: the run flows through all stories autonomously (after setup), then opens a single decision + fix + commit phase.

## Operating principles (read first)

1. **One story at a time, but don't halt between them.** QA exactly one story to completion, record its findings, and move straight to the next — no per-story stop, no asking the user what to do. The only thing that halts the loop mid-run is a true **⛔ BLOCKER** that prevents you from QA-ing the stories that follow (e.g. the area won't load at all); surface that immediately. Everything else accumulates and is decided at the end.
2. **Exhaustive per story.** Happy path + every action/variant + role/persona gating + localization (if the app is multi-language) + adjacent-area regressions + edge cases + the network/DB side-effects. Verify against the LIVE app, not just unit tests.
3. **The findings file is the product, and it's about problems — not praise.** It captures concerns, errors, bugs, risks, doc-inaccuracies, and things that could go wrong — the actionable stuff to resolve. Don't pad it with positive annotations or "this works great" notes. Record each story's verdict + the tests you ran (so coverage is auditable) and then every finding worth acting on.
4. **Fix-first, file rarely.** The end goal is the fewest possible open issues. Fix in-session whatever you reasonably can — and small/obvious fixes you just *do*, without filing an issue or writing the user a note about them. Reserve filing an issue for work that's genuinely too big for the session, and never file (or offer to file) one before a deep dive confirms no existing open issue or code already covers it.
5. **The user decides the actions — at the end, once.** The per-story loop runs autonomously. Commits and the "what do we do about everything" decisions happen in the end-of-run consolidation, with the user.
6. **Truth over the document — and the report is ephemeral.** The QA report is a *throwaway guide* for this session only: a set of claims to verify, not a file to maintain. **Do not keep it updated, re-sync it, or treat its file-state as meaningful** — its accuracy doesn't matter; the QA you perform and the inconsistencies you surface do. Verify every claim against the live app; flag each report-vs-reality mismatch as a **doc-inaccuracy finding** (logged in the durable findings log / per-story verdict), and distinguish real bugs from documented TODOs and from test-environment/seed limitations. If the report is wrong, that's a finding — never a reason to edit the report.
7. **Don't report automation artifacts as product bugs.** UI driving (browser-automation clicks especially) can silently no-op or be refused. Prove a UI bug with DOM-level evidence before calling it (see "The UI-click pitfall").
8. **Nothing ships red.** Fixes trigger a full test suite + e2e run; commits are gated behind green + user approval + a final pre-commit test run.
9. **Branch discipline.** Work on the batch branch. Never commit to the default branch. Commit/push only when the user asks. (Honor any repo ground-rules file, e.g. `CLAUDE.md`.)
10. **One consolidated findings file, always.** Maintain a single durable **QA findings markdown** for the whole run (distinct from the ephemeral input report). Create it up front, append each story's verdict + tests-run + every finding as you go, and finalize it with a batch roll-up at the end — so the moment the session ends the user has one actionable document. This is a standing deliverable, **not** an optional per-finding action: every finding lands here regardless of what else is later decided about it (fix / file an issue / defer / accept). It is a report **output**, never committed to the repo (see Phase 0 for where it lives).

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
   - **The report is ephemeral** (principle 6): you extract from it once, here, to plan the QA — you never edit, update, or re-sync it. Inaccuracies become findings, not edits.
   - The accounts / personas and their permissions, and the **stack start instructions**.
2. **Create the QA findings file — the run's durable deliverable (always, not optional).**
   - **Where it lives:** the **same directory as the input QA report**, named `qa-findings.md`. When the report is the `qa-report.html` that `sequential-bmad-github-orion-v4` emitted, that directory is the batch session folder — so the findings land right beside it at `~/Downloads/batch-<repo-name>-<timestamp>-<issue-suffix>/qa-findings.md`. If the report's directory isn't a sensible/writable spot (e.g. the report lives inside the repo tree, or you were handed claims rather than a file), fall back to `~/Downloads/qa-findings-<branch-slug>-<YYYY-MM-DD>.md`. It is a **report output — never inside the committed repo tree** and never staged/committed.
   - **What it is:** a record of **concerns, errors, bugs, risks, and doc-inaccuracies to act on** — plus each story's verdict and the tests you ran (for audit). It is **not** a place for praise or "this works well" notes; if a story is clean, its section is just the verdict + tests-run table with no findings.
   - **Seed it now** with a header: branch name, date, the path of the input report, the ordered story map, the personas/accounts in play, and the detected stack/test commands. Add a `## Findings by story` section (filled in per story) and an empty `## Batch summary` section (filled at wrap-up).
   - Tell the user the absolute path of the findings file so they know where to look.
3. **Create a task list** — one task per story, in order, plus a "stack up" task and a "batch wrap-up" task. This is the spine of the run.
4. **Confirm scope with the user** only if the order, personas, or which-report is ambiguous. Otherwise state your plan briefly and proceed.

## Phase 1 — Bring up the stack (and confirm true readiness)

5. **Ask about a clean slate before starting.** Use `AskUserQuestion`: *"Kill all running servers and reset Docker resources (stop + remove containers and volumes) for a clean-slate QA run?"* — options: **Yes, clean slate** / **No, use what's running**. If yes: stop the project's dev servers/processes, then `docker compose down -v` (or `docker rm -f` + `docker volume rm` for the project's containers/volumes). **Never remove or prune images** (`docker rmi` / `docker image prune` / `docker system prune` are off-limits — image rebuilds are expensive and not the user's intent). Then bring the stack up fresh. If no: probe and reuse the running stack.
5b. **Check if it's already running** (probe the app port / health). If not (or after a clean-slate reset), start it with the project's command (from the report or detected).
6. **Wait for *true* readiness, not just the dev server.** A live SPA port ≠ a ready stack. Wait for the auth provider (OIDC/SSO/session), the DB/migrations, and the API health/ready marker. Poll until the real "ready" signal appears (log line, health 200, dashboard green), with a sane timeout.
7. **If startup fails, diagnose before nuking.** Common failure modes: orphaned containers, stuck DB/migration locks, migration-history drift. Surgical fixes beat a full volume wipe. Surface the diagnosis if you can't recover quickly.
8. **Confirm you can log in** as each persona you'll need.
9. **Establish the QA language up front, and run the whole walkthrough in it.** Confirm the language the user actually reads (ask once if unknown) and treat that as the **base language** for the entire QA. If the app boots in a different default UI language, **switch the UI to the user's language immediately** — before story 1 — so the user can follow every step. Do this once, early; don't make the user read a language they don't speak. (Locale *coverage* — confirming each supported locale renders without raw keys — still happens per story in Phase 2; that's a verification step, not the language you narrate in.)

## Phase 2 — Per-story exhaustive QA loop (THE CORE)

Repeat this whole block for each story, **in order, one at a time — but without stopping between stories.** You QA a story fully, record its verdict and findings, and roll straight into the next. No per-story halt, no per-story "what do you want to do?" — all of that is consolidated into Phase 3 at the end. (Exception: a true **⛔ BLOCKER** that prevents QA-ing the remaining stories — surface it right away rather than charging on blind.)

### 2A — Understand the story
- Restate, in plain English, what the story does and who it's for. Pull from the report; read the code if the report is thin or you need the real contract (e.g. how an action builds a URL, how a permission is computed, what a query scopes by).
- List its acceptance criteria / expected behaviours **and** its known TODOs (from Phase 0). You'll judge findings against both.

### 2B — Exhaustive live QA

**QA like a HUMAN USER, not a computer (read before driving).** Reach every feature the way a real user would: start from the home/login page and **navigate through the actual UI** — click the nav menu, the buttons, the links — to get where you're going. Do NOT deep-link by typing a URL you happen to know into the address bar, and do NOT call the API directly to set up UI state, *unless that deep-link/endpoint is itself the behavior under test* (then verify both the human click-path AND the direct path). A computer "knows" the URL and jumps straight there; a human has to find the door — and that path is exactly where real-user bugs hide: a missing or broken nav entry, a button that doesn't wire up, a route guard that redirects, a link with the wrong href, a menu item hidden for the wrong role. If a feature can't be reached by clicking like a user, that's a finding in itself — even when the page renders fine on a direct URL visit.

Pick the right tool for the story type:
- **UI stories** → drive the real browser with a browser-automation tool (e.g. Playwright, including via an MCP server): navigate, type, click, snapshot. Walk the actual user journey end-to-end, reaching each screen through the UI as above (not by jumping to known URLs).
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

### 2C — Record the story's verdict + findings (no halt)
Don't stop and don't ask. Write this story's section into the **QA findings file** (Phase 0) and move on:
1. **Verdict** — one of: ✅ PASS · 🟡 PASS-with-notes · 🔴 FAIL · ⛔ BLOCKER.
2. **What the story does** — plain English, 2-4 lines.
3. **Tests I ran** — concrete steps and their results (a table works well: action → expected → observed → ✓/✗). Include personas, localization, endpoints fired, edge cases. This is the audit trail of coverage — keep it, but don't editorialize about what works well.
4. **Findings** — every bug / error / concern / improvement / doc inaccuracy / confirmed-TODO, each with: severity, evidence, root cause (if known), and a concrete suggested fix. Explicitly tag **real bugs** vs **documented TODOs / env-limitations** so by-design behaviour isn't mistaken for a defect. Findings are the point of the file — concerns, errors, risks, things that could go wrong; **no praise, no "looks great" notes.**

A short one-line progress note to the user is fine ("Story 3/8 done — 🟡 PASS-with-notes, 2 findings logged; moving to story 4"), but **do not present the full report or ask what to do** — that's Phase 3.

**Fix-as-you-go is encouraged for the trivial stuff.** If, while QA-ing, you spot a *small, obvious, low-risk* fix (a typo, a wrong label, an off-by-one, a missing null guard), just **make the fix in the working tree** rather than logging it as a finding to discuss later — that's the fastest path to "as few open issues as possible." Note it briefly in the findings file under the story as "fixed in-session." Anything bigger or riskier than that → log it as a finding and leave it for the Phase 3 decision; don't expand scope mid-loop.

### 2D — Continue to the next story automatically
Verdict and findings are recorded (2C). **Go straight to the next story.** No `AskUserQuestion`, no waiting. The only reasons to break the loop early are: a **⛔ BLOCKER** that stops you QA-ing what's left, or the user interjecting. Otherwise, keep going until every story has a verdict — then proceed to Phase 3.

## Phase 3 — End-of-run consolidation & decisions (the single gate)

This is the one interactive checkpoint. With every story QA'd and all findings in the file:

1. **Present the consolidated picture, not a story-by-story replay.** Give the user a compact roll-up: per-story verdicts (✅/🟡/🔴/⛔), and the findings grouped by severity/category — what's a real bug, what's a concern, what's a doc-inaccuracy, what's by-design. Flag the small fixes you already applied in-session (2C) so they know those are handled.

2. **Triage each open finding fix-first.** The goal is **the fewest possible open issues**. For each finding, the default is *fix it in this session*. Only escalate to "file an issue" when the fix is genuinely **too big** for the session (large refactor, cross-cutting design change, needs product decision, risky blast radius). Don't manufacture notes or issues for things you can just fix.

3. **MANDATORY dedup deep-dive before filing OR offering to file anything.** Before you propose filing a new issue — or even raise it to the user as a candidate — **deep-dive the code and the existing open issues** to confirm nothing already covers it. This has been gotten wrong repeatedly; do it properly every time:
   - Search the **codebase** for an existing implementation, TODO, partial handling, or guard that already addresses (or intentionally defers) the finding.
   - Search the **tracker's open (and recently-closed) issues** with several term variations — `gh issue list --search …` / `gh search issues` (or the repo's tracker) — not a single keyword. Read the candidates, don't just count them.
   - Only if both come up empty is the finding genuinely new. If something already covers it, **link to it instead of filing** — add a comment to the existing issue if you have material new detail; otherwise just reference its `#N` in the findings file. State, in your proposal to the user, what you searched and why you concluded it's new (or which existing `#N` covers it).

4. **Ask once what to do with the residue.** Use a single `AskUserQuestion` (multi-select across the remaining findings, or grouped) covering only the decisions that genuinely need the user: which "too big to fix now" items to file vs defer vs accept, and confirmation to apply the batch of in-session fixes. Don't ask about anything you've already trivially fixed.

## Phase 4 — Carry out the agreed actions

- **Fix in-session** (the default): find the real **root cause** (don't patch symptoms), keep the fix **narrowly scoped**, and match the surrounding code's conventions. After each fix:
  - Re-verify the fix **live** (and, for UI, with the DOM-level proof from 2B).
  - Run the **affected unit tests** to confirm nothing local broke.
  - If a fix turns out more invasive than expected (new dependency, shared component, test-infra/config change), **surface the trade-off** before committing to it; don't silently expand scope. (For example: introducing a UI component that depends on a context provider from a component library can require the test runner to dedupe/inline that package so a single context instance is used — that's a config change worth flagging.)
  - **Do not commit yet** — commits are gated by Phase 5.
- **File an issue** (only for genuinely too-big work, only after the Phase 3 dedup deep-dive): title + repro steps + expected/actual + scope/impact + suggested fix; apply sensible existing labels; **no assignee unless asked**. Use the project's issue tracker (e.g. GitHub via `gh issue create`, or whatever the repo uses). Confirm the issue URL back to the user, **and write the resulting `#N`/URL beside that finding in the QA findings file** so the document is self-contained. If the dedup turned up an existing issue, **link/comment on that one instead of opening a duplicate.**
- **Defer (real future work)**: must produce a **tracked artifact** — a filed `#N` (via the project's tracker) **or** an entry in a running ledger that itself carries a follow-up `#N`. A bare note is **not** sufficient — this is exactly the path that loses committed work. The same dedup deep-dive applies before creating the `#N`. **Record the `#N` against the finding in the QA findings file.**
- **Accept / non-work**: notes-only is allowed ONLY for genuine non-work — by-design 404s, role-scoped empty results, environment/seed limitations, or documented TODOs that **already** carry a `#N`. Record it as accepted (with the reason) in the QA findings file and move on.

## Phase 5 — Batch wrap-up: full suite + e2e BEFORE any commit

This phase runs once all stories are QA'd and all agreed fixes are applied. The user's hard requirement:

> If bugs were found and fixed, the **whole test suite (e2e included)** must run; only when everything is green and the user — with your help — agrees it all passed do we run the tests once more as the pre-commit gate, and *then* commit.

Steps:
1. **Run the WHOLE test suite** — every unit/integration suite the repo has (backend + frontend), not just the ones touched.
2. **Run the e2e suite** against the live stack (start/keep the stack up; honor any project-specific e2e/runbook quirks).
3. **If anything is red**: fix it (root cause, scoped), then **re-run the WHOLE suite + e2e again** — not just the failing test. Loop until fully green. Cap retries on a single stubborn failure and surface it rather than thrashing.
4. **Joint go/no-go**: present the green results and your assessment; the user decides "all passed."
5. **Pre-commit gate**: once the user agrees, run the tests **one more time** as the final gate immediately before committing. Only on green do you proceed.
6. **Commit** (only now): scoped staging (never `git add -A`), Conventional Commits, on the **batch branch**. One commit per logical fix or a tidy grouping. Use the repo's commit conventions (incl. any required `Co-Authored-By` trailer). **Push / open a PR only when the user explicitly asks.** Never commit or push to the default branch. **The `qa-findings.md` is never staged** — it lives under `~/Downloads/…`, outside the repo tree, by design.
7. **Finalize the QA findings file.** Fill in its `## Batch summary`: the per-story verdict roll-up (✅/🟡/🔴/⛔), the count of findings by category, what was fixed (with commit refs if committed), every filed/deferred `#N`, and the final test+e2e result. This happens at wrap-up **whether or not anything was committed**. Print the absolute path of the findings file to the user as the closing deliverable.

## Hard rules — what this skill never does

- Never halts the per-story loop to surface findings or ask what to do — record and continue; consolidate all decisions into Phase 3. (Only a true ⛔ BLOCKER that prevents QA-ing the rest, or the user interjecting, breaks the loop.)
- Never files a new issue — or even offers to file one — before a deep dive into the code AND the existing open (and recently-closed) issues confirms nothing already covers it. Link to the existing `#N` instead of duplicating. This dedup step is mandatory and has been gotten wrong repeatedly.
- Never files an issue or writes the user a note for something it can just fix in-session — the goal is the fewest possible open issues; small/obvious fixes are simply done.
- Never pads the findings file with positive annotations — it's a record of concerns/bugs/risks/doc-inaccuracies to act on, plus per-story verdicts and the tests run for audit. No praise.
- Never commits anything before the **full suite + e2e are green** AND the user has approved AND a final pre-commit test run passed.
- Never commits or pushes to the default branch; batch branch only; push/PR only on request.
- Never reports a browser-automation artifact (silent no-op / hit-test refusal) as a product bug without DOM-level proof (`pointer-events`, `elementFromPoint`, dispatched-event control).
- Never labels a documented TODO, by-design 404, role-scoped empty result, or absent-seed result as a bug — classify it correctly and say so.
- Never overstates a verdict: if a test was skipped or only partially verifiable in the environment, say exactly that.
- Never defers real future code work with only a note — it must carry a tracked `#N` (or a ledger entry that does). Notes-only is for genuine non-work.
- Never edits, updates, or re-syncs the input QA report — it's an ephemeral guide; its inaccuracies are findings, not edits.
- Never finishes a run without a finalized **`qa-findings.md`** that captures every story's verdict, the tests run, and every finding (with each filed/deferred `#N` written beside it) — it's a standing deliverable, not an optional per-finding action.
- Never writes the findings file into the committed repo tree or stages/commits it — it's a report output that lives under `~/Downloads/` (beside the input report).
- Never removes or prunes Docker images, even on a clean-slate reset — containers and volumes only.
- Never QAs like a computer when a human path exists: reach features by navigating the UI from the landing page, not by jumping to known URLs or pre-seeding state via the API (except to additionally test an intended deep-link/endpoint). An unreachable-by-clicking feature is a finding.

## Field notes & recurring pitfalls (from real runs)

- **Unit / headless-DOM tests can't see CSS or layout.** A green unit suite says nothing about real-browser rendering — a headless DOM (e.g. jsdom) ignores layout, stacking, overlays, and `pointer-events`, so a CSS bug that makes an element unclickable (or an overlay that swallows clicks) sails right through. Any interaction an AC depends on must be confirmed in a real browser, not inferred from passing tests. (One real instance: a CSS attribute-*presence* selector matched far more elements than intended and disabled pointer events on all of them — invisible to the headless DOM, broken in the real browser.)
- **Don't judge an async-triggering action by its first frame.** When a click kicks off a fetch (a deep-linked dialog, a lazy panel, a late-rendered list), "nothing happened" immediately afterwards is often just the load not having finished. Re-check after the data settles before concluding it failed.
- **Role scoping vs. bugs**: an empty result for a non-admin persona is often correct scoping (verify against the query/permission logic), and an empty list for a seeded-but-unassigned entity is a seed limitation — not a defect.
- **Doc claims drift from reality**: deep-link params, persistence storage keys, and "verified live" claims are frequently slightly wrong. Verify each; report the delta as a doc inaccuracy, not necessarily a product bug.
- **Stack readiness**: SPA port up ≠ ready. Wait for auth + DB + API health. On restart trouble, check orphaned containers / DB locks / migration drift before wiping volumes.
- **Test-env module/context mismatches**: adding a component that relies on a library's shared context (e.g. a dialog/title from a component library) can throw "must be used within X" in the test runner even though it works at runtime — because the runner resolves two module instances. Fix via the runner's dedupe/inline config, and flag it as a config change.

## Cleanup checklist (every run)

- [ ] The **`qa-findings.md`** is finalized (every story verdict + findings + filed/deferred `#N`s + batch summary) and its absolute path was reported to the user. It is a durable deliverable — do **not** delete it as scratch.
- [ ] Scratch artifacts (screenshots, temp files) are outside the committed tree or removed.
- [ ] No marker/scratch files staged.
- [ ] Stack left in the state the user expects (running if they want to keep testing; stopped if asked).
- [ ] Every story has a recorded verdict; deferred items are logged where the user chose. **Deferred items representing code work have a GitHub `#N`** — an MD/HTML note alone does not satisfy this. Genuine non-work (by-design 404s, role-scoped empties, env/seed limits, already-`#N`'d TODOs) may be notes-only.
- [ ] Findings were resolved fix-first: small/obvious ones were fixed in-session (not filed); issues were filed only for genuinely too-big work. **Every newly filed/deferred `#N` was dedup-checked against the code AND existing open issues first** — no duplicates of work already tracked or already implemented.
- [ ] Nothing committed unless the full suite + e2e were green and the user approved.
