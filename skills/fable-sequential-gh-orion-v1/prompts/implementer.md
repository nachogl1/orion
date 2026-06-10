# IMPLEMENTER — issue #<N>

Your job: build exactly what the spec comment (`## Spec (fable-sequential-gh-orion-v1)` on
issue #<N>) defines, in the worktree, to production quality. The spec is your authoritative
input; the issue body is background (the spec's Grounding corrections table supersedes it).

Post a 📦 start comment, then:

1. **Dep-install preflight.** Worktrees don't inherit installed dependencies — if a lockfile
   exists, run the project's install command first. Verify the project compiles BEFORE you
   change anything (a broken start is a baseline fact to record, not your bug).
2. **Implement to the spec.** Code + targeted tests for every acceptance check + i18n strings
   for every user-facing string IF the project has locales (detect from the repo). Handle every
   edge case the spec lists. Tick the AC checkboxes on the issue body as each lands.
3. **Opportunistic fixes** in code you already touch go through the cheap-and-safe test
   (shared standards): pass → fix + 🔗 "opportunistic fix" note on the issue; fail → record as
   a deferral candidate in your return. No hunting unrelated work.
4. **Targeted tests only** (the affected suites; max 5 fix-retry cycles per command — then
   record honestly and move on). The full suite belongs to the batch gate, not you.
5. **Mandatory pre-handoff FULL COMPILE** (not full suite). Never hand off code that doesn't
   build.
6. Post ONE final 🤝 handoff comment on the issue: dependencies added, assumptions, decisions,
   potential merge-conflict surfaces, skipped checks (each with its reason), deferral
   candidates (each naming its failed cheap-and-safe criterion), new TODO/FIXME markers
   (file:line + why).

Return (schema-validated):
```json
{
  "status": "done | failed",
  "filesChanged": ["..."],
  "testsAdded": ["..."],
  "acStatus": [{"ac": "...", "state": "done | partial | blocked", "note": "..."}],
  "deferralCandidates": [{"what": "...", "failedCriterion": "..."}],
  "newMarkers": [{"location": "file:line", "what": "...", "why": "..."}],
  "skippedChecks": [{"what": "...", "why": "..."}],
  "diagnosis": "(failed only)"
}
```
