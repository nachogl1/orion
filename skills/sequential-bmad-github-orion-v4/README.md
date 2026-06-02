# sequential-bmad-github-orion-v4

A Claude Code skill that takes a queue of GitHub issues, ships each through a four-agent BMAD pipeline (create-story → implement → code-review → build/PR/CI/merge into a shared batch branch), then runs a two-agent batch-QA pipeline (full tests + e2e + live-stack QA gate) and opens a Draft PR batch→**base branch**. **BMAD methodology + GitHub Issues as source of truth are hard requirements.** The run is fully autonomous through cheap retries + one Opus recovery attempt; on genuine failure it pauses the queue and converses with you to decide skip / retry / fix-manually / abort.

**New in v4** (the previous version is kept, deprecated, as [`sequential-bmad-github-orion-v3-old`](../sequential-bmad-github-orion-v3-old/); see [CHANGELOG.md](./CHANGELOG.md) for the full list):

- **Run from any base branch, not just `main`.** The skill forks the batch from — and targets the Draft PR at — whatever branch you invoke it from (the *base branch*). Run it from a feature/integration branch, or from a separate worktree, and your `main` is never touched while the batch runs. Running from `main` behaves exactly as before.
- **TODOs left during development are recorded in `lessons-learned.md`.** Markers were already surfaced (PR body, QA report); now a left-behind TODO/FIXME also gets a durable lessons-learned entry naming the `file:line`, what was deferred, and why — so a feature/gap punted to "later" doesn't get forgotten.
- **The `qa-report.html` is a neutral, exhaustive test plan** — written for an independent full-round QA agent (e.g. `/guided-qa-orion`), not as a "we're green" sign-off. Claims are phrased as things to *verify*; automated-gate results are reported factually and separately; each story adds error/empty/persistence angles, a **Risks — most likely to be broken** section, and a **What automation did NOT cover** gap map.

**Also in v5.1** (in-place edits to this `-v4` folder, from later-run lessons — see [CHANGELOG.md](./CHANGELOG.md)): Agent D now stops at PR-open and the **orchestrator** owns the CI-watch + hard pre-merge gate + merge (removes the background-yield failure mode); an **empty CI rollup is settled-and-repolled** before any no-CI fallback; Agent D runs **targeted tests + a compile** locally instead of the full suite (CI is the full-suite gate); a **pre-flight issue-triage gate** (code-grounding, no-op/already-resolved short-circuit, human-gate readiness); a hardened **terminal-line contract** with mandatory on-disk artifact verification; **never `git stash` in sub-agents** (repo-global stash hazard); **worktree-path discipline**; and finalize **git discipline** (precise staging, ignore-check, portable grep).

It also keeps everything from v3: deferral tracking into find-or-reuse `#N`s linked back into PR bodies, the hard CI-green merge gate + post-merge audit, human-like live-stack QA, and the fix-in-place-first gate (Core Principle #10).

> [!NOTE]
> **Thinking of editing this skill?** Prefer creating a *new version* — copy it to a new skill name (e.g. bump the `-vN` suffix) — and leave this one as-is. People and automated workflows may rely on the current behaviour, so versioning beats editing in place. See [CHANGELOG.md](./CHANGELOG.md) for how prior versions evolved.

## When to use

- You have N issues (BMAD stories, bugs, chores) you want shipped sequentially.
- You want them merged into a shared batch branch + a single Draft PR you review and merge into your base branch (`main`, or a feature/integration branch so `main` stays untouched).
- You're OK with strict serialization (issue `i+1` doesn't start until issue `i` is merged into the batch).
- You're comfortable with the autonomy contract: the skill runs end-to-end through the Draft PR, then pauses and waits for you to say "merged" (or "closed/abandoned") before running Phase 4 finalization. It also pauses to converse with you on real failures.

## When NOT to use

- BMAD isn't set up in your project — Agents A/B/C invoke `/bmad-create-story`, `/bmad-dev-story`, `/bmad-code-review`, and will fail immediately without them.
- GitHub Issues isn't your team's source of truth (you use Jira, Linear, etc.). The skill posts milestone comments on issues throughout the run and closes them in Phase 4.
- You want parallel execution — this skill is sequential by design. (`/assign-issues-orion` helps you pick a parallelizable, collision-free set of issues up front, but execution here is still strictly one-at-a-time.)
- You want a non-merged review queue. This skill drops everything into a batch branch and opens a Draft PR; if you'd rather review per-issue PRs separately, use a different flow.

## Quick start

