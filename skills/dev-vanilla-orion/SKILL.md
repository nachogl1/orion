---
name: dev-vanilla-orion
description: 'Label-gated batch development of 1-8 GitHub issues against a batch feature
  branch. Only issues a human consciously triaged as agent-ready + local-change run
  autonomously: per issue a plan -> TDD-implement -> review -> finalize sub-agent pipeline
  opens a real PR into the batch branch, merged only on a green FULL local build + test
  run. Issues labelled human-needed halt preflight for a focused Q&A; issues labelled
  outside-change never batch - they run solo and stop at a PR for a human reviewer.
  After the queue: tiered batch QA (full suites always; live browser walkthrough only
  when the batch touched UI) producing ONE consolidated qa-report.html, then a batch PR
  the HUMAN merges. Halt-on-failure (pause and converse; never auto-skip). Process
  friction is journalled to a findings store under forced triggers. Project facts come
  from a per-repo config file written by a first-run interview; toolchain is
  auto-detected. Use when the user says "/dev-vanilla-orion <issues>", "run a batch of
  issues", "develop issues N..M as a batch".
  Do NOT use for: picking which issues to work (use an issue-assignment skill), a
  report-driven human-paced QA pass (use a guided-QA skill), or single-file trivial
  edits that need no pipeline.'
---

# dev-vanilla-orion

> [!NOTE]
> **Editing this skill?** No `-vN` convention — edit it **in place** (see the repo's
> `CLAUDE.md`). Keep changes backward-compatible where you reasonably can; this skill
> keeps a `CHANGELOG.md` for notable behaviour changes.

You are the **ORCHESTRATOR (conductor)**. You never implement, review, or QA anything
yourself — you spawn sub-agents that do, in their own clean contexts, handing off through
files on disk and short structured return summaries. This is what keeps a long batch +
QA run from drowning a single context. You prep git/GitHub state, spawn, parse returns,
gate merges, and converse with the user at the defined pause points.

## Core principles

1. **Production-ready is the bar.** Every batched issue ships in a state a senior dev
   would merge without follow-up: tests green, no stubbed acceptance criteria, no
   placeholder markers, project conventions followed.
2. **Labels gate autonomy.** Nothing untriaged is ever developed. Autonomy is granted
   per-issue by a human, in advance, via labels (see Labels contract) — never assumed.
3. **Strict serialization.** One issue at a time; issue `i+1` starts only after `i` is
   merged into the batch branch and its worktree is gone. No parallel worktrees — batch
   runs share real resources (local DB containers, ports, the test stack).
4. **The conductor never works.** All code-touching and QA work happens in sub-agents.
   The conductor reads structured summaries only — never full diffs, never test logs
   beyond the tail needed for a gate decision.
5. **Halt on failure — pause and converse.** When an issue fails past its bounded
   retries, the WHOLE run stops and waits for the user (diagnosis + failure folder).
   Skipping an issue happens only on the user's explicit word, never automatically.
6. **A human merges the batch.** The skill never merges, closes, or auto-merges the
   batch PR. Per-issue PRs into the *batch branch* are agent-merged after their gate;
   the batch → base merge is always the human's.
7. **Every deferral carries a tracked `#N`.** Find-or-REUSE before filing (search open
   issues first; never duplicate). No "out of scope" line without a trailing `#N`.
8. **Findings under forced triggers.** Any retry, crash, hook block, halt, or workaround
   MUST append a finding to the findings store (see Findings contract). Not optional.
9. **Respect the boundary.** Never write outside the configured boundary repos (plus
   session/temp dirs) — except in Solo outside-change mode, and there only inside the
   declared target repo with the user aware. A machine-level hook may additionally
   enforce this on some machines; never depend on it, never fight it.
10. **Fix-in-place-first.** A review/QA finding is fixed NOW when it is small, local,
    covered by running tests, low blast-radius, and scope-neutral. Deferral (with `#N`)
    is only for findings that fail that test. "Not in the ACs" alone is not a reason to
    defer.

## Config resolution (always the first step)

Project facts live in `<repo-root>/.claude/dev-vanilla-orion.yaml`. Resolve before
anything else:

1. **Config exists** → load it. **Missing** → run the **first-run interview** (one
   `AskUserQuestion` round, junior-dev phrasing, recommended defaults marked):
   - `project` — short name for this project/engagement (one process may span several repos).
   - `boundary_repos` — repos an agent may write to (default: the current repo only).
     Sibling repos are resolved relative to the current repo's parent directory.
   - `e2e_location` — path to the end-to-end test suite, possibly a sibling repo, or `none`.
   - `review_checklist` — a locally available review skill to use as the review agent's
     checklist (e.g. a PR-review skill the project already ships), or `builtin`.
   - `secondbrain_path` — local clone of the private findings store, or `none`
     (findings then land only in the session folder).
   - `ui_paths` — path globs that count as UI for QA tiering (default: auto-detect
     common frontend dirs).
