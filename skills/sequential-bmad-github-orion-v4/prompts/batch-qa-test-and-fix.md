Your scope: run Gates 1+2+3 against the integrated batch, fix any bugs found, and re-verify. You do NOT write the qa-report.html, open the Draft PR, or resolve merge conflicts — those belong to the downstream pr-author sub-agent. You hand off via the structured ```handoff block in your return summary.

═══════════════════════════════════════════════════════════════════════
SCOPE EXCLUSIONS — DO NOT QA OR FIX
═══════════════════════════════════════════════════════════════════════

**Failed issues from Phase 1** (skipped + reverted off batch, surfaced by pr-author later — you ignore them at gate time):

<failed-issues-list>

**Carry-forward framework gaps** — KNOWN LIMITATIONS that no batched story can fix (e.g. router entries missing for a feature, shared utility unwired). Do NOT attempt to fix them. If a gate failure traces back to a documented carry-forward, treat it as expected behavior, not a regression. Full list:

<carry-forward-flags-block>

**TODO/FIXME/HACK markers introduced by this batch** — allowed under Core Principle #1, surfaced for triage by the human reviewer. You do NOT remove, "resolve," or downgrade them. If you encounter one while debugging a Gate failure, leave it alone. Full list passed through for the pr-author handoff:

<new-todos-by-issue-block>

───────────────────────────────────────────────────────────────────────
EVERYTHING ELSE: FIX-IN-PLACE-FIRST (Core Principle #10)
───────────────────────────────────────────────────────────────────────

The three blocks above are HARD exclusions — leave them alone. **Every other bug or gap you find during the gates is subject to the fix-in-place-first gate: deferring is the fallback, not the default.** Before you route any finding to the pr-author as "out of scope / follow-up," run the cheap-and-safe test: is it **small · local · covered by the gates you're already running · low blast-radius (no schema/migration, no shared-contract or public-API change, no new dependency) · scope-neutral**? If it PASSES, fix it here and re-verify — even if it wasn't anyone's story AC. If it FAILS (large, cross-cutting, touches a shared contract/schema, needs a product/design decision, or belongs to a different slice), hand it to the pr-author as a deferral and name the single failing criterion so it becomes a tracked `#N`. When genuinely unsure about blast-radius, defer.

═══════════════════════════════════════════════════════════════════════
PRIORITY: PRE-EXISTING BASELINE FAILURES REPEATED ACROSS THE QUEUE
═══════════════════════════════════════════════════════════════════════

Every Agent D in Phase 1 ran a baseline-vs-regression check before classifying a failing test as a regression. The orchestrator aggregated the "Pre-existing baseline failures observed" lists across all batched issues. The following test files were reported by MULTIPLE issues (≥2), indicating a shared root cause that is NOT story-local — almost certainly a single underlying bug in shared infrastructure (test setup, mock layer, library upgrade, etc.):

<priority-baseline-list>

Treat investigating and fixing these failures as Gate 1's TOP PRIORITY. A single root-cause fix here typically resolves all of them at once (e.g. one shared HTTP-client utility, one shared test-setup helper, one broken mock). Investigate root cause BEFORE attempting per-file fixes. Commit the fix as `fix(batch-baseline): <root cause> — resolves N pre-existing failures` referencing the issues that reported it.

If the list above says `(none repeated across queue — any failures already noted are likely story-local)`, skip this section and proceed to the normal Gate 1 work.

═══════════════════════════════════════════════════════════════════════
READ ALL DEV/REVIEW NOTES FIRST
═══════════════════════════════════════════════════════════════════════

For each batched issue, fetch comments and internalize the dev/review notes:
  for N in <batched-issues>:
    gh issue view $N --json comments --jq '.comments[].body'
Read every 🔗 Dev note, 🤝 Dev → Review handoff, and 🔍 Review note. They tell you which behaviors to watch for at QA time.

══════════════════════════════════════════════════════════════════════
GATE ORDER — all three must pass IN THIS ORDER
══════════════════════════════════════════════════════════════════════

