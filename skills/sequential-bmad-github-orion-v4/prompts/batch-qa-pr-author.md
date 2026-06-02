The test-and-fix sub-agent has finished Gates 1+2+3; you take over.

Your scope: render `<session-folder>/qa-report.html`, open the Draft PR (batch → base branch `<base-branch>`), and resolve any merge conflict (one autonomous attempt; pause for the user if it fails). You do NOT touch batch code. `<base-branch>` is the branch the batch was forked from (`main` in the classic case; a feature/integration branch when the run was started off-main) — it is given in the boilerplate context above; use it everywhere this prompt says "base branch", and never assume `main`.

═══════════════════════════════════════════════════════════════════════
HANDOFF FROM test-and-fix (read this FIRST)
═══════════════════════════════════════════════════════════════════════

The orchestrator injected the verbatim handoff block below. It contains test/QA results and bug-fix SHAs you need for the report and the PR body.

<handoff-block>

If `batch-qa-gates-status: failed — <reason>`, skip the conflict-resolution step and open the Draft PR with a top-of-body `❌ DO NOT MERGE — automated batch QA failed` callout (template at the end of this prompt). Otherwise proceed normally.

═══════════════════════════════════════════════════════════════════════
PRE-EXISTING FAILED ISSUES FROM PHASE 1 (skipped + reverted off batch)
═══════════════════════════════════════════════════════════════════════

The orchestrator's Phase 1 per-issue loop paused and the user chose to skip these issues. They are NOT on the batch branch — they were reverted off — but they ARE part of this run's reporting surface. You MUST cover them in qa-report.html's "Failed issues" slide and in the Draft PR body's top callout.

Failed issues to surface:

<failed-issues-list>

For each failed issue:
  • Read the diagnosis at `<session-folder>/failures/<N>-<slug>/diagnosis.md`.
  • Read `last-state.diff` to understand what work was lost on revert.
  • Skim the agent transcripts in `<session-folder>/failures/<N>-<slug>/agent-transcripts/`.
  • Surface the full diagnosis (verbatim) in the QA report's "Failed issues" slide.
  • Surface a one-line summary + link to the failure folder in the Draft PR body's top "⚠️ Failed issues" callout.

═══════════════════════════════════════════════════════════════════════
CARRY-FORWARD FRAMEWORK GAPS (DO NOT FIX — known limitations)
═══════════════════════════════════════════════════════════════════════

Carry-forwards are KNOWN LIMITATIONS that no single batched story can fix. The orchestrator aggregated them across the merged stories — per-story carry-forwards (story-local) AND framework gaps (same gap reported by ≥2 stories — the strong signal it's not story-local).

Full list:

<carry-forward-flags-block>

Required actions for the qa-report.html:

  1. **Add a Cover-slide DO-NOT-FIX callout** if total > 0: `🚧 <count> carry-forward framework gaps documented — known limitations that no batched story can fix. The downstream QA agent must NOT report them as bugs against any batched story. Per-gap details in the per-story dossiers (slide 3) and in run.jsonl (key: carry-forward-summary).` Skip if total == 0.
  2. **Per merged story with ≥1 carry-forward affecting it**, add a "Known limitations (carry-forward gaps)" section to that story's dossier (slide 3, Part 2) BEFORE the cross-story spot-checks. Format: bullet list of `\`<gap text>\` — owning framework: <ref>`. Above the list: *"These are KNOWN limitations the QA agent must verify documented behavior against (e.g. 'feature works in API but UI can't trigger it') but MUST NOT report as bugs against this story — they are framework-level gaps owned by separate follow-up issues."*
  3. **For framework gaps (reported by ≥2 stories)**, add ONE consolidated entry to the Cover callout listing the gap + the issues affected so the QA agent sees the cross-story pattern at the top of the report.

═══════════════════════════════════════════════════════════════════════
TODO/FIXME/HACK MARKERS INTRODUCED BY THIS BATCH
═══════════════════════════════════════════════════════════════════════

TODOs are ALLOWED under Core Principle #1 (production-ready code) — intentional, documented debt. But they MUST be loudly surfaced so the downstream QA agent + the human reviewer don't miss them.

Full list (per issue):

<new-todos-by-issue-block>

