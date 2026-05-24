# sequential-bmad-github-orion-v2

A Claude Code skill that takes a queue of GitHub issues, ships each through a four-agent BMAD pipeline (create-story → implement → code-review → build/PR/CI/merge into a shared batch branch), then runs a two-agent batch-QA pipeline (full tests + e2e + live-stack Junior-tester QA gate) and opens a Draft PR batch→main. **BMAD methodology + GitHub Issues as source of truth are hard requirements.** The run is fully autonomous through cheap retries + one Opus recovery attempt; on genuine failure it pauses the queue and converses with you to decide skip / retry / fix-manually / abort.

> [!NOTE]
> **Thinking of editing this skill?** Prefer creating a *new version* — copy it to a new skill name (e.g. bump the `-vN` suffix) — and leave this one as-is. People and automated workflows may rely on the current behaviour, so versioning beats editing in place. See [CHANGELOG.md](./CHANGELOG.md) for how prior versions evolved.

## When to use

- You have N issues (BMAD stories, bugs, chores) you want shipped sequentially.
- You want them merged into a shared batch branch + a single Draft PR you review and merge into `main`.
- You're OK with strict serialization (issue `i+1` doesn't start until issue `i` is merged into the batch).
- You're comfortable with the autonomy contract: the skill runs end-to-end through the Draft PR, then pauses and waits for you to say "merged" (or "closed/abandoned") before running Phase 4 finalization. It also pauses to converse with you on real failures.

## When NOT to use

- BMAD isn't set up in your project — Agents A/B/C invoke `/bmad-create-story`, `/bmad-dev-story`, `/bmad-code-review`, and will fail immediately without them.
- GitHub Issues isn't your team's source of truth (you use Jira, Linear, etc.). The skill posts milestone comments on issues throughout the run and closes them in Phase 4.
- You want parallel execution — this skill is sequential by design. (`/assign-issues-orion` helps you pick a parallelizable, collision-free set of issues up front, but execution here is still strictly one-at-a-time.)
- You want a non-merged review queue. This skill drops everything into a batch branch and opens a Draft PR; if you'd rather review per-issue PRs separately, use a different flow.

## Quick start

1. Install the skill folder to `~/.claude/skills/sequential-bmad-github-orion-v2/`.
2. Verify prerequisites (see [PREREQUISITES.md](./PREREQUISITES.md)).
3. From your repo's `main` branch (clean working tree, no staged changes), invoke `/sequential-bmad-github-orion-v2` with no args (defaults to issues assigned to `@me`) or pass an explicit issue specifier:
   - Single: `/sequential-bmad-github-orion-v2 230`
   - Space- or comma-list: `/sequential-bmad-github-orion-v2 230 231 232`
   - Range: `/sequential-bmad-github-orion-v2 230-235`
   - Mixed: `/sequential-bmad-github-orion-v2 230 232-234,237`
4. The skill walks you through Phase 0 (preconditions + batch-size confirmation if queue > 4), then runs autonomously. It will pause and converse if it hits a genuine failure.

## What it does

- **Phase 0** — confirm BMAD + GitHub-Issues preconditions, validate the queue, resolve the batch branch name, create the session folder.
- **Phase 1** — per-issue 4-agent pipeline against a fresh worktree forked from the batch branch (Agent A creates the BMAD story, Agent B implements, Agent C code-reviews and auto-fixes, Agent D builds + tests + opens a PR targeting the batch branch + waits CI green + squash-merges into batch).
- **Phase 2** — two-agent batch-QA pipeline against the integrated batch branch: 2.2a `test-and-fix` runs Gates 1 (full tests) + 2 (full e2e) + 3 (live-stack Junior-tester QA), fixes bugs in batch as it goes, re-runs gates; 2.2b `pr-author` writes a junior-friendly `qa-report.html` and opens the Draft PR batch→main.
- **Phase 3** — pause and wait for your merge signal. Reply "merged" (Phase 4 runs), "closed/abandoned" (manifest written, exit clean), or describe what happened. No polling, no `ScheduleWakeup`.
- **Phase 4** — on your "merged" signal: close every batched issue with an audit comment, write a per-run stats report HTML to `~/Downloads/`, tear down the batch worktree + branch.

## What it costs

For a typical 4-issue batch: ~16 per-issue agent spawns (Agent A/B/C/D × 4 issues) + 2 batch-QA agent spawns + occasional recovery spawns when something goes sideways. The cost scales linearly with batch size. **Start with a 1-2 issue batch on your first run** so you can observe the pipeline end-to-end before trusting it with a longer queue. Phase 0 prompts for confirmation when the queue exceeds 4 issues (override the threshold via `BATCH_PIPELINE_SIZE_PROMPT_THRESHOLD`).

## Where things live

- **Session folder:** `~/Downloads/batch-<repo-name>-<timestamp>-<issue-suffix>/` (preserved on success for later inspection).
- **Per-run stats report:** `~/Downloads/<repo-name>-stats-<DD_MM_YYYY>-<HH_MM>.html` (fresh file per run; the skill never modifies or deletes existing stats reports).
- **Run log:** `<session-folder>/run.jsonl` (mechanical event log, one JSON object per line).
- **Lessons-learned log:** `<session-folder>/lessons-learned.md` (higher-signal findings for skill self-improvement).
- **QA report:** `<session-folder>/qa-report.html` (consumed by humans + by downstream agents like `/guided-qa-orion`).
- **Per-issue failure folders** (only on §1.7 skip): `<session-folder>/failures/<N>-<slug>/` with `diagnosis.md`, `last-state.diff`, `agent-transcripts/`.

The skill **never touches** any long-lived `<repo-name>-status-*.html` deck you maintain by hand.

## Failure mode summary

The skill is autonomous through cheap retries + one Opus recovery attempt. On a genuine failure both have rejected, it **pauses the queue, prints the diagnosis + failure-folder path, and waits for your free-form direction** — no multiple-choice menu. You can ask questions, dig into the worktree, propose a fix, or just tell the orchestrator to skip / retry the slot / abort. The two hard halts are Phase 0 precondition failures and an explicit "stop" mid-loop; everything else is a soft failure that either pauses-and-converses or opens the Draft PR with a `❌ DO NOT MERGE` callout so you can resolve manually.

## Pointers

- [PREREQUISITES.md](./PREREQUISITES.md) — hard requirements (BMAD, gh, git, default branch), soft requirements, and environment variables.
- [SKILL.md](./SKILL.md) — the full orchestrator spec.
- [CHANGELOG.md](./CHANGELOG.md) — version history.
- `prompts/` — the sub-agent prompt templates (read by the orchestrator at spawn time).
