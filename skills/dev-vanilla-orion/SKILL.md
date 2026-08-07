---
name: dev-vanilla-orion
description: 'Label-gated batch development of 1-8 GitHub issues against a batch feature
  branch. Issues triaged agent-ready + local-change run autonomously - triage labels come
  from a human in advance or are auto-applied by the skill via an evidence-logged
  deep-read, with a readiness audit as the backstop gate:
  per issue a plan -> TDD-implement -> review -> finalize sub-agent pipeline
  opens a real PR into the batch branch, merged only on a green FULL local build + test
  run. Issues labelled human-needed are excluded from the run - labelled, commented with
  the blocking questions, and reported - so the batch never stalls on a Q&A; issues
  labelled outside-change never batch - they run solo and stop at a PR for a human reviewer.
  After the queue: tiered batch QA (full suites always; live browser walkthrough only
  when the batch touched UI), then a fresh-eyes review of the WHOLE combined diff for
  cross-issue defects no per-issue review can see, producing ONE consolidated
  qa-report.html, then a batch PR the HUMAN merges. Runs unattended by default: it asks
  NOTHING between invocation and batch-PR-open - config, triage labels and every in-place
  fix are decided from evidence, logged, and reported. Only four pauses exist: an
  unrecoverable issue failure, the batch PR merge, destroying work the run did not create,
  and a machine boundary-hook prompt. Process
  friction is journalled to a findings store under forced triggers. Project facts come
  from a per-repo config file auto-derived on first run; toolchain is
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
2. **Labels gate autonomy — and the skill can set them.** Nothing *unassessed* is ever
   developed. Triage labels come from a human in advance, or the skill applies them
   itself from an evidence-logged deep-read (see Labels contract). The readiness audit,
   not a human keystroke, is the gate.
3. **Strict serialization.** One issue at a time; issue `i+1` starts only after `i` is
   merged into the batch branch and its worktree is gone. No parallel worktrees — batch
   runs share real resources (local DB containers, ports, the test stack).
4. **The conductor never works.** All code-touching and QA work happens in sub-agents.
   The conductor reads structured summaries only — never full diffs, never test logs
   beyond the tail needed for a gate decision.
5. **Run to the end; halt only when truly stuck.** An issue that cannot be made green
   after its bounded self-recovery attempts stops the run with a diagnosis + failure
   folder — that is a real blocked state, not a checkpoint. Everything short of it is
   handled autonomously. An issue is never silently dropped from the batch: excluded
   issues are reported, commented on GitHub, and named in the report.
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

## Autonomy contract (read before pausing for anything)

Default mode is **`autonomy: full`** — the run is expected to go from invocation to
"batch PR is open" **without a single question**. Announce what you are doing and keep
going; never ask permission for anything on the autonomous list.

**Autonomous — do it, log it, do NOT ask:**

- Writing the per-repo config from auto-derived defaults (Config resolution).
- `gh label create` for any of the four triage labels missing from the repo.
- Applying triage labels to an unlabelled/conflictingly-labelled issue from a deep-read.
- Rewriting an issue body to sharpen ACs when the intent is unambiguous (audit comment
  records the before/after).
- Creating branches, worktrees, commits, per-issue PRs; squash-merging a per-issue PR
  into the **batch** branch once its gate is green; tearing its worktree down.
- Filing/reusing deferral tracking issues, posting status comments, assigning issues.
- Every in-place fix an R / QA-1 / BR agent decides on under fix-in-place-first.
- Opening the batch PR (draft).

**Not autonomous — these four pauses are the only ones that exist:**

| Pause | Why it survives |
|---|---|
| Unrecoverable issue failure (past bounded retries + recovery) | Genuinely blocked; no correct action to guess |
| Batch PR → base merge | A human owns the merge decision, always |
| Anything destructive to work that isn't this run's own (deleting a user branch/worktree, resetting, discarding uncommitted user changes) | Hard to undo |
| A write outside `boundary_repos` in Solo mode | Announced-and-proceed by default; a real *prompt* only if the machine's own boundary hook raises one |

**`autonomy: checkpointed`** restores the old behaviour — the skill then confirms label
writes, issue-body edits, and label creation before applying them. Set it in the config
only if you want to supervise triage.

**When you would have asked, do this instead:** pick the best-evidenced option, state the
choice and the evidence in one line, write it to `run.jsonl`, and continue. If the
evidence is genuinely absent, the issue is **excluded from this run** (reported +
commented) — the run does not stop for it.

