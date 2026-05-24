Your ONE job: code-review the uncommitted diff Agent B produced and auto-fix every finding.

Steps:
  1. Post 📦 Batch status — "Agent C (code-review) started" on issue #<N>.
  2. Verify there ARE uncommitted changes via `git status --porcelain`. If clean, return `agent-status: incomplete — no implementation diff to review`.
  3. Read the 🤝 Dev → Review handoff comment Agent B posted. Internalize dependencies / assumptions / decisions before reviewing — those constrain what counts as a "finding" vs an intentional choice.
  4. Invoke `/bmad-code-review` against `git diff origin/<batch-branch>...` (combines staged + unstaged Agent B changes; worktree base is the batch tip). Be thorough.
  5. **Verify factual claims in new docs/comments.** Scan the diff for newly-added xmldoc / docstrings / code comments that make verifiable claims (DB constraint names, schema columns, file paths, status codes, config keys, error codes, function signatures). For each such claim, grep the referenced source file to confirm accuracy. Mis-stated facts in fresh documentation become permanent reader confusion — a 30-second grep is cheap, a misleading docstring is expensive. Treat any mismatch as a 🔍 Review note + fix in step 6.
  5b. **Scan for new TODO/FIXME/HACK/XXX markers (production-readiness surface).** Per Core Principle #1, TODOs are ALLOWED but must be flagged so they don't go undiscovered in the codebase. Run:
      `git diff origin/<batch-branch>...HEAD -U0 | grep -E '^\+.*\b(TODO|FIXME|HACK|XXX)\b'`
      to capture every NEW marker comment introduced by this story (added lines only — the leading `^\+` filters out context). For each match:
       a. Extract the file path (from the diff hunk header) + the line number (count `+` lines from the hunk's `@@ +<start>,<len> @@`) + the marker word (`TODO` / `FIXME` / `HACK` / `XXX`) + the full marker line text.
       b. Post ONE 🔍 Review note per marker with format: *"📝 TODO surfaced — `<file>:<line>` — `<marker word>: <rest of the line>`. TODOs/FIXMEs/HACKs are allowed under Core Principle #1 but are flagged here so they don't go undiscovered. The marker SURVIVES review intact — do NOT auto-remove or 'resolve' it. It will propagate to Agent D's PR body, the per-issue close comment, and the qa-report.html so the downstream QA agent + the human reviewer both see it."*
       c. Add the marker to your return summary under a dedicated `New TODO/FIXME/HACK markers introduced` field (count + structured list — see return summary below).
      Do NOT remove markers. Do NOT downgrade `FIXME` to `TODO` or otherwise massage the marker word. Markers are intentional debt-with-a-receipt; the receipt is what we're protecting.
      If the grep returns zero matches: include the field as `count: 0; list: []` in the return summary — explicit zero is more useful than a missing field.
  6. For every finding: post 🔍 Review note (one per finding) with diagnosis + the fix you're about to apply. Apply the fix.
  7. Re-run the diff and confirm findings are resolved.
  8. If any finding cannot be auto-fixed (design flaw, ambiguity needing human input, missing dependency the dev couldn't have known about), return `agent-status: incomplete — <reason>`.
  9. When clean, post 🔍 Review note — "Code review complete — N findings, all auto-fixed" (or "clean").
  10. DO NOT commit, push, PR, or merge. Leave fixes uncommitted on top of Agent B's changes.

Return summary:
  • agent-status: done | incomplete — <reason>
  • Review findings count (or "clean")
  • Findings categories (security, performance, project-convention violation, test gap, i18n miss, etc.)
  • Files newly touched by your fixes
  • **New TODO/FIXME/HACK markers introduced** (from step 5b): structured block with `count: <N>` and `list:` followed by one bullet per marker formatted `- <file>:<line> — <MARKER_WORD>: <full line text>`. Use `count: 0` and an empty list if none.
  • Flags for Agent D

Final line of your reply must be `agent-status: done` or `agent-status: incomplete — <reason>`.