Required actions for qa-report.html:

  1. Add a Cover-slide callout if total markers > 0: `<count> TODO/FIXME/HACK markers introduced by this batch (<count-of-issues-with-markers> of <Z> stories). Reviewer + QA agent should triage which to keep, which to file follow-up issues for. Full list in the per-story dossiers (slide 3).` Skip if total == 0.
  2. Per merged story with ≥1 marker, add a "TODOs introduced" section to that story's dossier (slide 3, Part 2) at the END (after Cross-story spot-checks). Format: bullet list of `\`<file>:<line>\` — \`<MARKER>: <text>\``. Include the same one-line preamble from the PR body: *"These markers were introduced by this story and are intentionally allowed under the production-ready bar — they survive the pipeline and are surfaced here so the reviewer + downstream QA agent can decide which to keep, which to file follow-up issues for, and which to address before merge."* Skip the section on stories with zero markers.
  3. Do NOT auto-remove, "resolve," or downgrade any marker. They are intentional.

══════════════════════════════════════════════════════════════════════
DEFERRAL FILING — file & link every deferral BEFORE you write the report or open the PR (Core Principle #9)
══════════════════════════════════════════════════════════════════════

This is the step that closes the scope leak: the pipeline already DETECTED deferred work; your job is to make sure each piece is TRACKED by a GitHub `#N` and that the `#N` is written back into the PR bodies that mentioned it. Do this FIRST — before qa-report.html and before the Draft PR — so both can reference the tracking issues.

You do NOT touch batch code in this step. You only run `gh issue list` / `gh issue create` / `gh issue edit` / `gh pr edit` and `gh pr view`. (No `git stash`, no branch switching, no commits — same multi-agent safety rules as the rest of your slot.)

The orchestrator injected the deduped, whole-batch deferral map below. Each distinct item lists the issues that observed it and their per-issue PR numbers:

<deferral-filing-block>

If the block is `(no baseline-failure or carry-forward annotations to file this batch)`, skip straight to the QA report — but still apply the **hard rule** below to anything you write.

**For each distinct `baseline-failure` (keyed by test_file):**
  1. **Find-or-REUSE first (never duplicate per run).** Search open issues for the test path before creating anything:
     `gh issue list --state open --search "<test_file basename or path>" --json number,title,labels`
     Also check for an existing `baseline-failure`-labelled umbrella that already names the file. If a matching issue exists, REUSE its number — do NOT open a new one.
  2. **Only if none exists, create one umbrella issue:**
     `gh issue create --title "Baseline test failures: <test_file>" --label baseline-failure --label recovered-scope --body "<body>"`
     Body: which test(s) fail, that they pre-date this batch (not a regression introduced here), the batch + per-issue PRs that observed them, and that they were deferred out of each story's scope. Create the labels if the repo lacks them (`gh label create baseline-failure --color BFD4F2 2>/dev/null; gh label create recovered-scope --color D4C5F9 2>/dev/null` — tolerate "already exists").
  3. Record `{ kind: baseline-failure, key: <test_file>, issue: #<N>, action: created|reused, linked_prs: [...] }` for your return.

**For each distinct `carry-forward` (keyed by normalized gap):**
  1. **Find-or-REUSE first:** `gh issue list --state open --search "<distinctive words from the gap>" --json number,title,labels` — reuse a matching open tracking issue if one exists.
  2. **Only if none exists, create one tracking issue:**
     `gh issue create --title "Carry-forward: <short gap>" --label recovered-scope --body "<gap text, owning_framework, the stories it affects, why no single batched story can close it>"`. For framework gaps (`is_framework_gap: true`), say so in the body and list every affected issue.
  3. Record `{ kind: carry-forward, key: <gap>, issue: #<N>, action: created|reused, linked_prs: [...] }`.

**Write the `#N` back into every per-issue PR that observed the item (`observed_by` list):**
  For each per-issue PR `#<pr>` in the item's `observed_by`:
  - `gh pr view <pr> --json body` to read the current body.
  - Ensure the body has a `## Out of scope / Follow-ups (tracked)` section. Under it, one bullet per deferral that PR observed: `` - `<test_file or gap>` — tracked in #<N> ``. If the PR body already has a "Pre-existing baseline failures (out of scope)" section (Agent D wrote it), append the `— tracked in #<N>` reference to each matching line there too (don't delete Agent D's prose; just link it).
  - `gh pr edit <pr> --body "<updated body>"`. These PRs are already merged into the batch — editing a merged PR's body is fine and is exactly the point.

**HARD RULE (applies to everything you emit from here on — per-issue PR bodies, the batch PR body, and qa-report.html):** never write an "out of scope" / "pre-existing baseline failures" / "follow-up" / "deferred" line for real future work without a trailing GitHub `#N`. If you're about to write such a line and don't have a `#N`, file-or-reuse one first (same logic as above), then write the line with the `#N`. A bare prose deferral with no `#N` is the exact defect this skill exists to prevent — treat emitting one as a contract violation.

Log nothing yourself (the orchestrator owns run.jsonl) — but surface what you filed in your return's `deferrals-filed` block (schema in the Return summary section). If you hit something surprising (e.g. an ambiguous existing issue you weren't sure whether to reuse), append a lessons-learned finding.

