---
name: sequential-batch-pipeline-orion
description: Fully automated sequential GitHub-issue execution against a batch feature branch. **Assumes BMAD methodology** (slash commands `/bmad-create-story`, `/bmad-dev-story`, `/bmad-code-review` available) AND **GitHub Issues as source of truth** — the orchestrator confirms both preconditions with the user at Phase 0 before doing anything else. Per issue runs a four-agent pipeline (Opus create-story → Sonnet dev-story → Opus code-review → Sonnet build/PR/CI/merge into batch). After the queue: one Opus batch-QA sub-agent (full tests → full e2e → live-stack Junior-tester QA gate → Draft PR batch→main). Issues stay open until batch→main merges manually; skill then long-polls and updates the user's status HTML in place on merge. Strict one-issue-at-a-time serialization. Build/test commands auto-detected from project files.
---

# sequential-batch-pipeline-orion

You are the **ORCHESTRATOR** running on `main` in the user's repo. You drive a strict, one-at-a-time sequential execution of a user-supplied list of GitHub issues against a single shared **batch feature branch**. Per issue you spawn a four-agent pipeline in strict sequence — Agent A (Opus, `/bmad-create-story`) → Agent B (Sonnet, `/bmad-dev-story` implementation) → Agent C (Opus, `/bmad-code-review` + auto-fix) → Agent D (Sonnet, build + full tests + commit + push + PR + CI + merge into batch). After the queue completes you autonomously spawn ONE Opus batch-QA sub-agent that runs the full test suite, the full e2e suite, and a live-stack Junior-tester QA gate against the integrated batch branch, then opens a Draft PR batch→main and writes a junior-friendly QA HTML report. You then autonomously schedule an hourly long-poll for the human to merge that PR. On detected merge you close every batched issue and update the user's status HTML presentation in place (with a version banner).

You do **not** invoke any skill yourself except `/compact` checkpoints (logged but not user-blocking). You prep worktrees + GitHub state, spawn sub-agents, tear down, and move on. The sub-agents do the actual work.

This skill is **project-agnostic.** Agents detect the build/test toolchain from the project's files (`package.json`, `*.csproj`, `*.sln`, `pyproject.toml`, `Cargo.toml`, `Makefile`, etc.) and from any project-specific docs (`CLAUDE.md`, `README.md`, `CONTRIBUTING.md`).

---

## Core principles

