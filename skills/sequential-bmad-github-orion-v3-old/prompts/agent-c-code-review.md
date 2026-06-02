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
  6b. **Adjacent findings — apply the fix-in-place-first gate (Core Principle #10).** `/bmad-code-review` and your own reading will surface findings that sit just OUTSIDE the immediate diff or the story's literal ACs (a nearby latent bug, a missing guard one call up, a stale comment in a file you touched). Do NOT reflexively route these to deferral just because they weren't in the story — deferral is the fallback, not the default. For each such finding, run the cheap-and-safe test: is it **small**, **local** (in or directly adjacent to touched code), **covered** by tests already running here (or trivially coverable), **low blast-radius** (no schema/migration, no shared-contract or public-API change, no new dependency, no cross-cutting behavior change), and **scope-neutral** (doesn't expand user-facing scope or pull in a different slice)?
       - **Passes the test → fix it now**, even though it extends beyond the original diff. Post a 🔍 Review note labelled *"🛠 Opportunistic fix (in-scope per CP#10)"* with the diagnosis + fix, and apply it.
       - **Fails the test → defer it** and name the single failing criterion (e.g. *"defer: blast-radius — touches shared auth middleware"*). Surface it as a 🔍 Review note + a flag for Agent D so it enters the tracked-deferral path (Core Principle #9). When genuinely unsure about blast-radius, defer.
  7. Re-run the diff and confirm findings are resolved.
  8. If any finding cannot be auto-fixed (design flaw, ambiguity needing human input, missing dependency the dev couldn't have known about) — i.e. it failed the gate in 6b on a blast-radius / product-decision criterion — return `agent-status: incomplete — <reason>` only when it BLOCKS the story; otherwise record it as a tracked deferral (flag for Agent D) and continue.
  9. When clean, post 🔍 Review note — "Code review complete — N findings, all auto-fixed" (or "clean").
  10. DO NOT commit, push, PR, or merge. Leave fixes uncommitted on top of Agent B's changes.

Return summary:
  • agent-status: done | incomplete — <reason>
  • Review findings count (or "clean")
  • Findings categories (security, performance, project-convention violation, test gap, i18n miss, etc.)
  • **Opportunistic fixes applied** (from step 6b — adjacent findings that PASSED the CP#10 gate and were fixed in-place): count + one-line list, or `count: 0`.
  • **Findings deferred** (from step 6b — failed the gate): count + one bullet per item formatted `- <short description> — defer: <single failing criterion>`. These are flags for Agent D's tracked-deferral path. Use `count: 0` if none.
  • Files newly touched by your fixes
  • **New TODO/FIXME/HACK markers introduced** (from step 5b): structured block with `count: <N>` and `list:` followed by one bullet per marker formatted `- <file>:<line> — <MARKER_WORD>: <full line text>`. Use `count: 0` and an empty list if none.
  • Flags for Agent D

Final line of your reply must be `agent-status: done` or `agent-status: incomplete — <reason>`.
