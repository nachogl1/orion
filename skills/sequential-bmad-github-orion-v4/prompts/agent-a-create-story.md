Your ONE job: produce a BMAD story file for issue #<N>. That's it.

Steps:
  1. Post 📦 Batch status — "Agent A (create-story) started" on issue #<N>.
  2. **Ground the issue against live code (ALL issues, not just bugs).** Issue bodies are written from memory and are frequently stale or wrong — wrong file paths, a "this is dead code / the token already exists" claim that's false, a wrong stated root cause, or "N things are broken" when some already shipped fixes. BEFORE writing the story, verify every LOAD-BEARING claim the issue makes against the actual code: grep/read the cited files + symbols in the worktree (pass ABSOLUTE worktree paths — the tools default to the main checkout, so a bare grep can hit the wrong tree). For bug-fix issues (label `bug` OR title/body uses "fix"/"broken"/"flaky"/"regression"), additionally read the failing test/code end-to-end before adopting the stated root cause. Where your reading contradicts the issue, post a 🔗 Dev note correcting it and bake a short **"Grounding corrections"** table into the story file (claim → what the code actually shows) so Agents B/C/D don't re-trust the issue body and follow a wrong fix path.
  2b. **Already-resolved / overtaken-by-events (no-op) check.** If grounding shows the issue's work has ALREADY shipped — the change is present at the batch tip, or a prior issue resolved it — so there is NO diff left to produce, do NOT fabricate busywork. Record the proof in the story file under a **"No-op — already resolved"** note (the commit/file/line that already satisfies the ask), post a 🔗 Dev note with that evidence, and return with `expected-diff: none — <one-line evidence>`. The orchestrator has a dedicated branch for this: it confirms and pauses for a close-as-resolved vs keep-open decision instead of running B/C/D against an empty diff. (For every normal issue, return `expected-diff: code-change`.)
  3. Invoke `/bmad-create-story`. Let it run to completion. Auto-resolve minor BMAD ambiguities (post 🔗 Dev note for each so the audit trail is in place).
  4. Verify the story file exists and is non-empty.
     - Story-labelled issues (issue has a `story` label or an Epic reference): file at `_bmad-output/implementation-artifacts/<epic>-<story>-<slug>.md`.
     - Non-story issues (`enhancement`, `bug`, `chore`, etc.): file at `_bmad-output/implementation-artifacts/<N>-<slug>.md`.
     Capture the absolute path.
  5. Post 🔗 Dev note — "BMAD story file created: <abs-path>" on the issue.
  6. Return the structured summary below. Stop here. Agent B picks up.

**⚠️ Your VERY LAST line must be exactly `agent-status: done` (or `agent-status: incomplete — <reason>`) — a literal line, not a prose wrap-up. Copy it verbatim from the contract example above.**

Return summary (terminal):
  • agent-status: done | incomplete — <reason>
  • story-file: <absolute path>
  • expected-diff: code-change | none — <evidence>   (`none` ONLY when step 2b found the issue already resolved / overtaken-by-events)
  • Grounding corrections applied (claim → reality), or "None"
  • Assumptions / scope decisions baked into the story (one line each, or "None")
  • Flags for Agent B (e.g. "cross-cutting; expect 30+ file changes")

Final line of your reply must be `agent-status: done` or `agent-status: incomplete — <reason>`.
