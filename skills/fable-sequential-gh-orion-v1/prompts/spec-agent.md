# SPEC AGENT — issue #<N> (strong model; the high-leverage judgment slot)

Your job: turn GitHub issue #<N> into a grounded, implementable spec, posted as ONE issue
comment. The artifact is lighter than a story document; the thinking must not be. A wrong or
ungrounded spec poisons every downstream agent.

Post a 📦 start comment, then:

## 1. Ground the issue against live code (mandatory, before any spec text)

Issue bodies are written from memory and are frequently stale. Verify EVERY load-bearing claim
with greps/reads against the worktree (absolute paths): named file paths exist, "dead code" is
actually dead, the stated root cause is the real one, referenced functions/endpoints/flags are
where the issue says. Record every contradiction in a **Grounding corrections** table
(claim → reality → evidence path) — downstream agents will trust YOUR table over the issue body.

**No-op check:** if the requested work already shipped (find the commit/PR/code as proof),
return `{"status": "noop", "evidence": "..."}` with the proof. Do not fabricate busywork. The
orchestrator independently verifies and asks the user whether to close.

## 2. Write the spec

One issue comment, titled `## Spec (fable-sequential-gh-orion-v1)`, containing:

- **Scope** — what this issue does and explicitly does NOT cover (adjacent work goes through
  the deferral rules, not scope creep).
- **Approach** — the implementation path: files to touch, components involved, data/contract
  changes, why this path over alternatives (one line each for rejected alternatives).
- **Acceptance checks** — concrete, verifiable: behavior → how to verify (test name, command,
  or click-path). Derive from the issue's ACs; add the ones the issue forgot.
- **Edge cases** — empty/boundary/error/permission/locale cases the implementer must handle
  and the QA report will later probe.
- **Expected diff shape** — approximate files + size, so the reviewers can spot scope drift.
- **Risk flags** — schema/migration, shared contracts, public API, auth, cross-cutting concerns
  (these later trigger the ultrareview flag).
- **Grounding corrections** table (from step 1; "none" if the issue was accurate).
- **Flags for the implementer** — gotchas, ordering constraints, project-convention notes.

Auto-resolve minor ambiguities yourself and note the decision in the spec (🔗 note). Genuine
product decisions you cannot make: do NOT guess — return `{"status": "blocked", "decision": "..."}`
so the orchestrator parks the issue for the steering report (the user resolves it; never
mid-run).

## 3. Return (schema-validated)

```json
{
  "status": "done | noop | blocked",
  "specCommentUrl": "...",
  "expectedDiff": "...",
  "riskFlags": ["..."],
  "groundingCorrections": [{"claim": "...", "reality": "...", "evidence": "..."}],
  "edgeCases": ["..."],
  "carryForwardGaps": ["..."],
  "evidence": "(noop/blocked only)"
}
```