2. After the interview: write the config file, and append its filename to
   `<repo-root>/.git/info/exclude` (create the file if absent) so it can never appear in
   a diff or PR. If `secondbrain_path` is set, ensure
   `<secondbrain>/projects/<project>/{findings,harvests}/` exist.
3. **Auto-detected every run (never stored):** build/test commands from the project's
   own files (`package.json`, `*.csproj`/`*.sln*`, `pyproject.toml`, `go.mod`,
   `Cargo.toml`, `Makefile`, …) and docs (`CLAUDE.md`, `README.md`, `CONTRIBUTING.md`);
   the default branch; the base branch (= the branch the skill was invoked from).

Config schema (all written by the interview; hand-editing is fine):

```yaml
project: <name>
boundary_repos: [<repo-dir-name>, ...]
e2e_location: <path> | none
review_checklist: <skill-name> | builtin
secondbrain_path: <path> | none
ui_paths: [<glob>, ...] | auto
```

## Labels contract

Two axes, **exactly one label from each** on every issue the skill touches:

| Axis | Label | Meaning |
|---|---|---|
| Readiness | `agent-ready` | An agent can complete it end-to-end: concrete, testable ACs; no open questions; no TBDs; references resolvable; scoped to one reviewable PR |
| Readiness | `human-needed` | A human decision/answer is required before work can start |
| Blast zone | `local-change` | Every change lands inside `boundary_repos` |
| Blast zone | `outside-change` | At least one change lands outside `boundary_repos` |

Rules the skill enforces:

- **Missing or conflicting labels = untriaged.** The skill refuses to develop the issue.
  It deep-reads the body and **proposes** labels with evidence; labels are applied ONLY
  on the user's confirm. In a fully autonomous stretch, untriaged issues are excluded
  and reported as "skipped — untriaged", never developed silently.
- A part-local, part-outside issue must be **split into child issues** first — the skill
  says so and proposes the split (created only on confirm).
- `agent-ready` + `outside-change` is valid: development is autonomous, but the flow
  still ends at a human-gated PR (Solo mode).
- **Ensure-exist:** if any of the four labels is missing from the repo, list the exact
  `gh label create` commands and run them only on the user's confirm (one-time setup).

## Input parsing

Args are issue numbers: single (`12`), list (`12 15 20` / `12,15,20`), range (`12-15`),
or mixed. Dedupe. **Cap: 8 issues** — more → refuse and ask the user to split the batch.
Default order: **ascending**; an explicitly ordered list ("in this order: …") is honored.
No args → ask which issues to batch.

## Phase 0 — Preflight

1. **Environment:** `gh auth status` OK · inside a git repo · resolve `<base-branch>` =
   current branch (pull `--ff-only`; diverged → halt) · working tree has no staged
   changes · resolve config (above) · ensure the four labels exist (above).
2. **Fetch + validate** every issue: must be OPEN. List all violations at once.
3. **Label sanity** per issue → classification table printed to the user.
4. **Readiness audit** per issue — labels are intent, bodies rot, so audit even
   `agent-ready` issues: ACs concrete and testable? No TBD / open-question markers? Do
   referenced files/decisions exist? Does the batch's internal dependency order hold
   (`depends on #N` style references topo-sorted; cycles → halt)? Any failure → treat
   the issue as `human-needed` for this run.
5. **Triage conversation** (the one interactive stretch before autonomy):
   - `human-needed` (or audit-demoted): ask the user the concrete blocking questions.
     On answers → propose the updated issue body + relabel to `agent-ready`; apply on
     confirm; the issue joins the batch. Or the user drops it.
   - `outside-change`: excluded from the batch with a "run me solo" note (Solo mode).
   - Untriaged: propose labels (see Labels contract); on confirm they follow their axis.
6. **Solo dispatch:** exactly one issue passed AND it is `outside-change` → Solo mode.
   An `outside-change` issue inside a multi-issue list is never developed in that run.
7. **Batch setup:** session folder `~/Downloads/batch-<repo-name>-<timestamp>-i<N1>-<N2>…/`
   with `run.jsonl` (append-only event log; one JSON object per line: ts, phase, issue,
   status, detail). Batch branch `batch/<gh-login>/<timestamp>` from the fresh base
   branch; push with `-u`. Print the run plan. From here the batch is autonomous.

