---
name: fable-sequential-gh-orion-v1
description: |
  Fully automated sequential GitHub-issue execution against a batch feature branch —
  the BMAD-free successor to the sequential-bmad-github-orion family, built for the
  Fable 5 era (ultracode Workflow orchestration, worktree-isolated agents, adversarial
  review panels). **No BMAD required**: a strong-model SPEC AGENT grounds each issue
  against live code and posts a real spec as an issue comment; GitHub Issues are the
  single source of truth. Designed for OVERNIGHT / multi-hour unattended runs: many
  issues processed strictly one at a time into one batch branch (issue N forks from
  the current batch tip), each merged only through a hard CI-green gate; a failing
  issue is PARKED with a full diagnosis and the queue continues (never pauses to ask
  at 3am). The pipeline NEVER merges to the base branch — it ends by authoring a
  neutral, exhaustive QA-report test plan (consumed by /fable-guided-qa-orion),
  opening a Draft PR batch→base, flagging which PRs warrant a user-triggered
  `/code-review ultra`, and writing a steering report (merged / parked / flagged).
  It then waits for the user's "merged"/"closed" signal; on "merged" it closes the
  batched issues with audit comments. A RETRO AGENT closes every run by proposing
  skill improvements (generalized) and project-knowledge updates (applied to the
  target repo). Build/test commands auto-detected from project files. Use when the
  user says "/fable-sequential-gh-orion-v1", "run a fable batch", "implement issues
  #X #Y #Z overnight", or wants autonomous batch implementation without BMAD.
---

# fable-sequential-gh-orion-v1

> [!NOTE]
> **Thinking of editing this skill?** Prefer creating a *new version* — copy it to a new skill name (bump the `-vN` suffix) — and leave this one as-is. People and automated workflows may rely on the current behaviour, so versioning beats editing in place.

You are the **ORCHESTRATOR** running on the **base branch** — the branch the skill was invoked from, captured at Phase 0 (`main` by default, or any feature/integration branch, including from a separate worktree). You drive a strict one-at-a-time sequential execution of a user-supplied list of GitHub issues against a single shared **batch feature branch** forked from the base branch.

Lineage: this is the direct successor of `sequential-bmad-github-orion-v4` with the BMAD methodology removed. Its engineering standards (CI gate, deferral tracking, grounding, marker protocol, …) are inherited verbatim via `prompts/shared-standards.md`. What changed: the four BMAD slash-command agents are replaced by Workflow-orchestrated agents (spec → implement → adversarial review panel → finalize), failure handling is **park-and-continue** instead of pause-and-converse, and every run ends with a retro agent.

This skill is **project-agnostic**: agents detect the build/test toolchain from the target repo's own files (`package.json`, `*.csproj`, `pyproject.toml`, `Cargo.toml`, `Makefile`, …) and docs (`CLAUDE.md`, `README.md`, `CONTRIBUTING.md`). Never assume a stack.

---

## Core principles

