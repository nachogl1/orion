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
  4. Commit using Conventional Commits style (`feat(<scope>):`, `fix(<scope>):`, etc.). **DO NOT include any of these GitHub auto-close keywords ANYWHERE in the commit message — subject line, body, OR footer (case-insensitive, with or without trailing period):** `Closes`, `Close`, `Closed`, `Fixes`, `Fix`, `Fixed`, `Resolves`, `Resolve`, `Resolved` followed by `#<N>`. The issue MUST remain OPEN — Phase 4 is the explicit closer (via `gh issue close` after the orchestrator posts an audit comment). When a per-issue PR squash-merges into the batch and the batch later squash-merges into main, GitHub walks the resulting squash-commit message and auto-closes anything matching these keywords, bypassing the audit comment. Use `Refs #<N>` instead, which does NOT trigger auto-close. This applies to the initial commit AND any fixup commits within the 5-cycle CI retry loop.
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

     ## TODOs introduced by this story
     <Read this verbatim from Agent C's return summary "New TODO/FIXME/HACK markers introduced" field. If count > 0: render as a bullet list of `\`<file>:<line>\` — \`<MARKER>: <text>\``. If count == 0: write exactly `None.`>
     <Above the list (when non-empty), include this one-line note: *"These markers were introduced by this story and are intentionally allowed under the production-ready bar (Core Principle #1) — they survive the pipeline and are surfaced here so the reviewer + downstream QA agent can decide which to keep, which to file follow-up issues for, and which to address before merge."*>

     ## Pre-existing baseline failures (out of scope)
     <ONLY include this section if step 2's baseline check found pre-existing failures. Otherwise OMIT it entirely. Format: bullet list of test file names + one-line failure summary + confirmation that the file does not appear in this story's diff. Example: "- `apps/<frontend>/src/pages/<SomePage>.test.tsx` — 3 tests fail on batch baseline (same set); file not in story diff. Flagged for batch-QA.">
     ```
     DO NOT include any auto-close keyword (`Closes`, `Close`, `Closed`, `Fixes`, `Fix`, `Fixed`, `Resolves`, `Resolve`, `Resolved`) followed by `#<N>` in the PR body, case-insensitive, with or without trailing period — the same rule as the commit message (step 4). Use `Refs #<N>` only. The issue MUST remain OPEN; Phase 4 closes it explicitly with an audit comment.
  7. Post 📦 Batch status — "PR opened: <url> (targeting <batch-branch>)" on issue #<N>.
  8. Wait CI green. Poll `gh pr checks <pr-number>` until every required check SUCCESS. If a check FAILS: read logs (`gh run view <run-id> --log-failed`), fix in this worktree, commit, bare push (upstream is set), re-wait. Max 5 fix-and-retry CI cycles. If still red, return `agent-status: incomplete — CI red after retries: <diagnosis>`.
  9. Post 📦 Batch status — "CI green" on issue #<N>.
  10. Merge: `gh pr merge <pr-number> --squash --delete-branch`. Capture squash SHA via `gh pr view <pr-number> --json mergeCommit --jq .mergeCommit.oid`.
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
