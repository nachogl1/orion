Issue title: <issue-title>

Your job: take the uncommitted work in the worktree from agents B+C, get it COMPILING with its targeted tests green, commit, push, and open a PR targeting the batch branch. **You STOP at PR-open.** You do NOT wait for CI and you do NOT merge — the orchestrator owns the CI-watch + hard pre-merge gate + squash-merge. This split is deliberate: it removes the long CI wait from your turn, which is where finalize agents used to reach for a background/Monitor wait tool and end their turn non-terminally, breaking the return contract. Stay foreground, do your mechanical work, return terminally at PR-open.

IMPORTANT — first-push gotcha: the orchestrator created this worktree with `git worktree add -b feature/<N>-<slug> <path> origin/<batch-branch>`, so the feature branch's upstream currently tracks `origin/<batch-branch>` — NOT `origin/feature/<N>-<slug>`. Your FIRST push MUST be `git push -u origin feature/<N>-<slug>` (the `-u` flag is mandatory — it resets upstream). A bare `git push` will try to push to the batch branch and either fail or contaminate it. Use `-u` ONLY on the first push.

Steps:
  1. Post 📦 Batch status — "Agent D (finalize) started" on issue #<N>.
  2. **Targeted tests + full compile (NOT the full suite).** CI is the authoritative full-suite gate — the orchestrator waits on it before merge, and batch-QA Gate 1 runs the full suite once more on the integrated tip — so running the whole suite HERE just to have CI re-run the identical suite is wasted wall-time (it was the single biggest cost in finalize). Instead, locally:
       a. Run a FULL COMPILE / build of the project (auto-detect: `dotnet build <solution>`, `npm run build`, `cargo build`, `make`) — this catches cross-project compile breaks cheaply.
       b. Run ONLY the TARGETED tests: the test projects/packages whose source THIS diff touches. Use `git -C <worktree> diff --name-only origin/<batch-branch>...HEAD` to see what changed, then map to the owning test project(s) and run just those.
     Max 5 fix-and-retry cycles per command.
     **Baseline-vs-regression check (do this BEFORE fixing any failing targeted test).** A failing test may be pre-existing batch-baseline debt, not a regression from this story. **Do NOT use `git stash`** — the stash stack is a repo-global ref shared across all worktrees and corrupts the orchestrator's / other agents' trees. Check the baseline in a throwaway DETACHED worktree instead:
       a. `git worktree add --detach <session-folder>/scratch/agent-D/baseline origin/<batch-branch>` (install deps there if the project needs them).
       b. Re-run the same failing test in that baseline worktree.
       c. If it ALSO fails on baseline → pre-existing. `git worktree remove --force <session-folder>/scratch/agent-D/baseline`, note it under a "Pre-existing baseline failures (out of scope)" section in the PR body (step 6), flag the affected test file in your return summary so batch-QA picks it up in Phase 2, and DO NOT fix it. Out-of-scope fixes introduce unreviewed changes into the merge.
       d. If it passes on baseline → real regression caused by this story. Remove the baseline worktree, then fix within the 5-cycle budget.
     If a targeted test stays red after the cycle budget (regressions only — pre-existing failures don't count), or the compile won't go green, return `agent-status: incomplete — build/targeted-tests cannot be made green: <diagnosis>`.
  3. Post 🔍 Review note — "Full compile + targeted tests green".
  4. Commit using Conventional Commits style (`feat(<scope>):`, `fix(<scope>):`, etc.). **DO NOT include any of these GitHub auto-close keywords ANYWHERE in the commit message — subject line, body, OR footer (case-insensitive, with or without trailing period):** `Closes`, `Close`, `Closed`, `Fixes`, `Fix`, `Fixed`, `Resolves`, `Resolve`, `Resolved` followed by `#<N>`. The issue MUST remain OPEN — Phase 4 is the explicit closer (via `gh issue close` after the orchestrator posts an audit comment). When a per-issue PR squash-merges into the batch and the batch later squash-merges into the base branch (and ultimately the repo's default branch), GitHub walks the resulting squash-commit message and auto-closes anything matching these keywords once it reaches the default branch, bypassing the audit comment. Use `Refs #<N>` instead, which does NOT trigger auto-close. This applies to the initial commit AND any fixup commits within the 5-cycle CI retry loop.
  4a. **Precise staging (never `git add -A`).** Stage exactly the files this issue should ship — the implementation + its tests + the BMAD story artifact — and nothing else. Before committing, run `git -C <worktree> status --porcelain` and compare it against the expected file list; investigate anything unexpected (leftover probe/baseline files, stray screenshots, build artifacts) and exclude it, rather than sweeping it in with `git add -A`, which is how scope-creep and unrelated edits leak into a PR. Before including the BMAD story file (or any framework/output artifact), check whether it is tracked or ignored in THIS repo: `git -C <worktree> check-ignore -v <path>` — include it only if it is NOT ignored (some repos track `_bmad-output/`, others ignore it; do not assume).
  4b. **Pre-push auto-close keyword audit (the single point of enforcement).** BEFORE the first push, scan every unmerged commit (yours and any an earlier agent may have left) for the auto-close keyword regex. The issue MUST stay OPEN until Phase 4 closes it explicitly with an audit comment, so any `Closes #N` / `Fixes #N` / `Resolves #N` in a commit message must be rewritten to `Refs #N` before push.
     Procedure:
       a. List all commits between batch tip and HEAD:
          `git -C <worktree> log origin/<batch-branch>..HEAD --format=%H`
          For each SHA, get the full commit message (subject + body + footer):
          `git -C <worktree> show --no-patch --format=%B <sha>`
       b. Grep each commit message body (case-insensitive, multi-line) for the regex:
          `\b(close[sd]?|fix(es|ed)?|resolve[sd]?)\s+#[0-9]+`
          **Use `grep -iE` (extended regex), NOT `grep -P`** — the bundled Windows/Git-Bash grep has no Perl-regex support and `-P` fails (often silently), which would FALSE-NEGATIVE the audit and let a keyword through. `-iE` is sufficient for this pattern. If you ever need a Unicode character class (not required here), use a Node/JS regex rather than `grep -P`.
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
  7. Post 📦 Batch status — "PR opened: <url> (targeting <batch-branch>) — handing off to the orchestrator for the CI-watch + hard pre-merge gate + merge" on issue #<N>.
  8. **STOP HERE — return terminally with `agent-status: pr-opened pr:<N>`.** Do NOT wait for CI. Do NOT run `gh pr merge`. Do NOT poll with any background / Monitor / wait / schedule tool. Your turn ends, terminally, at PR-open. The orchestrator immediately takes over (per SKILL §1.4 Agent-D handling): it runs the synchronous CI-watch, the HARD pre-merge CI gate — every check in `statusCheckRollup` treated as merge-gating (not only the ones GitHub marks "required"), and an EMPTY rollup settled-and-repolled for ≥90–120s and cross-checked against `gh run list` before any no-CI fallback — then the squash-merge and the §1.5 post-merge audit.
     **If CI comes back red,** the orchestrator re-dispatches a fix — you (or the Opus recovery agent) get a FRESH focused turn with the failing-check details. In that turn: read the failing logs (`gh run view <run-id> --log-failed`), fix in this worktree, commit (precise staging from step 4a + the step-4b auto-close audit still apply), bare-push (upstream is already set from your first push), and return `agent-status: pr-opened pr:<N>` again so the orchestrator re-watches + re-gates. Never merge yourself, never `--admin`, never bypass a failing/pending check.

Return summary:
  • agent-status: pr-opened pr:<N> | incomplete — <reason>
  • PR number + URL
  • local-gate evidence: <full-compile result> + <targeted tests pass/total, naming which test projects ran>. The orchestrator uses this ONLY in the rare genuine-no-CI case (after it settles an empty rollup and confirms zero CI runs); when used, it re-runs the FULL local suite itself as the real gate — so report honestly, never implying the full suite passed locally when you only ran targeted tests.
  • Build (compile) status: green
  • Targeted tests run + result (which test projects)
  • Pre-existing baseline failures observed: none | list (e.g. "6 tests in `<some-test-file-pattern>` — same set fails on batch baseline, not in story diff")
  • **TODOs introduced by this story** (pass-through from Agent C's return summary): structured block with `count: <N>` and `list:` followed by one bullet per marker formatted `- <file>:<line> — <MARKER_WORD>: <full line text>`. Use `count: 0` and an empty list if none. The orchestrator parses this field into `annotations[]` (kind=`todo`) for Phase 2 batch-QA.
  • **Carry-forward framework gaps** (STRUCTURED — distinct from the freeform "Flags for batch-QA" below). Carry-forwards are KNOWN LIMITATIONS that no single story can fix — typically framework-level gaps that propagate across multiple stories in an epic (e.g. "list+detail pages for `/some-feature-route` don't exist in the router yet — clicking any related palette `open` action 404s"; "a debounced-query variable in a shared command-palette hook is never populated from the visible input — no entity-search story can trigger the network call from the palette"). Format: `count: <N>` + `list:` of bullets `- <one-line gap description> — owning_framework: <framework/epic/issue ref OR "tbd"> — affects_this_story: <how the story is affected>`. Use `count: 0` and an empty list if none. **Source from**: Agent A's "Carry-forward gaps" notes in the story file, plus any TODO(post-epic)-style comments, plus any "out of scope for this story" notes from Agent C. The orchestrator parses this field into `annotations[]` (kind=`carry-forward`) — gaps repeated by ≥2 issues are aggregated at query time as framework gaps the QA agent must NOT report as bugs.
  • Files changed (count)
  • Flags for the Phase 2 batch-QA sub-agent (e.g. "this issue touches an audit/log table — verify audit rows"; "i18n keys added — confirm each supported locale renders"; "new endpoint added — smoke it")

**⚠️ Your VERY LAST line must be exactly `agent-status: pr-opened pr:<N>` (or `agent-status: incomplete — <reason>`) — a literal line, not a prose wrap-up. You no longer emit a `merge-sha` line; the orchestrator captures the merge SHA when IT merges.**

Final line of your reply must be `agent-status: pr-opened pr:<N>` or `agent-status: incomplete — <reason>`.