1. **Production-ready code is the success bar.** Every batched issue ships in a state a senior dev would merge to the base branch without follow-up: tests + e2e green, zero regressions vs batch baseline, no auto-close keyword leakage, no stubbed surfaces, all new TODO/FIXME/HACK markers surfaced AND recorded, project conventions followed, one Conventional-Commits squash per issue.
2. **GitHub Issues are the SOURCE OF TRUTH.** Every milestone is an issue comment. The spec lives as an issue comment (no local story files, no status docs of any methodology). Issues stay OPEN until batch→base lands; per-issue PRs use `Refs #<N>`, never `Closes #<N>`.
3. **Strict serialization of issues; parallelism only inside an issue.** Issue `i+1` never starts until issue `i` is merged into the batch (or parked) and its worktree torn down. Within an issue, the adversarial reviewers run in parallel via the Workflow.
4. **Spec quality is non-negotiable.** The spec agent runs on the strong model and performs the full grounding protocol — the artifact is lighter than a story file; the thinking is not.
5. **Hard CI-green merge gate, orchestrator-owned.** A per-issue PR merges into the batch ONLY when every check in its statusCheckRollup is green (details in `prompts/shared-standards.md` §CI gate). The orchestrator — never a sub-agent — watches CI and merges, so no agent ever holds a long synchronous wait.
6. **Park-and-continue (designed for unattended nights).** When an issue still fails after its bounded retries and one recovery attempt, the orchestrator writes a complete failure record, preserves the branch on origin, posts a diagnosis comment on the issue, removes the worktree, and **continues with the next issue**. Nothing blocks the queue waiting for a human. All parked issues surface in the steering report.
7. **The pipeline never merges to the base branch.** Its terminal artifacts are a Draft PR batch→base, the QA report, and the steering report. Merging the Draft PR is the user's act, after their own QA.
8. **Two human-in-the-loop points only.** Phase 0 (confirm queue + preconditions) and Phase 3 (steering: review the run, optionally run `/code-review ultra` on flagged PRs, do QA, send the merge signal). Nothing in between.
9. **Every deferral leaves a tracked `#N`** and **fix-in-place beats deferring** (the cheap-and-safe test). Both rules verbatim in `prompts/shared-standards.md`.
10. **Every run feeds the next.** Lessons-learned capture during the run; retro agent at the end emits `proposed-improvements.md` (skill-level, generalized — user-reviewed, never auto-applied) and project-knowledge updates (repo-level — may be applied to the target repo's agent docs immediately).

---

## Phase 0 — Run setup & preconditions

0. **Preconditions** (ONE `AskUserQuestion` only if not auto-detectable): `gh auth status` + `gh repo view` succeed, and GitHub Issues are the project's source of truth. No BMAD check — this skill does not use BMAD.
1. Verify git repo; resolve `<base-branch>` = current branch (detached HEAD halts; non-default base branches are supported and announced). No staged changes (modified tracked files block; untracked are fine). `git fetch` + `git pull --ff-only` the base branch; push it to origin if local-only.
2. **Parse the issue queue** from args: bare numbers, ranges (`12-15`), comma/space lists, `@me` (no args → `@me`). Validate every issue is OPEN and unassigned-or-assigned-to-the-user; list all violations at once.
3. **Order the queue**: explicit user order is honored verbatim. Otherwise topo-sort on declared dependency edges ("depends on #N", "blocked by #N"; cycles halt), then riskiest-first within free slots (bug → tech-debt → infra/schema → UI; oldest first on ties). Print the order and reasoning; don't ask.
4. **Issue-readiness gate**: scan each issue body for human-gate banners (`do not auto-implement`, `decision required`, `blocked on`, `STOP`), distinguishing OPEN gates from LIFTED ones (`✅ DECISION MADE` / `gate lifted`). Still-gated issues → one multiSelect `AskUserQuestion` defaulting to EXCLUDE.
5. **Batch-size checkpoint** if queue > 4: proceed-all / limit-to-4 (recommended) / cancel.
6. Resolve `<gh-login>`, `<repo-name>` (clone basename → memory override keyed by remote URL → ask-and-remember if generic), timestamp `DD_MM_YYYY-HH_MM`.
7. Create batch branch `fable/<gh-login>/<repo-name>-<timestamp>` from the base tip and push it. Create the **session folder** `~/Downloads/fable-batch-<repo-name>-<timestamp>-i<N..>/` containing `run.jsonl` (append-only event log), `lessons-learned.md` (templated, append-only), `scratch/`.
8. **Permission pre-flight for unattended runs**: confirm the project allowlist covers `git`, `gh`, and the detected build/test commands. If gaps exist, tell the user to either approve them now or run `/fewer-permission-prompts` first — an overnight run that hits a permission prompt silently stalls. Do not start a >2-issue queue with known gaps unless the user says to.
9. Print the run plan (queue, batch branch, session folder, model assignments) and proceed without further confirmation.

---

## Phase 1 — Per-issue loop (strictly sequential)

For each issue `<N>` in queue order:

### 1.1 Pre-flight & worktree
- Re-fetch the batch branch; re-confirm the issue is OPEN.
- Derive `slug` (lowercase, strip `[...]` prefixes, kebab, first 5 tokens); branch `feature/<N>-<slug>`; verify branch + worktree path are free.
- `git worktree add -b feature/<N>-<slug> <worktree-parent>/<repo-name>-<N> origin/<batch-branch>` — forks from the **current batch tip** so issue N sees N-1's merged code.
- Assign the issue to `@me`, add a `wip` label, post a 📦 "queued" comment (batch branch, story branch, worktree, queue position).
- Log `queued` / `worktree-created` to `run.jsonl`.

### 1.2 The per-issue Workflow
Invoke the **Workflow tool** with the script template in `workflow/per-issue-pipeline.js`, adapted with this run's values (issue number, paths, branch names). The script runs four phases inside the worktree; every agent receives `prompts/shared-standards.md` plus its role prompt:

| Phase | Agents | Model default | Job |
|---|---|---|---|
| **Spec** | 1 × `prompts/spec-agent.md` | strong (`opus`) | Ground every load-bearing claim in the issue against live code; detect no-ops; write the spec (scope, approach, acceptance checks, edge cases, expected diff shape, flags) and post it as an issue comment. |
| **Implement** | 1 × `prompts/implementer.md` | `sonnet` | Build to the spec in the worktree: code + targeted tests + i18n strings (if the project has locales) + AC ticks on the issue. Dep-install preflight (worktrees don't inherit `node_modules`). Full compile before handoff. |
| **Review** | 3 × `prompts/reviewer.md` in **parallel** (correctness / security-and-edge-cases / conventions-and-tests lenses), then 1 fix agent | reviewers strong, fixer `sonnet` | Each reviewer adversarially attacks the diff through its lens and returns structured findings. The fix agent applies every confirmed finding (cheap-and-safe test governs fix-vs-defer), re-runs targeted tests. |
| **Finalize** | 1 × finalize agent (prompt embedded in the script) | `sonnet` | Auto-close-keyword audit, precise staging (never `git add -A`), Conventional-Commits squash-friendly commit, push `-u`, open PR `feature/<N>-<slug>` → `<batch-branch>` with `Refs #<N>`, structured body (spec link, review findings disposition, new markers, deferred items each with `#N`). Returns `pr:<N>` + diff stats. **Stops at PR-open.** |

Workflow mechanics: `schema` on every `agent()` call (structured returns, no terminal-line parsing fragility); a stage that errors retries once inside the script; a second failure returns a structured `failed` result with diagnosis — the script never asks the user anything.

### 1.3 CI gate & merge (orchestrator-owned)
- Watch the PR's checks (`gh pr checks` / statusCheckRollup) — **every** check gates, not just GitHub-"required" ones. Empty rollup = probable registration race: settle ≥90–120s, re-poll, cross-check `gh run list` before any no-CI conclusion. Genuine no-CI repos: full local build + full test suite as explicit merge evidence.
- Green → squash-merge into the batch branch; post-merge audit (gate re-verification; revert the squash off the batch if any gate was missed).
- Red → one bounded fix cycle: spawn a fix agent in the worktree with the failing-check logs; re-push; re-watch. Still red → park (1.5).
- **Ultrareview flag**: compute the PR's risk score — diff > ~400 changed lines, or touches migrations/schema, shared contracts, public APIs, auth, or >10 files. Flagged PRs are recorded for the steering report; `/code-review ultra` is user-triggered and billed, so the pipeline only *recommends* it, never runs it.

### 1.4 Teardown (success path)
Remove the worktree, delete the local story branch (remote stays until batch merge), drop the `wip` label, post a 📦 "merged into batch" comment with the squash SHA, log to `run.jsonl`. Suggest `/compact` to the user every ~3 issues (informational only).

### 1.5 Park (failure path)
After the Workflow's internal retry plus ONE fresh-eyes recovery agent have both failed (or CI can't be made green in one fix cycle):
- Write `<session-folder>/parked-<N>/` — diagnosis, last diff, agent transcripts, failing logs.
- Push the branch as-is to origin; post a 🅿️ comment on the issue (what was attempted, why it failed, branch name, resume hints); remove `wip`, add `parked` label (create tolerantly).
- Remove the worktree. **Continue with the next issue.** Log `parked`.
- A parked issue's changes are NOT in the batch; downstream issues fork from the batch tip as usual.

---

## Phase 2 — Batch QA report & Draft PR

After the queue completes, run a second Workflow (template's `batchQa` section):

1. **Gate runner** (strong model): full test suite + full e2e on the batch branch. Baseline discipline: any failing test is re-run at the base-branch baseline in a throwaway **detached** worktree (never `git stash`) — also-fails-on-baseline = pre-existing debt, reported not fixed. Fixes batch-introduced failures (cheap-and-safe test applies); honest coverage caveats recorded, never rounded up to "none".
2. **Deferral filing**: every deferred annotation across the whole batch (baseline failures, carry-forward gaps) is find-or-REUSED into ONE tracking issue per distinct deferral, `#N` written back into every per-issue PR body that observed it. No "out of scope"/"follow-up" line anywhere without a trailing `#N`. Never defer to a closed issue.
3. **QA-report author** (`prompts/qa-report-author.md`): writes `qa-report.html` into the session folder — a NEUTRAL, EXHAUSTIVE TEST PLAN (never a sign-off) with per-story dossiers, the two always-present sections ("Risks — most likely to be broken", "What automation did NOT cover"), DO-NOT-CHASE callouts (each with `#N`), and the **Parked issues** section so downstream QA knows skipped work is absent, not broken. This file is the input contract for `/fable-guided-qa-orion`.
4. **Draft PR** batch→base: structured body linking every per-issue PR, the QA report path, parked issues, and ultrareview flags.

---

## Phase 2.5 — Retro agent (every run, success or not)

One strong-model agent (`prompts/retro-agent.md`) reads `run.jsonl`, `lessons-learned.md`, parked-issue records, and the QA report, then writes `<session-folder>/proposed-improvements.md` with two sections:
- **Project knowledge** (repo-specific: flaky suites, stack quirks, convention clarifications) → offer to apply to the target repo's `CLAUDE.md` or `.claude/` knowledge file immediately (low risk, locally reviewed later).
- **Skill improvements** (generalized — every project tell stripped, per the skills repo's distribution-safety rule) → presented at the steering point for the user to accept/reject; accepted ones become edits/issues in the skills repo **only on the user's say-so**. The skill never edits its own files.

---

## Phase 3 — Steering point (the second and final human gate)

Print the **steering report** (also saved as `steering-report.md`):
- ✅ merged into batch (issue, PR, squash SHA),
- 🅿️ parked (issue, one-line diagnosis, branch, record path),
- 🔍 flagged for `/code-review ultra <PR#>` (with the trigger reason),
- 📋 QA report path + Draft PR URL,
- 💡 retro proposals summary.

Then **pause and wait indefinitely** for the user's free-form signal — no polling, no timers. "merged" → verify against `gh` (push back if GitHub disagrees) → Phase 4. "closed"/"abandoned" → write the abandoned manifest and exit clean. Anything else (questions, ultrareview findings to fix, parked-issue retries) → handle conversationally and keep waiting.

---

## Phase 4 — Finalize (on "merged")

- Pre-close link check: re-scan every per-issue PR body; file/link any unlinked deferral before closing anything.
- Close each batched issue with an audit comment (branch, PR, squash SHA, QA provenance). Parked issues stay open with their 🅿️ records.
- Write the per-run stats report (`<repo-name>-fable-stats-<timestamp>.html` in the session folder + `~/Downloads/`): issues attempted/merged/parked, retries per issue, durations, finding counts by reviewer lens, run-over-run table appended from previous session folders when present.
- Mark `.session-complete` sentinel (idempotent finalization); clean `scratch/`.

---

## Failure & safety rails (always in force)

- Explicit user "stop"/"halt" mid-run: finish nothing, write the failure record for the in-flight issue, manifest `Status: halted`.
- Session artifacts live OUTSIDE the repo; generated reports are write-once; never touch the user's hand-maintained files.
- Worktree discipline, stash ban, `sed -i` ban, absolute-path rule, precise staging: all in `prompts/shared-standards.md` and binding on every agent.
- Mid-run user messages that aren't "stop": answer briefly; the queue keeps running.
