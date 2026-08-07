# Changelog — dev-vanilla-orion

Edited in place (no `-vN` convention); notable behaviour changes are recorded here.

## 1.3.0 — unattended by default

The skill used to stop for a confirm at every tracker write and every triage decision,
which meant a "batch" run needed a human sitting next to it. It now runs from invocation
to batch-PR-open without asking anything.

- **New `Autonomy contract` section** — the authoritative list of what the skill does
  without asking versus the only four pauses that survive: an unrecoverable issue failure,
  the batch PR → base merge, destroying work the run did not create, and a machine-level
  boundary-hook prompt. Everything else (labels, config, issue-body sharpening, in-place
  fixes, deferral issues, per-issue PR merges into the batch) is announce-and-continue.
- **No first-run interview.** Every config field is auto-derived from the repo and
  written to `.claude/dev-vanilla-orion.yaml`, with the assumed values printed. New
  `autonomy: full | checkpointed` field (default `full`); `checkpointed` restores the old
  confirm-before-tracker-writes behaviour for anyone who wants to supervise triage.
- **Self-triage.** Untriaged or conflictingly-labelled issues are labelled by the skill
  from an evidence-logged deep-read (comment records the decision + evidence) instead of
  waiting for a confirm. Missing triage labels are created without a confirm.
- **Readiness gaps self-repair before demoting.** A stale path or an AC the code makes
  unambiguous is fixed in the issue body (audit comment records before/after) and the
  issue stays in the batch; demotion is reserved for a missing *decision*.
- **Excluded instead of blocking.** `human-needed`, mixed blast-zone, and cyclic-dependency
  issues are excluded from the run — labelled, commented with the concrete blocking
  questions, and named in `qa-report.html` and the final summary — rather than stopping
  the batch for a live Q&A. More than 8 issues trims to 8 and reports the remainder; no
  args derives the queue from the user's own assigned `agent-ready` + `local-change`
  issues. If every issue is excluded, the run exits clean without creating a branch.
- **Solo mode announces instead of asking** — invoking the skill on an `outside-change`
  issue is the go signal; it still never routes around a machine boundary hook.
- **More autonomous recovery before the halt:** a logical `incomplete` now gets two
  recovery attempts, the second required to root-cause from the first's diagnosis rather
  than re-run it. Papering over a red gate remains forbidden.

## 1.2.0 — whole-batch review (BR)

- **New Phase 2 agent, `BR — batch review`**, between QA-1 and QA-2: a fresh agent that
  reviews the **whole combined diff** (`<base>...<batch tip>`) before the batch PR opens.
  Closes two blind spots that previously reached the human unreviewed:
  - **Cross-issue interactions** — Phase 1's R agents each see one issue's diff, so a
    defect that exists only in the *combination* (issue B invalidating an assumption
    issue A relies on, two issues changing one contract incompatibly, duplicated logic)
    was structurally invisible to every reviewer in the run.
  - **QA-1's in-place fixes** — new code written after the last review, previously
    shipped with no review at all.
- BR runs **after** QA-1 so it reviews the code that actually ships, fixes per
  fix-in-place-first (re-running every gate a fix touches), and defers with `#N`.
  It never opens, merges or comments on a PR. On a single-issue batch the cross-issue
  axis is declared vacuous but BR still runs for the QA-1 fix-review axis.
- `qa-report.html` now carries BR's verdict and cross-issue findings as their own
  section; the cleanup checklist gained a matching item.
- Documentation: the R row now states explicitly that R is a **fresh agent that has
  never seen D's context** and is scoped to one issue's diff — the independence was
  already real, but readers could not tell from the table.

## 1.1.0 — ownership visibility

- Issue prep now **assigns each issue to the invoking user the moment work starts**
  (idempotent `--add-assignee @me`, batch and solo modes alike) so teammates see it is
  taken from the issue list, not just from a comment. Stays assigned on a user-skip.
- Preflight validation now refuses an issue **assigned to someone else** (collision
  guard — mirrors the v4 pipeline's rule).

## 1.0.0 — initial release

- Label-gated batch development of 1–8 GitHub issues: two-axis labels
  (`agent-ready`/`human-needed` + `local-change`/`outside-change`), untriaged = refused
  with an assisted label proposal (applied only on user confirm).
- Conductor + sub-agent architecture (plan → TDD dev → review → finalize per issue;
  two-agent batch QA) with disk handoffs — QA runs in fresh contexts so a full
  develop-then-QA run fits one invocation.
- Per-issue PRs (`Refs #N`) into a batch branch, agent-merged only on a green FULL
  local build + test run (standard gate; PR checks additionally honored where they
  exist). Batch PR carries the `Closes #N` lines; a human always merges it.
- Halt-on-failure: bounded retries + one recovery attempt, then pause-and-converse
  (fix / retry / skip / abort are the user's call — never auto-skip).
- Tiered batch QA: full suites always; e2e + live human-style browser walkthrough only
  when the batch touched UI. One consolidated `qa-report.html` with an honest
  "NOT verified" list.
- Solo mode for `outside-change` issues: develop in the target repo, stop at PR for a
  human reviewer; never merge.
- Per-repo config via first-run interview (`.claude/dev-vanilla-orion.yaml`, kept out
  of git via `.git/info/exclude`); toolchain auto-detected each run.
- Findings journal under forced triggers (crash/retry/hook-block/halt/workaround) into
  a configurable private findings store, one file per finding, with a harvest reminder.

Design notes: the pipeline shape and merge-gate rules descend from
`sequential-bmad-github-orion-v4`; the QA disciplines (human-style navigation,
DOM-level click proof, fix-first + mandatory dedup, Docker hygiene) descend from
`guided-qa-orion`. Sub-agent prompt contracts are inline in `SKILL.md` for now; a
`prompts/` split can come later if the file grows unwieldy.