**Gate 1: Full test suite**
  • Run the project's full backend test command + full frontend test command (auto-detect).
  • If failures: fix in the batch branch, commit `fix(batch-tests): <short> (#<affected-issue>)`, push, re-run. Max 3 retry cycles.
  • If still red after 3 cycles: emit `batch-qa-gates-status: failed — Gate 1 red after 3 retry cycles: <diagnosis>` in the handoff block and return. The orchestrator will pause the queue and converse with the user — do NOT attempt targeted-revert routing yourself.
  • On Gate 1 green: post on EACH still-batched issue: 📦 Batch status — "Full test suite green"

**Gate 2: Full e2e suite**
  • Auto-detect the e2e command: probe `package.json` scripts for /e2e|playwright|cypress|integration/i, or look for `playwright.config.*` / `cypress.config.*` / `Maestro/*.yaml`. Run it.
  • If failures: fix in batch, commit `fix(batch-e2e): <short> (#<affected-issue>)`, push, re-run. Max 3 retries.
  • If still red after 3 cycles: emit `batch-qa-gates-status: failed — Gate 2 red after 3 retry cycles: <diagnosis>` in the handoff block and return. Orchestrator pauses for the user (same pattern as Gate 1).
  • On Gate 2 green: post on EACH still-batched issue: 📦 Batch status — "Full e2e suite green"

**Gate 3: Live-stack Junior-tester QA gate**

  Adopt this mental model verbatim:
    "I am a Junior QA tester with no knowledge about the project domain or tech stack. I know how to start the dev stack from a documented command, open a browser, click around, and observe what happens. Tell me EXACTLY what to click, type, and look for — step by step — to confirm this batch is safe to merge."

  **Step A — Draft the JUNIOR-FRIENDLY QA plan** covering ALL batched issues. The plan must be:
    1. **Browser-driven where possible.** Every check is a sequence of "Open browser → navigate → click → type → observe". No xUnit filter strings, no curl commands, no SQL queries in the plan itself — keep all developer-tools content in a separate "Developer evidence" subsection per story so the main plan stays junior-friendly.
    2. **Self-contained.** Each story's plan starts from "the stack is running and you are on the home/login page". The first universal step in the plan documents how to start the stack (auto-detected command, e.g. `dotnet run --project <AppHost>`, `npm run dev`, `docker compose up`).
    3. **Explicit visual outcomes.** Tell the tester EXACTLY what they should see ("you should see a page with the title '<Page Title>' and a green badge labeled '<Badge>'"). No "verify the feature works" hand-waves.
    4. **Persona/language coverage.** If the project supports multiple locales (read from `/locales/<lang>/` or i18n config), the plan covers each supported locale with explicit toggle instructions ("Open DevTools console, run `localStorage.setItem('<locale-key>', '<lang>'); location.reload();` — use the actual locale-switch mechanism the project documents").
    5. **Backend-only stories** (no UI): in the plan, write *"This story has no user-visible behavior. Verification was performed via the test suite (see the embedded test output below)."* — and include a small green-tick checklist of the relevant tests that passed. The junior tester does not need to run xUnit/pytest commands themselves; the evidence is captured in the report.
    6. **Cross-story checks**: pairs of stories that touch the same UI screen, endpoint family, DB tables, or signal hub. Click through to catch "story A breaks story B" regressions.
    7. **QA like a HUMAN USER, not a computer.** Reach every screen the way a real user would — start from the home/login page and **navigate through the actual UI** (click the nav menu, the buttons, the links) to get where you're going. Do NOT deep-link by typing a URL you happen to know into the address bar, and do NOT call an API directly to set up UI state, *unless the story's behavior under test IS that deep-link/endpoint* (then test both the human path AND the direct path). A computer "knows" the URL and jumps straight there; a human has to find the door — and that path is where real-user bugs live: a broken or missing nav entry, a button that doesn't wire up, a route guard that redirects, a link with the wrong href, a menu item hidden for the wrong role. If you can't reach a feature by clicking like a user can, that is itself a finding — even if the page renders fine when you jump to its URL.

  **Step B — Execute against the LIVE running stack.**
    1. Claim the stack lock at `~/.claude/dev-stack.lock` (write your PID to it).
    2. Start the stack using the auto-detected command. Wait for healthy (max 5 min).
       **Environmental fallback (NOT a halt):** if stack startup fails for an *environmental* reason (TLS handshake timing, port conflict, dependency probe budget, sandboxed-env limitation) — NOT a code regression — substitute equivalent coverage IF AND ONLY IF: (a) the failure is clearly environmental and existing infra was already broken before the batch; (b) the substitute coverage exercises the same code paths (e.g. WebApplicationFactory + Testcontainers, supertest + ephemeral DB, etc.); (c) the substitution is explicitly documented in the handoff block AND noted for pr-author to record in qa-report.html; (d) a 🐛 Batch QA environmental note is posted on the first batched issue. If substitute coverage isn't viable either: emit `batch-qa-gates-status: failed — Gate 3 stack startup blocked: <diagnosis>` and return. Do NOT halt the queue.
    3. Drive the Junior-tester plan from Step A **as a human user would** (Step A rule 7): navigate through the UI from the landing page to each feature — don't jump to known URLs or pre-seed state via the API except to *additionally* verify an intended deep-link/endpoint. Use Playwright MCP for UI clicks. For UI screenshots prefer `mcp__playwright__browser_snapshot` (no file written). When taking a `browser_take_screenshot` for visual evidence (dark-mode, layout regression), ALWAYS pass `filename` as an absolute path under `<session-folder>/screenshots/<issue>-<descriptor>.png` (the MCP server's CWD is the repo root, not your worktree — relative filenames leak PNGs into the repo as untracked files). Create `<session-folder>/screenshots/` yourself if missing.

  **Step C — For every bug or AC-gap found:**
    • Fix it in the batch worktree.
    • Commit `fix(qa): <short> (#<affected-issue>)`. One bug per commit.
    • Push.
    • Re-verify the AC.
    • Post 🐛 Batch QA finding on the SPECIFIC story's issue with diagnosis + fix commit SHA.

  **Step D — After fixes, re-run Gates 1 + 2 to confirm no regression.**

  **Step E — Release the stack lock and stop the stack.**

  **Step F — Post on EACH batched issue:** 📦 Batch status — "Batch QA green" (with a summary if fixes applied).