1. Install the skill folder to `~/.claude/skills/sequential-bmad-github-orion-v4/`.
2. Verify prerequisites (see [PREREQUISITES.md](./PREREQUISITES.md)).
3. From the branch you want the batch to target (your `main`, or a feature/integration branch / separate worktree to keep `main` untouched — clean working tree, no staged changes), invoke `/sequential-bmad-github-orion-v4` with no args (defaults to issues assigned to `@me`) or pass an explicit issue specifier:
   - Single: `/sequential-bmad-github-orion-v4 230`
   - Space- or comma-list: `/sequential-bmad-github-orion-v4 230 231 232`
   - Range: `/sequential-bmad-github-orion-v4 230-235`
   - Mixed: `/sequential-bmad-github-orion-v4 230 232-234,237`
4. The skill walks you through Phase 0 (preconditions + batch-size confirmation if queue > 4), then runs autonomously. It will pause and converse if it hits a genuine failure.

## What it does

- **Phase 0** — confirm BMAD + GitHub-Issues preconditions, capture the base branch (the branch you invoked from; published to `origin` if local-only), validate the queue, resolve the batch branch name, create the session folder.
- **Phase 1** — per-issue 4-agent pipeline against a fresh worktree forked from the batch branch (Agent A grounds the issue against live code + creates the BMAD story, Agent B implements, Agent C code-reviews and auto-fixes, Agent D compiles + runs targeted tests + opens a PR targeting the batch branch and **stops at PR-open**; the **orchestrator** then watches CI, runs a hard pre-merge gate, and squash-merges into the batch). A per-issue PR is **not** merged while its CI is red or still pending — an empty check-rollup is settled-and-repolled before any no-CI fallback — and the orchestrator re-audits CI after the merge and reverts off the batch if a non-green PR slipped through.
- **Phase 2** — two-agent batch-QA pipeline against the integrated batch branch: 2.2a `test-and-fix` runs Gates 1 (full tests) + 2 (full e2e) + 3 (live-stack QA, driven like a real user through the UI), fixes bugs in batch as it goes, re-runs gates; 2.2b `pr-author` files-and-links every deferral into a tracking `#N`, writes the neutral, exhaustive `qa-report.html`, and opens the Draft PR batch→base-branch.
- **Phase 3** — pause and wait for your merge signal. Reply "merged" (Phase 4 runs), "closed/abandoned" (manifest written, exit clean), or describe what happened. No polling, no `ScheduleWakeup`.
- **Phase 4** — on your "merged" signal: close every batched issue with an audit comment, write a per-run stats report HTML to `~/Downloads/`, tear down the batch worktree + branch.

## What it costs

For a typical 4-issue batch: ~16 per-issue agent spawns (Agent A/B/C/D × 4 issues) + 2 batch-QA agent spawns + occasional recovery spawns when something goes sideways. The cost scales linearly with batch size. **Start with a 1-2 issue batch on your first run** so you can observe the pipeline end-to-end before trusting it with a longer queue. Phase 0 prompts for confirmation when the queue exceeds 4 issues (override the threshold via `BATCH_PIPELINE_SIZE_PROMPT_THRESHOLD`).

## Where things live

- **Session folder:** `~/Downloads/batch-<repo-name>-<timestamp>-<issue-suffix>/` (preserved on success for later inspection).
- **Per-run stats report:** `~/Downloads/<repo-name>-stats-<DD_MM_YYYY>-<HH_MM>.html` (fresh file per run; the skill never modifies or deletes existing stats reports).
- **Run log:** `<session-folder>/run.jsonl` (mechanical event log, one JSON object per line).
- **Lessons-learned log:** `<session-folder>/lessons-learned.md` (higher-signal findings for skill self-improvement).
- **QA report:** `<session-folder>/qa-report.html` (a **neutral, exhaustive test plan** consumed by humans + by downstream full-round QA agents like `/guided-qa-orion` — claims phrased as things to verify, with per-story risks + a "what automation did NOT cover" gap map).
- **Per-issue failure folders** (only on §1.7 skip): `<session-folder>/failures/<N>-<slug>/` with `diagnosis.md`, `last-state.diff`, `agent-transcripts/`.

The skill **never touches** any long-lived `<repo-name>-status-*.html` deck you maintain by hand.

## Failure mode summary

The skill is autonomous through cheap retries + one Opus recovery attempt. On a genuine failure both have rejected, it **pauses the queue, prints the diagnosis + failure-folder path, and waits for your free-form direction** — no multiple-choice menu. You can ask questions, dig into the worktree, propose a fix, or just tell the orchestrator to skip / retry the slot / abort. The two hard halts are Phase 0 precondition failures and an explicit "stop" mid-loop; everything else is a soft failure that either pauses-and-converses or opens the Draft PR with a `❌ DO NOT MERGE` callout so you can resolve manually.

## Pointers

- [PREREQUISITES.md](./PREREQUISITES.md) — hard requirements (BMAD, gh, git, a named base branch), soft requirements, and environment variables.
- [SKILL.md](./SKILL.md) — the full orchestrator spec.
- [CHANGELOG.md](./CHANGELOG.md) — version history.
- `prompts/` — the sub-agent prompt templates (read by the orchestrator at spawn time).
