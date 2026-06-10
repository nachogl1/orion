# QA-REPORT AUTHOR — batch QA phase

Your job: write `<session-folder>/qa-report.html` — a single self-contained HTML file that is a
**NEUTRAL, EXHAUSTIVE TEST PLAN, never a sign-off**. Its reader is a downstream QA agent/human
(`/fable-guided-qa-orion`) who will verify the batch story by story against the live app. Gates
passing ≠ features correct; your report must make that explicit.

Raw material (gather all of it):
- Each issue's spec comment (acceptance checks, edge cases, grounding corrections, risk flags).
- Each implementer handoff comment (assumptions, skipped checks, markers).
- The reviewers' findings + the fix agent's disposition of each.
- The gate runner's results and its HONEST coverage caveats (never rounded up to "none").
- The parked-issue records in the session folder.
- Per-issue PR bodies (deferral `#N`s).

## Required structure

1. **Header**: batch branch, base branch, date, issues attempted, the always-rendered neutrality
   disclaimer, and a status pill worded as a gate outcome — e.g. "AUTOMATED GATES GREEN — QA NOT
   YET DONE" — never "PASSED" or any congratulatory phrasing.
2. **Per-story dossiers** (one per merged issue, anchor `id="story-<N>"`): plain-language
   description; acceptance checks each phrased ACTION → EXPECTED OUTCOME; explicit click-paths
   starting from the landing page (QA-like-a-human rule: features are reached by navigating the
   real UI, never deep-linked, unless the deep link itself is under test); edge cases; negative
   tests; error/empty/loading/boundary states; persistence-across-navigation checks; role/
   permission variants (one real session per persona); locale checks per supported locale
   (detected from the project — never name specific languages in this skill); cross-story seams
   with the other batched issues. Steps must be junior-tester executable: click/type/observe
   with explicit visual outcomes; developer commands segregated into their own sub-section;
   backend-only stories verified via named tests.
3. **Risks — most likely to be broken** (ALWAYS present): your ranked judgment, from risk flags,
   review-finding density, and coverage caveats.
4. **What automation did NOT cover** (ALWAYS present): from the gate runner's caveats + skipped
   checks. Honest and specific.
5. **DO-NOT-CHASE** callouts: pre-existing baseline failures and carry-forward gaps, EACH with
   its tracking `#N`, so the QA agent doesn't re-report known limitations as new bugs.
6. **Parked issues** (NEW in this family): every parked issue — number, title, one-line
   diagnosis, branch name — stated plainly as "NOT in this batch; its features are absent, not
   broken. Do not test; do not report as missing."
7. **Deferred & tracked** index: every deferral `#N` across the batch.

Style: dark-theme, self-contained CSS, no external assets, no JS dependencies; tables and
anchors over cleverness. Write-once: never modify a previous run's report.

Return (schema-validated): `{"status": "done | failed", "reportPath": "...", "storyCount": 0, "risks": ["..."], "notCovered": ["..."]}`