══════════════════════════════════════════════════════════════════════
QA HTML report — a NEUTRAL, EXHAUSTIVE test plan (4 slides)
══════════════════════════════════════════════════════════════════════

Write `<session-folder>/qa-report.html` as the canonical batch-QA artifact. Two consumers:

  • **Humans** — navigate the slides as a tester would (browser-only walkthrough).
  • **Downstream QA agents** (typically `/guided-qa-orion`) — read the prose directly. No separate machine manifest; the per-story sections use consistent headings + stable IDs so the agent can navigate via DOM/fragment URLs.

**THE REPORT IS A TEST PLAN FOR AN INDEPENDENT QA AGENT — NOT A STATUS OR SIGN-OFF.** This is the single most important rule for this artifact. The downstream consumer does a full, adversarial round of QA; your job is to hand it a complete, *neutral* work-order, not to reassure anyone that the batch is good. Concretely:

  • **State claims as things to VERIFY, never as facts already proven.** Write "Verify that the invite email is sent" / "Expected: a 403 is returned", NOT "the invite email is sent" / "returns 403 correctly" / "works as intended" / "this is handled". Every per-story step is a hypothesis the QA agent must independently confirm against the live app — phrase it that way.
  • **Do not editorialize or congratulate.** No "successfully", "robust", "cleanly handles", "as expected", "looks good", "all working". Those words bias the reader into skipping the check. Strip them.
  • **Automated gates passing ≠ the feature is correct.** The Phase-2 gates (tests/e2e/live-QA) are reported ONCE, factually, on the cover — they do NOT pre-certify anything in the per-story plan. A test passing means a test passed, not that the user-facing behavior is right. Assume nothing below the cover is proven until the QA agent confirms it.
  • **Surface uncertainty loudly.** Where something is a judgment call, thinly covered, environmentally substituted, or backend-only (no UI proof), SAY SO in that story's "Risks" and "What automation did NOT cover" sections (below). Hiding a gap is worse than an ugly report.

**Core rule:** the report's center of gravity is **exhaustive, neutral per-story QA steps + tests that visit every corner**. Everything else is minimal scaffolding. Do NOT pad with executive summaries, per-story endpoint tables, JSON manifests, persona matrices, etc. — only the four slides below. "Exhaustive" means: every AC, every interactive element on each touched screen, every role, every locale, plus the edge / negative / error / empty / persistence angles in Part 2 — don't drop an angle because it "probably works" (that is exactly the bias this report exists to counter).

**Stable IDs are mandatory** — every story section gets `id="story-<N>"` so the downstream agent can deep-link to a specific story. Within a story, use natural sub-headings (`<h3>` / `<h4>`); no rigid subsection schema, but use these heading words consistently when relevant: `Intro`, `Acceptance criteria`, `Click-paths`, `Edge cases`, `Negative tests`, `Error & failure states`, `Empty / loading states`, `Persistence & state`, `Persona / role variants`, `i18n / locale checks`, `Cross-story spot-checks`, `Risks — most likely to be broken`, `What automation did NOT cover`, `Known limitations (carry-forward gaps)`, `TODOs introduced`. Skip any heading whose section is empty for the story.

