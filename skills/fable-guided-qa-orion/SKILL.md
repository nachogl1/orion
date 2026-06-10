---
name: fable-guided-qa-orion
description: |
  Story-by-story QA of a developed batch, driven by a QA report the user provides — the
  Fable-5-era sibling of guided-qa-orion (which stays untouched): same supervised loop the
  user trusts (agent drives autonomously, user is present and checking; record-and-continue,
  ONE consolidated decision session at the end), upgraded with: FULL TEST SUITES RUNNING AS
  BACKGROUND TASKS while live UI testing continues in parallel; a per-story CODE-LEVEL FINDER
  fan-out (ultracode Workflow) that pre-reads each story's diff and claims ahead of the live
  walkthrough so the agent clicks with a target list; first-class handling of the
  fable-sequential-gh-orion-v1 report contract (DO-NOT-CHASE callouts and the Parked-issues
  section — parked features are absent, not broken); and a RETRO/lessons capture feeding the
  pipeline's self-improvement loop. The live walkthrough itself stays strictly sequential and
  human-like: every feature reached by clicking from the landing page, real persona sessions,
  full locale coverage, DOM-level click verification. Findings accumulate in one qa-findings.md
  (problems only); small fixes are just made; issues are filed only after a mandatory dedupe
  deep-dive; nothing commits until the whole suite + e2e are green AND the user approves AND a
  final pre-commit run is green. Use when the user says "/fable-guided-qa-orion", "guided QA
  this batch", "QA the fable batch with this report", or points at a qa-report from a pipeline
  run.
---

# fable-guided-qa-orion

> [!NOTE]
> This skill has **no `-vN` convention** — it's edited in place. Its predecessor
> `guided-qa-orion` remains available and unchanged; this sibling exists so users can fall
> back to the proven flow at any time.

You QA an already-developed batch against the live application, story by story, exhaustively —
with the user present but interrupted as little as possible. Your contract: as long as a story
is QA-able you record every bug/concern/risk into the consolidated findings file and KEEP
GOING; only a true ⛔ BLOCKER (or the user interjecting) breaks the loop. One decision session
at the end. The goal is to clear the batch for production with the FEWEST possible open
issues: fix what's small in-session, file only what's genuinely too big — and only after the
dedupe deep-dive.

Project-agnostic: stack, test commands, e2e wiring, personas, locales all detected from the
target repo and confirmed once. GitHub Issues (or whatever tracker the repo uses) for filings.

---

## Phase 0 — Intake & plan

1. **The QA report is mandatory input** — if no path was given, stop and ask. Canonical input:
   `qa-report.html` from a `/fable-sequential-gh-orion-v1` run (session folder
   `~/Downloads/fable-batch-<repo>-<timestamp>-<issues>/`); any HTML/MD report with stories +
   expected behaviours works. The report is EPHEMERAL INPUT — claims to verify, never a file
   to maintain; report-vs-reality mismatches are doc-inaccuracy findings.
2. Parse: story list + anchors, personas, **DO-NOT-CHASE** callouts (known limitations with
   their `#N` — never re-report), and the **Parked issues** section (features absent from the
   batch — do not test, do not report as missing).
3. Pre-flight: working branch must be the batch branch (on the default branch → stop and ask);
   detect + confirm unit/integration and e2e commands; confirm story order/personas only if
   ambiguous. Create `qa-findings.md` next to the input report (header: branch, date, report
   path, story map, personas, detected commands).

## Phase 1 — Stack up + parallel preparation

1. AskUserQuestion: clean-slate reset (stop + remove containers/volumes — never images) vs use
   what's running. Bring the stack up and WAIT for genuine readiness (auth provider, DB +
   migrations, API health) with a timeout; diagnose before wiping volumes on startup failures.
   Confirm login per persona before story 1. Establish the user's base UI language once and
   switch the app to it (per-locale checks are separate steps).
2. **Background suites (new):** launch the FULL unit/integration suite and the FULL e2e suite
   as background tasks NOW — they run while you click. Their results land before the decision
   session; failures become findings with the baseline discipline (re-run at the batch base in
   a throwaway detached worktree — never stash; also-fails-on-baseline = pre-existing →
   DO-NOT-CHASE check first).
3. **Code-level finder fan-out (new):** one read-only Workflow agent per story, in parallel:
   read the story's spec comment + PR diff, and return a target list — the riskiest spots, the
   states worth probing, suspicious seams with other stories, claims in the report worth extra
   scrutiny. You walk each story WITH its target list in hand instead of discovering risk
   mid-click.

## Phase 2 — The live walkthrough (sequential, human-like; user present)

One story at a time, exhaustively, with the finder's target list + the report's dossier:

- **QA like a human:** reach every feature by navigating the real UI from the landing page —
  never deep-link by URL or pre-seed via API (unless the deep-link/endpoint IS under test —
  then verify both paths). Unreachable-by-clicking = a finding even if it renders on direct
  visit.
- **Click verification at DOM level** before any click verdict: `pointerEvents` computed style,
  `document.elementFromPoint` at the element centre, negative+positive control dispatch —
  automation clicks silently no-op and headless DOMs hide real-browser CSS bugs.
- Full per-story coverage: every action/variant happy path; permission/role gating with a real
  session per persona (server-computed permissions never assumed); locale toggle across every
  supported locale (no raw keys, persistence verified); side-effects (network/DB/audit)
  actually fire; adjacent-area regression smoke; edge cases; every report claim cross-checked.
  Async-triggered UI re-checked after data settles before declaring failure.
- **Record-and-continue:** every observation classified (Real bug + severity / concern-risk /
  improvement / doc-inaccuracy / documented-TODO-confirmed / environment-or-seed limitation)
  with evidence, root cause, and a concrete suggested fix, into `qa-findings.md` (four-level
  verdict per story: ✅ / 🟡 / 🔴 / ⛔; auditable "tests I ran" table: action → expected →
  observed → ✓/✗). One-line progress note per story; NO per-story questions to the user.

## Phase 3 — Consolidated decision session (the user moment)

When all stories have verdicts and the background suites have reported: present the residue —
in-session fixes made (batch confirmation), too-big findings (file vs defer vs accept, with
the mandatory dedupe deep-dive done BEFORE offering to file: code + open + recently-closed
issues searched with variations; reuse over create; never defer to a closed issue), and
anything ambiguous. ONE grouped AskUserQuestion / discussion — only decisions that genuinely
need the user. Every deferred code item leaves with a `#N` written back beside its finding.

## Phase 4 — Fix → green → approve → commit

Fix-first, file-rarely: root-cause fixes, narrowly scoped, conventions matched; surface any
unexpectedly invasive fix (new dependency, shared component, test-runner config) before
proceeding. Then the triple gate, unchanged from the proven flow: (1) WHOLE suite + full e2e
green (re-run whole after each red-fix; capped retries); (2) the user's explicit "all passed";
(3) one final green pre-commit run. Scoped staging only; Conventional Commits; batch branch
only; push/PR only on explicit request.

## Phase 5 — Wrap-up + retro (new)

- Finalize `qa-findings.md` (absolute path reported; every story has a verdict; every deferral
  has a `#N`; nothing scratch staged; stack left as the user expects).
- **Retro block** appended to the findings file: which finding classes the pipeline's report
  did NOT predict (these are proposed additions to the pipeline's reviewer lenses / QA-report
  author), plus any skill-instruction friction — generalized, feeding the same
  `proposed-improvements.md` loop as the pipeline. The skill never edits itself or the
  pipeline; proposals are for the user's review.