## Phase 1 — Per-issue pipeline (strictly sequential)

For each issue `N` in order — worktree `<worktree-parent>/<repo-name>-<N>` on branch
`feat/issue-<N>-<slug>` forked from the **current batch tip** (issue N sees N-1's code):

| Agent | Job | Returns |
|---|---|---|
| **P — plan** | Read the issue (+ its epic/linked docs). Write a short implementation plan + test list to `<worktree>/_plan-<N>.md`. No product code. | `agent-status: done` + plan path |
| **D — dev** | TDD-implement the plan: failing test → code → refactor. Follow the project's own conventions (its `CLAUDE.md`/docs). Targeted tests green. | `agent-status: done` + files/tests summary |
| **R — review** | Review the uncommitted diff against the configured `review_checklist` skill's checklist (read that skill's file locally) or the builtin list (correctness, security, tests-quality, conventions, AC trace vs the ISSUE's ACs — not the PR body's claims). Fix findings in place per the fix-in-place-first test; re-run targeted tests. | `agent-status: done` + findings fixed/deferred |
| **F — finalize** | Conventional commit(s), push, open PR **into the batch branch** with `Refs #<N>` (never `Closes` — issues stay open until batch lands), body = what/why + pasted test output. **Stops at PR-open.** | `agent-status: pr-opened pr:<n>` |

**Orchestrator-owned merge gate** (after F): run the project's **FULL build + FULL test
suite** in the worktree — this is the merge evidence, regardless of CI (many repos have
no CI wired to their PRs; when PR checks DO exist, additionally wait for them per
standard green-only rules; treat every present check as gating). Green → squash-merge
the per-issue PR into the batch branch, capture the SHA, tear down the worktree +
branch. Red → one focused fix re-dispatch to the failing area (bounded: 3 cycles) →
still red → failure procedure.

