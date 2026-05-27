---
name: sequential-bmad-github-orion-v3
description: |
  Fully automated sequential GitHub-issue execution against a batch feature branch.
  **The purpose of this skill is to produce PRODUCTION-READY code** — every batched
  issue must ship in a state a senior dev would merge to main without follow-up work.
  **Assumes BMAD methodology** (slash commands `/bmad-create-story`, `/bmad-dev-story`,
  `/bmad-code-review` available) AND **GitHub Issues as source of truth** — the
  orchestrator confirms both preconditions with the user at Phase 0 before doing
  anything else. Per issue runs a four-agent pipeline (Opus create-story → Sonnet
  dev-story → Opus code-review → Sonnet build/PR/CI/merge into batch); a per-issue
  PR never merges into the batch with red or still-pending CI. After the
  queue: a two-agent batch-QA pipeline (Opus test-and-fix → Sonnet pr-author)
  that runs full tests, full e2e, a live-stack Junior-tester QA gate, writes a
  qa-report.html, files-and-dedupes every deferred annotation (pre-existing
  baseline failures, carry-forward gaps) into find-or-create tracking issues and
  links the resulting #N back into the per-issue PR bodies (so no deferral leaks
  unlinked), then opens a Draft PR batch→main. The skill then pauses and
  waits for the user's "merged" / "closed" signal — no polling. On "merged" it
  closes the batched issues and writes a fresh per-run stats report HTML to
  ~/Downloads/. Strict one-issue-at-a-time serialization. Build/test commands
  auto-detected from project files.
---

# sequential-bmad-github-orion-v3

> [!NOTE]
> **Thinking of editing this skill?** Prefer creating a *new version* — copy it to a new skill name (e.g. bump the `-vN` suffix) — and leave this one as-is. People and automated workflows may rely on the current behaviour, so versioning beats editing in place.

You are the **ORCHESTRATOR** running on `main` in the user's repo. You drive a strict one-at-a-time sequential execution of a user-supplied list of GitHub issues against a single shared **batch feature branch**. Per issue you spawn a four-agent pipeline (A=create-story Opus → B=dev-story Sonnet → C=code-review Opus → D=build/PR/CI/merge Sonnet). After the queue completes you spawn the two-agent batch-QA pipeline (2.2a `test-and-fix` Opus → 2.2b `pr-author` Sonnet) which runs full tests + e2e + live-stack QA, writes `qa-report.html`, and opens a Draft PR batch→main. You then **pause and wait for the user's free-form signal** ("merged" → run Phase 4; "closed/abandoned" → write the abandoned manifest and exit). On "merged" you close every batched issue and write a fresh `<repo-name>-stats-<DD_MM_YYYY>-<HH_MM>.html` to `~/Downloads/`. The skill never touches the user's hand-maintained `<repo-name>-status-*.html` deck.

You do not invoke any skill yourself except `/compact` checkpoints (logged but not user-blocking). You prep worktrees + GitHub state, spawn sub-agents, tear down, and move on. The sub-agents do the actual work.

This skill is **project-agnostic.** Agents detect the build/test toolchain from the project's files (`package.json`, `*.csproj`, `*.slnx`, `pyproject.toml`, `Cargo.toml`, `Makefile`, etc.) and from any project docs (`CLAUDE.md`, `README.md`, `CONTRIBUTING.md`).

---

## Core principles

