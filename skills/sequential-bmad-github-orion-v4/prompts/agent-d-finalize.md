Issue title: <issue-title>

Your job: take the uncommitted work in the worktree from agents B+C, get the full build + test suite green, commit, push, open a PR targeting the batch branch, wait for CI green, and merge into batch.

IMPORTANT — first-push gotcha: the orchestrator created this worktree with `git worktree add -b feature/<N>-<slug> <path> origin/<batch-branch>`, so the feature branch's upstream currently tracks `origin/<batch-branch>` — NOT `origin/feature/<N>-<slug>`. Your FIRST push MUST be `git push -u origin feature/<N>-<slug>` (the `-u` flag is mandatory — it resets upstream). A bare `git push` will try to push to the batch branch and either fail or contaminate it. Use `-u` ONLY on the first push.

Steps:
  1. Post 📦 Batch status — "Agent D (finalize) started" on issue #<N>.
  2. Run the project's FULL build + FULL test suite + frontend build/tests if applicable (auto-detect from package.json / *.csproj / *.slnx etc.). Max 5 fix-and-retry cycles per command.
     **Baseline-vs-regression check (do this BEFORE fixing any failing test).** A failing test is not automatically a regression caused by this story — it may be pre-existing batch-baseline debt.
       a. `git stash --include-untracked` to set the worktree back to the batch tip.
       b. Re-run the failing test.
       c. If it ALSO fails on baseline → pre-existing. `git stash pop` to restore, note it under a "Pre-existing baseline failures (out of scope)" section in the PR body (step 6), flag the affected test file in your return summary so batch-QA picks it up in Phase 2, and DO NOT fix it. Out-of-scope fixes introduce unreviewed changes into the merge.
       d. If it passes on baseline → real regression caused by this story. `git stash pop` to restore, then fix within the 5-cycle budget.
     If any command stays red after the cycle budget (regressions only — pre-existing failures don't count), return `agent-status: incomplete — build/tests cannot be made green: <diagnosis>`.
  3. Post 🔍 Review note — "Full build + test suite green".
  4. Commit using Conventional Commits style (`feat(<scope>):`, `fix(<scope>):`, etc.). **DO NOT include any of these GitHub auto-close keywords ANYWHERE in the commit message — subject line, body, OR footer (case-insensitive, with or without trailing period):** `Closes`, `Close`, `Closed`, `Fixes`, `Fix`, `Fixed`, `Resolves`, `Resolve`, `Resolved` followed by `#<N>`. The issue MUST remain OPEN — Phase 4 is the explicit closer (via `gh issue close` after the orchestrator posts an audit comment). When a per-issue PR squash-merges into the batch and the batch later squash-merges into the base branch (and ultimately the repo's default branch), GitHub walks the resulting squash-commit message and auto-closes anything matching these keywords once it reaches the default branch, bypassing the audit comment. Use `Refs #<N>` instead, which does NOT trigger auto-close. This applies to the initial commit AND any fixup commits within the 5-cycle CI retry loop.
  4b. **Pre-push auto-close keyword audit (the single point of enforcement).** BEFORE the first push, scan every unmerged commit (yours and any an earlier agent may have left) for the auto-close keyword regex. The issue MUST stay OPEN until Phase 4 closes it explicitly with an audit comment, so any `Closes #N` / `Fixes #N` / `Resolves #N` in a commit message must be rewritten to `Refs #N` before push.
     Procedure:
       a. List all commits between batch tip and HEAD:
          `git -C <worktree> log origin/<batch-branch>..HEAD --format=%H`
          For each SHA, get the full commit message (subject + body + footer):
          `git -C <worktree> show --no-patch --format=%B <sha>`
       b. Grep each commit message body (case-insensitive, multi-line) for the regex:
          `\b(close[sd]?|fix(es|ed)?|resolve[sd]?)\s+#[0-9]+`
          Capture every match: SHA + matched text + line number within the message.
       c. If ZERO matches across all commits: log `auto-close-keyword-audit-clean` with the commit count audited and proceed to step 5.
       d. If ANY matches: do NOT push. For each contaminated commit:
          - If it's the most recent commit (HEAD): `git -C <worktree> commit --amend -m "<reworded message with Refs #<N>>"` — preserve the Conventional Commits prefix, replace every auto-close keyword with `Refs` (e.g. `Closes #123` → `Refs #123`).
          - If it's an older commit: `git -C <worktree> rebase -i <commit>^` is interactive and not allowed. Use a non-interactive sequence instead: `git -C <worktree> rebase --rebase-merges --exec 'commit-message-rewrite-sed-here' origin/<batch-branch>` OR fall back to `git filter-repo --commit-callback` to rewrite all messages between origin/<batch-branch> and HEAD with the keyword substitution. Both work non-interactively; prefer `filter-repo` if installed (`git filter-repo --version`), else fall back to a non-interactive `rebase --exec`.
          - After any amend/rewrite, re-run step 4b's grep to confirm clean. If grep STILL matches: return `agent-status: incomplete — auto-close keyword could not be removed from commit <sha>: <details>` (this routes through the orchestrator's per-issue failure procedure).
       e. Log `auto-close-keyword-leak-fixed` per fixed commit with original message → new message + the leak-source attribution (yours / Agent B / earlier amend).
       f. Append a lessons-learned finding for each leak so the next skill iteration can investigate the source (often correlates with model auto-completion habits or BMAD template drift).
     This is the only point in the pipeline that prevents auto-close-keyword leakage — there is no post-merge detective audit. Catching it here, before the push, is when amend/rewrite is still trivial and the issue audit trail stays clean.
  5. First push: `git push -u origin feature/<N>-<slug>`.
  6. Open PR targeting the BATCH branch (NOT the base branch, NOT the default branch):
     `gh pr create --base <batch-branch> --head feature/<N>-<slug> --title "[#<N>] <issue-title>" --body "<body>"`
     PR body template:
     ```
     ## Summary
     <one-paragraph summary of what shipped>

     ## Acceptance criteria
     <each AC from the issue body, ticked ✓ if satisfied>

     ## Refs
     Refs #<N> (issue stays open until the batch branch lands on the base branch).

     ## BMAD artifacts
     - Story file: <story-file-path>
     - Code review: <N findings, all auto-fixed | clean — see issue comments>

     ## TODOs introduced by this story
     <Read this verbatim from Agent C's return summary "New TODO/FIXME/HACK markers introduced" field. If count > 0: render as a bullet list of `\`<file>:<line>\` — \`<MARKER>: <text>\``. If count == 0: write exactly `None.`>
     <Above the list (when non-empty), include this one-line note: *"These markers were introduced by this story and are intentionally allowed under the production-ready bar (Core Principle #1) — they survive the pipeline and are surfaced here so the reviewer + downstream QA agent can decide which to keep, which to file follow-up issues for, and which to address before merge."*>

     ## Pre-existing baseline failures (out of scope)
     <ONLY include this section if step 2's baseline check found pre-existing failures. Otherwise OMIT it entirely. Format: bullet list of test file names + one-line failure summary + confirmation that the file does not appear in this story's diff. Example: "- `apps/<frontend>/src/pages/<SomePage>.test.tsx` — 3 tests fail on batch baseline (same set); file not in story diff. Flagged for batch-QA.">
     <These lines are intentionally left WITHOUT a tracking `#N` at this stage — the umbrella issue does not exist yet. The Phase 2 `pr-author` finds-or-creates ONE tracking issue per distinct baseline-failure across the whole batch and edits this PR body to append the `#N` (Core Principle #9). Do not file the umbrella issue yourself; just report the file accurately so the orchestrator's annotation ingest picks it up.>
     ```
     DO NOT include any auto-close keyword (`Closes`, `Close`, `Closed`, `Fixes`, `Fix`, `Fixed`, `Resolves`, `Resolve`, `Resolved`) followed by `#<N>` in the PR body, case-insensitive, with or without trailing period — the same rule as the commit message (step 4). Use `Refs #<N>` only. The issue MUST remain OPEN; Phase 4 closes it explicitly with an audit comment.
  7. Post 📦 Batch status — "PR opened: <url> (targeting <batch-branch>)" on issue #<N>.
  8. Wait CI green. Poll `gh pr checks <pr-number>` until every required check SUCCESS. If a check FAILS: read logs (`gh run view <run-id> --log-failed`), fix in this worktree, commit, bare push (upstream is set), re-wait. Max 5 fix-and-retry CI cycles. If still red, return `agent-status: incomplete — CI red after retries: <diagnosis>`.
  8b. **HARD PRE-MERGE CI GATE (do NOT skip — a red or unfinished PR must never merge into the batch).** The pipeline cannot rely on GitHub branch protection / required-check enforcement (the runner may lack admin access on this repo), so this gate IS the enforcement — GitHub may not stop a red merge for you. Polling `gh pr checks` is not enough on its own: a check can flip, a new run can queue after your last poll, or a check can still be pending. Immediately before merging, take an authoritative reading and refuse to merge unless it is unambiguously green:
       a. `gh pr view <pr-number> --json mergeable,mergeStateStatus,statusCheckRollup` — inspect EVERY entry in `statusCheckRollup`.
       b. **Treat every check in `statusCheckRollup` as merge-gating — NOT only the ones GitHub marks "required".** Without branch protection nothing is flagged required, so a "required-only" reading would gate on nothing and pass everything. When the rollup is non-empty, the PR is mergeable ONLY if every entry has `conclusion` ∈ {`SUCCESS`, `NEUTRAL`, `SKIPPED`} AND its `status` is `COMPLETED`; AND no entry is `QUEUED` / `IN_PROGRESS` / `PENDING` / `EXPECTED`; AND `mergeStateStatus` is not `DIRTY` / `BLOCKED` / `BEHIND` for a CI reason. Any `FAILURE` / `ERROR` / `CANCELLED` / `TIMED_OUT` / `ACTION_REQUIRED`, or any still-running check → NOT mergeable.
       c. **Empty `statusCheckRollup` (no workflow fired for this PR's changed paths) — do NOT pass vacuously.** An empty rollup is zero evidence, not a green light. Re-run the SAME full build + full test command(s) you ran in step 2, in this worktree, and require them green as the merge evidence. If they pass, the local build IS the gate (proceed to merge). If any is red, do NOT merge — return `agent-status: incomplete — local build/test red at merge gate (no CI ran): <failing command>`.
       d. If NOT green (rollup non-empty but not all-terminal-SUCCESS): do NOT merge. If checks are merely still running, re-poll (within the step-8 cycle budget) and re-take the reading. If a check is red after the budget, return `agent-status: incomplete — CI not green at merge gate: <failing checks>` — this routes through the orchestrator's per-issue failure procedure. Never `--admin`, never bypass, never merge "to save a cycle".
       e. Logging — record WHICH gate passed (the two are mutually exclusive per PR):
          - Remote-checks case (non-empty rollup, all green): log `pre-merge-ci-gate-pass` with the audited check count.
          - Empty-rollup local-build case: log `pre-merge-local-gate-pass` with the build + test command(s) that went green as the merge evidence.
  9. Post 📦 Batch status on issue #<N>, reflecting WHICH gate from step 8b passed (do NOT claim "N checks SUCCESS" when the evidence was the local build):
       - Remote-checks case: "CI green (pre-merge gate passed: <N> checks SUCCESS)".
       - Empty-rollup local-build case: "No CI ran for this PR's changed paths; pre-merge gate passed via green local build + test (<command(s)>)".
  10. Merge: `gh pr merge <pr-number> --squash --delete-branch`. Do NOT pass `--admin` or any flag that overrides failing/pending checks — if the merge is rejected because checks aren't green, that's the gate working; return `agent-status: incomplete — merge rejected, CI not green: <details>` rather than forcing it. After a successful merge, re-confirm: `gh pr view <pr-number> --json state,mergedAt,statusCheckRollup` — `state` must be `MERGED` and the rollup must still match whichever gate passed in step 8b (all-green for the remote-checks case; still-empty, certified by the step-8b local build+test, for the empty-rollup case — an empty rollup is NOT a failure here). The orchestrator runs the same audit in §1.5 as a backstop and will revert + fail the issue if it finds red or a vacuously-waved-through empty rollup. Capture squash SHA via `gh pr view <pr-number> --json mergeCommit --jq .mergeCommit.oid`.
  11. Post 📦 Batch status — "Merged into batch as <squash-sha>" on issue #<N>.

Return summary:
  • agent-status: done | incomplete — <reason>
  • merge-sha: <40-char squash SHA on the batch branch>
  • PR number + URL
  • CI status: green (or red — what failed)
  • Build status: green
  • Test suite: <pass/total>
  • Pre-existing baseline failures observed: none | list (e.g. "6 tests in `<some-test-file-pattern>` — same set fails on batch baseline, not in story diff")
  • **TODOs introduced by this story** (pass-through from Agent C's return summary): structured block with `count: <N>` and `list:` followed by one bullet per marker formatted `- <file>:<line> — <MARKER_WORD>: <full line text>`. Use `count: 0` and an empty list if none. The orchestrator parses this field into `annotations[]` (kind=`todo`) for Phase 2 batch-QA.
  • **Carry-forward framework gaps** (STRUCTURED — distinct from the freeform "Flags for batch-QA" below). Carry-forwards are KNOWN LIMITATIONS that no single story can fix — typically framework-level gaps that propagate across multiple stories in an epic (e.g. "list+detail pages for `/some-feature-route` don't exist in the router yet — clicking any related palette `open` action 404s"; "a debounced-query variable in a shared command-palette hook is never populated from the visible input — no entity-search story can trigger the network call from the palette"). Format: `count: <N>` + `list:` of bullets `- <one-line gap description> — owning_framework: <framework/epic/issue ref OR "tbd"> — affects_this_story: <how the story is affected>`. Use `count: 0` and an empty list if none. **Source from**: Agent A's "Carry-forward gaps" notes in the story file, plus any TODO(post-epic)-style comments, plus any "out of scope for this story" notes from Agent C. The orchestrator parses this field into `annotations[]` (kind=`carry-forward`) — gaps repeated by ≥2 issues are aggregated at query time as framework gaps the QA agent must NOT report as bugs.
  • Files changed (count)
  • Flags for the Phase 2 batch-QA sub-agent (e.g. "this issue touches an audit/log table — verify audit rows"; "i18n keys added — confirm each supported locale renders"; "new endpoint added — smoke it")

Final line of your reply must be `agent-status: done` or `agent-status: incomplete — <reason>`. If `done`, the line immediately before the final line must be `merge-sha: <40-char hex>`.
