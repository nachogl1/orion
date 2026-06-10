# Changelog — fable-sequential-gh-orion-v1

## v1.0 — initial release

First version of the **fable-** generation pipeline: the BMAD-free successor to
`sequential-bmad-github-orion-v4` (which remains untouched and fully supported as the
fallback). Created as a parallel skill, not an edit — both families coexist.

### Inherited unchanged from sequential-bmad-github-orion-v4

Production-ready merge bar; orchestrator-owned hard CI-green gate (every rollup check gates;
empty-rollup settle-and-repoll; no-CI full-local-evidence fallback; post-merge audit);
`Refs #N`-only auto-close hygiene with pre-push audit; deferral tracking (find-or-reuse, every
deferral ends in a `#N`, never defer to a closed issue) paired with the cheap-and-safe
fix-in-place-first test; issue grounding before implementation; human-gate readiness scanning;
baseline-vs-regression discipline (detached-worktree baseline, never stash); TODO/FIXME marker
protocol; neutral exhaustive QA-report contract; lessons-learned capture; session folder +
append-only `run.jsonl` + idempotent finalization sentinel; multi-worktree safety rules;
queue construction (topo-sort, riskiest-first, batch-size checkpoint); base-branch flexibility
(run from any branch); steering-then-merge-signal flow (the pipeline never merges to base).

### New in the fable generation

- **BMAD removed.** `/bmad-create-story` → a strong-model **spec agent** that grounds the
  issue against live code and posts the spec as an issue comment (no local story files).
  `/bmad-dev-story` → the implementer prompt. `/bmad-code-review` → a **panel of 3 parallel
  adversarial reviewers** (correctness / security-and-edge-cases / conventions-and-tests)
  plus a fix agent.
- **Workflow-orchestrated sequencing.** The per-issue pipeline is a deterministic ultracode
  Workflow script (`workflow/per-issue-pipeline.js`) with schema-validated agent returns —
  replacing prose sequencing and the fragile terminal-line contract + recovery machinery.
- **Park-and-continue failure handling.** Designed for unattended overnight runs: a failing
  issue is parked with a full diagnosis record (branch preserved on origin, 🅿️ issue comment)
  and the queue continues. v4's pause-and-converse would freeze a 3am run on one stubborn
  issue.
- **Ultrareview flagging.** PRs crossing a size/risk threshold are flagged in the steering
  report for the user to run `/code-review ultra <PR#>` (user-triggered and billed — the
  pipeline never invokes it).
- **Retro agent + self-improvement loop.** Every run ends with `proposed-improvements.md`:
  project-knowledge entries (target repo, may be applied with consent) and generalized skill
  proposals (user-reviewed; the skill never edits itself). Run-over-run metrics appended.
- **QA report gains a Parked issues section** so downstream QA knows skipped work is absent,
  not broken.
- **Permission pre-flight** at Phase 0 for unattended runs.