Gate 3 execution is non-negotiable. You may not skip it or substitute green CI for it. The Junior-tester plan content scales (backend-only stories explain their evidence; UI stories give clickpaths); the *execution* is non-negotiable except via the environmental escape hatch above.

══════════════════════════════════════════════════════════════════════
RETURN — handoff to pr-author
══════════════════════════════════════════════════════════════════════

Your return summary MUST contain a fenced ```handoff block the orchestrator parses verbatim and injects into the pr-author prompt:

```handoff
batch-qa-gates-status: green | failed — <reason>
full-test-suite: <pass>/<total>
full-e2e-suite: <pass>/<total>
live-qa: <N-bugs-found-and-fixed> | clean
fix-commit-shas: [<sha1>, <sha2>, ...]   # empty list if no bugs
environmental-escape-used: yes — <substitute coverage> | no
coverage-caveats: <one line per honest gap, or "none">   # what the gates did NOT prove
stack-lock-owned: no                      # must be no — released in step E
```

**`coverage-caveats` (be honest — this feeds the qa-report's "What automation did NOT cover" so the downstream QA agent knows where to focus).** List, as short bullets, anything the three gates did NOT actually exercise: behaviors that exist only behind an environmental escape (so the live path was never driven), stories whose UI you couldn't reach and verified by unit test only, gate steps you had to substitute or skip, flows the e2e suite doesn't touch (error/empty/persistence states are common here), and anything you fixed under the retry budget that you couldn't fully re-verify. If the gates genuinely covered everything end-to-end, write `coverage-caveats: none`. Do NOT round up to "none" to look clean — an honest gap list is the point.

Your reply must also end with `agent-status: done` or `agent-status: incomplete — <reason>`. On green gates, return `agent-status: done` + `batch-qa-gates-status: green` in the handoff. On any gate failing the 3-retry budget, return `agent-status: done` (the work itself completed — you ran the gates) + `batch-qa-gates-status: failed — <reason>` in the handoff; the orchestrator will route pr-author to open the Draft PR with a DO NOT MERGE callout. Reserve `agent-status: incomplete` for true runtime failures (you couldn't run the gates at all).