1. **Production-ready code is the success bar.** Every batched issue ships in a state a senior dev would merge to main without follow-up: all tests + e2e green; live-stack QA green; zero regressions vs batch baseline; no `Closes #N` keyword leakage; no stubbed surfaces (every AC actually wired); TODO/FIXME/HACK markers surfaced (not buried); project conventions followed; Conventional-Commits clean history (one squash per issue). **A per-issue PR is merged into the batch ONLY when its CI is fully green — never with a red, errored, cancelled, or still-pending required check** (enforced by Agent D's pre-merge re-check, §1.4 / Agent D step 8b, and backstopped by an orchestrator post-merge audit in §1.5). Every other principle serves this bar.
2. **GitHub issue is the SOURCE OF TRUTH for status.** Every milestone is an issue comment. Never write to BMAD `sprint-status.yaml`, `epics-done.md`, or similar. BMAD story files + code-review reports are dev aids and audit trail, not status.
3. **Issues stay OPEN until batch→main lands.** Per-issue PRs target the batch branch with `Refs #<N>` (NOT `Closes #<N>`). Phase 4 closes each batched issue explicitly after detecting the manual batch→main merge.
4. **Strict serialization.** Issue `i+1` cannot start until issue `i` is merged into the batch branch and its worktree torn down. No parallel branches or worktrees.
5. **Four sub-agents per issue (model-mixed); two sub-agents for batch QA.** Each agent has ONE bounded job matching the natural terminal state of its BMAD skill.
6. **Autonomous through cheap retries + one recovery attempt; pause and converse when both have failed.** The orchestrator handles transient failures without bothering the user: per-slot crash retries (2), terminal-line recovery (1 SendMessage), and one dedicated Opus recovery sub-agent on `incomplete`. If all of those fail, the orchestrator PAUSES the queue: prints the diagnosis + failure-folder path, then stops and waits for the user's free-form direction. No `AskUserQuestion`, no multi-option menu — just diagnosis + halt + conversation. The user picks skip / retry / fix-manually / abort. Revert + GitHub comment + worktree cleanup happen only AFTER the user picks "skip" (or equivalent). The only OTHER hard halts are Phase 0 precondition failures and explicit user "stop" mid-loop.
7. **Autonomous through Phase 2, with two upfront human checkpoints.** Exactly ONE user question at Phase 0 (BMAD + GitHub-Issues preconditions, plus the repo name if ambiguous). After that: no user question between Phase 1 and Phase 2. The skill runs end-to-end through the Draft PR autonomously. At Phase 3 it pauses and waits for the user's free-form merge signal ("merged" → Phase 4, "closed" → abandoned). No polling, no `ScheduleWakeup`, no auto-finalize — the merge signal is the second and final human-in-the-loop point.
8. **Project conventions stick.** Sub-agents follow `CLAUDE.md` / `CONTRIBUTING.md` / `README.md`. Orchestrator does not commit code itself.
9. **Every deferral leaves a tracked `#N`.** The pipeline detects deferred work (pre-existing baseline failures, carry-forward framework gaps, TODOs) — but detection without filing is how work leaks. Before the Draft PR opens, the `pr-author` finds-or-creates ONE tracking issue per distinct deferral (whole-batch deduped) and writes the resulting `#N` back into every per-issue PR body that observed it (Phase 2, "Deferral filing"). No PR body may carry an "out of scope" / "pre-existing baseline failures" / "follow-up" line without a trailing `#N`. Phase 4 re-checks this before closing each issue (§4.2). Find-or-**reuse** is mandatory: search existing open issues first; never open a fresh duplicate per run. (Principle #9 governs how *tracked* deferrals are recorded; **Principle #10 governs whether something should defer at all** — apply #10 first.)
10. **Fix-in-place-first; defer is the fallback, not the default.** A deferral is only as good as the work it *avoids needing later* — and the pipeline's rich tracking machinery (#9) makes deferring frictionless, which biases agents toward filing an issue for things they could just fix now. This principle is the counterweight. Before any code-review finding, adjacent bug, or small gap is routed into the deferral machinery, it must first FAIL the **cheap-and-safe test**. A finding is **fixed now, in the current PR** when ALL of these hold:
   - **Small** — bounded, single-concern change (rule of thumb: a handful of lines / one function or one file; no broad refactor).
   - **Local** — in code the current story already touches, or directly adjacent to it.
   - **Covered** — exercised by tests already running in this pipeline, or trivially coverable by adding one.
   - **Low blast-radius** — no DB schema/migration, no shared-contract or public-API change, no cross-cutting behavior change, no new dependency.
   - **Scope-neutral** — does not expand the story's user-facing scope or pull in a different feature slice.

   A finding is **deferred (and then tracked per #9)** only when it FAILS the test — i.e. it is large, cross-cutting, touches a shared contract/schema/migration, needs a product or design decision, or belongs to a different slice. **"It wasn't in the story's ACs" is NOT, by itself, a reason to defer** — if the cheap-and-safe test passes, fix it. Each deferral names the single criterion it failed (e.g. "defer: blast-radius — touches shared auth contract"), so the choice is auditable. When genuinely uncertain about blast-radius, defer (safety wins ties). This applies to Agent B (opportunistic fixes in touched code), Agent C (adjacent code-review findings), and the batch-QA `test-and-fix` gate (anything not in its hard SCOPE EXCLUSIONS).

---

## Per-issue 4-agent pipeline

| Agent | Job | Model | Why this model |
|---|---|---|---|
| **A** | `/bmad-create-story` → produce BMAD story file | Opus | Strategy + scope decisions; getting the spec right is high-leverage |
| **B** | `/bmad-dev-story` → implement code + targeted tests + i18n + AC ticks | Sonnet | Longest token-spending step; Agent C catches slips |
| **C** | `/bmad-code-review` against the uncommitted diff → auto-fix every finding | Opus | Critical-thinking step; do not cheap out |
| **D** | Full build + full tests + commit + push + PR + wait CI green + squash-merge into batch | Sonnet | Mostly mechanical bash + waiting; retries cap at 5 per command |

Each agent operates inside the same worktree, reading and writing on-disk state. Handoff happens through the worktree, not through agent memory. The orchestrator chains them.

---

## Input parsing

Args are an issue specifier: a mix of bare numbers, ranges, lists, and the `@me` shortcut.

| Form | Example | Parsed |
|---|---|---|
| Single | `230` | `[230]` |
| Space-list | `230 231 232` | `[230, 231, 232]` |
| Comma-list | `230,231,232` | `[230, 231, 232]` |
| Range | `230-235` | `[230, 231, 232, 233, 234, 235]` |
| Mixed | `230 232-234,237` | `[230, 232, 233, 234, 237]` |
| Assigned-to-me | `@me` or `--mine` | result of `gh issue list --assignee @me --state open --limit 50 --json number` |

Parse rules:
- Whitespace and commas are equivalent separators. Ranges inclusive, ascending only (`235-230` → error).
- Dedupe while preserving first-seen order.
- **No args → default to `@me`** (solo-developer is the dominant use case).
- **Explicit numeric list → honor caller-supplied order; skip the Phase 0 heuristic.** The user's deliberate ordering signal is preserved.
- `@me` resolving to zero issues → exit cleanly with "No open issues assigned to you. Assign yourself some via `gh issue edit <N> --add-assignee @me` and re-run, or pass explicit numbers."

**Validate every issue** via `gh issue view <N> --json number,title,state,assignees,labels,url`: each must be `state: OPEN` and either unassigned or assigned to the current user. List all violations at once and stop. Do not partially run.

---

## Per-issue state

Working memory (also reflected in `run.jsonl` + the GitHub issue, which are authoritative):

```
issue_number, title, slug, branch_name, worktree_path,
phase ∈ {pending, dev-running, merged-into-batch, failed},
pr_number, pr_url, merge_sha, started_at, finished_at
```

Plus one run-level register consumed by Phase 2 batch-QA + Phase 4 finalize:

```
annotations[]  ← list of { issue_number, kind, ...kind-specific fields }
                 where kind ∈ {
                   "failure"          → { slug, failed_at_phase, diagnosis,
                                          recovery_attempts, failure_folder }
                                        (populated by §1.7)
                   "baseline-failure" → { test_file }
                                        (from Agent D's "Pre-existing baseline failures observed")
                   "carry-forward"    → { gap, owning_framework, affects_this_story, raw_text }
                                        (from Agent D's "Carry-forward framework gaps")
                   "todo"             → { file, line, marker, text }
                                        (from Agent D's "TODOs introduced", pass-through
                                         of Agent C's step-5b scan)
                 }
```

Phase 2 pre-flight queries by `kind`. Aggregation (e.g. baseline-failure files reported by ≥2 issues = priority; carry-forwards with the same normalized `gap` across ≥2 issues = `is_framework_gap`) is applied at query time, not at insert time.

A second run-level register, `filed_deferrals[]`, is populated in Phase 2 from `pr-author`'s `deferrals-filed` return — one entry per distinct deferral that got a tracking issue: `{ kind, key (test_file | normalized gap), issue_number (#N filed/reused), action ∈ {created, reused}, linked_prs[] }`. It feeds the Phase 4.3 scope-ledger panel and the §4.2 pre-close check's "already linked?" determination.

**`slug` derivation:** lowercase title → strip leading bracketed prefix (`[Story 3.1]`, `[Bug]`, `[Feature]`) and whitespace → kebab-case (whitespace + non-alphanumeric runs → single hyphens; trim) → keep first 5 word-tokens → strip remaining non-alphanumeric (preserve hyphens).

Examples: *"Add user invitation flow for admins"* → `add-user-invitation-flow-for` · *"[Story 3.1] PostgreSQL as Primary Read Layer"* → `postgresql-as-primary-read-layer`.

---

## Session artifacts

### Session folder

```
~/Downloads/batch-<repo-name>-<timestamp>-i<N1>-<N2>-<N3>/
├── run.jsonl              ← append-only log (one JSON object per line)
├── lessons-learned.md     ← append-only findings log (for SKILL improvement, not status)
├── qa-report.html         ← created at end of Phase 2 by pr-author
└── manifest.md            ← written at end of Phase 4 (success) or on halt
```

Preserved on success for later inspection. The user's long-lived status presentation stays at `~/Downloads/` root and is never moved into the session folder.

### Lessons-learned file

`<session-folder>/lessons-learned.md` is an append-only findings log for **skill self-improvement** — separate from `run.jsonl` (mechanical events) and GitHub comments (status). The user reads it after the run to harvest improvements for the next skill version.

**Created at Phase 0** with this template (append-only afterwards):

```markdown
# Lessons learned — batch-<repo-name>-<timestamp>-<issue-suffix>

> Append-only. Each finding is a fenced block. Do not rewrite earlier findings.
> Format legend: ⚠️ Concern · 🐛 Bug · 💡 Improvement · ✅ Worked well

## Run snapshot
- Started: <ISO timestamp>
- Batch branch: <batch-branch>
- Batched issues: #<N1>, #<N2>, ...
- Session folder: <session-folder>

## Findings
<!-- append below; one fenced block per finding -->
```

**Append-finding format** (orchestrator + every sub-agent use verbatim):

```markdown
### <icon> Finding #<N> — <one-line title>

**Source:** <orchestrator | agent-A-issue-<N> | ... | batch-qa-test-and-fix | batch-qa-pr-author>
**Phase:** <phase-name>
**When:** <ISO timestamp>

<2-6 sentences describing what happened, why it matters, any workaround applied.>

**Suggested skill change** (optional): <one-line proposal for the next skill version, or "None">
```

Append when something surprising / blocking / notably-smooth happens (precondition mismatch, environmental quirk, workaround worth promoting, behavior that worked surprisingly well). Mundane progress goes to `run.jsonl`, not here.

### Batch branch + timestamps

Resolve once at Phase 0:
- `<gh-login>` = `gh api user --jq .login`
- `<repo-root>` = `git rev-parse --show-toplevel`
- `<repo-name>` = Phase 0 step 6 resolution (basename → memory override → ask-and-remember if ambiguous)
- `<worktree-parent>` = parent dir of `<repo-root>`
- `<timestamp>` = local time formatted `DD_MM_YYYY-HH_MM` (filename-safe on Windows; minute resolution)
- `<issue-suffix>` = `i<N1>-<N2>-<N3>-...` (every batched issue number joined with hyphens, prefixed with `i`)
- `<batch-branch>` = `batch/<gh-login>/<repo-name>-<timestamp>`
- `<session-folder>` = `~/Downloads/batch-<repo-name>-<timestamp>-<issue-suffix>/`
- `<stats-report>` = `~/Downloads/<repo-name>-stats-<DD_MM_YYYY>-<HH_MM>.html` resolved at Phase 4.3 write time (TODAY's local date + current local time, NOT the Phase-0 timestamp; the skill never modifies or deletes existing `<repo-name>-stats-*.html`, and NEVER touches any long-lived `<repo-name>-status-*.html` deck)

### Log file (JSONL)

Append-only at `<session-folder>/run.jsonl`. Each line:

```json
{"ts":"<ISO-8601>","source":"orchestrator|story-<N>|batch-qa","story":<N|null>,"phase":"<phase>","status":"info|pass|fail|blocked","detail":"<short>"}
```

Sub-agents report back; the orchestrator transcribes their results when they return.

**Required checkpoints:**
- Run-level: `queue-start`, `batch-branch-created`, `session-folder-created`, `compact-checkpoint`, `queue-end`, `batch-qa-spawned`, `batch-qa-returned`, `deferral-filing-map-built`, `deferrals-filed`, `wait-start`, `wait-poll`, `merge-detected`, `finalize-start`, `finalize-end`, `stats-report-written`, `session-complete`.
- Per issue: `queued`, `branch-created`, `worktree-created`, `issue-prepped`, `agent-A-spawned`, `agent-A-returned`, ... (analogous for B/C/D), `pre-merge-ci-gate-pass` or `pre-merge-local-gate-pass` (Agent D step 8b — exactly one per merged issue, depending on whether CI ran), `post-merge-ci-audit-clean` (or `red-ci-merge-detected` on a gate miss), `merged-into-batch`, `cleanup-complete`.
- Phase 4: `pre-close-link-check-clean` (or `deferral-linked-before-close`) per issue, then `issue-closed`.

### Manifest

Written at end-of-run (`succeeded` / `succeeded-with-failures` / `succeeded-with-qa-failure` / `abandoned` / `halted`) to `<session-folder>/manifest.md`:

```markdown
# batch-<repo-name>-<timestamp>-<issue-suffix>

**Status:** <one of the five>
**Batch branch:** <batch-branch>
**Draft PR (batch→main):** <pr-url-or-N/A>
**Final merge SHA on main:** <sha-or-N/A>
**Total wall time:** <duration>

## Issues
| # | Title | Per-issue PR | Merged into batch | Status |
|---|---|---|---|---|
| 230 | Add user invite flow | https://...#101 | a1b2c3d | ✓ merged |
| 231 | Refactor auth flow | https://...#102 | (reverted) | 🚧 failed at Agent C — see failures/231-refactor-auth-flow/ |

## Artifacts
- run.jsonl
- qa-report.html
- <repo-name>-stats-<DD_MM_YYYY>-<HH_MM>.html (one fresh file per run in ~/Downloads/)
- failures/<N>-<slug>/  (one folder per failed issue, only when Status includes -with-failures or -halted)

## Failed issues (if any)
| # | Slug | Failed at slot | Diagnosis (one-line) | Failure folder |
|---|---|---|---|---|
| 231 | refactor-auth-flow | C (code-review) | Recovery agent flagged contradictory spec | failures/231-refactor-auth-flow/ |

## QA failure detail (if Status == succeeded-with-qa-failure)
<reason from batch-qa-status>

## Halt detail (if Status == halted)
<diagnosis>
```

---

## Sub-agent prompts (lives under `prompts/`)

Every agent prompt is split into a self-contained file under `prompts/`. The orchestrator **concatenates the appropriate boilerplate + the slot-specific file** at spawn time, then substitutes every `<bracketed-placeholder>` from the run state before passing to the Agent tool.

Two boilerplates exist because per-issue agents and batch-QA agents operate on different worktrees:

- **`prompts/shared-boilerplate.md`** — per-issue context. Placeholders: `<worktree-parent>/<repo-name>-<N>`, `feature/<N>-<slug>` story branch, single `<issue_url>`, queue position `<i> of <total>`, "X of 4 agents" identity.
- **`prompts/shared-boilerplate-batch-qa.md`** — batch-QA context. Placeholders: `<worktree-parent>/<repo-name>-batch-<timestamp>` batch worktree, `<batch-branch>` (the branch under QA), the batched-issues list, "X of 2 batch-QA agents" identity. Includes e2e + dev-stack startup hints in the project-tool-detection block.

Both boilerplates share the same universal contracts (return-summary, project-rules, source-of-truth, lessons-learned, scratch-file) — repeated verbatim in each file to keep the spawned prompt self-contained.

| Slot | Prompt file | Boilerplate | Model |
|---|---|---|---|
| Agent A (create-story) | `prompts/agent-a-create-story.md` | `shared-boilerplate.md` | Opus |
| Agent B (dev-story) | `prompts/agent-b-dev-story.md` | `shared-boilerplate.md` | Sonnet |
| Agent C (code-review) | `prompts/agent-c-code-review.md` | `shared-boilerplate.md` | Opus |
| Agent D (finalize) | `prompts/agent-d-finalize.md` | `shared-boilerplate.md` | Sonnet |
| Recovery sub-agent (§1.7) | `prompts/recovery-agent.md` | `shared-boilerplate.md` | Opus |
| Batch-QA 2.2a (test-and-fix) | `prompts/batch-qa-test-and-fix.md` | `shared-boilerplate-batch-qa.md` | Opus |
| Batch-QA 2.2b (pr-author) | `prompts/batch-qa-pr-author.md` | `shared-boilerplate-batch-qa.md` | Sonnet |

---

## Phase 0 — Run setup (one upfront precondition check, then autonomous)

0. **Precondition confirmation.** Before any git/gh, surface ONE `AskUserQuestion` confirming the two non-negotiable assumptions. Skip ONLY if `/bmad-create-story` is in the harness's available-skills AND `gh auth status` succeeds AND `gh repo view --json defaultBranchRef` succeeds — print a one-line "Auto-detected BMAD + authenticated gh + GitHub repo found; precondition check skipped" and proceed. Otherwise ask:

   ```
   Question: "Before this skill runs, confirm two preconditions so it doesn't fail mid-pipeline."
   Options (multiSelect: true):
     1. "BMAD methodology is set up (Recommended)"
        description: "/bmad-create-story, /bmad-dev-story, /bmad-code-review are available. Without BMAD the pipeline halts at Agent A."
     2. "GitHub Issues are this project's source of truth (Recommended)"
        description: "Every batched issue exists in GitHub; status flows through issue comments; gh issue view/edit/comment/close works. If your team uses Jira/Linear/etc., this skill is the wrong tool."
   ```

   Both must be selected. Else halt: "This skill assumes BMAD + GitHub Issues. Both must be in place — see skill description." Exit cleanly without creating branches or session folder.

1. **Verify cwd**: `git rev-parse --show-toplevel` resolves cleanly; capture `<repo-root>`. Not in a git repo → stop.
2. **Verify branch**: `git rev-parse --abbrev-ref HEAD` must be `main` (or `master` if the repo's default — check `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`).
3. **Verify working tree**: `git status --porcelain` must show no STAGED changes. Untracked files outside run scope are OK (log, don't block). Modified tracked files BLOCK.
4. **Sync main**: `git fetch origin <default-branch> && git pull --ff-only origin <default-branch>`. Non-fast-forward → stop.
5. **Parse + validate args.** No args → `@me`.

5b. **Queue ordering**:
   - Explicit numeric list → honor caller order; skip heuristic.
   - Otherwise auto-order: fetch issue bodies + labels; topo-sort by strong dependency edges (`depends on #N`, `blocked by #N`, `after #N`, etc.; refuse on cycles → halt with "Cyclic dependencies between #A and #B. Resolve in GitHub or pass explicit ordering."). Within independent slots, rank by blast radius (riskiest first): `bug` label → tech-debt/refactor/breaking-change → infrastructure/schema/migration → UI/visual last → oldest `createdAt` as tie-break.
   - **Print resolved order with one-line per-issue reasoning.** No confirmation question. Proceed.

5c. **Batch-size confirmation checkpoint.** Threshold = 4 (override via env var `BATCH_PIPELINE_SIZE_PROMPT_THRESHOLD`). If queue > threshold, ONE `AskUserQuestion` before any branch/folder creation:

   ```
   Question: "Batch contains <N> issues. Estimated wall time ~<N×60>min (varies with suite duration). Estimated <N×4 + 2> sub-agent spawns. Each issue runs sequentially."
   Options (single-select):
     1. "Proceed with all <N> issues"
        description: "Run the full queue as-is."
     2. "Limit to first <threshold> issues (Recommended)"
        description: "Truncate to the first <threshold>; remaining <N-threshold> stay assigned to you for a follow-up run."
     3. "Cancel — let me re-think the queue"
        description: "Exit cleanly without creating branches or folders."
   ```

   If queue ≤ threshold, skip silently. On "Limit", truncate the resolved queue. On "Cancel", exit cleanly (no session folder, no batch branch). Log `batch-size-checkpoint` with the decision.

6. **Resolve identity + paths**:
   - `<gh-login>` = `gh api user --jq .login`
   - `<worktree-parent>` = parent of `<repo-root>`
   - `<repo-name>` resolution: (1) basename of `git rev-parse --show-toplevel`; (2) memory override at `~/.claude/projects/<harness-project-key>/memory/project_skill_repo_name.md` keyed by `git remote get-url origin` (a rename of the local clone keeps the override); (3) if basename matches the generic denylist (`src`, `repo`, `code`, `work`, `project`, `projects`, `my-project`, `dev`, `tmp`, `temp`, `clone`, `checkout`) AND no memory override applies → ONE `AskUserQuestion` ("The local folder name `<candidate>` looks generic. What name should this skill use for branches, folders, and the per-run stats-report HTML?") with `gh repo view --json name --jq .name` as the recommended option, save the answer to the memory file; (4) else use the basename.
   - `<timestamp>` = local time `DD_MM_YYYY-HH_MM`
   - Derive `<issue-suffix>`, `<batch-branch>`, `<session-folder>` per "Batch branch + timestamps" above.

7. **Create session folder** (stop if it already exists). Also create `<session-folder>/scratch/` as the root for sub-agent scratch files. Agents create their own per-slot subdirectories on demand.

8. **Open log file** at `<session-folder>/run.jsonl`. Write `queue-start` with full issue list, batch branch, gh-login, repo name.

8b. **Create lessons-learned file** at `<session-folder>/lessons-learned.md` with the template above (zero findings initially).

9. **Create batch branch** from latest main and push:
   ```
   git branch <batch-branch> <default-branch>
   git push -u origin <batch-branch>
   ```
   Verify with `git ls-remote --exit-code origin <batch-branch>`. Log `batch-branch-created`.

10. **Stale stack-lock cleanup**: read `~/.claude/dev-stack.lock` if present; if recorded PID is dead, remove.

11. **Print run plan** (ordered queue, batch branch, session folder, expected worktree paths). **No confirmation.** Proceed.

---

## Phase 1 — Per-issue loop

For each issue `N` in queue order:

### 1.1 Pre-flight (orchestrator)

a. Re-sync batch branch locally: `git fetch origin <batch-branch>`. (Orchestrator stays on main.)
b. Stale stack-lock: clear if PID dead.
c. Re-fetch the issue: confirm state is OPEN.
d. Derive slug + branch name `feature/<N>-<slug>`.
e. Verify branch does not exist locally or remotely; verify worktree path does not exist.

Log: `queued`.

### 1.2 Branch + worktree creation

Story branch forks from the **current tip of the batch branch** (NOT main) so issue `N` sees issue `N-1`'s already-merged code:

```bash
git worktree add -b feature/<N>-<slug> <worktree-parent>/<repo-name>-<N> origin/<batch-branch>
```

Verify with `git worktree list`. Log: `branch-created` + `worktree-created`.

### 1.3 Issue prep

a. Assign to user (idempotent): `gh issue edit <N> --add-assignee @me`.
b. Add `wip` label (idempotent): `gh issue edit <N> --add-label wip`.
c. Post 📦 Batch status — start comment on the issue:
   ```
   📦 Batch status — issue queued
   Batch branch: <batch-branch>
   Story branch: feature/<N>-<slug>
   Worktree: <worktree-parent>/<repo-name>-<N>
   Session folder: <session-folder>
   Position in queue: <i> of <total>.
   Issue stays open until the batch branch is merged into main.
   ```

Log: `issue-prepped`.

### 1.4 Run the 4-agent pipeline (A → B → C → D in strict sequence)

Each agent runs foreground; the orchestrator parses the return summary, transcribes to `run.jsonl`, and decides advance / halt / retry.

**Failure-vs-crash-vs-contract-violation distinction** (all paths terminate in §1.7's pause-and-converse on persistent failure):

- **Logical incomplete** = agent returns `agent-status: incomplete — <reason>` → spawn recovery sub-agent (§1.7 step 1). On recovery failure → §1.7 step 2 (capture record) + step 3 (pause + converse).
- **Contract violation (terminal-line botched)** = `agent-status:` line missing OR uses invalid sentinel, BUT the rest of the structured summary parses AND clearly describes a terminal outcome → ONE Terminal-line recovery attempt (see below). On recovery failure → §1.7 step 2 + step 3.
- **Runtime crash** = Agent tool returns an error envelope with NO return summary → up to TWO retries per slot. Third crash → §1.7 step 2 + step 3.

Use the Agent tool. Args: `subagent_type: "general-purpose"`, `model: "opus"` (A, C, recovery) or `"sonnet"` (B, D, pr-author), foreground. Do NOT use `isolation: "worktree"` — the orchestrator created the real worktree; sub-agent `cd`s into it as first action.

#### Agent A

Post 📦 Batch status — "Pipeline starting: spawning Agent A (create-story, Opus)" on issue #<N>.

Spawn with the concatenated prompt: `prompts/shared-boilerplate.md` (placeholders substituted) + `prompts/agent-a-create-story.md`.

When Agent A returns:
- Log `agent-A-returned` with the story file path.
- `agent-status: done` → proceed to Agent B.
- `agent-status: incomplete — <reason>` → spawn recovery agent (§1.7 step 1). On success → Agent B. On failure → §1.7.
- Missing/invalid `agent-status:` line → Terminal-line recovery (below). On failure → §1.7.
- Tool error envelope → per-agent crash retry (below). Third crash → §1.7.

#### Agent B

Post 📦 Batch status — "Agent A returned. Spawning Agent B (implementation, Sonnet)." on issue #<N>.

Spawn with concatenated prompt: shared-boilerplate + `prompts/agent-b-dev-story.md`. Inject `<story-file-path>` from Agent A's return.

When Agent B returns: log `agent-B-returned`; on `done` proceed to Agent C; on `incomplete` → recovery → on failure §1.7; on contract violation → Terminal-line recovery → on failure §1.7; on crash → retry → on third crash §1.7.

#### Agent C

Post 📦 Batch status — "Agent B returned. Spawning Agent C (code-review, Opus)." on issue #<N>.

Spawn with concatenated prompt: shared-boilerplate + `prompts/agent-c-code-review.md`.

When Agent C returns: same dispatch pattern as Agent B.

#### Agent D

Post 📦 Batch status — "Agent C returned. Spawning Agent D (finalize, Sonnet)." on issue #<N>.

Spawn with concatenated prompt: shared-boilerplate + `prompts/agent-d-finalize.md`. Inject `<issue-title>`.

When Agent D returns:
- Tool error envelope → per-agent crash retry. Third crash → §1.7.
- `agent-status: done` → parse the `merge-sha:` line from the same return summary. Log `agent-D-returned` + `merged-into-batch` with the squash SHA. Proceed to 1.5. (Missing `merge-sha:` on a `done` return → §1.7 with diagnosis `"Agent D returned done but no merge-sha line"`.)
- `agent-status: incomplete — <reason>` → classify:
  - **CI infra flake** (reason mentions `setup-bun` / `setup-node` / `setup-dotnet` 401/503, `Failed to fetch url`, `Bad credentials`, `ECONNRESET`, runner provisioning failures): one `gh run rerun --failed <run-id>`, re-poll. If green, treat as `done` (parse `merge-sha:`) → 1.5. If still red, fall through.
  - **Code regression / build red / test red / true CI red after rerun** → recovery agent (§1.7 step 1). On success → 1.5. On failure → §1.7.
- Missing/invalid `agent-status:` → Terminal-line recovery. On success → log + 1.5 with the recovered SHA. On failure → §1.7.

**Post-merge CI audit (orchestrator-side backstop for Core Principle #1).** On any `done` return, BEFORE proceeding to §1.5, verify the per-issue PR actually merged green — never trust the merge happened on green just because Agent D returned done. The pipeline cannot rely on GitHub branch protection (the runner may lack admin access), so this audit mirrors Agent D step 8b exactly. Run `gh pr view <pr-number> --json state,mergedAt,statusCheckRollup` and inspect every entry in `statusCheckRollup`. **Treat every present check as merge-gating, NOT only the ones GitHub marks "required"** (without branch protection nothing is flagged required, so a "required-only" reading would certify nothing):
  - **Non-empty rollup:** the merge is acceptable ONLY if every entry reached a terminal `SUCCESS` (treat `NEUTRAL`/`SKIPPED` as acceptable). If ANY entry is `FAILURE` / `ERROR` / `CANCELLED` / `TIMED_OUT` / `ACTION_REQUIRED`, or any entry never reached a terminal conclusion (still `PENDING`/`IN_PROGRESS`/`QUEUED`/`EXPECTED` at merge time), Agent D breached the CI gate and merged a red or unfinished PR into the batch — the single most damaging failure mode.
  - **Empty rollup (no workflow fired for this PR's changed paths):** do NOT wave it through as vacuously green. The merge is acceptable ONLY if Agent D logged `pre-merge-local-gate-pass` — the green local build + test it ran as merge evidence per step 8b. If the rollup is empty AND no `pre-merge-local-gate-pass` evidence exists in this issue's run-log/return summary, Agent D passed the gate vacuously — treat it as a gate breach.
If the merge is not acceptable by either branch above, do NOT proceed to §1.5. Instead:
  1. Log `red-ci-merge-detected` with the offending PR + the list of non-green checks (or, for an empty rollup with no `pre-merge-local-gate-pass` evidence, the detail `empty rollup waved through without local-build evidence`).
  2. Revert the contaminating squash off the batch branch: `git checkout <batch-branch> && git revert --no-edit <squash-sha> && git push origin <batch-branch>` (then `git checkout` back to the default branch — the orchestrator never lingers off main). Verify the revert landed (`git merge-base --is-ancestor <revert-sha> origin/<batch-branch>`).
  3. Post a 🚧 Batch status on issue #<N>: *"Per-issue PR #<pr> merged into the batch with non-green CI (<failing-checks>); the squash has been reverted off the batch branch. This is a hard gate — see Core Principle #1."*
  4. Route to §1.7 with diagnosis `"Agent D merged PR #<pr> into the batch with non-green CI (<failing checks>); squash reverted off batch — needs investigation before retry"`. Append a lessons-learned finding (the gate failed; the next iteration should harden Agent D step 8b).
This backstop catches a gate miss; Agent D step 8b is the primary defense (it should make this audit a no-op on every healthy run). Log `post-merge-ci-audit-clean` when acceptable — with the audited check count for a non-empty rollup, or the `pre-merge-local-gate-pass` reference for an empty-rollup local-build merge.

**Annotation ingest (orchestrator-side, on Agent D return):** parse three structured fields and append each entry to `annotations[]` with the issue_number stamped:
- `Pre-existing baseline failures observed` → `{ issue_number: N, kind: "baseline-failure", test_file: <path> }` (one per file).
- `TODOs introduced by this story` → `{ issue_number: N, kind: "todo", file, line, marker, text }` (one per marker).
- `Carry-forward framework gaps` → `{ issue_number: N, kind: "carry-forward", gap, owning_framework, affects_this_story, raw_text }` (one per gap).

`failure`-kind entries are appended by §1.7 when an issue dies. No aggregation at ingest time — cross-issue rollups happen at query time in Phase 2 pre-flight.

#### Per-agent crash retry (runtime crashes only — up to TWO retries per slot)

Runtime crash = tool error envelope with no return summary. Logical incompletes do NOT use this path.

1. Log `crash-retry-start` with slot + attempt number.
2. Reset state for the dead agent:
   - **Before Agent A**: `cd <worktree>`, `git reset --hard HEAD`, `git clean -fdx` (wipes partial BMAD story file, build artifacts).
   - **Before Agent B**: same reset BUT preserve the story file at `_bmad-output/implementation-artifacts/...` — use `git stash` if `git clean -fdx` would remove it.
   - **Before Agent C / Agent D**: do NOT reset — uncommitted implementation must survive. Just `cd` back and re-spawn.
   - `cd <repo-root>` afterward.
3. Post 🔄 Batch status: "Agent <X> crashed (runtime error). State reset; re-spawning. Crash retry <N> of 2 — third crash invokes the per-issue failure procedure."
4. Re-spawn with IDENTICAL prompt + model.
5. Third crash → §1.7 with diagnosis `"Agent <X> crashed 3 times consecutively (runtime/infrastructure failure, not a code regression)"`.

#### Terminal-line recovery (missing/invalid `agent-status:` line — at most ONE SendMessage per slot)

The agent returned a full summary; only the literal `agent-status:` line is missing or uses an invalid sentinel (`terminal`, `complete`, `finished`, `ok`, `success`, `green`, `merged`, etc.). Long-context agents under heavy compaction sometimes invent a wrap-up word. The work itself is presumed done — we only need the contract line.

**Gates — ALL must hold (otherwise → §1.7):**
1. The structured summary parses (PR number, files changed, test counts, build status, etc.).
2. The narrative clearly describes a TERMINAL state. Anything hedged ("I'll continue next pass", "still need to fix X") → §1.7.
3. Only the literal `agent-status:` line is missing/invalid; everything else is consistent with done.

**Procedure:**

a. Log `terminal-line-recovery-start` with slot.
b. **SendMessage availability check** (probe via `ToolSearch` for `select:SendMessage`):
   - **Available** → SendMessage to the same sub-agent ID: *"Your final response is missing the literal `agent-status:` contract line (or used an invalid value). The only valid terminal values are `agent-status: done` or `agent-status: incomplete — <reason>`. Reply with EXACTLY one of those lines and nothing else. Do not redo any work."* Parse the reply for the literal line.
   - **Not available** → apply **inferred-terminal-proceed**. All three gates already passed; the work is presumed complete. Log `terminal-line-inferred-proceed` with the slot + the original line value. Post a 🔄 Batch status: *"Agent <X> contract-line was missing/invalid; SendMessage unavailable in this harness, so the orchestrator inferred terminal state from the parsed summary."* Append a lessons-learned finding. Treat as recovery success.
c. SendMessage reply contains a valid line → log `terminal-line-recovery-success` + the recovered value. Post 🔄 Batch status: *"Agent <X> contract-line recovered after one orchestrator follow-up."* Proceed normally.
d. SendMessage reply still missing valid line OR hedged → §1.7 with diagnosis `"Agent <X> terminal-line recovery failed: <one-line summary>"`. Log `terminal-line-recovery-failed`. No second SendMessage.

**Hard limit:** at most ONE terminal-line recovery (or one inferred-proceed) per slot per issue.

### 1.5 Post-merge teardown for this issue

**Trigger:** Agent D returned `agent-status: done` (with parsed `merge-sha:`).

a. **Verify merge on batch**: `git fetch origin <batch-branch>` then `git merge-base --is-ancestor <squash-sha> origin/<batch-branch>`. Not ancestor → retry once after 30s. Still not → §1.7 with diagnosis `"Agent D returned done but squash SHA <sha> is not an ancestor of origin/<batch-branch> on refetch"`. Do NOT halt the queue.
b. **Remove the worktree**: `git worktree remove --force <worktree-parent>/<repo-name>-<N>`. Force is required (install/build leaves untracked artifacts).
c. **Belt-and-suspenders directory removal** (cross-shell): PowerShell `Remove-Item -Recurse -Force <path>` or Bash `rm -rf <path>`; then `git worktree prune`.
d. **Force-delete local branch** (idempotent): `git branch -D feature/<N>-<slug>`.
e. **Remote branch cleanup** (idempotent): `git push origin --delete feature/<N>-<slug>`.
f. **Verify everything is gone** — log `cleanup-incomplete` if anything lingers (warning, not halt).
g. Log: `cleanup-complete`.

### 1.6 Compact checkpoint every 3 issues

After every 3 completed issues (`i % 3 == 0 && i > 0`), write a `compact-checkpoint` entry and **surface a one-line note** to the user: *"3-issue compact checkpoint reached — context may be getting heavy; consider running `/compact` between sub-agent spawns if convenient."* Do not attempt to call `/compact` — it's CLI-only.

### 1.7 Per-issue failure procedure (pause and converse on persistent failure)

**Invoked from:** any agent returning `incomplete` after recovery agent also fails; terminal-line recovery exhaustion; third runtime crash on the same slot; recovery agent itself crashing. NEVER from Phase 0 precondition failures (those still halt) or user "stop" mid-loop.

The orchestrator does NOT auto-skip. It pauses and converses with the user; only AFTER the user picks "skip" (or equivalent) does it revert + post + clean up.

#### Step 1 — Spawn the dedicated recovery sub-agent (one attempt only)

The first call into §1.7 from an `incomplete` return ALWAYS goes here. Recovery agent is Opus, foreground, in the same worktree.

Spawn with concatenated prompt: `prompts/shared-boilerplate.md` (placeholders substituted) + `prompts/recovery-agent.md`. Inject `<X>` (failed slot), `<reason>` (original incomplete reason), and the full return summary of the failed agent.

**When recovery returns:**
- `recovery-status: recovered` → log `recovery-success`. Re-spawn the failed slot (or jump to the suggested next slot). Proceed normally.
- `recovery-status: recovered; skip-to-<slot>` → log `recovery-success-skip`. Spawn the suggested next slot directly.
- `recovery-status: unrecoverable — <reason>` → log `recovery-unrecoverable`. Proceed to Step 2.
- Tool error / no summary / missing line → log `recovery-crashed`. Proceed to Step 2 with diagnosis `"Recovery agent crashed or returned unparseable output; original failure: <reason>"`.

#### Step 2 — Capture failure record (always, even before pause)

Build the failure record on disk so the user (and the assistant talking to them) can inspect everything without further orchestrator action:

a. Create `<session-folder>/failures/<N>-<slug>/`.
b. Write `diagnosis.md`: failed agent slot, original incomplete reason, recovery verdict, full root-cause analysis, suggested manual next steps.
c. Write `last-state.diff` = `git diff origin/<batch-branch>...HEAD`.
d. Write `last-state.status` = `git status --porcelain` output.
e. Create `agent-transcripts/` and save the last 3 agent return summaries (A, B, C if reached) verbatim.
f. Log `issue-failed-pause` with full diagnosis + failure_folder path.

Nothing reverted yet. Nothing posted to GitHub yet. Branch + worktree stay intact so the user can inspect. All of that is deferred to step 4, AFTER the user picks a direction.

#### Step 3 — Pause the queue and hand control to the user

Print to the user's conversation:

```
⏸️  Batch paused — issue #<N> failed at slot <X> (<role>) after retries + Opus recovery agent.

Diagnosis (one-line): <recovery agent's one-line verdict>
Full record: <session-folder>/failures/<N>-<slug>/diagnosis.md
Worktree (intact for inspection): <worktree-parent>/<repo-name>-<N>
Story branch (intact on origin): feature/<N>-<slug>

The queue is paused. Let me know how you want to handle this — we can discuss the
diagnosis, dig into the worktree, propose a fix, or you can just tell me to skip,
retry the slot, or abort. The remaining queue (<remaining-count> issues) will not
advance until you give a clear go-signal.
```

Then STOP. Do NOT call `AskUserQuestion`. Do NOT call `ScheduleWakeup`. Do NOT start any timer. Wait for the user's next free-form message and respond conversationally.

The user may ask questions, request investigation, propose a fix, etc. Engage normally. Only resume the orchestrator loop on a clear signal (paraphrase-tolerant):

- "skip this issue and continue" → execute step 4 (revert + cleanup + post comment) then resume from §1.1 with issue N+1.
- "retry the failed slot" / "rerun from slot X" → respawn the named slot in the same worktree. Reset state per the crash-retry rules.
- "I fixed it manually, resume from <slot>" → verify the worktree is in a clean-enough state, then resume from the named slot.
- "abort the batch" / "stop the run" → treat as the explicit-user-stop hard halt. Write manifest with `Status: halted`.

If the signal is ambiguous, ask one clarifying question — "do you want me to skip and continue, retry, or wait while you fix it?" — then act.

#### Step 4 — Execute the chosen path (only on "skip" or "abort")

**If skip-and-continue:**

a. **Revert any commits this issue contributed to the batch branch.** Usually none (Agents B and C don't commit; Agent D commits inside the per-issue PR). But check: if Agent D's squash already landed (failure happened post-merge), revert: `gh pr view <pr-number> --json mergeCommit --jq .mergeCommit.oid` → on the batch branch: `git checkout <batch-branch> && git revert --no-edit <squash-sha> && git push origin <batch-branch>`. If no commits hit batch, no revert.
b. **Close the per-issue PR** if opened: `gh pr close <pr-number> --comment "Closed by /sequential-bmad-github-orion-v3 §1.7: this issue was skipped by the user after batch-pipeline pause. See <session-folder>/failures/<N>-<slug>/diagnosis.md."`. Leave the failed branch on origin.
c. **Remove the worktree**: `git worktree remove --force <path>` then `git worktree prune`. Belt-and-suspenders cross-shell cleanup.
d. **Post 🚧 Failure comment** on the GitHub issue:
   ```
   🚧 Batch failure — this issue was skipped by the user after the batch pipeline paused for review.

   - Failed agent slot: <X> (<role>)
   - Original incomplete reason: <reason>
   - Recovery agent verdict: <recovered | unrecoverable — reason>
   - Failure folder: `<session-folder>/failures/<N>-<slug>/`
   - Per-issue PR (closed, branch retained on origin): <pr-url-or-"never opened">
   - Story branch on origin: `feature/<N>-<slug>` (NOT deleted)
   - Batch state: any contributions from this issue have been reverted off the batch branch.

   This issue remains OPEN and assigned to you. To resume manually: check out `feature/<N>-<slug>` in a fresh worktree, address the diagnosis, push, open a PR against `main`.
   ```
e. **Remove `wip` label**: `gh issue edit <N> --remove-label wip` (suppress errors).
f. **Append to `annotations[]`**: `{ issue_number: N, kind: "failure", slug, failed_at_phase: <slot>, diagnosis: <one-line>, recovery_attempts: 1, failure_folder: <path>, pr_url: <url-or-null>, user_action: "skip" }`.
g. Log `issue-failed-user-skipped`.

**If abort:** write manifest with `Status: halted`, halt diagnosis `"User aborted batch at issue #<N>"`, write `.session-complete` sentinel, exit.

**If retry or manual-fix-then-resume:** no revert, no comment, no register append. Respawn the named slot.

#### Step 5 — Continue (only after skip)

Resume from §1.1 for issue `N+1`. Orchestrator is back on main; batch branch is in a known-green state (revert applied if needed); `annotations[]` has one more `failure`-kind entry.

#### End-of-queue summary (printed before Phase 2 spawn)

After the per-issue loop exits, print a one-block summary:

```
Phase 1 complete:
  • Merged into batch: <M> issues (#<list>)
  • Skipped by user after pause: <K> issues (#<list>)
  <if K > 0:>
  Skipped issues require manual resumption. See <session-folder>/failures/ for per-issue diagnosis.
  Spawning batch-QA over the <M> merged issues.
  <if K == 0:>
  Spawning batch-QA over all <M> issues.
```

The `failure`-kind entries in `annotations[]` are passed to the batch-QA prompts and consumed by qa-report.html's "Failed issues" slide and the Draft PR body's top callout.

---

## Phase 2 — End-of-queue batch QA (autonomous, two-agent pipeline)

After Phase 1's loop exits, **autonomously** spawn the batch-QA pipeline. No user question.

### 2.1 Pre-flight

a. `git fetch origin <batch-branch>`.
b. Create batch-QA worktree from the batch tip:
   ```
   git worktree add <worktree-parent>/<repo-name>-batch-<timestamp> origin/<batch-branch>
   ```
   Log `batch-qa-worktree-created`.
c. Clear stale stack-lock if PID dead.
d. **Failure-kind annotations summary** (query `annotations[]` where `kind == "failure"`). If non-empty:
   - Print one-line summary: *"Phase 1 had <K> issue failure(s) skipped + reverted off the batch branch: #<list>. Batch-QA proceeds over the <M> merged issues."*
   - Build `<failed-issues-list>` for both QA prompts: one line per failed issue of the form `#<N> — <slug> — failed at <slot> — <one-line diagnosis> — failure folder: <session-folder>/failures/<N>-<slug>/`. If empty, substitute `(none — all queued issues merged successfully)`.
   - Log `failed-issues-summary` with the full set.
e. **Baseline-failure summary** (query `annotations[]` where `kind == "baseline-failure"`, group by `test_file`). For each file reported by ≥2 issues (the strong signal it's not story-local):
   - Print one-line summary listing top files inline (≤5) or top 3 + "…and N more".
   - Build `<priority-baseline-list>` for the test-and-fix prompt: per-file line `<file path> — reported by N of <Z> issues (#<i1>, #<i2>, ...)`. Empty → substitute `(none repeated across queue — any failures already noted are likely story-local)`.
   - Log `baseline-failure-summary`.
f. **TODOs-introduced summary** (query `annotations[]` where `kind == "todo"`):
   - Print one-line summary: *"TODO/FIXME/HACK markers introduced by this batch: <total> markers across <count-of-issues-with-markers> of <Z> issues."* If `total == 0`, print *"TODOs introduced: none."*.
   - Build `<new-todos-by-issue-block>` for both QA prompts: per issue with ≥1 marker, one block of the form `#<N> — <count> markers:` followed by indented bullets `  - <file>:<line> — <MARKER>: <text>`. Empty → substitute `(none introduced by this batch)`.
   - Log `new-todos-summary`.
g. **Carry-forward summary** (query `annotations[]` where `kind == "carry-forward"`). Normalize `gap` (lowercase, collapse whitespace); entries with the same normalized `gap` in ≥2 issues are `is_framework_gap: true` at query time. Then:
   - Print one-line summary including framework-gap count.
   - Build `<carry-forward-flags-block>`: framework gaps first (sorted by issue count desc), then story-local. Per entry: `- <gap text> — owning_framework: <ref> — affects: #<i1>, #<i2>, …`. Empty → substitute `(none flagged)`.
   - Log `carry-forward-summary` with dedupe annotations.
h. **Deferral-filing map** (the Delta that closes the scope leak — feeds the `pr-author` filing step in 2.2b). The summaries above are for the QA narrative; this block is the actionable map the `pr-author` files against. Build `<deferral-filing-block>` mapping each **distinct** deferral (whole-batch deduped) to the per-issue PRs that must be back-linked. The per-issue PR number for each issue is in per-issue state (`pr_number`); include it so `pr-author` can `gh pr edit` the right PR bodies without re-deriving them. Two groups:
   - **baseline-failure**, grouped by normalized `test_file` — one entry per distinct file.
   - **carry-forward**, grouped by normalized `gap` — one entry per distinct gap, carrying `owning_framework` + `is_framework_gap` (true when ≥2 issues).

   Format (substitute real numbers; `observed_by` lists every issue that reported the item plus its per-issue PR):
   ```
   baseline-failure:
     - test_file: <path>
       observed_by: #<N1> (PR #<pr1>), #<N2> (PR #<pr2>)
   carry-forward:
     - gap: <text> | owning_framework: <ref> | is_framework_gap: <true|false>
       observed_by: #<N1> (PR #<pr1>), …
   ```
   If BOTH groups are empty, substitute `(no baseline-failure or carry-forward annotations to file this batch)`. `todo`-kind annotations are NOT auto-filed here — they're surfaced for human triage (Core Principle #1) and only become tracked issues if a human decides so. Log `deferral-filing-map-built` with the distinct-deferral count (baseline + carry-forward).

### 2.2 Spawn the two-agent batch-QA pipeline

The work splits across two sub-agents the orchestrator chains.

- **2.2a `test-and-fix` (Opus, foreground)** — owns Gates 1+2+3 + bug fixes + re-running gates. All work that *touches batch code*. Returns the structured handoff schema below.
- **2.2b `pr-author` (Sonnet, foreground)** — owns `qa-report.html` + Draft PR open + merge-conflict resolution (one autonomous attempt; pause for the user if it fails). Reads the 2.2a handoff. Does NOT touch batch code.

The split honors the natural coupling: anything that fixes batch code re-runs the gates that prove the code green (one agent); report + PR + conflict don't touch code (cheaper Sonnet).

#### 2.2a — Spawn `test-and-fix`

Agent tool args: `subagent_type: "general-purpose"`, `model: "opus"`, foreground.

Spawn with concatenated prompt: `prompts/shared-boilerplate-batch-qa.md` + `prompts/batch-qa-test-and-fix.md`. Inject `<count>`, the merged issues list (`#<N1>, #<N2>, …, #<Nk>`), `<failed-issues-list>`, `<carry-forward-flags-block>`, `<new-todos-by-issue-block>`, `<priority-baseline-list>`.

#### Handoff from 2.2a `test-and-fix` to 2.2b `pr-author`

`test-and-fix` returns BEFORE the Draft PR opens. Its return summary contains a fenced ```handoff block:

```handoff
batch-qa-gates-status: green | failed — <reason>
full-test-suite: <pass>/<total>
full-e2e-suite: <pass>/<total>
live-qa: <N-bugs-found-and-fixed> | clean
fix-commit-shas: [<sha1>, <sha2>, ...]   # empty list if no bugs
environmental-escape-used: yes — <substitute coverage> | no
stack-lock-owned: no                      # must be no — released in step E
```

It also emits a terminal `agent-status: done | incomplete — <reason>` line (per the shared contract).

**Orchestrator dispatch when test-and-fix returns:**
- `agent-status: done` AND `batch-qa-gates-status: green` → log `test-and-fix-returned green`. Spawn 2.2b with the handoff injected at the top.
- `agent-status: done` AND `batch-qa-gates-status: failed — <reason>` → log `test-and-fix-returned failed`. Spawn 2.2b anyway so the human still gets a Draft PR with the `❌ DO NOT MERGE` callout — pass the failed handoff in. `pr-author` skips conflict resolution.
- `agent-status: incomplete` → mark `batch-qa-status: failed` with the diagnosis and spawn `pr-author` with a synthesized failed handoff so the PR still opens with the DO NOT MERGE callout.
- Missing `agent-status:` or missing handoff block → Terminal-line recovery (same path as §1.4); on failure, treat as `incomplete`.

#### 2.2b — Spawn `pr-author`

Agent tool args: `subagent_type: "general-purpose"`, `model: "sonnet"`, foreground.

Spawn with concatenated prompt: `prompts/shared-boilerplate-batch-qa.md` + `prompts/batch-qa-pr-author.md`. Inject `<count>`, merged issues list, `<failed-issues-list>`, `<carry-forward-flags-block>`, `<new-todos-by-issue-block>`, `<deferral-filing-block>`, and the verbatim handoff block from 2.2a.

When `pr-author` returns:
- **Capture the `deferrals-filed` block** from its return summary (one line per filed/reused tracking issue: `kind | key | issue: #N | action: created|reused | linked-prs: #<pr1>,#<pr2>`). Append each to a run-level `filed_deferrals[]` register and log `deferrals-filed` with the count of created vs reused. This register feeds the Phase 4.3 scope-ledger panel. If the block is absent on an otherwise-green return, log `deferrals-filed-missing` and append a lessons-learned finding (the filing step is mandatory whenever `<deferral-filing-block>` was non-empty) — do NOT halt.
- `batch-qa-status: green` → log `batch-qa-returned green`, capture Draft PR number + URL. Post 📦 Batch status — "Draft PR opened: <pr-url>. Awaiting human QA + manual merge. Issue will close when batch lands on main." on EACH still-batched issue. Log `queue-end`. Proceed to §2.3 then Phase 3.
- `batch-qa-status: failed — <reason>` → DO NOT HALT. If pr-author opened a Draft PR with the DO NOT MERGE callout itself, just log + post the warning comment on each batched issue. If it returned without opening (e.g. it incomplete'd during writing), the orchestrator opens the PR from main targeting the batch branch in draft mode with title `[batch] <gh-login> — ❌ QA FAILED — <count-merged> issues (#<...>) — <date>` and the DO NOT MERGE body block. Post 📦 Batch status on each still-batched issue: *"⚠️ Batch QA failed — Draft PR opened with DO NOT MERGE callout."*. Append a lessons-learned finding. Proceed to Phase 3 pause-and-converse anyway — the user may resolve the failure manually and merge, in which case "merged" still triggers a normal Phase 4 finalization. Log `queue-end-with-qa-failure`.
- `agent-status: incomplete` (e.g. merge-conflict resolution failed; pr-author returned a conflict-diagnosis path and asked for direction) → pause and converse with the user (same pattern as §1.7 step 3). On resume signal, spawn pr-author again from where it left off, or follow the user's chosen path.
- Missing `batch-qa-status:` OR ambiguous → treat as `failed — <missing line; assuming worst case>` and follow the failed flow. Do NOT halt.

### 2.3 Batch-QA worktree disposition

Do NOT tear down the batch-QA worktree at end of Phase 2 — preserve it so the user can navigate the integrated code during manual QA. The orchestrator removes it in Phase 4 after batch→main merge.

---

## Phase 3 — Wait for the user's merge signal (pause-and-converse)

After Phase 2 opens the Draft PR, the orchestrator pauses and waits for a free-form signal from the user. **No `ScheduleWakeup`, no polling.** Same pause-and-converse pattern as §1.7.

Before pausing: log `wait-start` and post 📦 Batch status — "Draft PR opened: <pr-url>. Waiting for merge signal." on the first batched issue (just one — not all — to avoid spam).

Then print to the user's conversation:

```
Phase 2 complete — Draft PR opened: <pr-url>

When you've handled this PR, let me know:
  • "merged" / "I merged it" / "done" → I'll close the batched issues, write the stats report,
    and tear down (Phase 4).
  • "closed" / "abandoned" / "I closed it without merging" → I'll mark the batch as abandoned
    and exit clean (no issues closed; story branches and session folder preserved).
  • Or just describe what happened in your own words — I'll figure it out.

Session folder (preserved for inspection): <session-folder>
Batch worktree (preserved for manual QA): <worktree-parent>/<repo-name>-batch-<timestamp>
```

Then STOP. Do NOT call `AskUserQuestion`. Do NOT call `ScheduleWakeup`. Wait for the user's next free-form message and respond conversationally.

If the conversation is cleared before the user signals, they can re-trigger Phase 4 in a fresh session by invoking the skill again with the session folder as an explicit argument: `/sequential-bmad-github-orion-v3 finalize <session-folder>`. In that mode the orchestrator skips Phases 0–3 and runs Phase 4 directly against the recorded batch state. (The `.session-complete` sentinel at Phase 4.5 then prevents accidental double-finalize.)

### Signal handling (paraphrase-tolerant)

- **"merged" / "I merged it" / "done" / "go ahead and finalize"** → verify via `gh pr view <pr-number> --json state,mergedAt,mergeCommit`. If `state == "MERGED"` and `mergeCommit.oid` is present, capture the merge SHA and proceed to Phase 4. If `state == "OPEN"`, gently push back: *"GitHub still reports the PR as OPEN — did you merge it? Try refreshing the PR page or double-check the URL."* If `state == "CLOSED"` with `mergedAt == null`, ask: *"GitHub shows this as closed without merge — should I treat the batch as abandoned, or did you mean merged?"*.
- **"closed" / "abandoned" / "I closed it without merging" / "let's drop this batch"** → write `<session-folder>/manifest.md` with `Status: abandoned`, write `<session-folder>/.session-complete` (so a re-invocation of finalize mode short-circuits at Phase 4.0). Print exit summary. Leave session folder + batch worktree + batch branch intact for the user to inspect or resume manually. Log `abandoned`.
- **"wait, I haven't merged yet" / "later" / "not yet"** → acknowledge ("Okay, still waiting. Let me know when you've decided.") and continue waiting.
- **Ambiguous** → ask one clarifying question; do not act without a clear signal.

### Main drift during the wait

Ignored. The orchestrator does NOT compare the batch base ref against main during the wait. If main advances and the merge becomes problematic, that's a problem the user resolves at merge time (the batch-QA pr-author's autonomous additive-resolution attempt during Phase 2 is the only place the skill touches main-drift; during Phase 3 the orchestrator is just waiting for a signal).

---

## Phase 4 — Post-merge finalization

Triggered by the user's "merged" signal in Phase 3, or by direct invocation in finalize mode. Phase 4 NEVER halts — every step is best-effort.

### 4.0 — Idempotency check

Read `<session-folder>/.session-complete` if present. If it exists, this batch is already finalized — print *"Batch already finalized at <finalized-at>; nothing to do."* and exit. Do NOT re-run 4.1 → 4.5 (would re-post close comments, re-write the stats report, overwrite the manifest).

### 4.1 — Verify merge on main

```
cd <repo-root>
git fetch origin <default-branch>
git pull --ff-only origin <default-branch>
git merge-base --is-ancestor <merge-sha> origin/<default-branch>
```

If not ancestor → log hard error, re-fetch once after 60s; if still missing, log `merge-sha-not-found-on-main` AND continue with 4.2 → 4.5 anyway (the merge is reported by `gh` so audit comments + closes are still correct).

### 4.2 — Close each batched issue

**Pre-close link check (the last guard against a silent scope leak — runs before each close).** Phase 2's `pr-author` already filed-and-linked deferrals (Core Principle #9), but this is the final gate before an issue is closed forever, and it also covers finalize-mode re-invocations where the Phase-2 register was lost. For each issue `N`, BEFORE writing the close comment:
- Fetch issue `N`'s per-issue PR body: `gh pr view <story-pr-number> --json body` (PR number from per-issue state or the manifest's Issues table). Also scan the merged batch PR body once.
- Scan for any "out of scope" / "pre-existing baseline failures" / "follow-up" / "deferred" list whose items lack a trailing GitHub `#N` reference (regex for `#[0-9]+` on each such line).
- If any **unlinked** item is found: find-or-create a tracking issue for it (same find-or-**reuse** logic as Phase 2 — search open issues for the test path / gap text first; reuse if present; apply the `baseline-failure` / `recovered-scope` label), then `gh pr edit <pr> --body` to rewrite the line(s) with the resulting `#N`. Log `deferral-linked-before-close` per item (with the issue it links to and whether it was created or reused). Only then continue to the close comment.
- If everything is already linked: log `pre-close-link-check-clean` for issue `N` and proceed.

```
for each N in <batched-issues>:
  # (pre-close link check above has already run for N)
  gh issue comment N --body "✅ This issue shipped via batch <batch-branch>, merged to main as <merge-sha> in PR #<pr-number>.

  - Per-issue PR: #<story-pr-number>
  - Squash commit on batch: <squash-sha>
  - Acceptance criteria: all ✓ (see issue body)
  - Batch QA: green (see qa-report.html in session folder)
  - Deferrals: all tracked (see the per-issue PR's 'Out of scope / Follow-ups (tracked)' section)

  Closing now."
  # Tolerate already-closed issues defensively (user may have closed one manually mid-run).
  gh issue close N --reason completed  (suppress 'already closed' errors)
  gh issue edit N --remove-label wip  (suppress 'not present' errors)
```

Log `finalize-start` before the loop and `issue-closed` per issue.

### 4.3 — Generate per-run stats report HTML

Output: `~/Downloads/<repo-name>-stats-<DD_MM_YYYY>-<HH_MM>.html` (today's local date + current local time AT WRITE TIME). One fresh file per run. The skill NEVER modifies or deletes any existing `<repo-name>-stats-*.html` or `<repo-name>-status-*.html`.

**4.3.a — Gather data via `gh` CLI:**
- All issues: `gh issue list --state all --limit 2000 --json number,title,state,labels,assignees,createdAt,closedAt,updatedAt,milestone,url`
- Recent merges (last 30 days, for context): `gh pr list --state merged --base <default-branch> --limit 500 --json number,title,mergedAt,labels,author`

Log `stats-data-fetched` with issues_count + prs_count.

**4.3.b — Resolve optional target deadline:**
Check `~/.claude/projects/<harness-project-key>/memory/project_target_date.md` for:
```yaml
target_date: 2026-05-27
description: "MVP feature-complete deadline"
```
If present, parse + use for the target-rate section. If absent, OMIT target-rate sections and print one-line note: *"No target_date configured — to enable target-rate forecast, save `target_date: <YYYY-MM-DD>` to <memory-path>/project_target_date.md."*

**4.3.c — Compute statistics:**

- **Counts** (from all-issues fetch): stories total/closed/open + closed share % (count where labels include `story`); issues total/closed/open + closed share % (any label).
- **Project timeline**: project_start = earliest `closedAt`; cal days elapsed = `(today − project_start).days`; work days elapsed = count of Mon–Fri in that range.
- **Velocity**: stories/issues per cal day, per work day, per 7-day week (extrapolated as per-cal-day × 7).
- **Linear-forecast predictions** (three scenarios per metric): current pace (open / per_cal_day → finish_date); conservative (pace × 0.7); aggressive (pace × 1.3).
- **Target-rate analysis** (only if target_date present): days to target (cal + work); required rate (cal + work) = open / days_to_target; gap = required − actual (negative = behind); per-engineer required rate = required_team_rate / engineer_count.
- **Per-person breakdown**: team = unique assignees across all CLOSED issues. Per person: stories closed, non-story closed, total, share %, avg/work-day, avg/cal-day, speed classification (above/at/below team-avg ±10% band). Sort by total desc.
- **Confidence indicators**: cycle time avg + median + max of `(closedAt − createdAt).days`; stale-open count (open issues with updatedAt > 7 days ago); open without assignee; open without labels.
- **Composition**: per epic (group by `epic-*` labels OR milestone): total, closed, open, % done, last-merged-PR-from-epic — sort by open desc. Per assignee (open): one row per person + open count + top 3 by updatedAt. Per-person delta this batch: count closed with `closedAt >= <batch-start-ISO>`, compare to running avg.
- **Scope ledger (this batch)**: from `annotations[]` + the `filed_deferrals[]` register (Phase 2). Per kind (`baseline-failure`, `carry-forward`, `todo`): distinct count detected this batch, how many got a tracked `#N` (created vs reused, from `filed_deferrals[]`), and how many remain **unlinked**. `todo` markers are expected to be unlinked unless a human filed them — show them as "surfaced for triage", not as a leak. Unlinked `baseline-failure` / `carry-forward` counts SHOULD be zero after Phase 2 + the §4.2 pre-close check; a non-zero count is the metric the whole Delta exists to drive to zero.

**4.3.d — Render the HTML.** Self-contained single-page (no JS, no external assets). Dark theme matching the user's existing deck (`#0d1117` bg, `#c9d1d9` text). Single scrollable page, not a slide deck.

Required sections (in order):
1. Header — repo name, today's date+time (DD-MM-YYYY HH:mm), batch PR # + URL, batched issues list, status pill (`✅ Batch merged` / `🚧 With failures: K issues skipped` / `❌ Batch QA failed`). Footer: "Generated by /sequential-bmad-github-orion-v3 v<X.Y>".
2. Counts at a glance — two side-by-side stat-card groups (Stories | Issues): total, closed (green), open (yellow), closed share %.
3. Current velocity — Metric · Stories · Issues. Rows: Closed since project start (with start date footnote); Per cal day; Per work day; Per 7-day week.
4. Predictions (linear forecast) — Scenario · Stories finish · Issues finish. Rows: Current pace · Conservative · Aggressive.
4b. Target-rate analysis (only if target_date present) — target date, cal-days-to-target, work-days-to-target, required stories/issues per day (cal+work), gap-vs-actual with colored ±. Below: per-engineer required rate.
5. Per-person breakdown — table sorted by total desc. Columns: Engineer · Stories · Non-story · Total · Share % · Avg/work-day · Avg/cal-day · Speed (↑ ↔ ↓). Highlight the row matching `<gh-login>`.
6. Confidence indicators — card grid: cycle time (avg/median/max), stale-open count, open without assignee, open without labels.
7. Composition — three sub-sections: open per epic (sorted by open desc, footer links to GitHub label filter); open per assignee (one row per person + open count + top 3 stale-open); per-person delta this batch.
8. Scope ledger (this batch) — a small card grid / compact table from the scope-ledger computation. One row per annotation kind (`baseline-failure`, `carry-forward`, `todo`): Detected · Tracked (`#N`) · Created · Reused · Unlinked. Render unlinked `baseline-failure`/`carry-forward` counts in red when > 0 (a scope leak escaped both Phase 2 and the §4.2 pre-close check), green when 0; render `todo` unlinked as neutral "surfaced for triage". Below the table, one line: *"Deferrals filed this run: \<created\> new + \<reused\> existing tracking issues. Unlinked code-work deferrals: \<n\> (target: 0)."* Omit the whole section only if there were zero annotations of any kind this batch.

Style: pull CSS from any existing `<repo-name>-status-*.html` if readable; otherwise inline a minimal dark-theme block. Numbers are the content; prose minimal. One-line caveat at bottom: *"All numbers derived from `gh issue list` at <ISO timestamp>. Project start inferred from earliest `closedAt`."*

**4.3.e — Write the file** at `~/Downloads/<repo-name>-stats-<DD_MM_YYYY>-<HH_MM>.html`. Do NOT modify or delete any existing `<repo-name>-stats-*.html` or `<repo-name>-status-*.html`. Log `stats-report-written` with the absolute path.

**4.3.f — Print final note**: `Stats report written: <absolute-path>`. If 4.3.b reported no target_date, append the configuration hint as a second line.

### 4.4 — Teardown

a. Remove batch-QA worktree: `git worktree remove --force <worktree-parent>/<repo-name>-batch-<timestamp>` then `git worktree prune`.
b. Delete batch branch (local + remote — `gh`'s PR merge should have removed the remote ref already; be defensive): `git branch -D <batch-branch>` then `git push origin --delete <batch-branch>` (suppress 'remote ref does not exist' errors).

Log `cleanup-complete`.

### 4.5 — Manifest + final printout + session-complete sentinel

Write `<session-folder>/manifest.md` with `Status: succeeded` (or `succeeded-with-failures` / `succeeded-with-qa-failure` per the manifest section in Failure handling).

Write `<session-folder>/.session-complete` with content:
```
status=succeeded
merge-sha=<merge-sha>
merged-at=<mergedAt ISO timestamp from gh>
finalized-at=<now ISO timestamp>
batched-issues=<comma-separated list of issue numbers>
batch-pr=<batch-pr-url>
```

This sentinel is what step 4.0 checks for double-finalize protection (e.g. when the user manually invokes `/sequential-bmad-github-orion-v3 finalize <session-folder>` against an already-finalized run).

Print final summary (batched issues, PR URL, merge SHA, stats-report path, wall time). Log `session-complete`.

---

## Failure handling

Only TWO hard halts. Everything else is a soft failure that either pauses-and-converses (§1.7) or opens the Draft PR with a DO NOT MERGE callout.

### Hard halts

1. **Phase 0 precondition failure** — not in a git repo, not on the default branch, working tree has staged uncommitted changes, default branch is not `main`/`master`, BMAD slash-commands missing (and user did not confirm them at Phase 0 step 0), `gh auth status` fails, repo-name ambiguous and user declined to disambiguate. Stops before creating any branches or session folders.
2. **Explicit user "stop" mid-loop** — clear stop intent ("stop", "halt", "abort the queue"). Finish the in-flight sub-agent's current tool call if possible, write a §1.7-style failure record for the in-flight issue, manifest with `Status: halted` + diagnosis "user requested stop", exit.

### Soft failures (orchestrator continues; flags + diverts)

| Trigger | Path |
|---|---|
| Agent A/B/C `incomplete` | Recovery agent (§1.7 step 1) → on failure, §1.7 pause-and-converse |
| Agent D `incomplete` (CI red / build red / test red) | Classify reason (infra flake → `gh run rerun --failed`; real red → recovery → §1.7) |
| Agent D returns `done` but post-merge CI audit finds non-green checks on the merged PR | §1.5 backstop: revert the squash off the batch branch, log `red-ci-merge-detected`, post 🚧 status, route to §1.7. A per-issue PR must never sit in the batch with red/pending CI (Core Principle #1) |
| `pr-author` returns green but `deferrals-filed` block absent while map was non-empty | Log `deferrals-filed-missing` + lessons-learned finding; the §4.2 pre-close check still files/links before close. Do NOT halt |
| Missing/invalid `agent-status:` line | Terminal-line recovery (SendMessage if available; inferred-terminal-proceed if not). On failure → §1.7 |
| Runtime crash | Crash retry up to 2. Third crash → §1.7 |
| Recovery agent itself crashes or returns unparseable | §1.7 step 2 with diagnosis "Recovery agent crashed; original failure: <reason>" |
| Phase 2 merge conflict | One autonomous additive-resolution attempt (pr-author). On failure → pause and converse with the user (§1.7 step 3 pattern, surfaced through the pr-author return) |
| `batch-qa-status: failed` | Draft PR opened with `❌ DO NOT MERGE` callout at top; still pause at Phase 3 for the user's signal; user resolves manually or closes |
| Phase 3 user signals "closed" / abandoned | Write manifest `Status: abandoned`, write `.session-complete`, exit clean (no issues closed; story branches + session folder preserved) |
| Phase 3 user gives no signal | Orchestrator stays paused — Phase 3 has no timeout (the conversation ends naturally; user can resume in a fresh session via finalize mode) |
| Phase 3 user claims "merged" but `gh pr view` shows OPEN | Push back conversationally; do NOT run Phase 4 until `state == "MERGED"` |
| Phase 4 per-issue close failure | Log + continue with remaining issues (best-effort) |
| Phase 4 stats-report write failure | Log + continue (best-effort) |
| Phase 4 worktree teardown failure | `cleanup-incomplete` warning + continue |
| Phase 4 merge-SHA not on local main after refetch | One re-fetch after 60s; if still missing, log hard error AND continue with remaining 4.x steps |
| Phase 4 invoked but `.session-complete` already exists | Print "Batch already finalized" and exit — no double-finalize |

### On any soft failure

1. Log appropriate event in `run.jsonl` with full diagnosis.
2. Capture failure record per §1.7 step 2 if it routes through §1.7.
3. Post the appropriate GitHub issue comment (🚧 failures, 🔄 recoveries, 📦 status).
4. Append the appropriate annotation entry (kind=`failure` for skipped issues; the orchestrator does this after the user picks "skip").
5. Surface a one-line chat notice to the user (§1.7 step 3 pause template, or one-line `📦 Batch status` for non-pause cases).
6. Continue the next phase / next issue.

### Manifest on completion

`<session-folder>/manifest.md` is written at end-of-run with one of:

- `succeeded` — all queued issues merged + batch-QA green + batch→main merged.
- `succeeded-with-failures` — at least one issue failed via §1.7 but batch still completed end-to-end (Draft PR opened; if merged, Phase 4 finalized).
- `succeeded-with-qa-failure` — all queued issues merged but Phase 2 batch-QA returned failed; Draft PR opened with DO NOT MERGE callout; user resolved manually (merged or closed).
- `abandoned` — user signaled "closed" / "abandoned" at Phase 3 instead of merging.
- `halted` — Phase 0 hard halt OR explicit user stop. Includes halt diagnosis.

---

## What this skill does NOT do

- Does not discover or select issues itself (that's `/assign-issues-orion`'s job — run it first, then pass `@me` here to pick up what it assigned you, or supply issue numbers explicitly).
- Does not poll for the batch→main merge. Phase 3 is pause-and-converse only — no `ScheduleWakeup`, no hourly poll, no auto-finalize.
- Does not rebase the batch branch onto main during Phase 3 wait — drift is the user's concern at merge time.
- Does not force-push (except `--force-with-lease` during batch-QA additive-rebase) or skip hooks.
- Does not delete worktrees or branches of issues that haven't completed (preserved on failure).
- Does not run live-stack QA per issue. The Junior-tester gate runs ONCE on the integrated batch in Phase 2.
- Does not write a per-issue HTML report. ONE `qa-report.html` per session + ONE `<repo-name>-stats-<DD_MM_YYYY>-<HH_MM>.html` per run.
- Does not touch any long-lived `<repo-name>-status-*.html` deck. The user owns it entirely.

---

## Cleanup checklist (every run)

- [ ] Session folder created at `<session-folder>` (NOT inside the repo).
- [ ] No marker files written into the repo (no `.sequential-state`, `.run-status`, etc.).
- [ ] No `.gitignore` additions for skill artifacts.
- [ ] On success: per-merged-issue worktrees + branches + remote refs gone; batch worktree + branch + remote ref gone (Phase 4); Draft PR merged.
- [ ] **On per-issue failure (§1.7)**: per-failed-issue worktree removed locally; per-failed-issue branch RETAINED on origin so the user can investigate; per-failed-issue PR (if opened) closed; `<session-folder>/failures/<N>-<slug>/` written with diagnosis.md + last-state.diff + agent-transcripts/.
- [ ] On hard halt: nothing torn down beyond what completed before the halt.
- [ ] **Every per-issue PR merged into the batch had green CI or a green local build+test at merge time** (Agent D step 8b + §1.5 post-merge audit — `pre-merge-ci-gate-pass` when CI ran, `pre-merge-local-gate-pass` when the rollup was empty); no red/pending PR and no vacuously-empty rollup contaminated the batch.
- [ ] **Every deferral (baseline-failure, carry-forward) is tracked by a `#N`** and back-linked into the per-issue PR bodies under `## Out of scope / Follow-ups (tracked)`; no PR body carries an unlinked "out of scope" / "pre-existing baseline failures" / "follow-up" line (Phase 2 filing + §4.2 pre-close check). Tracking issues were find-or-**reused**, not duplicated per run.
- [ ] Stale stack-lock cleared between issues and between phases.
- [ ] `<session-folder>/run.jsonl` present.
- [ ] Manifest written with one of the five `Status:` values.
- [ ] `<session-folder>/.session-complete` sentinel written so a re-invocation in finalize mode exits at Phase 4.0 instead of double-finalizing.
- [ ] On success (any of the three -with-* / clean variants): one fresh `<repo-name>-stats-<DD_MM_YYYY>-<HH_MM>.html` written to `~/Downloads/`. All previously-written `<repo-name>-stats-*.html` files left untouched. Any `<repo-name>-status-*.html` deck the user maintains is NEVER touched.

---

## Implementation notes for the orchestrator

- **Prompt assembly**: at sub-agent spawn time, the orchestrator concatenates the appropriate boilerplate (`prompts/shared-boilerplate.md` for per-issue agents A/B/C/D + recovery; `prompts/shared-boilerplate-batch-qa.md` for the two Phase 2 batch-QA agents) + the slot's prompt file, then substitutes every `<bracketed-placeholder>` from the run state before passing to the Agent tool. Sub-agents see one self-contained prompt; the file split is purely a maintainability artifact.
- **Shell tool selection**: prefer the platform's native shell (PowerShell on Windows, Bash on POSIX). Both work via the corresponding tool. git/gh commands are identical; only filesystem ops differ (`Remove-Item` vs `rm -rf`, `Move-Item` vs `mv`, `Test-Path` vs `test -e`).
- **Log file append**: PowerShell `Add-Content -Path <path> -Value <json> -Encoding utf8`, or Bash `echo '<json>' >> <path>`. JSONL = one object per line.
- **Stay on default branch**: the orchestrator must remain on `main` (or the repo's default) in `<repo-root>` throughout. Never `cd` away. All worktree operations use absolute or sibling-relative paths.
- **Mid-loop user message**: clear stop intent ("stop", "halt", "abort") → explicit-user-stop hard halt. Finish the in-flight sub-agent's current tool call if possible, write §1.7-style failure record for the in-flight issue, manifest `Status: halted` + diagnosis "user requested stop", exit. Non-stop messages mid-loop → answer briefly then resume; queue keeps running unless explicitly stopped.

---

## Version history

See [CHANGELOG.md](./CHANGELOG.md).
