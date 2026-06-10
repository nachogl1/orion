# fable-sequential-gh-orion-v1

Fully automated sequential GitHub-issue execution against a batch feature branch — the
**BMAD-free successor** to the `sequential-bmad-github-orion` family, built on Fable-5-era
Claude Code primitives: ultracode **Workflow** orchestration, worktree-isolated sub-agents,
parallel adversarial review panels, and schema-validated structured returns.

## What it does

```
/fable-sequential-gh-orion-v1 12 14 15-17
```

1. **Phase 0** — preconditions (gh auth; GitHub Issues as source of truth — *no BMAD*),
   queue parsing/ordering, readiness gate, batch branch + session folder, permission
   pre-flight for unattended runs.
2. **Phase 1** — per issue, strictly sequential: a Workflow runs **spec agent** (strong model;
   grounds the issue against live code, posts the spec as an issue comment) → **implementer**
   (worktree forked from the current batch tip) → **3 parallel adversarial reviewers**
   (correctness / security-and-edge-cases / conventions-and-tests) + fix agent → **finalize**
   (audit, commit, push, PR-open). The orchestrator then watches CI (every check gates),
   squash-merges into the batch, and tears down. Failures **park-and-continue** — a stubborn
   issue never blocks the night.
3. **Phase 2** — full-suite + e2e gate with baseline discipline, whole-batch deferral filing
   (every deferral gets a `#N`), the neutral **qa-report.html** test plan (the input contract
   for `/fable-guided-qa-orion`), and a **Draft PR** batch→base.
4. **Phase 2.5** — **retro agent**: proposes project-knowledge updates (target repo) and
   generalized skill improvements (user-reviewed; the skill never edits itself).
5. **Phase 3** — **steering point**: merged / parked / ultrareview-flagged report, then waits
   for your free-form "merged" / "closed" signal. The pipeline **never merges to the base
   branch** — that's yours, after QA.
6. **Phase 4** — on "merged": close batched issues with audit comments, stats report.

## Design highlights vs the v4 predecessor

| | sequential-bmad-github-orion-v4 | fable-sequential-gh-orion-v1 |
|---|---|---|
| Methodology | BMAD slash commands required | none — spec lives as an issue comment |
| Sequencing | prose instructions to the orchestrator | deterministic Workflow script (`workflow/per-issue-pipeline.js`) |
| Review | one code-review agent | 3 parallel adversarial lenses + fix agent |
| Agent returns | terminal `agent-status:` line + recovery paths | schema-validated structured output |
| Per-issue failure | pause-and-converse (blocks the queue) | **park-and-continue** (queue keeps running) |
| Self-improvement | manual lessons harvest | retro agent every run + run-over-run metrics |
| `/code-review ultra` | n/a | risky PRs flagged for the user to trigger at steering |

Unchanged on purpose: production-ready bar, hard CI-green merge gate, `Refs #N` hygiene,
deferral tracking + cheap-and-safe test, TODO-marker protocol, stash ban and worktree
discipline, the neutral QA-report contract, session folder + `run.jsonl` durability.

## Long-run durability (how it survives hours unattended)

All load-bearing state lives OUTSIDE the model's context: `run.jsonl` event log, GitHub
comments/labels/PRs, the batch branch on origin, Workflow resume caching. Context compaction
or even a machine reboot costs at most the in-flight issue; completed issues are durable.

## Files

- `SKILL.md` — orchestrator spec.
- `prompts/shared-standards.md` — the engineering standards injected into every agent.
- `prompts/spec-agent.md`, `implementer.md`, `reviewer.md`, `qa-report-author.md`,
  `retro-agent.md` — role prompts.
- `workflow/per-issue-pipeline.js` — the Workflow template the orchestrator adapts per issue.

See `PREREQUISITES.md` before the first run.