## Config resolution (always the first step)

Project facts live in `<repo-root>/.claude/dev-vanilla-orion.yaml`. Resolve before
anything else:

1. **Config exists** → load it. **Missing** → **derive it and write it, without asking.**
   Every field has a safe auto-derivation; print the resolved table as "assumed config —
   edit `.claude/dev-vanilla-orion.yaml` to change it" and continue in the same breath:
   - `project` — the repo name (strip any owner prefix).
   - `boundary_repos` — the current repo only. Sibling repos are resolved relative to the
     current repo's parent directory; nothing is added without the user editing the file.
   - `e2e_location` — first match among the repo's own e2e dirs / e2e test scripts in
     `package.json` / a sibling dir whose name marks it as the e2e suite; else `none`.
   - `review_checklist` — an installed review skill if one is present in `~/.claude/skills`
     or the repo's own `.claude/`; else `builtin`.
   - `secondbrain_path` — `none` unless a path is already configured by another skill's
     config in the same repo; findings then land in the session folder (never lost).
   - `ui_paths` — `auto`.
   - `autonomy` — `full`.
   The only reason to ask is a *conflict* the repo itself cannot settle (e.g. two
   plausible e2e suites) — and even then prefer the better-evidenced one, log the choice,
   and move on.
2. After deriving: write the config file, and append its filename to
   `<repo-root>/.git/info/exclude` (create the file if absent) so it can never appear in
   a diff or PR. If `secondbrain_path` is set, ensure
   `<secondbrain>/projects/<project>/{findings,harvests}/` exist.
3. **Auto-detected every run (never stored):** build/test commands from the project's
   own files (`package.json`, `*.csproj`/`*.sln*`, `pyproject.toml`, `go.mod`,
   `Cargo.toml`, `Makefile`, …) and docs (`CLAUDE.md`, `README.md`, `CONTRIBUTING.md`);
   the default branch; the base branch (= the branch the skill was invoked from).

Config schema (all auto-derived on first run; hand-editing is fine and expected):

```yaml
project: <name>
boundary_repos: [<repo-dir-name>, ...]
e2e_location: <path> | none
review_checklist: <skill-name> | builtin
secondbrain_path: <path> | none
ui_paths: [<glob>, ...] | auto
autonomy: full | checkpointed   # default full — see Autonomy contract
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

- **Missing or conflicting labels → the skill triages the issue itself** (`autonomy:
  full`). Deep-read the body, its epic, and every referenced file; decide each axis on
  evidence; apply the labels with `gh issue edit`; post a comment recording the decision
  and the evidence that drove it, and log it to `run.jsonl`. Nothing is developed
  *unassessed*, but assessment no longer needs a human. Under `autonomy: checkpointed`
  the same decision is *proposed* and applied only on confirm.
- **Readiness is decided by evidence, not by the label.** The deep-read lands on
  `agent-ready` only when the ACs are concrete and testable, there are no TBDs or open
  questions, and every reference resolves. Otherwise it lands on `human-needed`: that
  issue is **excluded from this run** (labelled, commented with the exact blocking
  questions, reported in the summary) and the batch continues with the rest. The run does
  not stop to interview the user about it.
- A part-local, part-outside issue is **excluded from the batch** and gets a comment
  spelling out the proposed split (parent + child scopes). The skill does not create the
  child issues on its own — splitting rewrites the tracker's structure, which is the
  user's call — but it never stops the run over it either.
- `agent-ready` + `outside-change` is valid: development is autonomous, but the flow
  still ends at a human-gated PR (Solo mode).
- **Ensure-exist:** any of the four labels missing from the repo is created immediately
  (`gh label create`, one-time, idempotent) and the creation is logged — no confirm.

## Input parsing

Args are issue numbers: single (`12`), list (`12 15 20` / `12,15,20`), range (`12-15`),
or mixed. Dedupe. Default order: **ascending**; an explicitly ordered list ("in this
order: …") is honored.

- **Cap: 8 issues.** More than 8 → batch the first 8 in resolved order and report the
  remainder as "not batched this run — invoke again for these" in the run plan and the
  final summary. Don't stop to negotiate the split.
- **No args → derive the queue:** open issues assigned to the invoking user
  (`gh issue list --assignee @me --state open`) that are `agent-ready` + `local-change`,
  ascending, up to 8. Print the derived queue and proceed. If that set is empty, say so
  and exit clean — there is nothing to guess at.

## Phase 0 — Preflight

1. **Environment:** `gh auth status` OK · inside a git repo · resolve `<base-branch>` =
   current branch (pull `--ff-only`; diverged → halt) · working tree has no staged
   changes · resolve config (above) · ensure the four labels exist (above).
2. **Fetch + validate** every issue: must be OPEN, and either unassigned or already
   assigned to the invoking user — an issue assigned to someone ELSE is a collision:
   refuse it and say who holds it. List all violations at once.
3. **Label sanity** per issue → classification table printed to the user.
4. **Readiness audit** per issue — labels are intent, bodies rot, so audit even
   `agent-ready` issues: ACs concrete and testable? No TBD / open-question markers? Do
   referenced files/decisions exist? Does the batch's internal dependency order hold
   (`depends on #N` style references topo-sorted; cycles → drop the cyclic pair from the
   run and report, rather than halting the whole batch)? Any failure → treat the issue as
   `human-needed` for this run.
   - **Self-repair first.** Before demoting, try to close the gap from the repo itself: a
     vague AC that the code makes unambiguous, a moved file reference, a stale path — fix
     the issue body (audit comment records before/after) and keep the issue in the batch.
     Demote only when the missing thing is a *decision* no amount of reading can supply.
