# CHANGELOG

## v3.2 — Distribution hardening: editor note + final sensitive-data scrub

- **Editor note added.** A `> [!NOTE]` block at the top of `SKILL.md` and `README.md` recommends creating a *new version* (bump the `-vN` suffix) over editing this skill in place, since people and automated workflows may depend on the current behaviour.
- **Final sensitive-data scrub for distribution** (three independent Opus review rounds). Neutralized the last project-specific tells so the skill adapts to any user/repo (only BMAD + GitHub Issues are assumed):
  - A real-looking issue number in the auto-close-keyword example replaced with a generic placeholder (and the auto-close keyword softened to `Refs`).
  - A project-specific DB table name in an Agent D flag example generalized to "an audit/log table".
  - A team-revealing locale set generalized to "confirm each supported locale renders".
  - A project-specific locale-switch key generalized to `localStorage.setItem('<locale-key>', '<lang>')` with a "use the project's actual mechanism" caveat, consistently across both batch-QA prompts.
  - The CHANGELOG's own residual tell ("German persona names") reworded to "Locale-specific persona names".
- **Fixed dangling skill references.** Two pointers to non-existent skills from the original environment (`pick-parallel-issues` in `README.md`, `/pick-next-issue` in `SKILL.md`) now point to the companion issue-selection skill `/assign-issues-orion`, with the surrounding prose corrected to describe what it actually does (select a parallelizable, collision-free set of issues to feed this skill via `@me`).
- No behaviour, logic, or structural changes — scrub + note only.

---

## v3.1 — Drop Phase 3 long-polling; merge signal is now pause-and-converse

- **Removed**: hourly `ScheduleWakeup`-based long-poll for the manual batch→main merge.
- **Removed**: `prompts/phase3-resume.md` (168-line resume prompt the long-poll used to pass to `ScheduleWakeup`).
- **Removed**: ghost-wakeup defenses (Step 0 sentinel gate inside the resume prompt, `ghost-wakeup-skipped` log event, the "ScheduleWakeup queue semantics" rationale).
- **Removed**: Phase 3 compact-cadence-during-wait (`compact-checkpoint` after 12 hours / 3 poll cycles).
- **Replaced** with Phase 3 pause-and-converse: after Phase 2 opens the Draft PR, the orchestrator prints a one-message prompt with the PR URL and the two signals ("merged" → Phase 4; "closed/abandoned" → manifest + exit), then stops. Same pattern §1.7 already uses for per-issue failures.
- **Signal verification**: on "merged", the orchestrator verifies via `gh pr view <pr-number> --json state,mergedAt,mergeCommit`. If GitHub disagrees with the user's claim ("OPEN" state), the orchestrator pushes back conversationally and does NOT run Phase 4.
- **Phase 4 standalone**: no longer embedded inside the resume prompt — now a normal SKILL.md section (4.0 idempotency check → 4.1 verify merge → 4.2 close issues → 4.3 stats report → 4.4 teardown → 4.5 manifest + sentinel). Triggered by the user's signal in Phase 3 OR by direct invocation in finalize mode (`/sequential-bmad-github-orion-v2 finalize <session-folder>` in a fresh session if the original conversation was cleared).
- **`.session-complete` sentinel kept** but its role changed: was idempotency against ghost wake-ups; is now idempotency against manual re-invocation in finalize mode. Step 4.0 checks for it and exits if present.
- **Core Principle #7 reworded**: was "Autonomous through Phase 3"; now "Autonomous through Phase 2, with two upfront human checkpoints" (Phase 0 preconditions + Phase 3 merge signal).
- **Failure handling table updated**: dropped "Phase 3 PR OPEN indefinitely → keep polling"; added "Phase 3 user gives no signal → orchestrator stays paused, no timeout" and "Phase 3 user claims 'merged' but `gh pr view` shows OPEN → push back conversationally".
- **Trade-offs documented**: the only use case that loses something is "merge overnight and let the skill finalize while I sleep." Recoverable by invoking finalize mode in a fresh session the next morning.

---

## v3.0 — Rewrite for distribution + halt-and-converse model