Required slides (one `<section class="slide">` each with `page-break-before: always`):

  ### Slide 1 — **Cover**
  - Batch branch name, batched issues with titles, gh-login, today's date.
  - Counts: total queued / merged / failed.
  - **Gate-results line (factual, one line):** the automated Phase-2 results from the handoff — full tests `<pass>/<total>`, e2e `<pass>/<total>`, live-stack QA `<bugs-found-and-fixed>`, environmental escape `<yes/no>`. Report the numbers, nothing more.
  - **Neutrality disclaimer (always render, directly under the gate-results line):** *"Automated gates green ≠ QA complete. This document is the INPUT to an independent QA pass, not a sign-off. Every per-story step below is something to verify against the live app — treat nothing as proven until you confirm it. Be adversarial: the gates already caught what they can; your job is to find what they can't."*
  - Status pill (read from the handoff block + failure-kind annotations) — note these describe the *automated gate* outcome, not a QA verdict, and the pill label says so:
    • `AUTOMATED GATES GREEN — QA NOT YET DONE (awaiting independent QA + merge)` (green) — when `batch-qa-gates-status: green` AND no failure-kind annotations
    • `AUTOMATED GATES GREEN, WITH <K> SKIPPED ISSUES — QA NOT YET DONE (see slide 4)` (yellow) — when green but failures occurred
    • `❌ AUTOMATED GATES FAILED — DO NOT MERGE` (red) — when `batch-qa-gates-status: failed` (any reason)
  - **DO NOT CHASE callout** (one-line each, only if non-empty):
    • Pre-existing baseline failures: `<count> test files were already failing on the batch baseline BEFORE this batch ran. They are NOT regressions and the QA agent must NOT chase them. Full list in run.jsonl (key: baseline-failure-summary).`
    • Carry-forward framework gaps: `<count> known framework-level gaps no single story can fix. The QA agent must NOT report them as bugs against any batched story. Full list in run.jsonl (key: carry-forward-summary).`
  - **TODOs to triage callout** (one-line, only if total markers > 0): `📝 <count> TODO/FIXME/HACK markers introduced by this batch (<count-of-issues-with-markers> of <Z> stories). Per Core Principle #1, markers are allowed but loudly surfaced — the reviewer + QA agent should triage which to keep, which to file follow-up issues for, and which to address before merge. Full list in the per-story dossiers (slide 3), per-issue PR bodies, and run.jsonl (key: new-todos-summary).`
  - **What automation did NOT cover callout** (render whenever `coverage-caveats` from the handoff is not `none`, OR the environmental escape was used): `🔍 The automated gates did NOT exercise everything. Focus manual QA here: <the coverage-caveats list, one item each>.` This is not a warning to hide — it's a map of where the QA agent's attention is worth the most. If `coverage-caveats: none` and no escape was used, render one neutral line instead: `The gates exercised the batch end-to-end; manual QA is independent confirmation, not gap-filling.`

  ### Slide 2 — **How to start the stack**
  Auto-detected from project files (CLAUDE.md / README dev-startup section, `package.json` scripts, `*.AppHost` projects, `docker-compose.yml`). Include:
  - The exact command(s) to run.
  - What to wait for in the output (e.g. `wait until you see "Now listening on: http://localhost:5173/"`).
  - URLs to open in the browser (app, admin/dashboard, API base).
  - Default credentials per persona/role (e.g. `<role-1>`: user/pw; `<role-2>`: user/pw — replace with the actual roles documented in the project's README/CLAUDE.md).

  Without this slide the QA agent cannot drive the live app. Keep it concise but complete.

  ### Slide 3 — **Per-story QA dossiers** (THE CORE SLIDE — bulk of the report lives here)
  One `<article class="story" id="story-<N>" data-issue="<N>">` per merged story. Each story has TWO required parts:

    #### Part 1 — **Intro** (short, neutral)
    A 2-4 sentence plain-English summary aimed at the QA agent: what changed for the user and what the developer touched. No jargon. Describe the change *factually* — do NOT assert it works or is correct (that's what the QA agent is here to determine). Aim for "the QA agent reads this and knows what they're about to test in under 30 seconds."

    #### Part 2 — **Exhaustive QA steps + tests**
    This is the bulk. The QA agent uses this to drive the live app and independently confirm — or refute — every claim in the issue. Cover EVERY relevant angle for the story; only include angles that actually apply, but do NOT drop an angle just because you believe it works. Every step is phrased as a verification (ACTION → EXPECTED OUTCOME), never as an assertion that the outcome already holds. Use what's relevant, skip what genuinely doesn't apply, do NOT pad with empty headings.

    Required when present in the story:
    - **Acceptance criteria.** One numbered step per AC, each ending in a verification — ACTION (verb in **bold**) + EXPECTED OUTCOME. Every AC from the issue body MUST appear (even ones the implementer deferred — mark `(deferred: <pointer to follow-up>)`). For backend-only ACs, replace the click-path with a one-line "verified via test `<test-name>`" pointer.
    - **Click-paths.** Browser-driven steps with explicit visual outcomes. 5-20 steps per UI surface. No xUnit filters or curl commands inline. **Write them as a HUMAN USER would navigate, not as a computer:** start from the home/login page and reach the feature by clicking through the real UI (nav menu → button → link), NOT by telling the tester to type a known URL into the address bar (deep-linking is a computer shortcut; a real user has to find the door, and that path surfaces broken nav, dead buttons, wrong hrefs, and role-gating bugs). Only instruct a direct-URL visit when the deep-link itself is the behavior under test — and then also include the click-through path.
    - **Edge cases to exercise.** Bullets pulled from the BMAD story file's edge-case section + the dev-handoff comment's decisions/assumptions. Each bullet: the case + the steps the QA agent should run to exercise it + expected behavior. Cover boundary values (empty, max-length, very large, zero, negative), state transitions (pending → running → completed → cancelled), permission boundaries (own data vs. another tenant's), and "what happens when a sibling feature is in state X" interactions.
    - **Negative tests (what should NOT happen).** Bullets explicitly listing prohibited behaviors the QA agent should ATTEMPT and confirm don't occur. E.g. "A lower-privilege role should NOT be able to delete another user's entity — try via the UI (the button should be hidden) AND via direct API call (expected: 403 Forbidden)." This is the most-skipped category in junior testing and the most-valuable to formalize.
    - **Error & failure states.** What the user should see when things go wrong — and how to provoke each. Bullets: invalid/malformed input (validation message, not a crash); a required field left blank; a server error (5xx) or failed request (kill the backend / go offline in DevTools → expected: a graceful error, not a white screen or infinite spinner); a permission/auth failure mid-flow; a concurrent edit / stale-data conflict where relevant. Each bullet: how to trigger it + what the user should see. A feature that only has a happy path documented is under-tested — make the QA agent drive it off the rails on purpose.
    - **Empty / loading / boundary states.** First-run with no data (empty list / zero-state copy, not a broken layout); a slow load (does a spinner/skeleton appear, then resolve?); pagination boundaries (first page, last page, exactly one page, more-than-one page); very large inputs or long strings (no overflow/truncation bug). Skip only if the story has genuinely none of these surfaces.
    - **Persistence & state across navigation.** Where the story creates or changes state: reload the page (does the change survive?); navigate away and back; use the browser Back/Forward buttons; if relevant, sign out and back in or let the session expire. Expected behavior for each. This catches "it looked right until I refreshed" bugs that click-path-only testing misses.
    - **Persona / role variants.** When the story behaves differently for Admin vs other roles vs anonymous, repeat the relevant click-path FOR EACH role with explicit sign-in steps and expected differences. If single-persona, omit.
    - **i18n / locale checks.** If the story touches UI strings: per supported locale, a one-line toggle instruction (e.g. `localStorage.setItem('<locale-key>', '<lang>'); location.reload();` — use the project's actual locale-switch mechanism) + 2-3 specific strings the QA agent should see in that locale + flag instructions ("if you see `{namespace.key}` or `[MISSING]` raw text, that's a fail"). Skip if backend-only.
    - **Cross-story spot-checks.** Bullets naming OTHER stories in this batch that share a UI surface, endpoint family, DB table, or signal hub with this one — plus a suggested smoke test to confirm no regression at the seam. Skip if the story has no overlap with other batched stories.
    - **Risks — most likely to be broken (always include; this is where the QA agent should be most skeptical).** A short, honest bullet list of the parts of THIS story you'd bet are weakest, and why — so the QA agent spends its skepticism well. Draw from: judgment calls / assumptions in the 🤝 Dev → Review handoff, code-review findings that were fixed under time pressure, complex or branchy logic, areas with thin automated coverage, anything touched late or by a fixup commit, and any TODO/FIXME left in this story. Each bullet: the risky area + why it's risky + the specific thing to probe. If you genuinely can't name a risk, write *"No specific high-risk area identified — exercise the ACs and edge cases above with normal skepticism"* rather than omitting the section (its presence reminds the QA agent to look).
    - **What automation did NOT cover (always include).** State plainly which of this story's behaviors were NOT proven by the Phase-2 gates, so the QA agent knows where manual effort actually matters. Sources: backend-only ACs verified only by unit tests (UI/integration unproven); anything covered only via the environmental escape hatch (`environmental-escape-used: yes` in the handoff, or the run-level `coverage-caveats`); UI states the e2e suite doesn't touch (error/empty/persistence angles above are usually here); cross-browser / accessibility / visual correctness (gates rarely assert these). If the gates genuinely covered everything for this story, write *"The automated gates exercised this story's ACs end-to-end; manual QA is confirmation, not gap-filling."* — but say it explicitly, don't leave it blank.
    - **Known limitations (carry-forward gaps)** (only if any carry-forward entry affects this story). Bullet list of `\`<gap text>\` — owning framework: <ref>`. Above the list, the preamble from the Carry-forwards section above.
    - **TODOs introduced** (only if this story added ≥1 marker). Bullet list of `\`<file>:<line>\` — \`<MARKER>: <text>\``. Above the list, the preamble from the TODOs section above.

    **Backend-only story shortcut:** if the story has no user-visible behavior, replace the entire click-path/edge-case/persona/i18n sections with: *"Backend-only story. Verification is via the tests listed below. The QA agent should NOT attempt UI verification."* Then list the relevant test names + how to invoke each. The AC matrix is still required, with `verified via test <name>` in each row.

    **End-of-story footer (always):** one line each with: per-issue PR URL · squash SHA on batch · link to the GitHub issue (so the agent can read dev-handoff / review notes / code-review summary directly via `gh issue view <N>`).

  ### Slide 4 — **Failed issues — manual intervention required** (mandatory when there are failure-kind annotations)
  Table per failed issue: issue #, slug, failed slot, one-line diagnosis (from `diagnosis.md`), failure-folder path (`<session-folder>/failures/<N>-<slug>/`), story branch on origin (`feature/<N>-<slug>`), per-issue PR URL (closed). Above the table: short paragraph explaining what to do — these issues paused the pipeline; the user chose to skip them and their contributions were reverted off the batch branch; story branches retained on origin; resume manually by checking out the branch, fixing per `diagnosis.md`, opening a fresh PR against the base branch `<base-branch>`. If no failures: OMIT this slide entirely — don't render an empty slide.

**Style:** dark GitHub-style theme (`#0d1117` bg, `#c9d1d9` text). No external assets, no JS frameworks. The HTML must be self-contained.

**HTML structural conventions** (so downstream agents can parse without fuzzy matching):
  • Each slide: `<section class="slide" id="slide-<N>-<slug>" data-slide="<N>">`
  • Each story: `<article class="story" id="story-<N>" data-issue="<N>">`
  • Headings within a story: `<h3>` for top-level. Optional `<h4>` for sub-groupings.
  • Numbered steps: `<ol>` with each `<li>` containing `<strong>ACTION VERB</strong>` followed by ` → ` and the expected outcome.
  • Tables: `<table class="qa-table">` with `<thead>` + `<tbody>`, no nested tables, no merged cells.

**After writing:** verify file exists and size > 5 KiB. Post 📦 Batch status — "QA report written (N stories): qa-report.html" on the first batched issue with the absolute path.

══════════════════════════════════════════════════════════════════════
Open Draft PR (batch → base branch `<base-branch>`)
══════════════════════════════════════════════════════════════════════

Only after Gates 1+2+3 succeeded (per the handoff block) AND qa-report.html is written:

  gh pr create --base <base-branch> --head <batch-branch> --draft \
    --title "[batch] <gh-login> — <count> issues (#<N1>, #<N2>, #<N3>, ...) — <date>" \
    --body "<batch PR body, see below>"

Title format notes:
  • `<count>` = number of batched issues.
  • The parenthesized list is EVERY batched issue number, comma-separated with a `#` prefix on each (GitHub auto-links them in the PR list view).
  • `<date>` = today's date as `YYYY-MM-DD`.

Batch PR body template:
```
<IF there are failure-kind annotations, insert this callout at the very top BEFORE "## Batch summary" — do NOT omit it; visibility is the point:>
## ⚠️ Failed issues — manual intervention required

The autonomous pipeline paused on these issues; the user chose to skip them, and their contributions were reverted off the batch branch. They are NOT included in this PR; their story branches remain on origin for manual investigation.

| Issue | Failed slot | Diagnosis (one-line) | Full diagnosis | Story branch |
|---|---|---|---|---|
| #<N> | <slot> | <one-line from diagnosis.md> | `<session-folder>/failures/<N>-<slug>/diagnosis.md` | `feature/<N>-<slug>` |
| ... | ... | ... | ... | ... |

To resume one manually: check out its `feature/<N>-<slug>` branch in a fresh worktree, fix the issue per the diagnosis, push, open a NEW PR against the base branch `<base-branch>` (NOT this batch branch — this batch closes once merged).

See the QA report's "Failed issues" slide for the full transcripts + last-state diff per failure.

---

</IF>
## Batch summary
This Draft PR integrates <count-of-MERGED> issues merged sequentially via /sequential-bmad-github-orion-v4.

**Issues shipped (merged into batch + QA-passed):** #<N1>, #<N2>, …, #<Nm>
<IF there are failure-kind annotations:>
**Issues attempted but failed (see top callout):** #<F1>, #<F2>, …, #<Fk>
</IF>

**Per-issue PRs (merged into this branch):**
- #<pr1> — <title1> (#<N1>)
- #<pr2> — <title2> (#<N2>)

## Pre-merge gates
- [x] Per-issue BMAD code review + build + tests (per-issue PRs)
- [x] Full test suite (batch)
- [x] Full e2e suite (batch)
- [x] Live-stack Junior-tester QA gate (batch)
- [ ] Human QA (manual — replay `<session-folder>/qa-report.html`)
- [ ] Manual merge into the base branch (`<base-branch>`)

## Artifacts
- QA report: `<session-folder>/qa-report.html`
- Run log: `<session-folder>/run.jsonl`
- Session folder: `<session-folder>`
<IF there are failure-kind annotations:>
- Failed-issue diagnoses: `<session-folder>/failures/`
</IF>

## Out of scope / Follow-ups (tracked)
<List EVERY deferral you filed-or-reused in the DEFERRAL FILING step, each with its tracking `#N`. One bullet per distinct item: `` - `<test_file or gap>` — tracked in #<N> (baseline-failure | carry-forward; created|reused) `` . If there were none, write exactly `None — no work was deferred out of this batch.` NEVER list a deferred item here without its `#N` (the hard rule). This section is the batch-level mirror of the `## Out of scope / Follow-ups (tracked)` sections you wrote into the per-issue PR bodies.>

## Closes
Issues are NOT auto-closed by this PR. They close automatically when the orchestrator detects the merge in Phase 4 (failed issues remain OPEN and unchanged).
```

══════════════════════════════════════════════════════════════════════
Merge-conflict handling — one autonomous attempt, then pause
══════════════════════════════════════════════════════════════════════

If GitHub reports the PR as not-mergeable, or `git merge-tree origin/<base-branch> origin/<batch-branch>` shows conflicts, attempt ONE autonomous resolution. On failure, hand control to the user via the same pause-and-converse pattern the orchestrator uses for per-issue failures — do NOT cascade through automatic revert-and-retry.

  1. Rebase: `git fetch origin <base-branch> && git rebase origin/<base-branch>` inside the batch worktree.
  2. For each conflicting file, BEFORE editing, read the dev/review notes that touch that file:
     `gh issue view <N> --json comments --jq '.comments[].body' | grep -F '<filename>'`
     for every batched issue that touched the file (use `git log --oneline origin/<base-branch>..HEAD -- <filename>` to identify which). Identify the set of batched issues `<contaminating-issues>` whose commits cover the conflicting hunks.
  3. **Autonomous additive resolution.** Attempt if these signals hold:
       a. **Scope** — at most ~3 conflicting files.
       b. **Recipe articulable** — you can write a clear plain-English additive-merge recipe describing which lines from `<their version>` (the base branch) and which from `<our version>` (batch) coexist, in what order. The common safe case is purely additive: keep BOTH sides' added imports and union/enum members (e.g. router entries, type-union members) — neither side deletes the other's, so the union compiles.
       c. **Dev-notes signal** — the relevant 🤝 Dev → Review handoff notes show the contributions are SEMANTICALLY COMPLEMENTARY (both additive feature paths that can coexist) rather than contradictory.
       d. **Targeted test exists** — a per-feature test file you can run after the merge to detect misjoin.
     If all four signals hold: write the recipe into the PR body BEFORE applying. Apply. Run targeted tests; then run the FULL suite. If BOTH green: log `additive-rebase-applied`, post 📦 Batch status on every batched issue with the recipe link, `git add <files>`, `GIT_EDITOR=true git rebase --continue` (the `GIT_EDITOR=true` auto-accepts the default commit message without opening an editor — note `--no-edit` does NOT exist for `git rebase`, only for `git commit`), force-push with `--force-with-lease`. SUCCESS — proceed to return.
     If targeted or full tests go red after the recipe is applied: abort (`git checkout -- <conflicting-files>`, restore conflict markers), and fall through to step 4.
  4. **Autonomous resolution not applicable OR failed.** Pause and hand control to the user: write the conflict diagnosis to `<session-folder>/conflict-diagnosis-<timestamp>.md` (list of conflicting files, contaminating-issues set, what was tried, what failed), print to chat with the path, then return `agent-status: incomplete — merge conflict requires user direction: <one-line summary>`. The orchestrator will surface the pause to the user.

══════════════════════════════════════════════════════════════════════
Return summary (final batch-QA verdict)
══════════════════════════════════════════════════════════════════════

Return with the literal line `batch-qa-status: green` (passed) or `batch-qa-status: failed — <reason>`, plus the standard agent-status line.

Fields:
  • agent-status: done | incomplete — <reason>
  • batch-qa-status: green | failed — <reason>
  • Draft PR number + URL
  • QA report path: <abs-path>
  • Conflict resolution: none | resolved (list files) | unresolvable (list files)
  • Pass-through from test-and-fix's handoff (verbatim): full test pass/total, full e2e pass/total, live-stack QA bug count + fix SHAs, environmental escape used?, coverage-caveats (rendered into the cover's gate-results line + each story's "What automation did NOT cover")
  • **`deferrals-filed`** — a fenced block, one line per distinct deferral you filed-or-reused in the DEFERRAL FILING step (the orchestrator parses this into `filed_deferrals[]` for the Phase 4 scope ledger):
    ```deferrals-filed
    <kind> | <key> | issue: #<N> | action: created|reused | linked-prs: #<pr1>,#<pr2>
    ...
    ```
    If nothing was filed, emit the block with a single line `none`. If `<deferral-filing-block>` was non-empty, this block MUST account for every distinct item in it — a green return that silently drops a deferral is a contract violation.

Final line of your reply must be `agent-status: done` or `agent-status: incomplete — <reason>`.

══════════════════════════════════════════════════════════════════════
DO-NOT-MERGE PR body template (only when handoff is failed)
══════════════════════════════════════════════════════════════════════

When the handoff reports `batch-qa-gates-status: failed`, the orchestrator still wants a Draft PR so the human can see the partial state. Skip conflict resolution; open the Draft PR with `--base <base-branch> --head <batch-branch>` (same batch→base-branch target as the normal case) with the title `[batch] <gh-login> — ❌ QA FAILED — <count-merged> issues (#<...>) — <date>` and prepend this block to the PR body (above the failed-issues callout and the batch summary):

```
# ❌ DO NOT MERGE — automated batch QA failed

The Phase 2 batch-QA gates could not certify this batch as production-ready. The autonomous pipeline opened this Draft PR anyway so the failure state is visible to a human reviewer.

**Failure reason:** <reason from batch-qa-gates-status>
**Full QA report:** `<session-folder>/qa-report.html` (read this FIRST)
**Session folder:** `<session-folder>`

Do NOT merge until the failure is resolved manually. Likely paths:
  - Investigate the failure reason; fix in the batch branch; re-run gates manually.
  - OR close this PR and resume the failed work via per-issue manual flow.
```

Then return `batch-qa-status: failed — <reason>` per the schema above.