5. **Triage resolution (no questions asked).** Every issue lands in exactly one bucket
   and the run proceeds with whatever remains:
   - Untriaged → labelled by the skill from the deep-read (see Labels contract).
   - `human-needed` (or audit-demoted after self-repair failed) → **excluded**, labelled,
     and commented with the concrete blocking questions so the human can answer them
     asynchronously. Re-invoke on that issue once they have.
   - `outside-change` → excluded with a "run me solo" comment (Solo mode).
   - Print the bucket table. If **every** issue was excluded, there is no batch: report
     the buckets and the blocking questions, and exit clean without creating a branch.
6. **Solo dispatch:** exactly one issue passed AND it is `outside-change` → Solo mode.
   An `outside-change` issue inside a multi-issue list is never developed in that run.
7. **Batch setup:** session folder `~/Downloads/batch-<repo-name>-<timestamp>-i<N1>-<N2>…/`
   with `run.jsonl` (append-only event log; one JSON object per line: ts, phase, issue,
   status, detail — every autonomous decision that would once have been a question goes
   here). Batch branch `batch/<gh-login>/<timestamp>` from the fresh base branch; push
   with `-u`. Print the run plan and start Phase 1 immediately — do **not** ask the user
   to approve the plan.

## Phase 1 — Per-issue pipeline (strictly sequential)