- Renamed skill from `sequential-batch-pipeline-orion-v2` to `sequential-bmad-github-orion-v2`.
- **Symmetric agent terminal contract.** All four per-issue agents now return `agent-status: done`. Agent D's squash SHA moved to a separate `merge-sha: <40-char hex>` line in its return summary. Inferred-terminal-proceed and the `done-is-INVALID-for-D` carve-outs are gone.
- **Stripped reactive MANDATORY/MUST/Reminder warnings** from all agent prompts. One-sentence contracts only (`"Final line of your reply must be `agent-status: done` or `agent-status: incomplete — <reason>`."`); recovery flow stays as the actual defense.
- **Consolidated three auto-close-keyword audit layers into one.** Kept only Agent D step 4b (the pre-push gate). Deleted Agent B no-commit verification + Phase 4.1a post-merge detective audit. Phase 4.2 retains a defensive `gh issue close` against manual close — that's tolerance, not enforcement.
- **Collapsed four parallel registers into one `annotations[]`** with `kind` discriminator (`"failure"` | `"baseline-failure"` | `"carry-forward"` | `"todo"`). Each entry stamps `issue_number`. Aggregation (≥2-issue thresholds, framework-gap dedupe) happens at query time, not at insert time.
- **Split Phase 2 batch-QA into two agents.** 2.2a `test-and-fix` (Opus, owns Gates 1+2+3 + bug fixes + re-verification). 2.2b `pr-author` (Sonnet, owns `qa-report.html` + Draft PR + autonomous additive-resolution conflict handling). Structured fenced ```handoff block carries gate results + fix SHAs.
- **New halt-and-converse failure model** (Core Principle #6 rewrite). Cheap retries + one Opus recovery attempt stay autonomous. When both have failed, the orchestrator pauses the queue, prints the diagnosis + failure-folder path, and waits for the user's free-form direction — no `AskUserQuestion` menu. Revert + GitHub comment + worktree cleanup happen only AFTER the user picks "skip" (or equivalent).
- **Phase 2 Gate retries reduced 10 → 3 cycles.**
- **Phase 2 conflict resolution: autonomous additive-resolution kept; the former Strategy B (targeted revert + retry rebase) and Strategy C (skip with DO NOT MERGE callout) removed — replaced by the same pause-and-converse pattern as §1.7.**
- **Phase 0 batch-size confirmation** when queue > 4. Single `AskUserQuestion`: proceed-all / limit-to-N / cancel. Threshold env-var overridable via `BATCH_PIPELINE_SIZE_PROMPT_THRESHOLD`. Skipped silently for queues ≤ 4.
- **Full PII / project-data scrub.** Locale-specific persona names, project-specific file paths, past-run session-folder names, and legacy back-compat references replaced with semantically-preserving generic equivalents.
- **Spec restructured for distribution.** Orchestrator logic in `SKILL.md`. Agent prompts moved to `prompts/*.md` (orchestrator concatenates shared boilerplate + slot-specific file at spawn time). `README.md` (first-time-user oriented), `PREREQUISITES.md` (external dependencies), and `CHANGELOG.md` (version history) separated out.

---

## v2.5 — anti-halt autonomy + production-ready-code framing + downstream-agent QA report

Changes vs v2.4:

- **Core Principle #1: Production-ready code is the success bar.** Front-matter description + new top-of-list Core Principle. Every other principle now formally serves this bar. Operational definition includes: all tests + e2e green, live-stack QA green, zero regressions, no `Closes #N` leakage, no stubbed/half-implemented surfaces, TODO/FIXME/HACK markers surfaced to user, project conventions adhered to, clean Conventional-Commits history. Existing principles 1-7 shifted to 2-8.
- **Anti-halt autonomy (Core Principle #6 rewrite).** The orchestrator no longer halts mid-queue. New §1.7 "Per-issue failure procedure (skip-and-continue with revert)" defines the full recovery flow: heavy retry → dedicated Opus recovery sub-agent → on persistent failure, revert any partial commits off the batch branch, mark the issue FAILED in a new `failed_issues[]` register, post 🚧 failure comment + write `<session-folder>/failures/<N>-<slug>/` (diagnosis.md + last-state.diff + agent-transcripts/), clean up worktree (story branch RETAINED on origin for manual investigation), surface a one-line chat notice, continue to next issue. Batch branch stays in a known-green state at all times. (Superseded in v3.0 by the halt-and-converse model.)
- **Failure flagging — 4 always-on + 4 end-of-run surfaces.** Every failure surfaces via: (1) GitHub issue 🚧 comment, (2) real-time chat notice to the user, (3) `<session-folder>/failures/<N>-<slug>/` folder with full record, (4) `run.jsonl` event. At end-of-run: (5) Phase 1 queue-end summary printed before batch-QA spawn, (6) Phase 2 qa-report.html's mandatory "Failed issues" slide, (7) Draft batch PR body's top-of-body `⚠️ Failed issues` callout, (8) `manifest.md` with one of five `Status:` values (`succeeded` / `succeeded-with-failures` / `succeeded-with-qa-failure` / `abandoned` / `halted`) plus a "Failed issues" summary section.
- **Hard halts narrowed to two.** Only Phase 0 precondition failures and explicit user "stop" mid-loop halt the skill. Everything else (logical incomplete, terminal-line unrecoverable, runtime crashes, merge conflicts, Gate 1/2/3 unresolvable, batch-QA failed) is a soft failure.
- **Phase 2 conflict-resolution expanded from one 4-gate strategy to three strategies (A → B → C).** (Superseded in v3.0: Strategies B and C removed; Strategy A kept; pause-and-converse for everything else.)
- **Phase 2 Gate retry budget bumped 5 → 10 cycles**, with targeted-revert-via-§1.7 fallback when 10 cycles can't make a gate green. (Superseded in v3.0: budget reduced back to 3 cycles.) Batch-QA failure now opens a Draft PR with a top-of-body `❌ DO NOT MERGE — automated batch QA failed` callout (full reason + qa-report.html link) instead of halting; Phase 3 long-poll still scheduled so the human can resolve manually or close.
- **Crash retry budget bumped 1 → 2 retries per agent slot.** Third crash on the same slot routes to §1.7 instead of halting.
- **Agent D return classification — CI infra-flake auto-rerun.** Agent D `incomplete` reasons are now classified: infra-flake patterns (`setup-bun`/`setup-node`/`setup-dotnet` 401/503, `Failed to fetch url`, `Bad credentials`, `ECONNRESET`) trigger one `gh run rerun --failed` before consuming the recovery path. Real code red goes through recovery agent → §1.7.
- **Agent B no-commit verification.** Orchestrator runs `git log origin/<batch-branch>..HEAD` to verify zero commits when Agent B returns. (Superseded in v3.0: removed in favor of Agent D step 4b as the single audit point.)
- **Agent D pre-push auto-close keyword audit (step 4b — most critical pre-push check).** Before the first push, Agent D MUST scan EVERY unmerged commit via `git log origin/<batch-branch>..HEAD` + per-commit `git show --no-patch --format=%B`, grepping each message for the regex `\b(close[sd]?|fix(es|ed)?|resolve[sd]?)\s+#[0-9]+`. On match: amend (if HEAD) or non-interactive rebase/filter-repo rewrite (if older) to replace every auto-close keyword with `Refs`. Re-grep to confirm clean. (In v3.0 this became the SINGLE audit point.)
- **SendMessage availability probe + inferred-terminal-proceed.** Terminal-line recovery now probes whether `SendMessage` is callable in this harness. If yes, use it. If no (and all three gates hold), apply inferred-terminal-proceed: treat the agent's terminal state as inferred from the parsed summary, log + post audit notice, continue.
- **Failure handling section rewritten.** New tabular layout: 2 hard halts vs N soft-failure paths. Five `Status:` values for `manifest.md`. Cleanup checklist updated.
- **qa-report.html — lean rewrite focused on QA steps + tests.** Restructured from 9 slides to 4 slides, with center-of-gravity moved decisively onto per-story exhaustive QA steps and tests. Dropped slides: Stories-shipped table, standalone i18n verification, Bugs-found, Cross-story integrations, Pre-existing baselines (collapsed to Cover callout), Carry-forwards (same), Downstream-agent guidance, Machine-readable JSON manifest, Developer Evidence appendix. New 4-slide structure: (1) Cover with DO-NOT-CHASE callouts; (2) How to start the stack; (3) Per-story dossiers — short intro + exhaustive QA steps covering Acceptance criteria, Click-paths, Edge cases, Negative tests, Persona/role variants, i18n/locale checks, Cross-story spot-checks; (4) Failed issues table (omitted entirely when no failures). Stable IDs preserved per story so downstream agents can deep-link.
- **TODOs allowed but flagged loudly.** Per Core Principle #1, `TODO`/`FIXME`/`HACK`/`XXX` markers are allowed but MUST be surfaced. Agent C adds step 5b — grep the diff for new markers, post one 🔍 Review note per marker, include the structured list in the return summary; Agent D passes the list through into both the PR body (new `## TODOs introduced by this story` section) and the return summary; orchestrator parses Agent D's field into a run-level register (in v3.0: into the unified `annotations[]` register with `kind: "todo"`); Phase 2 batch-QA renders a Cover callout when total markers > 0 plus an optional "TODOs introduced" section per story dossier. Markers are NEVER auto-removed or downgraded.
- **Carry-forward framework-gaps register.** New Agent D return field `Carry-forward framework gaps` carries STRUCTURED entries (count + list with one bullet per gap). Sourced from Agent A's scope decisions, TODO(post-epic) comments, and Agent C's "out of scope but worth knowing" review notes. Orchestrator parses into a run-level register (in v3.0: into `annotations[]` with `kind: "carry-forward"`); normalizes gap text and detects ≥2-issue repeats as framework gaps the QA agent must NOT report as bugs.
- **Status HTML decommissioned; replaced with per-run stats report HTML.** Phase 4.3 no longer touches any long-lived `<repo-name>-status-*.html` deck (user owns that). Replacement: Phase 4.3 generates a fresh `<repo-name>-stats-<DD_MM_YYYY>-<HH_MM>.html` in `~/Downloads/` each run (never modified, never deleted) containing live `gh issue list` snapshots: stories/issues pending+closed, current velocity (cal+work day), three-scenario linear-forecast finish dates, optional target-rate analysis (gap vs target deadline if `project_target_date.md` memory file is present), per-person breakdown (totals + daily rates + share + speed classification), confidence indicators (cycle time avg/median/max, stale-open count, hygiene), and composition (open per epic, open per assignee, per-person delta this batch vs running average). Run-level log checkpoint renamed `status-html-updated` → `stats-report-written`.

---

## v2.4 — six lessons from a multi-issue batch run encoded as inline contract / orchestration changes

Changes vs v2.3:

- **Agent terminal-line contract — explicit INVALID list + SendMessage recovery.** Each agent's return-summary block ended with an explicit "Reminder before returning" listing the ONLY valid `agent-status:` values plus the most common invented sentinels (`terminal`, `complete`, `finished`, `ok`, `success`, `green`, plus `done` as INVALID for Agent D). When the line was missing/invalid but the rest parsed and described a terminal outcome, the orchestrator used ONE `SendMessage` follow-up per agent slot. (Superseded in v3.0: symmetric `done` contract; reminders stripped to one sentence.)
- **Sub-agent scratch-file contract.** New paragraph in the shared boilerplate: all intermediate scratch files MUST go to `<session-folder>/scratch/<agent-slot>/`. Phase 0 step 7 creates `<session-folder>/scratch/`.
- **Agent D auto-close-keyword ban extended to commit messages.** The ban on `Closes`/`Close`/`Fixes`/`Fix`/`Resolves`/`Resolve` + `#<N>` now covers the PR body, the commit subject, the commit body, AND any commit footer. Phase 4 step 4.1a greps each per-issue squash commit for auto-close keywords. (Superseded in v3.0: 4.1a removed; Agent D step 4b is the single enforcement point.)
- **Phase 4.3a status-HTML multi-method discovery.** Three independent listing methods (Get-ChildItem -Filter, glob-path Get-ChildItem, Test-Path against today/yesterday date-stamped names), logged to `run.jsonl`. (Superseded in v3.0: status HTML decommissioned, stats report replaces it.)
- **Cross-queue baseline-failure aggregation.** Orchestrator dedupes "Pre-existing baseline failures observed" lists into a `baseline_failures_by_file` map. Phase 2 Pre-flight step (d) injects a `<priority-baseline-list>` (files reported by ≥2 issues) into the batch-QA prompt. (In v3.0 this lives in the unified `annotations[]` register with `kind: "baseline-failure"`.)
- **Long-batch drift warning + autonomous additive rebase under 4 gates.** Phase 0 step 5c soft warning when queue > 4 issues. (Superseded in v3.0: hard checkpoint with AskUserQuestion.) Phase 2 merge-conflict handling permits autonomous additive resolution when ALL FOUR gates pass: ≤2-3 files, written recipe, dev-handoff notes documenting complementary intent, targeted-test safety net.

---

## v2.3 — four lessons from an earlier batch run encoded as inline agent steps

Changes vs v2.2:

- **Agent A — bug-fix issue precheck.** For issues labelled `bug` or whose title/body uses fix/broken/flaky/regression vocabulary, Agent A reads the failing test/code end-to-end BEFORE adopting the issue's stated root cause. If the reading contradicts the issue, Agent A corrects via 🔗 Dev note + bakes the corrected diagnosis into the story.
- **Agent B — worktree dep install preflight.** New step 3: in JS-package-manager projects (`package.json` + lockfile), run the matching install command (`bun install` / `pnpm install` / `npm install` / `yarn install`) in the fresh worktree before any test/build command.
- **Agent C — factual-claims verification.** New step 5: scan the diff for newly-added xmldoc/docstrings/comments making verifiable factual claims (DB constraint names, schema columns, file paths, status codes), grep the referenced source for each, treat mismatches as review findings + fixes.
- **Agent D — baseline-vs-regression check.** Before treating any failing test as a regression, `git stash --include-untracked` + re-run on the batch baseline. Pre-existing failures are noted under a "Pre-existing baseline failures (out of scope)" section in the PR body and flagged in the return summary for batch-QA — NOT fixed.

---

## v2.2 — cosmetic-rename generalization + scannable PR title + digital-clock timestamp + lessons-learned + Phase 0 precondition check + dedupe

Changes vs v2.1:

- **BMAD + GH-issues precondition check at Phase 0 step 0.** ONE upfront AskUserQuestion before any git/gh work, confirming both assumptions. Auto-skip if BMAD slash-commands are detected in the harness AND `gh auth status` succeeds.
- **Lessons-learned file auto-created in session folder.** `<session-folder>/lessons-learned.md` is append-only, owned by orchestrator + every sub-agent. Higher-signal than `run.jsonl`.
- **Project-name substitution.** Branch names, folder names, and stats-HTML filenames are derived from `<repo-name>`, resolved at Phase 0 step 6 via basename → memory override → ask-and-remember-if-generic. Memory key is the git remote URL.
- **Timestamp format.** Session folder + batch branch use `DD_MM_YYYY-HH_MM` (filename-safe on Windows; minute-resolution).
- **Session folder gets issue suffix.** `~/Downloads/batch-<repo-name>-<timestamp>-i<N1>-<N2>-<N3>/`.
- **Batch PR title format.** `[batch] <user> — <count> issues (#<N1>, #<N2>, #<N3>, ...) — <date>`. Hash-prefixed issue numbers auto-link on GitHub.
- **Version banner timestamp.** `DD-MM-YYYY HH:mm` instead of ISO 8601.
- **Update-history slide.** Dedicated `<section class="slide" data-update-key="update-history">` inserted on first Phase-4 update; subsequent runs append ONE `<li>` row. (Superseded in v2.5: status HTML decommissioned.)
- **Dedupe pass.** ~25 lines pure duplication removed across "Does NOT do", Implementation notes, and "Specific halt conditions"; no behavior change.

---

## v2.1 — generalization of v1 for distribution

Derived from the v1 predecessor's lessons file (24 findings across the first end-to-end run). Notable changes vs v1:

- **Generalized for distribution.** No project-specific paths, tool commands, file names, or conventions. Agents detect everything from project files.
- **Autonomous from start to Phase 3 schedule.** No cost-protection confirm; no Phase-2 transition question; no Phase-3 scheduling question.
- **Explicit-ordering respect.** If the user passes a numeric list, that order is honored — the heuristic is skipped.
- **Clean-tree gate softened.** Only staged changes block; untracked files outside the run scope are logged but allowed.
- **Pre-handoff full build at Agent B.** Cross-project compile-break catches shift from Opus Agent C to cheap Sonnet Agent B.
- **Cross-shell filesystem ops.** Both PowerShell and Bash forms documented for teardown.
- **Non-story issues get a filename convention.** `_bmad-output/implementation-artifacts/<N>-<slug>.md`.
- **`/compact` no longer "invoked" by the orchestrator.** It's a CLI command — orchestrator logs a checkpoint and surfaces a recommendation.
- **Environmental halt escape hatch for Gate 3 Step B.** If stack startup fails for environmental reasons (TLS, ports, sandbox limits) the QA agent may substitute equivalent coverage with documented conditions.
- **Phase 4 procedure inlined verbatim in the Phase 3 resume prompt.** No more paraphrasing the long Phase 4.3 stats-report logic — it's copy-pasted into the ScheduleWakeup prompt (Finding #26).
- **Junior-tester QA report.** The qa-report.html's main slide is a browser-only click-path walkthrough — no xUnit filter strings, no curl commands, no SQL in the user-facing slides. Developer commands isolated to a "Developer Evidence" appendix. (Restructured in v2.5.)
- **Compact cadence 12h in Phase 3** (was 6h in v1).
