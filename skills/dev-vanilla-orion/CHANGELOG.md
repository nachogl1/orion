# Changelog — dev-vanilla-orion

Edited in place (no `-vN` convention); notable behaviour changes are recorded here.

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