For each issue `N` in order — worktree `<worktree-parent>/<repo-name>-<N>` on branch
`feat/issue-<N>-<slug>` forked from the **current batch tip** (issue N sees N-1's code):

| Agent | Job | Returns |
|---|---|---|
| **P — plan** | Read the issue (+ its epic/linked docs). Write a short implementation plan + test list to `<worktree>/_plan-<N>.md`. No product code. | `agent-status: done` + plan path |
| **D — dev** | TDD-implement the plan: failing test → code → refactor. Follow the project's own conventions (its `CLAUDE.md`/docs). Targeted tests green. | `agent-status: done` + files/tests summary |
| **R — review** | **Fresh agent — has never seen D's context**; it gets the diff on disk and nothing else, so the review is genuinely independent of the reasoning that produced the code. Review the uncommitted diff against the configured `review_checklist` skill's checklist (read that skill's file locally) or the builtin list (correctness, security, tests-quality, conventions, AC trace vs the ISSUE's ACs — not the PR body's claims). Fix findings in place per the fix-in-place-first test; re-run targeted tests. **Scope: this issue's diff only** — cross-issue interactions are structurally invisible here and are caught by BR in Phase 2. | `agent-status: done` + findings fixed/deferred |
| **F — finalize** | Conventional commit(s), push, open PR **into the batch branch** with `Refs #<N>` (never `Closes` — issues stay open until batch lands), body = what/why + pasted test output. **Stops at PR-open.** | `agent-status: pr-opened pr:<n>` |

**Orchestrator-owned merge gate** (after F): run the project's **FULL build + FULL test
suite** in the worktree — this is the merge evidence, regardless of CI (many repos have
no CI wired to their PRs; when PR checks DO exist, additionally wait for them per
standard green-only rules; treat every present check as gating). Green → squash-merge
the per-issue PR into the batch branch, capture the SHA, tear down the worktree +
branch. Red → one focused fix re-dispatch to the failing area (bounded: 3 cycles) →
still red → failure procedure.

**Failure procedure (recover autonomously; halt only when out of moves):** per-agent
runtime crash → retry (max 2). A logical `incomplete` → up to **two** recovery sub-agent
attempts, and the second is not a re-run: it receives the first's diagnosis and must
**root-cause** before touching code (a failure that looks familiar may have a different
cause — confirm it). Never paper over a red gate to get past it: no skipped or weakened
tests, no widened timeouts, no swallowed errors.

Past those bounds: write `<session-folder>/failures/<N>-<slug>/` (diagnosis.md,
last-state diff/status, agent summaries), then **PAUSE the whole run** and converse:
print the one-line diagnosis + folder path and wait. This is the one per-issue pause and
it means genuinely stuck — there is no correct next action to guess. The user chooses:
retry the slot · "I fixed it, resume" · skip this issue (only then: revert its batch
contributions, close its PR, comment on the issue, continue) · abort the batch. Every
failure appends a finding (forced trigger).

Issue prep, the moment work on issue `N` starts: **assign it to the invoking user**
(`gh issue edit <N> --add-assignee @me`, idempotent) — the assignee field is the
at-a-glance "taken" signal teammates scan, so it must be set BEFORE any code exists,
not at PR time. Then status comments: post short progress comments on each issue
(queued → PR opened → merged into batch → closed at finalize) so GitHub remains the
source of truth. On a user-skip after failure, the issue STAYS assigned — the failure
comment explains its state; unassigning would hide who owns the follow-up.

## Phase 2 — Batch QA (autonomous, tiered)

QA worktree from the batch tip. Tiering: **full unit/integration suites always** (all of
them, front and back). **End-to-end suite + live browser walkthrough only when the batch
touched UI** (changed paths vs `ui_paths`/auto-detection) — a backend-only batch skips
the browser tier, and the report says so.

Phase 1's R agents review **one issue's diff each**. Two blind spots survive that and
reach the human otherwise unreviewed: **cross-issue interactions** (each change correct
alone, wrong combined) and **QA-1's own in-place fixes** (new code written after the last
review). BR closes both before the batch PR opens.

| Agent | Job |
|---|---|
| **QA-1 — test-and-fix** | Run the full suites (+ e2e when tiered in). For UI batches: live walkthrough of each batched issue's surface against the running stack, **as a human user** — start from the landing page and navigate by clicking, never deep-link to known URLs (an unreachable-by-clicking feature is itself a finding); cover happy path, role/permission gating, side-effects (endpoints fired, persisted rows), adjacent-area regressions, edge cases. Before declaring any UI click broken (or fine), prove it at DOM level — computed `pointer-events`, `elementFromPoint`, dispatched-event control — browser automation can silently no-op. Fix findings per fix-in-place-first; after any fix, re-run the affected gates; bugs too big to fix → defer with `#N` (find-or-reuse). Docker hygiene: clean-slate = containers + volumes only, NEVER images; wait for true stack readiness (health signal, not a port). Returns a structured handoff: gates green/failed, suites pass/total, fixes made, coverage caveats. |
| **BR — batch review** | **Fresh agent, clean context — has seen no per-issue review and none of the pipeline's reasoning.** Reviews the **whole combined diff** (`<base-branch>..<batch tip>`, i.e. `git diff <base>...HEAD` in the QA worktree) against the configured `review_checklist` skill's checklist, PLUS two axes only visible at batch level: (1) **cross-issue interaction** — an assumption issue A relies on that issue B invalidated; the same file, contract, schema object, config key or shared helper changed by two issues in incompatible ways; duplicated logic two issues added independently; (2) **fix-cycle integrity over QA-1's fixes** — QA-1's in-place edits are unreviewed new code, so scan them with the same adversarial lens. On a single-issue batch axis (1) is vacuous — say so and still run axis (2); never skip BR. Fix findings per fix-in-place-first and **re-run every gate the fix touches**; too big → defer with `#N` (find-or-reuse). It is a REVIEW agent: it never opens, merges or comments on a PR. Returns a structured handoff for QA-2: verdict (clean / fixed-in-place / deferred), every finding with `file:line`, and which gates were re-run after fixes. |
| **QA-2 — report + PR** | Write **ONE consolidated `qa-report.html`** into the session folder: per-issue verdicts (✅/🟡/🔴), gate results, **BR's batch-review verdict + its cross-issue findings as their own section** (so the human sees the combined diff was reviewed, by whom, and what it found), findings (fixed in-session vs deferred-with-`#N`), a **"triaged out of this run"** section naming every issue the skill excluded at Phase 0 with the reason and (for `human-needed`) the blocking questions, every label the skill applied or body it rewrote autonomously with the evidence, and an HONEST **"NOT verified"** list — everything the local stack cannot reach (external systems, cross-app handoffs) stated plainly; a passing gate is not proof of correctness, and the report never overstates. File the deferral tracking issues (find-or-reuse, whole-batch deduped) and back-link each `#N` into the per-issue PR bodies. Then open the **batch PR** (draft) batch → base: `Closes #<N>` line per completed issue, gate evidence, link to the report path. QA-failed state → the PR still opens, with a prominent DO-NOT-MERGE callout. |

## Phase 3 — Wait, then finalize

Print the batch PR URL + report path, plus a one-line-per-item recap of every autonomous
triage decision and every excluded issue, then **pause and converse** — no polling, no
timers. This pause is unconditional: the batch → base merge belongs to a human even in
`autonomy: full`. On the user's "merged" signal (verify via `gh pr view` state): pre-close check
per issue (every deferral line carries a `#N`), close each batched issue with an audit
comment, tear down the QA worktree + batch branch, flush findings, and print the final
summary including the **count of unharvested findings** ("N findings accumulated —
worth a harvest pass" when ≥ 10). On "closed/abandoned": leave everything for
inspection, mark the run abandoned, exit clean.

## Solo mode — one `outside-change` issue

Invoked with exactly one issue labelled `outside-change`. This mode touches a repo
OUTSIDE the boundary, so it **announces** the target repo path in one line before the
first write and proceeds — invoking the skill on an `outside-change` issue *is* the go
signal. Announce-and-proceed, not ask-and-wait. A machine-level boundary hook may still
raise its own prompt on the first write there; that is expected, the user approves once,
and the skill never tries to route around it. If the target repo can't be located on
disk, say which path was tried and stop — that is a missing precondition, not a decision.

Same issue prep (assign to the invoking user first) and P → D → R → F pipeline, but:
the worktree/branch live in the **target repo**; the
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
| Preflight violation (no `gh` auth, not a git repo, dirty/staged tree, diverged base) | Hard halt before any branch/folder exists — missing precondition, not a decision |
| >8 issues passed · cyclic `depends on` pair · every issue excluded by triage | Not a halt: trim/exclude, report what was left out, run the remainder (or exit clean if nothing remains) |
| Agent crash | Retry ×2 → recovery ×2 (second must root-cause) → **pause-and-converse** |
| Merge gate red | Fix cycles ×3 → **pause-and-converse** |
| QA gates failed | Batch PR opens with DO-NOT-MERGE callout; still pause for the user |
| User says "stop" mid-run | Halt; failure record for the in-flight issue; nothing torn down beyond completed work |
| User claims "merged" but PR is OPEN | Push back conversationally; never finalize unverified |

## Hard constraints

- Never merge, auto-merge, or enable auto-merge on the **batch PR** — a human merges.
- Never commit or push to the base/default branch; never force-push; never bypass hooks.
- Never develop an *unassessed* or `human-needed` issue; never batch an `outside-change`
  issue. (Assessing and labelling it yourself is how it stops being unassessed.)
- Never delete or reset work this run did not create; never discard the user's
  uncommitted changes. Everything the run made — its worktrees, its branches, its PRs
  into the batch — it cleans up itself.
- Never stop to ask for approval of anything on the Autonomous list. Announce, log to
  `run.jsonl`, continue. Under `autonomy: checkpointed`, confirm only the tracker writes
  that section names.
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
- [ ] BR reviewed the whole combined diff; its verdict and findings are in the report.
- [ ] `qa-report.html` written and its absolute path reported.
- [ ] Findings flushed (secondbrain committed + pushed, or session-folder fallback);
      unharvested count reported.