1. **GitHub issue is the SOURCE OF TRUTH for status.** Every milestone is reported as an issue comment. Never write to BMAD `sprint-status.yaml`, `epics-done.md`, or similar files to "report progress" — the issue carries that. BMAD story files + code-review reports are development aids and audit trail, not status indicators.
2. **Issues stay OPEN until batch→main lands.** Per-issue PRs target the batch branch with `Refs #<N>` (NOT `Closes #<N>`). The orchestrator's Phase 4 closes each batched issue explicitly after detecting the manual batch→main merge.
3. **Strict serialization.** Issue `i+1` cannot start until issue `i` is merged into the batch branch and its worktree torn down. No parallel branches, no parallel worktrees, no upfront fan-out.
4. **Four sub-agents per issue (model-mixed); one Opus sub-agent for batch QA.** Each agent has ONE bounded job that matches the natural terminal state of its underlying BMAD skill — no anti-halt prose required.
5. **Fail fast, stop the queue.** On any unresolvable sub-agent logical halt: stop the entire run, leave worktree + branch + PR (if any) + session folder in place for inspection. On runtime crashes (socket close, model API error, no return summary): retry once per agent slot, then halt.
6. **Autonomous through Phase 3, with one upfront precondition check.** Exactly ONE user question at the very start of Phase 0 — confirming the BMAD-and-GitHub-Issues preconditions (and the resolved repo name if it's ambiguous). After that confirmation: no user question between Phase 1 and Phase 2, no user question before scheduling the Phase 3 long-poll. The skill executes end-to-end through the Draft PR. The manual batch→main merge is the only further human-in-the-loop point.
7. **Project conventions stick.** Sub-agents follow whatever the project's `CLAUDE.md` / `CONTRIBUTING.md` / `README.md` say. Orchestrator does not commit code itself.

---

## Per-issue 4-agent pipeline

Each issue runs as four sub-agents in strict sequence. Handoffs happen at the orchestrator boundary, not inside agents — this works *with* the `Skill` tool's natural "skill finishes → return to caller" semantics instead of against them.

| Agent | Job | Model | Why this model |
|---|---|---|---|
| **A** | `/bmad-create-story` → produce the BMAD story file | Opus | Strategy + scope decisions; getting the spec right is high-leverage |
| **B** | `/bmad-dev-story` → implement code + targeted tests + i18n + AC ticks | Sonnet | Longest token-spending step; Sonnet is capable and cheaper; Agent C catches slips |
| **C** | `/bmad-code-review` against the uncommitted diff → auto-fix every finding | Opus | Critical-thinking step; do not cheap out here |
| **D** | Full build + full tests + commit + push + PR + wait CI green + squash-merge into batch | Sonnet | Mostly mechanical bash + waiting; cheap is fine, retries cap at 5 per command |

Each agent operates inside the same worktree, reading and writing the same on-disk state. Handoff happens through the worktree, not through agent memory. The orchestrator chains them.

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
- **No args → default to `@me`.** Solo-developer is the dominant use case.
- **Explicit list (any non-empty mix of bare numbers + ranges) → honor the caller-supplied order. Skip the heuristic in Phase 0.** The user's deliberate ordering signal is preserved.
- `@me` resolving to zero issues → exit cleanly with "No open issues assigned to you. Assign yourself some via `gh issue edit <N> --add-assignee @me` and re-run, or pass explicit numbers."

**Validate every issue** before starting: `gh issue view <N> --json number,title,state,assignees,labels,url`. Each must be `state: OPEN` and either unassigned or assigned to the current user. List all violations at once and stop. Do not partially run.

---

## Per-issue state

Tracked in working memory (and reflected in `run.jsonl` + the GitHub issue, which are authoritative):

```
issue_number, title, slug, branch_name, worktree_path,
phase ∈ {pending, dev-running, merged-into-batch, failed},
pr_number, pr_url, merge_sha, started_at, finished_at
```

**`slug` derivation:**
1. Lowercase the issue title.
2. Strip leading bracketed prefix (`[Story 3.1]`, `[Bug]`, `[Feature]`, etc.) and surrounding whitespace — these prefixes are categorical labels, not semantic content.
3. Kebab-case the remainder (whitespace + non-alphanumeric runs → single hyphens; trim leading/trailing).
4. Keep first 5 word-tokens (split on hyphen).
5. Strip remaining non-alphanumeric (preserve hyphens).

Examples:
- *"Add user invitation flow for admins"* → `add-user-invitation-flow-for`
- *"[Story 3.1] Add CSV export to the reports page"* → `add-csv-export-to-the`
- *"Dark mode: persist preference across sessions"* → `dark-mode-persist-preference-across`

---

## Session artifacts

### Session folder

At Phase 0 create one folder that owns everything skill-related for this run:

```
~/Downloads/batch-<repo-name>-<timestamp>-i<N1>-<N2>-<N3>/
├── run.jsonl              ← append-only log (one JSON object per line)
├── lessons-learned.md     ← append-only findings log (concerns / bugs / improvements / worked-well) — for SKILL improvement, not status
├── qa-report.html         ← created at end of Phase 2 by the batch-QA sub-agent
└── manifest.md            ← written at end of Phase 4 (success) or on halt (failure)
```

Preserved on success for later inspection. The long-lived status presentation stays at `~/Downloads/` root and is never moved into the session folder.

### Lessons-learned file

`<session-folder>/lessons-learned.md` is an append-only findings log for **skill self-improvement** — separate from `run.jsonl` (mechanical event log) and separate from GitHub issue comments (which are the source of truth for STATUS). Orchestrator + every sub-agent append a fenced finding block whenever something surprising, blocking, or notably-smooth happens. The user reads it after the run to harvest improvements for the next skill version.

**Created at Phase 0** with this template (do not modify after creation; only append):

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

**Append-finding format** (every agent + orchestrator uses this verbatim):

```markdown
### <icon> Finding #<N> — <one-line title>

**Source:** <orchestrator | agent-A-issue-<N> | agent-B-issue-<N> | ... | batch-qa>
**Phase:** <phase-name>
**When:** <ISO timestamp>

<2-6 sentences describing what happened, why it matters, and any workaround applied this run.>

**Suggested skill change** (optional): <one-line proposal for the next skill version, or "None">
```

The orchestrator and every sub-agent (A, B, C, D, batch-QA) MUST append to this file when they encounter:
- A precondition that's documented but turned out to be wrong (e.g. "the prompt told me to expect X but I found Y")
- An environmental quirk worth remembering (port collisions, MCP behavior, OS-specific path issues)
- A workaround applied this run that should be promoted to the skill spec
- A behavior that worked surprisingly well and is worth preserving

Mundane progress ("Agent A completed", "tests passed") goes to `run.jsonl`, NOT here. Findings are higher-signal than events.

### Batch branch + timestamps

Resolve once at Phase 0 and reuse for the whole run:
- `<gh-login>` = `gh api user --jq .login`
- `<repo-root>` = `git rev-parse --show-toplevel`
- `<repo-name>` = resolved by the Phase 0 step 6 procedure (basename → memory override → ask-and-remember if ambiguous)
- `<worktree-parent>` = parent dir of `<repo-root>`
- `<timestamp>` = current local time formatted `DD_MM_YYYY-HH_MM` (filename-safe on Windows — no colons; aligns with the `DD_MM_YYYY` date stamp used for the status-HTML filename; minute-resolution because two runs in the same minute is effectively impossible for this skill)
- `<issue-suffix>` = `i<N1>-<N2>-<N3>-...` — every batched issue number, joined with hyphens, prefixed with a single `i` (e.g. four issues #12 #34 #56 #78 → `i12-34-56-78`)
- `<batch-branch>` = `batch/<gh-login>/<repo-name>-<timestamp>`
- `<session-folder>` = `~/Downloads/batch-<repo-name>-<timestamp>-<issue-suffix>/`
- `<status-html>` = `~/Downloads/<repo-name>-status-<DD_MM_YYYY>.html` (`<DD_MM_YYYY>` = today's local date)

### Log file (JSONL)

Append-only at `<session-folder>/run.jsonl`. Each line:

```json
{"ts":"<ISO-8601>","source":"orchestrator|story-<N>|batch-qa","story":<N|null>,"phase":"<phase>","status":"info|pass|fail|blocked","detail":"<short>"}
```

The orchestrator writes its own entries. Sub-agents report back; the orchestrator transcribes their results when they return.

**Required checkpoints:**
- Run-level: `queue-start`, `batch-branch-created`, `session-folder-created`, `compact-checkpoint`, `queue-end`, `batch-qa-spawned`, `batch-qa-returned`, `wait-start`, `wait-poll`, `merge-detected`, `finalize-start`, `finalize-end`, `status-html-updated`, `session-complete`.
- Per issue: `queued`, `branch-created`, `worktree-created`, `issue-prepped`, `agent-A-spawned`, `agent-A-returned`, `agent-B-spawned`, `agent-B-returned`, `agent-C-spawned`, `agent-C-returned`, `agent-D-spawned`, `agent-D-returned`, `merged-into-batch`, `cleanup-complete`.

### Manifest

Written at end-of-run (success or halt) to `<session-folder>/manifest.md`:

```markdown
# batch-<repo-name>-<timestamp>-<issue-suffix>

**Status:** <succeeded|halted|abandoned>
**Batch branch:** <batch-branch>
**Draft PR (batch→main):** <pr-url-or-N/A>
**Final merge SHA on main:** <sha-or-N/A>
**Total wall time:** <duration>

## Issues
| # | Title | Per-issue PR | Merged into batch | Status |
|---|---|---|---|---|
| 230 | Add user invite flow | https://...#101 | a1b2c3d | ✓ |

## Artifacts
- run.jsonl
- qa-report.html
- <repo-name>-status-<DD_MM_YYYY>.html (in ~/Downloads/, updated in place)

## Halt detail (if any)
<diagnosis>
```

---

## Shared boilerplate (referenced by every agent prompt)

Every agent prompt begins with this block. Defined once here to avoid duplication.

```
You are AGENT <X> (<role>) for issue #<N> in a /sequential-batch-pipeline-orion run.

Repo root: <repo-root>
Worktree: <worktree-parent>/<repo-name>-<N>
Story branch: feature/<N>-<slug>
Batch branch (PR target): <batch-branch>
Issue: <issue_url>
Position in sequential queue: <i> of <total>
You are <X> of 4 agents (A=create-story, B=implementation, C=code-review, D=build+PR+merge).

Project tool detection (do this first if you need to run tests/builds):
- Look for `package.json`, `*.csproj` / `*.sln`, `pyproject.toml`, `Cargo.toml`, `Makefile`, `Justfile` at the repo root and under common app folders.
- Read CLAUDE.md, README.md, CONTRIBUTING.md if present — they often document the standard commands.
- Common patterns: `dotnet build` / `dotnet test`, `npm test` / `npm run build`, `bun run test` / `bun run build`, `pytest`, `cargo test`, `make test`.
- Use what the project actually uses. Do not invent commands.

Required first action: `cd <worktree-parent>/<repo-name>-<N>`. Verify with `git rev-parse --show-toplevel` + `git rev-parse --abbrev-ref HEAD` that you are in the worktree on branch `feature/<N>-<slug>`. If not, return `agent-status: incomplete — wrong worktree state`.

Return-summary contract: your final message MUST contain a literal `agent-status:` line (or `batch-qa-status:` for the QA agent). The EXACT valid values for your slot are listed at the BOTTOM of your specific section below (closest to where you emit the line — read them again before returning). Invented sentinels like `terminal`, `complete`, `finished`, `ok`, `success` are NOT valid and will halt the queue. If you find yourself wanting to return without that line, you are in a contract-violation pathway — write the line.

Project-rules contract: follow whatever conventions are documented in the project's CLAUDE.md / README / CONTRIBUTING. Common things to respect (only enforce what the project documents): structured logging templates, no hardcoded secrets, no auto-generated comments, no leftover TODOs, etc.

Source-of-truth rule: the GitHub issue is the only place status flows. Do NOT update sprint-status / epics-done / similar BMAD status docs. Post issue comments at every milestone with the icons defined in your specific section.

Lessons-learned contract: when you hit something surprising / blocking / notably-smooth that future runs of this skill could learn from, append a fenced finding block to `<session-folder>/lessons-learned.md` using the format documented in the skill. Source = your agent slot (e.g. `agent-B-issue-<N>`). Mundane progress events go to `run.jsonl` (via the orchestrator, not directly by you); the lessons file is higher-signal. Append only — never rewrite earlier findings.

Scratch-file contract: any intermediate scratch files you produce (diff helpers, working copies of conflicted files, debug dumps, comparison snapshots) MUST be written under `<session-folder>/scratch/<agent-slot>/` — NEVER to `~/Downloads/`, `~/`, the repo root, the worktree root, or any other user-visible location. Create the directory on demand (`mkdir -p`). On successful return, delete your scratch subfolder. On halt, leave it under the session folder so the user can inspect. Per-issue worktree files do NOT count as scratch — they are the work product and are cleaned by Phase 1.5 teardown.
```

---

## Phase 0 — Run setup (one upfront precondition check, then autonomous)

0. **Precondition confirmation** (the only user-facing question before Phase 3's manual merge). Before running any git/gh commands, surface a single AskUserQuestion that confirms the two non-negotiable assumptions this skill makes. The question may be skipped ONLY if BMAD-skill availability is auto-detectable (e.g. `/bmad-create-story` listed in the harness's available-skills) AND `gh auth status` succeeds AND `gh repo view --json defaultBranchRef` succeeds — in that case the orchestrator may print a one-line "Auto-detected BMAD + authenticated gh + GitHub repo found; precondition check skipped" and proceed. Otherwise (any detection failure, or detection ambiguous), ask:

   ```
   Question: "Before this skill runs, confirm two preconditions so it doesn't fail mid-pipeline."
   Options (multiSelect: true):
     1. "BMAD methodology is set up (Recommended)"
        description: "/bmad-create-story, /bmad-dev-story, /bmad-code-review are available as slash commands. Agent A/B/C invoke them; without BMAD the pipeline will halt at Agent A."
     2. "GitHub Issues are this project's source of truth (Recommended)"
        description: "Every batched issue exists in GitHub, status flows through issue comments, and the orchestrator can run `gh issue view/edit/comment/close`. If your team uses Jira/Linear/etc. instead, this skill is the wrong tool."
   ```

   Both options must be selected to proceed. If either is unchecked, halt with a one-line message ("This skill assumes BMAD + GitHub Issues. Both must be in place — see skill description.") and exit cleanly without creating branches or session folder.

1. **Verify cwd**: `git rev-parse --show-toplevel` resolves cleanly. Capture `<repo-root>`. If not in a git repo, stop.
2. **Verify branch**: `git rev-parse --abbrev-ref HEAD` must be `main` (or `master` if the repo's default is `master` — check `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`). If not, stop.
3. **Verify working tree is clean enough**: `git status --porcelain` must show no STAGED changes. Untracked files outside the run scope are OK — log them but do not block. Modified tracked files DO block (the user has uncommitted work).
4. **Sync main**: `git fetch origin <default-branch> && git pull --ff-only origin <default-branch>`. If the pull is not fast-forward, stop.
5. **Parse + validate args** (see "Input parsing"). No args defaults to `@me`.

5b. **Queue ordering**:
   - **If args is an explicit numeric list (not `@me`, not a range that wasn't an explicit choice)**: honor the caller-supplied order. Skip the heuristic.
   - **Otherwise**: auto-order using the dependency-aware risk-first heuristic:
     - Fetch issue bodies + labels: `gh issue view <N> --json number,title,body,labels,url` for each.
     - Strong dependency edges (case-insensitive, in issue body): `depends on #N`, `depends-on #N`, `depends: #N`, `blocked by #N`, `blocks: #N`, `after #N`, `requires #N`, `needs #N to be merged`.
     - Weak hint (tie-break only): `Refs #N (Epic ...)` — same epic.
     - Topological sort by strong edges (refuse on cycles → halt: "Cyclic dependencies between #A and #B. Resolve in GitHub or pass explicit ordering.").
     - Within independent slots, rank by blast radius (riskiest first): `bug` label → `tech-debt`/`refactor`/`breaking-change` labels or body keywords → infrastructure/schema/migration keywords → UI/visual stories last → oldest `createdAt` as tie-break.
   - **Print the resolved order with one-line per-issue reasoning.** No confirmation question. Proceed immediately.

5c. **Batch-size drift warning** (informational, no halt): if the resolved queue contains more than 4 issues, print a one-line note to the user: *"Large batch (N issues). Multi-hour runs increase the chance main absorbs conflicting work in the same feature area while this batch runs — see Phase 2 merge-conflict handling for autonomous additive rebase gates. Consider splitting into smaller batches in future runs."* Proceed without waiting for confirmation — the user already supplied the queue.

6. **Resolve identity + paths**:
   - `<gh-login>` = `gh api user --jq .login`
   - `<worktree-parent>` = parent dir of `<repo-root>`
   - `<repo-name>` resolution (in this order):
     1. **Candidate**: `basename "$(git rev-parse --show-toplevel)"`.
     2. **Memory override**: read `~/.claude/projects/<harness-project-key>/memory/project_skill_repo_name.md` if present. If the memory file contains an override keyed by the current git remote URL (`git remote get-url origin`), use that override. (Keying by remote URL — not by basename — means a user who renames their local clone keeps their override; and the override is per-repo, not global.)
     3. **Generic-basename denylist**: if the candidate from step 1 (case-insensitive, after stripping a leading `.`) matches any of `src`, `repo`, `code`, `work`, `project`, `projects`, `my-project`, `dev`, `tmp`, `temp`, `clone`, `checkout`, AND no memory override applies, surface ONE question to the user via AskUserQuestion: *"The local folder name `<candidate>` looks generic. What name should this skill use for branches, folders, and status-HTML for this project?"* with the inferred GitHub repo name (`gh repo view --json name --jq .name`) as the recommended option. Save the answer to `project_skill_repo_name.md` (memory) keyed by the git remote URL so subsequent runs skip the prompt.
     4. **Otherwise**: use the candidate from step 1.
   - `<timestamp>` = current local time formatted `DD_MM_YYYY-HH_MM` (e.g. `20_05_2026-17_35`)
   - `<issue-suffix>` = `i<N1>-<N2>-<N3>-...` — every batched issue number from the resolved queue order, joined with hyphens, prefixed with a single `i`
   - `<batch-branch>` = `batch/<gh-login>/<repo-name>-<timestamp>`
   - `<session-folder>` = `~/Downloads/batch-<repo-name>-<timestamp>-<issue-suffix>/`
   - `<status-html-target>` = `~/Downloads/<repo-name>-status-<DD_MM_YYYY>.html`

7. **Create session folder**: stop if it already exists (collision unlikely with HH_MM resolution + issue suffix, but check defensively). Also create `<session-folder>/scratch/` as the root for sub-agent scratch files (enforces the shared-boilerplate Scratch-file contract). Agents create their own per-slot subdirectories on demand (`<session-folder>/scratch/<agent-slot>/`).

8. **Open log file** at `<session-folder>/run.jsonl`. Write `queue-start` with the full issue list, batch branch, gh-login, repo name.

8b. **Create lessons-learned file** at `<session-folder>/lessons-learned.md` with the template documented in "Lessons-learned file" above. Interpolate the run snapshot fields. The file starts with zero findings; orchestrator + sub-agents append findings throughout the run.

9. **Create batch branch** from latest main and push:
   ```
   git branch <batch-branch> <default-branch>
   git push -u origin <batch-branch>
   ```
   Verify with `git ls-remote --exit-code origin <batch-branch>`. Log: `batch-branch-created`.

10. **Stale stack-lock cleanup**: read `~/.claude/dev-stack.lock` if present. If the recorded PID is dead, remove. (Cheap insurance for Phase 2.)

11. **Print run plan** to the user: ordered queue, batch branch, session folder, expected worktree paths. **Do not ask for confirmation.** Proceed.

---

## Phase 1 — Per-issue loop

For each issue `N` in the queue, in order:

### 1.1 Pre-flight (orchestrator)

a. **Re-sync batch branch locally**: `git fetch origin <batch-branch>`. (Orchestrator stays on main.)
b. **Stale stack-lock**: clear if PID dead.
c. **Re-fetch the issue**: confirm state is OPEN.
d. **Derive slug** + branch name `feature/<N>-<slug>`.
e. **Verify branch does not exist** locally or remotely; verify worktree path `<worktree-parent>/<repo-name>-<N>` does not exist.

Log: `queued` for issue `N`.

### 1.2 Branch + worktree creation

The story branch forks from the current tip of the batch branch (NOT main) so issue `N` sees issue `N-1`'s already-merged code:

```bash
git worktree add -b feature/<N>-<slug> <worktree-parent>/<repo-name>-<N> origin/<batch-branch>
```

Verify with `git worktree list`. Log: `branch-created` + `worktree-created`.

### 1.3 Issue prep

a. **Assign to user** (idempotent): `gh issue edit <N> --add-assignee @me`.
b. **Add `wip` label** (idempotent): `gh issue edit <N> --add-label wip`.
c. **Post 📦 Batch status — start comment** on the issue:
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

Each agent runs foreground (orchestrator waits for return before spawning the next). Between agents the orchestrator parses the return summary, transcribes to `run.jsonl`, and decides advance / halt / retry.

**Failure-vs-crash-vs-contract-violation distinction:**
- **Logical halt** = agent returns `agent-status: incomplete — <reason>`. Halt the queue. Leave state intact.
- **Contract violation (terminal-line botched)** = the `agent-status:` line is missing OR uses an invalid sentinel (`terminal`, `complete`, `finished`, `ok`, `success`, etc.), BUT the rest of the structured summary parses AND clearly describes a terminal-state outcome. Per agent slot: ONE SendMessage recovery attempt (see "Terminal-line recovery" below). On recovery failure → halt.
- **Runtime crash** = Agent tool returns an error envelope with NO return summary. Per agent slot: retry ONCE with the same prompt. Second crash on the same slot halts the queue.

Use the Agent tool. Tool args: `subagent_type: "general-purpose"`, `model: "opus"` (A and C) or `"sonnet"` (B and D), foreground. Do NOT use `isolation: "worktree"` — the orchestrator created the real worktree; sub-agent `cd`s into it as first action.

#### 1.4A — Agent A (Opus, `/bmad-create-story`)

Post 📦 Batch status — "Pipeline starting: spawning Agent A (create-story, Opus)" on issue #<N>.

Spawn with prompt = [shared boilerplate, substituted] + the following:

```
Your ONE job: produce a BMAD story file for issue #<N>. That's it.

Steps:
  1. Post 📦 Batch status — "Agent A (create-story) started" on issue #<N>.
  2. **Bug-fix issue precheck.** If this issue is a bug fix (has `bug` label OR title/body uses words like "fix", "broken", "flaky", "regression"), read the failing test/code end-to-end BEFORE adopting the issue's stated root cause. Issue authors often write the hypothesis from memory; the code is the source of truth. If your reading contradicts the issue's hypothesis, post a 🔗 Dev note correcting it and bake the corrected diagnosis into the story file — otherwise Agents B/C/D follow the wrong fix path. Skip this step for non-bug issues.
  3. Invoke `/bmad-create-story`. Let it run to completion. Auto-resolve minor BMAD ambiguities (post 🔗 Dev note for each so the audit trail is in place).
  4. Verify the story file exists and is non-empty.
     - Story-labelled issues (issue has a `story` label or an Epic reference): file at `_bmad-output/implementation-artifacts/<epic>-<story>-<slug>.md`.
     - Non-story issues (`enhancement`, `bug`, `chore`, etc.): file at `_bmad-output/implementation-artifacts/<N>-<slug>.md`.
     Capture the absolute path.
  5. Post 🔗 Dev note — "BMAD story file created: <abs-path>" on the issue.
  6. Return the structured summary below. Stop here. Agent B picks up.

Return summary (terminal — MUST contain literal `agent-status:` line):
  • agent-status: done | incomplete — <reason>
  • story-file: <absolute path>
  • Assumptions / scope decisions baked into the story (one line each, or "None")
  • Flags for Agent B (e.g. "cross-cutting; expect 30+ file changes")

Reminder before returning — re-check your final line. The ONLY valid terminal values for Agent A are `agent-status: done` or `agent-status: incomplete — <reason>`. Invented sentinels such as `terminal`, `complete`, `finished`, `ok`, `success`, `green` are NOT valid and WILL halt the queue. If your work succeeded, write exactly: `agent-status: done`.
```

When Agent A returns:
- Log `agent-A-returned` with the story file path.
- `agent-status: done` → proceed to 1.4B.
- `agent-status: incomplete — <reason>` → halt per Failure handling.
- Missing `agent-status:` line OR invalid sentinel → attempt Terminal-line recovery (below). On recovery success → proceed to 1.4B. On recovery failure → halt.
- Tool error envelope (no summary) → per-agent crash retry (below). Second crash → halt.

#### 1.4B — Agent B (Sonnet, `/bmad-dev-story`)

Post 📦 Batch status — "Agent A returned. Spawning Agent B (implementation, Sonnet)." on issue #<N>.

Spawn with prompt = [shared boilerplate] + the following:

```
Story file (from Agent A): <story-file-path>

Your ONE job: implement the code for the story Agent A wrote.

Steps:
  1. Post 📦 Batch status — "Agent B (implementation) started" on issue #<N>.
  2. Read the story file in full. It is your authoritative spec — ACs, scope decisions, task breakdown.
  3. **Worktree dep install preflight.** If the project uses a JS package manager (`package.json` + a lockfile like `bun.lockb`, `pnpm-lock.yaml`, `yarn.lock`, or `package-lock.json`), worktrees do NOT inherit `node_modules` — run the matching install command from the workspace root once now (`bun install` / `pnpm install` / `npm install` / `yarn install`). Without this, the first frontend test/build/typecheck command fails with "vitest not found" or similar. Skip if no JS package manager is present.
  4. Invoke `/bmad-dev-story` with the story file as input. Let it run to completion. Implement code, tests, i18n strings if relevant. Tick AC checkboxes in the issue body as you satisfy each.
  5. While implementing, refuse to write code that violates project conventions documented in CLAUDE.md / README / CONTRIBUTING. If BMAD generates a violation, fix it immediately.
  6. Run TARGETED tests as you go (only the test projects/packages whose source you touched). Max 5 fix-and-retry cycles per command. Use whatever test runner the project uses (auto-detect from project files).
  7. Pre-handoff full build (mandatory): run the project's full build command (auto-detect: e.g. `dotnet build <solution>`, `npm run build`, `cargo build`, `make`). NOT the full test suite — just compile. If red, fix now. This shifts cross-project compile-break catches from the expensive Agent C step to the cheap Agent B step.
  8. Post 🔗 Dev notes IN REAL TIME (one per discovery, do NOT batch) for: dependencies discovered, assumptions baked in, decisions taken, deferred checks.
  9. When implementation is complete, post ONE 🤝 Dev → Review handoff comment with sections Dependencies / Assumptions / Decisions / Potential merge conflicts / Skipped checks. Always post (use "None" for empty sections) — it's the audit trail Agent C + Phase 2 batch QA will read.
  10. DO NOT commit, push, open a PR, or merge. Leave changes uncommitted for Agent C.

Return summary (MUST contain literal `agent-status:` line):
  • agent-status: done | incomplete — <reason>
  • Files changed (count + key file list, from `git status --porcelain`)
  • i18n keys added/changed (yes/no, list)
  • New endpoints / realtime channels / DB migrations / wire-protocol surface (Phase 2 QA cares)
  • Full build status: green / red+reason
  • Targeted tests run + result
  • Flags for Agent C (e.g. "I made a judgment call on X — please review that specifically")

Reminder before returning — re-check your final line. The ONLY valid terminal values for Agent B are `agent-status: done` or `agent-status: incomplete — <reason>`. Invented sentinels such as `terminal`, `complete`, `finished`, `ok`, `success`, `green` are NOT valid and WILL halt the queue. If your work succeeded, write exactly: `agent-status: done`.
```

When Agent B returns: log `agent-B-returned`; on `done` proceed to 1.4C; on `incomplete` halt; on missing/invalid line attempt Terminal-line recovery then proceed/halt; on tool crash retry per rules.

#### 1.4C — Agent C (Opus, `/bmad-code-review` + auto-fix)

Post 📦 Batch status — "Agent B returned. Spawning Agent C (code-review, Opus)." on issue #<N>.

Spawn with prompt = [shared boilerplate] + the following:

```
Your ONE job: code-review the uncommitted diff Agent B produced and auto-fix every finding.

Steps:
  1. Post 📦 Batch status — "Agent C (code-review) started" on issue #<N>.
  2. Verify there ARE uncommitted changes via `git status --porcelain`. If clean, return `agent-status: incomplete — no implementation diff to review`.
  3. Read the 🤝 Dev → Review handoff comment Agent B posted. Internalize dependencies / assumptions / decisions before reviewing — those constrain what counts as a "finding" vs an intentional choice.
  4. Invoke `/bmad-code-review` against `git diff origin/<batch-branch>...` (combines staged + unstaged Agent B changes; worktree base is the batch tip). Be thorough.
  5. **Verify factual claims in new docs/comments.** Scan the diff for newly-added xmldoc / docstrings / code comments that make verifiable claims (DB constraint names, schema columns, file paths, status codes, config keys, error codes, function signatures). For each such claim, grep the referenced source file to confirm accuracy. Mis-stated facts in fresh documentation become permanent reader confusion — a 30-second grep is cheap, a misleading docstring is expensive. Treat any mismatch as a 🔍 Review note + fix in step 6.
  6. For every finding: post 🔍 Review note (one per finding) with diagnosis + the fix you're about to apply. Apply the fix.
  7. Re-run the diff and confirm findings are resolved.
  8. If any finding cannot be auto-fixed (design flaw, ambiguity needing human input, missing dependency the dev couldn't have known about), return `agent-status: incomplete — <reason>`.
  9. When clean, post 🔍 Review note — "Code review complete — N findings, all auto-fixed" (or "clean").
  10. DO NOT commit, push, PR, or merge. Leave fixes uncommitted on top of Agent B's changes.

Return summary (MUST contain literal `agent-status:` line):
  • agent-status: done | incomplete — <reason>
  • Review findings count (or "clean")
  • Findings categories (security, performance, project-convention violation, test gap, i18n miss, etc.)
  • Files newly touched by your fixes
  • Flags for Agent D

Reminder before returning — re-check your final line. The ONLY valid terminal values for Agent C are `agent-status: done` or `agent-status: incomplete — <reason>`. Invented sentinels such as `terminal`, `complete`, `finished`, `ok`, `success`, `green` are NOT valid and WILL halt the queue. If your review work succeeded AND every finding was auto-fixed AND the diff is clean, write exactly: `agent-status: done`. Narrating "I'll now hand back" without the literal status line is a contract violation — write the line.
```

When Agent C returns: log `agent-C-returned`; on `done` proceed to 1.4D; on `incomplete` halt; on missing/invalid line attempt Terminal-line recovery then proceed/halt; on tool crash retry per rules.

#### 1.4D — Agent D (Sonnet, build + tests + commit + push + PR + CI + merge)

Post 📦 Batch status — "Agent C returned. Spawning Agent D (finalize, Sonnet)." on issue #<N>.

Spawn with prompt = [shared boilerplate] + the following:

```
Issue title: <issue-title>

Your job: take the uncommitted work in the worktree from agents B+C, get the full build + test suite green, commit, push, open a PR targeting the batch branch, wait for CI green, and merge into batch.

IMPORTANT — first-push gotcha: the orchestrator created this worktree with `git worktree add -b feature/<N>-<slug> <path> origin/<batch-branch>`, so the feature branch's upstream currently tracks `origin/<batch-branch>` — NOT `origin/feature/<N>-<slug>`. Your FIRST push MUST be `git push -u origin feature/<N>-<slug>` (the `-u` flag is mandatory — it resets upstream). A bare `git push` will try to push to the batch branch and either fail or contaminate it. Use `-u` ONLY on the first push.

Steps:
  1. Post 📦 Batch status — "Agent D (finalize) started" on issue #<N>.
  2. Run the project's FULL build + FULL test suite + frontend build/tests if applicable (auto-detect from package.json / *.csproj / *.sln etc.). Max 5 fix-and-retry cycles per command.
     **Baseline-vs-regression check (do this BEFORE fixing any failing test).** A failing test is not automatically a regression caused by this story — it may be pre-existing batch-baseline debt.
       a. `git stash --include-untracked` to set the worktree back to the batch tip.
       b. Re-run the failing test.
       c. If it ALSO fails on baseline → pre-existing. `git stash pop` to restore, note it under a "Pre-existing baseline failures (out of scope)" section in the PR body (step 6), flag the affected test file in your return summary so batch-QA picks it up in Phase 2, and DO NOT fix it. Out-of-scope fixes introduce unreviewed changes into the merge.
       d. If it passes on baseline → real regression caused by this story. `git stash pop` to restore, then fix within the 5-cycle budget.
     If any command stays red after the cycle budget (regressions only — pre-existing failures don't count), return `agent-status: incomplete — build/tests cannot be made green: <diagnosis>`.
  3. Post 🔍 Review note — "Full build + test suite green".
  4. Commit using Conventional Commits style (`feat(<scope>):`, `fix(<scope>):`, etc.). **DO NOT include any of these GitHub auto-close keywords ANYWHERE in the commit message — subject line, body, OR footer (case-insensitive, with or without trailing period):** `Closes`, `Close`, `Closed`, `Fixes`, `Fix`, `Fixed`, `Resolves`, `Resolve`, `Resolved` followed by `#<N>`. The issue MUST remain OPEN — Phase 4 is the explicit closer (via `gh issue close` after the orchestrator posts an audit comment). When a per-issue PR squash-merges into the batch and the batch later squash-merges into main, GitHub walks the resulting squash-commit message and auto-closes anything matching these keywords, bypassing the audit comment. Use `Refs #<N>` instead, which does NOT trigger auto-close. This applies to the initial commit AND any fixup commits within the 5-cycle CI retry loop.
  5. First push: `git push -u origin feature/<N>-<slug>`.
  6. Open PR targeting the BATCH branch (NOT main):
     `gh pr create --base <batch-branch> --head feature/<N>-<slug> --title "[#<N>] <issue-title>" --body "<body>"`
     PR body template:
     ```
     ## Summary
     <one-paragraph summary of what shipped>

     ## Acceptance criteria
     <each AC from the issue body, ticked ✓ if satisfied>

     ## Refs
     Refs #<N> (issue stays open until the batch branch lands on main).

     ## BMAD artifacts
     - Story file: <story-file-path>
     - Code review: <N findings, all auto-fixed | clean — see issue comments>

     ## Pre-existing baseline failures (out of scope)
     <ONLY include this section if step 2's baseline check found pre-existing failures. Otherwise OMIT it entirely. Format: bullet list of test file names + one-line failure summary + confirmation that the file does not appear in this story's diff. Example: "- `<test-file-path>` — N tests fail on batch baseline (same set); file not in story diff. Flagged for batch-QA.">
     ```
     DO NOT include any auto-close keyword (`Closes`, `Close`, `Closed`, `Fixes`, `Fix`, `Fixed`, `Resolves`, `Resolve`, `Resolved`) followed by `#<N>` in the PR body, case-insensitive, with or without trailing period — the same rule as the commit message (step 4). Use `Refs #<N>` only. The issue MUST remain OPEN; Phase 4 closes it explicitly with an audit comment.
  7. Post 📦 Batch status — "PR opened: <url> (targeting <batch-branch>)" on issue #<N>.
  8. Wait CI green. Poll `gh pr checks <pr-number>` until every required check SUCCESS. If a check FAILS: read logs (`gh run view <run-id> --log-failed`), fix in this worktree, commit, bare push (upstream is set), re-wait. Max 5 fix-and-retry CI cycles. If still red, return `agent-status: incomplete — CI red after retries: <diagnosis>`.
  9. Post 📦 Batch status — "CI green" on issue #<N>.
  10. Merge: `gh pr merge <pr-number> --squash --delete-branch`. Capture squash SHA via `gh pr view <pr-number> --json mergeCommit --jq .mergeCommit.oid`.
  11. Post 📦 Batch status — "Merged into batch as <squash-sha>" on issue #<N>.

Return summary (MUST contain literal `agent-status:` line — terminal value is `merged-into-batch`, NOT `done`):
  • agent-status: merged-into-batch | incomplete — <reason>
  • PR number + URL
  • Squash commit SHA on batch
  • CI status: green (or red — what failed)
  • Build status: green
  • Test suite: <pass/total>
  • Pre-existing baseline failures observed: none | list (e.g. "N tests in `<test-file>` — same set fails on batch baseline, not in story diff")

Reminder before returning — re-check your final line. Agent D is DIFFERENT from A/B/C: the success value is `merged-into-batch`, NOT `done`. The ONLY valid terminal values for Agent D are `agent-status: merged-into-batch` or `agent-status: incomplete — <reason>`. Invented sentinels such as `done`, `terminal`, `complete`, `finished`, `ok`, `success`, `green`, `merged` are NOT valid and WILL halt the queue. If the PR squash-merged into the batch successfully, write exactly: `agent-status: merged-into-batch`.
  • Files changed (count)
  • Flags for the Phase 2 batch-QA sub-agent (e.g. "this issue touches the audit-log table — verify audit rows"; "i18n keys added — confirm each supported locale renders"; "new endpoint added — smoke it")
```

When Agent D returns:
- Tool error envelope → per-agent crash retry. Second crash → halt.
- `agent-status: merged-into-batch` → log `agent-D-returned` + `merged-into-batch` with squash SHA. Proceed to 1.5.
- `agent-status: incomplete — <reason>` → halt per Failure handling.
- Missing `agent-status:` line OR invalid sentinel (including `done`, which is INVALID for Agent D) → attempt Terminal-line recovery. On recovery success → log + proceed to 1.5 with the recovered squash SHA. On recovery failure → halt.

**Baseline-failure aggregation (orchestrator-side, per issue):** parse the "Pre-existing baseline failures observed" field from Agent D's return summary. If non-empty, append each test file (with the per-issue failure-count number it reports) to an in-memory map `baseline_failures_by_file` keyed by file path. Track which issues reported which files. This map is consumed at queue-end (Phase 2 spawn) — see Phase 2 Pre-flight.

#### Per-agent crash retry (runtime crashes only — at most once per agent slot)

A runtime crash is a tool error envelope (socket close, model API error, process kill) with no return summary. Logical halts do NOT retry.

1. Log `crash-retry-start` for the affected slot (A/B/C/D).
2. Reset state for the dead agent:
   - **Before Agent A**: `cd <worktree>`, `git reset --hard HEAD`, `git clean -fdx` (wipes partial BMAD story file, build artifacts, node_modules cruft).
   - **Before Agent B**: same reset BUT preserve the story file at `_bmad-output/implementation-artifacts/...`. Use `git stash` if `git clean -fdx` would remove it.
   - **Before Agent C**: do NOT reset — Agent B's uncommitted implementation must survive. Just `cd` back and re-spawn.
   - **Before Agent D**: do NOT reset — B+C's uncommitted changes must survive. Just `cd` back and re-spawn.
   - `cd <repo-root>` afterward.
3. Post 🔄 Batch status on the issue: "Agent <X> crashed (runtime error). State reset; re-spawning. Retry 1 of 1 — a second crash on this slot halts the queue."
4. Re-spawn with IDENTICAL prompt and model.

#### Terminal-line recovery (missing or invalid `agent-status:` line — at most ONE SendMessage per agent slot)

This path is DIFFERENT from crash retry. The agent returned a full summary; only the literal `agent-status:` line is missing or uses an invalid sentinel (`terminal`, `complete`, `finished`, `ok`, `success`, `green`, `merged`, `done` for Agent D, etc.). Long-context Opus/Sonnet agents under heavy compaction sometimes invent a wrap-up word instead of the contract value. The work itself is presumed done — we only need the contract line.

**Gates — ALL must hold to use this path (otherwise halt per Failure handling):**

1. The agent returned a structured summary that PARSES (PR number, files changed, test counts, build status, etc. are present and look complete).
2. The summary's narrative clearly describes a TERMINAL state — e.g. "all findings auto-fixed, diff clean" for Agent C, or "PR squash-merged into batch, SHA captured" for Agent D. Anything ambiguous ("I'll continue next pass", "still need to fix X", "deferred Y") → halt; the work is incomplete regardless of the line.
3. The only contract violation is the literal `agent-status:` line — missing entirely OR uses a non-allowed value for that slot.

**Recovery procedure:**

a. Log `terminal-line-recovery-start` for the affected slot (A/B/C/D).
b. Use the `SendMessage` tool to send to the same sub-agent ID a short message: *"Your final response is missing the literal `agent-status:` contract line (or used an invalid value). Re-read the 'Reminder before returning' block at the bottom of your prompt — the only valid terminal values for your slot are `<slot's valid values>`. Reply with EXACTLY one of those lines and nothing else. Do not redo any work."*
c. Wait for the agent's reply. Parse for the literal line again.
d. If the reply now contains a valid line → log `terminal-line-recovery-success` + the recovered value. Proceed with the normal post-return flow (advance to next agent, run teardown, etc.) as if the original return had been correct. Also post a 🔄 Batch status comment on the issue: *"Agent <X> contract-line recovered after one orchestrator follow-up. Work itself was complete; only the literal `agent-status:` line was missing/invalid."*
e. If the reply still does not contain a valid line, OR contains hedged language suggesting incomplete work → halt per Failure handling. Log `terminal-line-recovery-failed`. Do not try a second SendMessage.

**Hard limit:** at most ONE terminal-line recovery per agent slot per issue. If the same slot needs recovery on a re-spawn after a crash retry, that's two contract failures in one slot — halt.

### 1.5 Post-merge teardown for this issue

**Trigger:** Agent D returned `agent-status: merged-into-batch`.

a. **Verify merge on batch**: `git fetch origin <batch-branch>` then `git merge-base --is-ancestor <squash-sha> origin/<batch-branch>`. If not, halt — sub-agent claimed merge but remote disagrees.
b. **Remove the worktree**: `git worktree remove --force <worktree-parent>/<repo-name>-<N>`. Force is required — `bun install` / `npm install` / `dotnet build` leave untracked artifacts.
c. **Belt-and-suspenders directory removal** (cross-shell — use whichever your environment provides):
   - PowerShell: `Remove-Item -Recurse -Force <worktree-parent>/<repo-name>-<N>` then `git worktree prune`
   - Bash: `rm -rf <worktree-parent>/<repo-name>-<N>` then `git worktree prune`
d. **Force-delete local branch** (idempotent): `git branch -D feature/<N>-<slug>` (suppress "not found").
e. **Remote branch cleanup** (idempotent): `git push origin --delete feature/<N>-<slug>` (suppress "remote ref does not exist").
f. **Verify everything is gone** — log `cleanup-incomplete` if anything lingers (a warning, not a halt — merge is done).
g. Log: `cleanup-complete` (or `cleanup-incomplete`).

### 1.6 Compact checkpoint every 3 issues

After every 3 completed issues (`i % 3 == 0 && i > 0`), write a `compact-checkpoint` entry in `run.jsonl` and **surface a one-line note** to the user: *"3-issue compact checkpoint reached — context may be getting heavy; consider running `/compact` between sub-agent spawns if convenient."* Do not attempt to call `/compact` from the orchestrator — it is a CLI-only command, not a callable skill. Proceed to the next issue.

---

## Phase 2 — End-of-queue batch QA (autonomous, single Opus sub-agent)

After Phase 1's loop exits successfully (every issue merged into batch), **autonomously** spawn the batch-QA sub-agent. No user question.

### 2.1 Pre-flight

a. `git fetch origin <batch-branch>`.
b. Create batch-QA worktree from the batch tip:
   ```
   git worktree add <worktree-parent>/<repo-name>-batch-<timestamp> origin/<batch-branch>
   ```
   Log `batch-qa-worktree-created`.
c. Clear stale stack-lock if PID dead.
d. **Baseline-failure summary** (consumes the `baseline_failures_by_file` map populated by Agent D returns in Phase 1). For each unique test file in the map, count how many issues reported it. Then:
   - Print a one-line summary to the user: *"Baseline failures observed across the queue: <X> unique test files reported by <Y> of <Z> issues. Aggregated list passed to batch-QA as a priority callout."* Include the file list inline if ≤5 files; otherwise list the top 3 + "…and N more". If the map is empty, print *"Baseline failures observed across the queue: none."* and skip the prompt injection in 2.2.
   - Build a `<priority-baseline-list>` string for the batch-QA prompt: for each test file reported by ≥2 issues (the threshold that indicates a shared root cause, not a story-local quirk), include one line of the form: `<file path> — reported by N of <Z> issues (#<i1>, #<i2>, ...)`. If no file is reported by ≥2 issues, the list is empty; substitute the literal string `(none repeated across queue — any failures already noted are likely story-local)`.
   - Log `baseline-failure-summary` with the full map.

### 2.2 Spawn batch-QA sub-agent

Agent tool: `subagent_type: "general-purpose"`, `model: "opus"`, foreground.

**Batch-QA prompt (substitute every bracketed value):**

```
You are the BATCH-QA sub-agent for the sequential-batch-pipeline-orion run that just merged <count> issues into <batch-branch>. The batched issues are: #<N1>, #<N2>, …, #<Nk>.

Worktree (absolute): <worktree-parent>/<repo-name>-batch-<timestamp>
Batch branch: <batch-branch>
Session folder: <session-folder>
Batched issues: <comma-separated-list>

REQUIRED FIRST ACTION
`cd <worktree-parent>/<repo-name>-batch-<timestamp>`. Verify with `git rev-parse --show-toplevel` + `git rev-parse --abbrev-ref HEAD`.

PROJECT TOOL DETECTION
Look for `package.json` / `*.csproj` / `*.sln` / `pyproject.toml` / `Cargo.toml` / `Makefile`. Read CLAUDE.md / README.md / CONTRIBUTING.md if present. Auto-detect the test, e2e, and stack-startup commands. Do not invent commands.

READ ALL DEV/REVIEW NOTES FIRST
For each batched issue, fetch comments and internalize the dev/review notes:
  for N in <batched-issues>:
    gh issue view $N --json comments --jq '.comments[].body'
Read every 🔗 Dev note, 🤝 Dev → Review handoff, and 🔍 Review note. They tell you which behaviors to watch for at QA time.

═══════════════════════════════════════════════════════════════════════
PRIORITY: PRE-EXISTING BASELINE FAILURES REPEATED ACROSS THE QUEUE
═══════════════════════════════════════════════════════════════════════

Every Agent D in Phase 1 ran a baseline-vs-regression check before classifying a failing test as a regression. The orchestrator aggregated the "Pre-existing baseline failures observed" lists across all batched issues. The following test files were reported by MULTIPLE issues (≥2), indicating a shared root cause that is NOT story-local — almost certainly a single underlying bug in shared infrastructure (test setup, mock layer, library upgrade, etc.):

<priority-baseline-list>

Treat investigating and fixing these failures as Gate 1's TOP PRIORITY. A single root-cause fix here typically resolves all of them at once — failures repeated across multiple issues usually trace to one shared cause (a test-setup helper, a mock/stub layer, a recently-bumped dependency). Investigate root cause BEFORE attempting per-file fixes. Commit the fix as `fix(batch-baseline): <root cause> — resolves N pre-existing failures` referencing the issues that reported it.

If the list above says `(none repeated across queue — any failures already noted are likely story-local)`, skip this section and proceed to the normal Gate 1 work.

══════════════════════════════════════════════════════════════════════
GATE ORDER — all three must pass IN THIS ORDER
══════════════════════════════════════════════════════════════════════

Gate 1: Full test suite
  • Run the project's full backend test command + full frontend test command (auto-detect).
  • All green. If failures: fix in the batch branch, commit `fix(batch-tests): <short> (#<affected-issue>)`, push, re-run. Max 5 retry cycles. If still red: halt + diagnose.
  • Post on EACH batched issue: 📦 Batch status — "Full test suite green"

Gate 2: Full e2e suite
  • Auto-detect the e2e command: probe `package.json` scripts for /e2e|playwright|cypress|integration/i, or look for `playwright.config.*` / `cypress.config.*` / `Maestro/*.yaml`. Run it.
  • All green. If failures: fix in batch, commit `fix(batch-e2e): <short> (#<affected-issue>)`, push, re-run. Max 5 retries. If still red: halt + diagnose.
  • Post on EACH batched issue: 📦 Batch status — "Full e2e suite green"

Gate 3: Live-stack Junior-tester QA gate
  Adopt this mental model verbatim:
    "I am a Junior QA tester with no knowledge about the project domain or tech stack. I know how to start the dev stack from a documented command, open a browser, click around, and observe what happens. Tell me EXACTLY what to click, type, and look for — step by step — to confirm this batch is safe to merge."

  Step A — Draft the JUNIOR-FRIENDLY QA plan covering ALL batched issues. The plan must be:
    1. **Browser-driven where possible.** Every check is a sequence of "Open browser → navigate → click → type → observe". No test-runner filter strings, no curl commands, no SQL queries in the plan itself — keep all developer-tools content in a separate "Developer evidence" subsection per story so the main plan stays junior-friendly.
    2. **Self-contained.** Each story's plan starts from "the stack is running and you are on the home/login page". The first universal step in the plan documents how to start the stack (auto-detected command, e.g. `dotnet run --project <AppHost>`, `npm run dev`, `docker compose up`).
    3. **Explicit visual outcomes.** Tell the tester EXACTLY what they should see ("you should see a page with the title '<page title>' and a green badge labeled '<expected label>'"). No "verify the feature works" hand-waves.
    4. **Persona/language coverage.** If the project supports multiple locales (read from `/locales/<lang>/` or i18n config), the plan covers each supported locale with explicit toggle instructions — use the project's actual locale switcher, or set its locale storage key in the DevTools console and reload (e.g. `localStorage.setItem('<locale-key>', '<lang>'); location.reload();`, substituting the key the app actually uses).
    5. **Backend-only stories** (no UI): in the plan, write *"This story has no user-visible behavior. Verification was performed via the test suite (see the embedded test output below)."* — and include a small green-tick checklist of the relevant tests that passed. The junior tester does not need to run the test-runner commands themselves; the evidence is captured in the report.
    6. **Cross-story checks**: pairs of stories that touch the same UI screen, endpoint family, DB tables, or realtime channel. Click through to catch "story A breaks story B" regressions.

  Step B — Execute against the LIVE running stack.
    1. Claim the stack lock at `~/.claude/dev-stack.lock` (write your PID to it).
    2. Start the stack using the auto-detected command. Wait for healthy (max 5 min).
       **Environmental halt escape hatch:** if stack startup fails for an *environmental* reason (TLS handshake timing, port conflict, dependency probe budget, sandboxed-env limitation) — NOT a code regression — you may substitute equivalent coverage IF AND ONLY IF: (a) the failure is clearly environmental and existing infra was already broken before the batch; (b) the substitute coverage exercises the same code paths (e.g. an in-process web-host test harness against ephemeral containers, or an HTTP-assertion suite against an ephemeral DB, etc.); (c) the substitution is explicitly documented in the return summary AND in qa-report.html; (d) a 🐛 Batch QA environmental note is posted on the first batched issue. Otherwise halt with diagnosis.
    3. Drive the Junior-tester plan from Step A. Use Playwright MCP for UI clicks. For UI screenshots prefer `mcp__playwright__browser_snapshot` (no file written). When taking a `browser_take_screenshot` for visual evidence (dark-mode, layout regression), ALWAYS pass `filename` as an absolute path under `<session-folder>/screenshots/<issue>-<descriptor>.png` (the MCP server's CWD is the repo root, not your worktree — relative filenames leak PNGs into the repo as untracked files). Create `<session-folder>/screenshots/` yourself if missing.

  Step C — For every bug or AC-gap found:
    • Fix it in the batch worktree.
    • Commit `fix(qa): <short> (#<affected-issue>)`. One bug per commit.
    • Push.
    • Re-verify the AC.
    • Post 🐛 Batch QA finding on the SPECIFIC story's issue with diagnosis + fix commit SHA.

  Step D — After fixes, re-run Gates 1 + 2 to confirm no regression.

  Step E — Release the stack lock and stop the stack.

  Step F — Post on EACH batched issue: 📦 Batch status — "Batch QA green" (with a summary if fixes applied).

THE QA GATE IS MANDATORY. You may not skip it or substitute green CI for it. The Junior-tester plan content scales (backend-only stories explain their evidence; UI stories give clickpaths); the *execution* is non-negotiable except via the environmental escape hatch above.

══════════════════════════════════════════════════════════════════════
QA HTML report — JUNIOR-FRIENDLY (this is the user-facing artifact)
══════════════════════════════════════════════════════════════════════

After Gate 3 passes, write `<session-folder>/qa-report.html` so a junior tester with **no domain or tech-stack knowledge** can replay the QA in ~30 minutes using only a browser.

Required slides (one `<section class="slide">` each, `page-break-before: always`):

  1. **Cover** — batch branch name, batched issues with titles, gh-login, today's date, total issues, total commits since main, status pill `BATCH QA GREEN — Draft PR open, awaiting human QA + merge`.

  2. **Stories shipped** — table of (issue #, plain-English one-liner of what changed for a user, files changed count, link to issue, link to per-issue squash commit). The one-liner must be readable by a non-developer ("Users can now reset their password from the login page" — not "AuthController.ResetAsync dispatches a TokenIssued event").

  3. **How to start the stack (Junior tester edition)** — one slide explaining EXACTLY which command(s) to run to bring up the stack, what to wait for (e.g. "wait until you see `Now listening on: http://localhost:<port>/`"), and where to open the browser. Auto-detected from project files. If the project documents a specific dev-startup command in CLAUDE.md / README, use that verbatim.

  4. **Manual QA — junior-tester walkthrough** — THE CORE SLIDE. For each batched issue:
     - Heading: "Issue #<N> — <plain-English summary>"
     - Subheading: "What the team did" — 1-2 sentences in plain English (no jargon).
     - Subheading: "How to verify in the browser":
       - Numbered step list. Each step is: ACTION (verb in bold) + EXPECTED OUTCOME.
       - Example step: *"**Click** the '<nav item>' link in the left sidebar → you should see a list of recent rows with timestamps."*
       - 5-15 steps per issue typically.
     - Subheading: "What to do if it looks wrong" — one or two failure modes the tester should escalate.
     - For backend-only issues: replace the click-path with "This change has no visible UI. The team verified it via the automated tests listed in the Developer Evidence appendix below."

  5. **i18n / locale verification** (if the project has multiple locales): per locale, explicit toggle instructions + 2-3 spot-check sentences the tester should see in that locale. No raw keys (e.g. `welcome.title`) should leak — junior tester is instructed to flag anything that looks like raw curly-brace text.

  6. **Bugs found + fixed during batch QA** — table of (story, finding, severity, fix commit SHA, retest result). If empty: `<p class="empty">None — QA was clean.</p>`.

  7. **Cross-story integrations checked** — bullets in plain English ("After enabling the new feature toggle from story A, the existing list from story B still shows its old entries correctly — no rows broke.")

  8. **Developer Evidence appendix** — for repeat-runs and engineers who want the raw test commands. Tables of test names + pass/total. Click-paths only if they used Playwright MCP and need to be replayable verbatim. This is the ONLY slide where developer commands live; everything else is browser-only.

Style: dark GitHub-style theme (`#0d1117` bg, `#c9d1d9` text). No external assets, no JS frameworks. Interpolate placeholders directly. The HTML must be self-contained.

After writing: verify file exists and size > 1 KiB. Post 📦 Batch status — "QA report written: qa-report.html" on the first batched issue with the absolute path.

══════════════════════════════════════════════════════════════════════
Open Draft PR (batch → main)
══════════════════════════════════════════════════════════════════════

Only after Gate 1 + Gate 2 + Gate 3 + QA HTML all succeed:

  gh pr create --base main --head <batch-branch> --draft \
    --title "[batch] <gh-login> — <count> issues (#<N1>, #<N2>, #<N3>, ...) — <date>" \
    --body "<batch PR body, see below>"

Title format notes:
  • `<count>` = number of batched issues.
  • The parenthesized list is EVERY batched issue number, comma-separated with a `#` prefix on each (GitHub auto-links them in the PR list view).
  • `<date>` = today's date as `YYYY-MM-DD` (orchestrator local time at PR creation).
  • Example: `[batch] <gh-login> — 4 issues (#12, #34, #56, #78) — YYYY-MM-DD`

Batch PR body template:
```
## Batch summary
This Draft PR integrates <count> issues merged sequentially via /sequential-batch-pipeline-orion.

**Issues shipped:** #<N1>, #<N2>, …, #<Nk>

**Per-issue PRs (merged into this branch):**
- #<pr1> — <title1> (#<N1>)
- #<pr2> — <title2> (#<N2>)

## Pre-merge gates
- [x] Per-issue BMAD code review + build + tests (per-issue PRs)
- [x] Full test suite (batch)
- [x] Full e2e suite (batch)
- [x] Live-stack Junior-tester QA gate (batch)
- [ ] Human QA (manual — replay `<session-folder>/qa-report.html`)
- [ ] Manual merge into main

## Artifacts
- QA report: `<session-folder>/qa-report.html`
- Run log: `<session-folder>/run.jsonl`
- Session folder: `<session-folder>`

## Closes
Issues are NOT auto-closed by this PR. They close automatically when the orchestrator detects the merge in Phase 4.
```

══════════════════════════════════════════════════════════════════════
Merge-conflict handling
══════════════════════════════════════════════════════════════════════

If GitHub reports the PR as not-mergeable, or `git merge-tree origin/main origin/<batch-branch>` shows conflicts:
  1. Rebase: `git fetch origin main && git rebase origin/main` inside the batch worktree.
  2. For each conflicting file, BEFORE editing, read the dev/review notes that touch that file:
     `gh issue view <N> --json comments --jq '.comments[].body' | grep -F '<filename>'`
     for every batched issue that touched the file (use `git log --oneline origin/main..HEAD -- <filename>` to identify which).
  3. Decide between AUTONOMOUS ADDITIVE RESOLUTION vs HALT:
     **Autonomous additive resolution is permitted ONLY when ALL FOUR gates pass:**
       a. **Scope gate** — at most ~2-3 conflicting files. Larger conflict surfaces have too many interactions to merge confidently without a human.
       b. **Recipe gate** — you can WRITE a clear additive-merge recipe in plain English BEFORE editing: which lines from `<their version>` (main) and which lines from `<our version>` (batch) coexist, in what order. If you can't articulate the recipe, you can't apply it safely.
       c. **Dev-notes gate** — every batched issue that touched each conflicting file has dev-handoff notes (🤝 Dev → Review handoff) documenting the intent of its contribution to those files. The notes must show the contributions are SEMANTICALLY COMPLEMENTARY (both additive feature paths that can coexist — e.g. two independent additive call sites on the same code path), NOT contradictory (e.g. both setting the same field to different values).
       d. **Test-safety gate** — there is a targeted test suite for the affected slice (per-feature test file, not a smoke test) that you can run AFTER applying the recipe to detect a misjoin. The FULL project test suite is your second safety net but must also pass.
     If ALL FOUR gates pass: write the recipe into the PR body BEFORE applying it (for audit). Apply the recipe. Run targeted tests; on red, abort and HALT. On green, run the FULL suite; on red, abort and HALT. Both green → log `additive-rebase-applied` with the file list + recipe text, post 📦 Batch status "Batch rebased; conflicts resolved autonomously per dev-handoff notes" on every batched issue with the recipe link, and continue Phase 2 normally.
     If ANY gate fails: HALT. Do NOT guess. Write the resolution recipe (with the gate that failed marked) into the PR body for the human reviewer.
  4. After (only on successful additive resolution): `git add <files>`, `git rebase --continue`, force-push the batch branch (`git push --force-with-lease`).
  5. Post 📦 Batch status — "Batch rebased; conflicts resolved using dev notes" on every batched issue with the list of resolved files.
  6. If gates fail or rebase produces a worse state: abort rebase (`git rebase --abort`) and HALT with which files conflicted + which gate failed + the recipe you would have applied if a human had cleared it.

══════════════════════════════════════════════════════════════════════
Return summary
══════════════════════════════════════════════════════════════════════

Return to me (the orchestrator) with the literal line `batch-qa-status: green` (passed) or `batch-qa-status: failed — <reason>`.

Fields:
  • batch-qa-status: green | failed — <reason>
  • Full test suite: pass/total
  • Full e2e suite: pass/total
  • Live-stack QA: N bugs found+fixed (list commit SHAs) | clean
  • Environmental escape used? (yes — describe substitute coverage / no)
  • Draft PR number + URL
  • QA report path: <abs-path>
  • Conflict resolution: none | resolved (list files) | unresolvable (list files)
  • Stack lock owned? (must be no — released in Step E)
```

When the sub-agent returns:
- Parse for `batch-qa-status: green`. Absent or `failed` → halt per Failure handling.
- Log `batch-qa-returned` (pass/fail), capture Draft PR number + URL.
- Post 📦 Batch status — "Draft PR opened: <pr-url>. Awaiting human QA + manual merge. Issue will close when batch lands on main." on EACH batched issue.
- Log `queue-end`.

### 2.3 Batch-QA worktree disposition

Do NOT tear down the batch-QA worktree at the end of Phase 2 — preserve it so the user can navigate the integrated code locally during their manual QA. The orchestrator removes it in Phase 4 after batch→main merge.

---

## Phase 3 — Wait for batch→main merge (autonomous long-poll)

Schedule the long-poll **autonomously**. No user question.

### Mechanics

Poll cadence: **1 hour.** Use `ScheduleWakeup` (not a tight sleep loop) so the orchestrator releases the foreground between polls.

**ScheduleWakeup call pattern (mandatory — do not skip the verbatim Phase 4 procedure inside the prompt):**

```
ScheduleWakeup(
  delaySeconds: 3600,
  reason: "long-poll for manual batch→main merge of PR #<pr-number>",
  prompt: "<RESUME PROMPT — see template immediately below>"
)
```

**RESUME PROMPT TEMPLATE** (substitute every bracketed value at scheduling time; copy-paste the ENTIRE Phase 4 procedure verbatim — Finding #26: paraphrasing has been shown to drop the Phase 4.3 status-HTML step):

```
You are resuming /sequential-batch-pipeline-orion Phase 3 long-poll for run <timestamp>.

State:
- Batch branch: <batch-branch>
- Draft PR: #<pr-number> (<pr-url>)
- Batched issues: #<N1>, #<N2>, …, #<Nk>
- Session folder: <session-folder>
- Repo root: <repo-root>
- Status HTML target: ~/Downloads/<repo-name>-status-<DD_MM_YYYY>.html (use TODAY's date at the time you wake up, not at the time this prompt was authored).

Step 0 — MANDATORY session-complete sentinel check (idempotency gate, runs BEFORE anything else):
  Check whether <session-folder>/.session-complete exists.
  If it exists, this is a GHOST wake-up firing after the run already finished (Phase 4 ran via an earlier wake-up OR via a user text signal that bypassed the schedule). DO NOT re-execute Phase 4 — that would post duplicate "Merged" comments, regenerate status-HTML, and overwrite the manifest.
  Required actions on sentinel-present:
    1. Read the sentinel contents (it has status=succeeded|abandoned, merge-sha, merged-at, finalized-at).
    2. Append a `ghost-wakeup-skipped` event to <session-folder>/run.jsonl with the sentinel's contents.
    3. Print ONE line to the user: "Phase 3 ghost wake-up neutralized — run already complete (status=<status>, finalized-at=<finalized-at>)."
    4. DO NOT call ScheduleWakeup again. DO NOT touch the manifest, status-HTML, issues, branches, or worktrees.
    5. Exit the turn immediately. Do not proceed to Step 1.

  Rationale: `ScheduleWakeup`'s queue semantics (replace vs append) are not 100% documented. This gate makes the orchestrator tolerant of either by treating the sentinel as the single source of truth for "run done." Belt-and-suspenders.

Step 1 — Poll PR state (only runs if Step 0's gate passes):
  gh pr view <pr-number> --json state,mergedAt,mergeCommit,closedAt

Step 2 — Branch on state:
  - state == "MERGED" → capture mergeCommit.oid, log `merge-detected`, proceed to Phase 4 below.
  - state == "CLOSED" AND mergedAt == null → log `abandoned`. Write <session-folder>/.session-complete with content `status=abandoned\nclosed-at=<closedAt>\nfinalized-at=<now ISO>\nbatched-issues=<comma-separated list>\nbatch-pr=<pr-url>` so any later ghost wake-up exits via the sentinel gate at Step 0. Print exit summary. Leave session folder + batch worktree + batch branch intact. End.
  - state == "OPEN" → log `wait-poll`. Re-schedule ANOTHER ScheduleWakeup with delaySeconds 3600 and this SAME resume prompt. If wait has exceeded 12 hours since last `compact-checkpoint`, log a `compact-checkpoint` entry and surface to the user: "Phase 3 long-poll has been running >12 hours since last compact-checkpoint — consider running /compact." Then re-schedule.

══════════════════════════════════════════════════════════════════════
PHASE 4 — Post-merge finalization (only when state == MERGED)
══════════════════════════════════════════════════════════════════════

Run these steps in order. On any failure mid-Phase-4, log diagnosis but continue with the remaining steps where possible (the merge already happened — finalization is best-effort hygiene). Halt only if a step is logically dependent on a prior failed step.

4.1 — Verify merge on main:
  cd <repo-root>
  git fetch origin <default-branch>
  git pull --ff-only origin <default-branch>
  git merge-base --is-ancestor <merge-sha> origin/<default-branch>
  If not ancestor → log hard error, re-poll once after 60s wait; if still missing, halt with diagnosis.

4.1a — Auto-close keyword leak audit (deterministic detection of Agent-D contract bypass):
  For each per-issue squash commit on the batch branch (the ones Agent D produced before batch→main merge):
    git log <merge-sha>~1..<merge-sha> --format=%B | head -n 200    # only relevant when batch was squash-merged into main
    OR walk per-issue squash SHAs captured in run.jsonl: `git show --no-patch --format=%B <squash-sha>` for each.
  Grep each commit message body (case-insensitive) for the regex:
    \b(close[sd]?|fix(es|ed)?|resolve[sd]?)\s+#[0-9]+
  Also, BEFORE running 4.2's `gh issue close` calls, fetch the current state of every batched issue: `gh issue view <N> --json state --jq .state`.
  Two failure modes to detect:
    (a) Keyword found in a commit message → log `auto-close-keyword-leaked` with issue #, commit SHA, exact matched text. This is an Agent D contract violation that escaped detection in Phase 1; flag for the lessons-learned file.
    (b) An issue is already CLOSED before 4.2 reaches it → log `issue-already-closed` with issue # and `closed_at` timestamp. The Phase 4.2 loop must tolerate this gracefully: SKIP the `gh issue close` call (it would error or no-op) but STILL post the audit comment from 4.2 (the comment is the source-of-truth record; the close was incidental).
  Neither failure halts Phase 4 — they are detective, not blocking. Both are logged for postmortem.

4.2 — Close each batched issue (loop over #<N1>, #<N2>, …):
  for each N:
    gh issue comment N --body "✅ This issue shipped via batch <batch-branch>, merged to main as <merge-sha> in PR #<pr-number>.

    - Per-issue PR: #<story-pr-number>
    - Squash commit on batch: <squash-sha>
    - Acceptance criteria: all ✓ (see issue body)
    - Batch QA: green (see qa-report.html in session folder)

    Closing now."
    # Tolerate already-closed issues from the 4.1a audit — post the audit comment regardless of state.
    # gh issue close on an already-closed issue is a no-op; suppress its error.
    gh issue close N --reason completed  (suppress error if 4.1a flagged this issue as already CLOSED)
    gh issue edit N --remove-label wip  (suppress 'not present' errors)
  Log `finalize-start` before the loop and `issue-closed` per issue (or `issue-already-closed-audit-comment-posted` if 4.1a flagged it).

4.3 — Update status HTML presentation in place:
  a. Discover the source file. Run THREE independent listing methods and log each attempt's raw result to `run.jsonl` as `status-html-discovery-attempt` (one log entry per method with the method name, command, and result count):
       - **Method 1** — Get-ChildItem with -Filter: `Get-ChildItem "$env:USERPROFILE\Downloads" -Filter "<repo-name>-status-*.html"`.
       - **Method 2** — Glob path: `Get-ChildItem "$env:USERPROFILE\Downloads\<repo-name>-status-*.html"` (path-embedded pattern; behaves differently from -Filter on some PowerShell versions).
       - **Method 3** — Test-Path against date-stamped names: probe today's filename `<repo-name>-status-<DD_MM_YYYY>.html` and yesterday's (in case run crossed midnight). On hit, treat as found.
     Take the union of all hits; pick the most recent by mtime as the source.
     Only if ALL THREE methods return empty: log `status-html-missing` (with all three attempt records as context) and skip the rest of this step (best-effort — do not halt). Bash equivalents (POSIX): `find ~/Downloads -maxdepth 1 -name '<repo-name>-status-*.html'`, `ls ~/Downloads/<repo-name>-status-*.html 2>/dev/null`, `test -e ~/Downloads/<repo-name>-status-<DD_MM_YYYY>.html`.
  b. Read the existing file in full. Preserve verbatim except for the sections this step explicitly rewrites.
  c. Re-derive dynamic sections from live state:
       - Completed / in-progress / blocked issue counts: gh issue list --state all --limit 1000 --json number,state,labels,closedAt,createdAt
       - Recent merges (last 30 days): gh pr list --state merged --base <default-branch> --limit 200 --json number,title,mergedAt,labels
       - Velocity / lead time / per-epic / per-story checkboxes: parse from the above
       - This batch's just-merged issues: highlighted as "newly shipped" with merge SHA + per-issue PR links
     Sections identified by <section data-update-key="<key>"> markers if present, else by <h2> heading text (case-insensitive substring: "status", "progress", "velocity", "completed", "in progress", "upcoming", "newly shipped", "stories", "epics"). Unmatched sections preserved verbatim.
  d. INSERT OR UPDATE the version block INSIDE the cover slide (NOT as a body-level header — that would render above every slide).
     - Locate the cover slide: the first `<section class="slide">` (or `<section class="slide chapter">`) inside `<template id="slides">`. Tag it `data-update-key="cover"` on the first run if not already present so subsequent runs find it deterministically.
     - Look for `<div class="status-version-block">` inside the cover slide.
     - **First run** (block absent): INSERT this block as the LAST child of the cover slide, just before its closing `</section>`. Interpolate `<CURRENT-LOCAL-TIME-DDMMYYYY-HHmm>` as today's local time in `DD-MM-YYYY HH:mm` format — e.g. `20-05-2026 17:35` — NOT ISO 8601, NOT milliseconds. Interpolate `<BATCH-BRANCH>`, `<PR-URL>`, `<PR-NUMBER>`, and the batched-issues `(#<N1>, #<N2>, …)` list.
       ```
       <div class="status-version-block" style="margin-top:32px;padding:16px 20px;background:#0d1117;border:1px solid #30363d;border-radius:6px;font:13px/1.5 ui-monospace,SFMono-Regular,Consolas,monospace;color:#c9d1d9;">
         <div style="display:flex;flex-wrap:wrap;gap:24px;align-items:center;margin-bottom:12px;">
           <span>last updated: <strong><CURRENT-LOCAL-TIME-DDMMYYYY-HHmm></strong></span>
         </div>
         <h3 style="margin:14px 0 6px;color:#c9d1d9;font-size:14px;">Update history</h3>
         <p style="color:#8b949e;margin:0 0 8px;font-size:12px;">Each batch run appends one row below — oldest at top, newest at bottom. Never rewritten.</p>
         <ul data-update-history style="list-style:none;padding:0;margin:0;font:13px/1.7 ui-monospace,SFMono-Regular,Consolas,monospace;">
           <!-- rows appended below; do not edit existing rows -->
           <li style="padding:6px 0;border-bottom:1px solid #1f2428;">
             <span style="color:#58a6ff;"><CURRENT-LOCAL-TIME-DDMMYYYY-HHmm></span>
             &nbsp;—&nbsp; batch PR
             <a href="<PR-URL>" style="color:#58a6ff;">#<PR-NUMBER></a>
             &nbsp;
             <span style="color:#8b949e;">(#<N1>, #<N2>, #<N3>, ...)</span>
           </li>
         </ul>
       </div>
       ```
     - **Subsequent runs** (block present): UPDATE the `<strong>` inside `last updated:` to today's timestamp, AND APPEND ONE new `<li>` row to the END of `<ul data-update-history>` — never rewrite existing rows. Row template:
       ```
       <li style="padding:6px 0;border-bottom:1px solid #1f2428;">
         <span style="color:#58a6ff;"><CURRENT-LOCAL-TIME-DDMMYYYY-HHmm></span>
         &nbsp;—&nbsp; batch PR
         <a href="<PR-URL>" style="color:#58a6ff;">#<PR-NUMBER></a>
         &nbsp;
         <span style="color:#8b949e;">(#<N1>, #<N2>, #<N3>, ...)</span>
       </li>
       ```
     - DO NOT inject anything at body level (e.g. no `status-version-banner` div outside the deck) — the deck container renders only one slide at a time, so anything outside it would be visible above every slide.
  e. Compute new filename: `<repo-name>-status-<DD_MM_YYYY>.html` using TODAY's local date (not original-run date).
  f. Write + rename:
     - If source filename == new filename (same path, same repo-name, same date) → write over in place.
     - Else → write under the new filename, then delete the old source file.
     - If multiple `<repo-name>-status-*.html` files accumulated for any reason: delete every one EXCEPT the one just written. Result: exactly ONE status HTML in ~/Downloads/.
  g. Report the diff in the final printout: which sections changed (before → after numbers), whether the version block was newly inserted vs updated, how many history rows the file now has. Log `status-html-updated` with the final path.

4.4 — Teardown:
  a. Remove batch-QA worktree:
     git worktree remove --force <worktree-parent>/<repo-name>-batch-<timestamp>
     git worktree prune
  b. Delete batch branch (local + remote — gh's PR merge should have removed remote already; be defensive):
     git branch -D <batch-branch>
     git push origin --delete <batch-branch>  (suppress 'remote ref does not exist' errors)
  Log `cleanup-complete`.

4.5 — Manifest + final printout + session-complete sentinel:
  Write <session-folder>/manifest.md with Status: succeeded.
  Write <session-folder>/.session-complete with content:
      status=succeeded
      merge-sha=<merge-sha>
      merged-at=<mergedAt ISO timestamp from gh>
      finalized-at=<now ISO timestamp>
      batched-issues=<comma-separated list of issue numbers>
      batch-pr=<batch-pr-url>
  This sentinel is what every future wake-up's Step 0 idempotency gate checks. Without it, any queued ghost ScheduleWakeup that fires after Phase 4 completes would re-execute Phase 4 — posting duplicate close comments, regenerating status-HTML, overwriting the manifest. With it, the ghost exits cleanly at Step 0.
  Print final summary (batched issues, PR URL, merge SHA, status-html path, sections updated, wall time).
  Log `session-complete`.
END OF RESUME PROMPT
```

### Pre-poll sentinel

Before scheduling the first wake-up: log `wait-start` and post a courtesy 📦 Batch status — "Waiting for batch→main merge. Polling hourly." on the first batched issue (just one — not all — to avoid spam).

### Compact cadence during the wait

Every 12 hours of wait OR every 3 poll cycles (whichever comes first), log a `compact-checkpoint` entry and surface a one-line note to the user. Do not attempt to call `/compact` programmatically — it is CLI-only.

### Main drift policy

Ignored. The orchestrator does NOT compare the batch base ref against main during the wait. If main advances and the manual merge becomes problematic, that is the human's concern at merge time (the batch-QA agent will rebase if needed during Phase 2 conflict-resolution; during Phase 3 wait we don't touch the batch).

---

## Phase 4 — Post-merge finalization

Phase 4 procedure is embedded verbatim in the Phase 3 ScheduleWakeup resume prompt above. When the wake-up fires and detects `state == MERGED`, the resumed orchestrator executes 4.1 → 4.5 exactly as listed there.

If the orchestrator is still in-context when the merge happens (rare — usually the conversation is cleared and resumed via ScheduleWakeup), execute 4.1 → 4.5 directly using the same procedure.

---

## Failure handling

On any halt:
1. Log a `fail` or `blocked` entry with the diagnosis.
2. Do NOT tear down: the failing issue's worktree + story branch, the batch worktree (if Phase 2), the batch branch, the batched issues, the Draft PR (if open), or the session folder. Leave everything in place.
3. Write `<session-folder>/manifest.md` with `Status: halted` and the halt diagnosis.
4. Print a stop report (batch branch, session folder, worktrees, remaining queue, log + manifest paths).
5. Stop. Do not retry, do not skip, do not ask the user "continue?".

### Halt-condition rules (each phase section spells out the specifics)

Three universal rules, applied per phase:

1. **Missing or invalid terminal status line** (no `agent-status:` line for A/B/C/D, no `batch-qa-status:` line for Phase 2, or an invented sentinel like `terminal`/`complete`/`finished`) → attempt Terminal-line recovery (Phase 1.4) FIRST. On recovery failure → halt. Recovery does NOT apply to Phase 2 batch-QA (single agent, much higher stakes — halt directly so the user inspects).
2. **Logical incomplete** (sub-agent returns `... incomplete — <reason>`) → halt. No retry; the contract is broken and needs fixing.
3. **Runtime crash** (tool error envelope, no return summary) → retry ONCE on the same agent slot. Second crash on the same slot halts.

Phase-specific overlays (the only deviations from the three rules):

- **Phase 1 teardown**: worktree/branch deletion failures = `cleanup-incomplete` warning, not halt (the merge already succeeded).
- **Phase 3 wait**: `CLOSED` without `mergedAt` is NOT a halt — it's `abandoned` (clean exit, skip Phase 4). `OPEN` indefinitely is NOT a halt — keep polling.
- **Phase 4**: best-effort hygiene — per-issue close failures, status-HTML update failures, worktree teardown failures → log + continue. Only "merge SHA not on local main after refetch" halts.

---

## What this skill does NOT do

Only facts not stated elsewhere in this file (Core principles + per-phase sections cover the rest):

- Does not discover issues (no `/pick-next-issue` integration — issue numbers are user-supplied; `@me` is the autodiscovery shortcut).
- Does not rebase the batch branch onto main during Phase 3 wait — drift is ignored.
- Does not force-push (except during batch-QA conflict-resolution rebase, with `--force-with-lease`) or skip hooks.
- Does not delete worktrees or branches of issues that haven't completed (preserved on failure).
- Does not run live-stack QA per issue. The live-stack Junior-tester QA gate runs ONCE on the integrated batch branch in Phase 2.
- Does not write a per-issue HTML report. ONE `qa-report.html` per session. The long-lived `<repo-name>-status-*.html` stays at `~/Downloads/` root and is never moved into the session folder.

---

## Cleanup checklist (every run)

- [ ] Session folder created at `<session-folder>` (NOT inside the repo).
- [ ] No marker files written into the repo (no `.sequential-state`, `.run-status`, etc.).
- [ ] No `.gitignore` additions for skill artifacts.
- [ ] On success: per-issue worktrees + branches + remote refs gone; batch worktree + batch branch + remote ref gone (in Phase 4); Draft PR merged.
- [ ] On halt: nothing torn down beyond what completed normally before the halt.
- [ ] Stale stack-lock cleared between issues and between phases.
- [ ] Log file closed and present at `<session-folder>/run.jsonl`.
- [ ] Manifest written at `<session-folder>/manifest.md`.
- [ ] On success: status HTML renamed to today's date under the `<repo-name>-status-*.html` pattern, cover-slide version block inserted/updated with `DD-MM-YYYY HH:mm` timestamp, one new history row appended, exactly ONE `<repo-name>-status-*.html` remaining in `~/Downloads/`.

---

## Implementation notes for the orchestrator (you)

Mechanical details not covered elsewhere:

- **Shell tool selection**: prefer the platform's native shell (PowerShell on Windows, Bash on POSIX). Both work via the corresponding tool. When the prompt template gives a command in only one shell's syntax, translate to the other if needed — git/gh commands are identical; only filesystem ops (`Remove-Item` vs `rm -rf`, `Move-Item` vs `mv`, `Test-Path` vs `test -e`) differ.
- **Log file append**: PowerShell `Add-Content -Path <path> -Value <json> -Encoding utf8`, or Bash `echo '<json>' >> <path>`. JSONL = one object per line.
- **Stay on default branch**: the orchestrator must remain on `main` (or the repo's default branch) in `<repo-root>` throughout. Never `cd` away. All worktree operations use absolute or sibling-relative paths.
- **Mid-loop user message**: if the user sends a message while you're mid-loop (e.g. "stop"), treat it as an explicit halt — finish the in-flight sub-agent's current step if possible, then stop. Do not start the next issue.

---

## Version

**v2.4.** Hardened across multiple real end-to-end batch runs; each iteration's lessons were folded directly into the inline agent contracts and orchestration steps above rather than kept as a separate changelog. The current behaviour — all specified in full in the sections above — includes:

- **Agent terminal-line contract** with an explicit invalid-sentinel list and ONE `SendMessage` recovery per agent slot before halting (Phase 1.4).
- **Sub-agent scratch-file contract** — intermediate files go under `<session-folder>/scratch/<agent-slot>/`, never to user-visible locations (shared boilerplate).
- **Auto-close-keyword ban** across the commit subject/body/footer and the PR body, with a Phase 4.1a detective audit that also tolerates already-closed issues (Agent D + Phase 4).
- **Status-HTML multi-method discovery** (three independent listing methods) before declaring the file missing (Phase 4.3).
- **Cross-queue baseline-failure aggregation** feeding a priority callout into the batch-QA agent (Agent D + Phase 2).
- **Long-batch drift warning** plus **autonomous additive rebase** gated behind four safety checks; any gate fails → halt with the resolution recipe written into the PR body (Phase 0 step 5c + Phase 2 merge-conflict handling).
- **Project-agnostic by construction** — branch names, folder names, and status-HTML filenames all derive from `<repo-name>` (resolved at Phase 0 step 6); agents detect the toolchain from project files. No project-specific paths, names, domain terms, or conventions are baked in.