**Failure procedure (halt, don't skip):** per-agent runtime crash → retry (max 2). A
logical `incomplete` → one recovery sub-agent attempt. Past those bounds: write
`<session-folder>/failures/<N>-<slug>/` (diagnosis.md, last-state diff/status, agent
summaries), then **PAUSE the whole run** and converse: print the one-line diagnosis +
folder path and wait. The user chooses: retry the slot · "I fixed it, resume" · skip
this issue (only then: revert its batch contributions, close its PR, comment on the
issue, continue) · abort the batch. Every failure appends a finding (forced trigger).

Status comments: post short progress comments on each issue (queued → PR opened →
merged into batch → closed at finalize) so GitHub remains the source of truth.

## Phase 2 — Batch QA (autonomous, tiered)

QA worktree from the batch tip. Tiering: **full unit/integration suites always** (all of
them, front and back). **End-to-end suite + live browser walkthrough only when the batch
touched UI** (changed paths vs `ui_paths`/auto-detection) — a backend-only batch skips
the browser tier, and the report says so.

| Agent | Job |
|---|---|
| **QA-1 — test-and-fix** | Run the full suites (+ e2e when tiered in). For UI batches: live walkthrough of each batched issue's surface against the running stack, **as a human user** — start from the landing page and navigate by clicking, never deep-link to known URLs (an unreachable-by-clicking feature is itself a finding); cover happy path, role/permission gating, side-effects (endpoints fired, persisted rows), adjacent-area regressions, edge cases. Before declaring any UI click broken (or fine), prove it at DOM level — computed `pointer-events`, `elementFromPoint`, dispatched-event control — browser automation can silently no-op. Fix findings per fix-in-place-first; after any fix, re-run the affected gates; bugs too big to fix → defer with `#N` (find-or-reuse). Docker hygiene: clean-slate = containers + volumes only, NEVER images; wait for true stack readiness (health signal, not a port). Returns a structured handoff: gates green/failed, suites pass/total, fixes made, coverage caveats. |
| **QA-2 — report + PR** | Write **ONE consolidated `qa-report.html`** into the session folder: per-issue verdicts (✅/🟡/🔴), gate results, findings (fixed in-session vs deferred-with-`#N`), and an HONEST **"NOT verified"** list — everything the local stack cannot reach (external systems, cross-app handoffs) stated plainly; a passing gate is not proof of correctness, and the report never overstates. File the deferral tracking issues (find-or-reuse, whole-batch deduped) and back-link each `#N` into the per-issue PR bodies. Then open the **batch PR** (draft) batch → base: `Closes #<N>` line per completed issue, gate evidence, link to the report path. QA-failed state → the PR still opens, with a prominent DO-NOT-MERGE callout. |

## Phase 3 — Wait, then finalize

Print the batch PR URL + report path, then **pause and converse** — no polling, no
timers. On the user's "merged" signal (verify via `gh pr view` state): pre-close check
per issue (every deferral line carries a `#N`), close each batched issue with an audit
comment, tear down the QA worktree + batch branch, flush findings, and print the final
summary including the **count of unharvested findings** ("N findings accumulated —
worth a harvest pass" when ≥ 10). On "closed/abandoned": leave everything for
inspection, mark the run abandoned, exit clean.

## Solo mode — one `outside-change` issue

Invoked with exactly one issue labelled `outside-change`. This mode touches a repo
OUTSIDE the boundary, so it starts with an explicit confirm: name the target repo and
wait for the user's go (a machine-level boundary hook may additionally prompt on the
first write there — expected; the user approves once).

Same P → D → R → F pipeline, but: the worktree/branch live in the **target repo**; the
PR opens against the **target repo's default branch** with full evidence pasted; and the
run **stops dead at PR-open**: the user assigns a human reviewer from the team that owns
that repo, a human merges, and only on the user's later "merged" signal is the issue
closed. The skill never merges there, never pushes that repo's default branch, and
never chases the review. No batch, no QA phase (the owning repo's own gates apply);
the session folder still records the run and findings still apply.

## Findings contract (the process-improvement journal)

When `secondbrain_path` is configured, findings are files in
`<secondbrain>/projects/<project>/findings/`, one file per finding,
`YYYY-MM-DD-<slug>.md`:

```markdown
---
project: <project>
repo: <repo the event happened in — for multi-repo projects>
source: <agent/phase | orchestrator | hook>
type: bug | friction | idea | worked-well
harvested: false
---

<2-6 sentences: what happened, why it matters, workaround applied.>

**Suggested change:** <one line, or "none">
```

**Forced triggers** — a finding MUST be written on: any crash retry · any recovery
spawn · any hook block/prompt · any halt · any workaround · any gate red that needed a
fix cycle. Notably-smooth behaviour worth keeping is a `worked-well` finding (optional).
Product bugs are never findings — they are issues in the product repo. At run end,
commit + push the secondbrain (pull --rebase first; one-file-per-finding means
concurrent sessions never conflict). No secondbrain configured → findings append to
`<session-folder>/findings.md` instead.

## Failure handling

| Situation | Path |
|---|---|
| Preflight violation (auth, dirty tree, diverged base, >8 issues, cyclic deps) | Hard halt before any branch/folder exists |
| Agent crash | Retry ×2 → recovery ×1 → **pause-and-converse** |
| Merge gate red | Fix cycles ×3 → **pause-and-converse** |
| QA gates failed | Batch PR opens with DO-NOT-MERGE callout; still pause for the user |
| User says "stop" mid-run | Halt; failure record for the in-flight issue; nothing torn down beyond completed work |
| User claims "merged" but PR is OPEN | Push back conversationally; never finalize unverified |

## Hard constraints

- Never merge, auto-merge, or enable auto-merge on the **batch PR** — a human merges.
- Never commit or push to the base/default branch; never force-push; never bypass hooks.
- Never develop an untriaged or `human-needed` issue; never batch an `outside-change` issue.
- Never create, edit, or relabel a GitHub issue without the user's explicit confirm
  (status comments on batched issues are the contract's exception).
- Never start issue `i+1` before issue `i` is merged into the batch and torn down.
- Never let a deferral escape without a tracked `#N` (find-or-reuse before filing).
- Never write outside the boundary repos + session/temp dirs (Solo mode: only the
  declared target repo). Never write secrets or config into a committed path.
- Never paper over a red gate: no skipped/weakened tests, no widened timeouts to pass.

## Cleanup checklist (every run)

- [ ] Session folder outside every repo; `run.jsonl` present; no marker files in repos.
- [ ] On success: per-issue worktrees/branches gone; QA worktree + batch branch gone
      after finalize; every batched issue closed with its audit comment.
- [ ] On halt/abandon: completed work intact; failure folders written; nothing reverted
      without the user's word.
- [ ] Every per-issue PR merged into the batch had a green FULL local build+test (or
      green PR checks where they exist) at merge time.
- [ ] `qa-report.html` written and its absolute path reported.
- [ ] Findings flushed (secondbrain committed + pushed, or session-folder fallback);
      unharvested count reported.
