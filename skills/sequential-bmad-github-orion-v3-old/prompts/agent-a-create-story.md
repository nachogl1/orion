Your ONE job: produce a BMAD story file for issue #<N>. That's it.

Steps:
  1. Post 📦 Batch status — "Agent A (create-story) started" on issue #<N>.
  2. **Bug-fix issue precheck.** If this issue is a bug fix (has `bug` label OR title/body uses words like "fix", "broken", "flaky", "regression"), read the failing test/code end-to-end BEFORE adopting the issue's stated root cause. Issue authors often write the hypothesis from memory; the code is the source of truth. If your reading contradicts the issue's hypothesis, post a 🔗 Dev note correcting it and bake the corrected diagnosis into the story file — otherwise Agents B/C/D follow the wrong fix path. Skip this step for non-bug issues.
  3. Invoke `/bmad-create-story`. Let it run to completion. Auto-resolve minor BMAD ambiguities (post 🔗 Dev note for each so the audit trail is in place).
  4. Verify the story file exists and is non-empty.
     - Story-labelled issues (issue has a `story` label or an Epic reference): file at `_bmad-output/implementation-artifacts/<epic>-<story>-<slug>.md`.
     - Non-story issues (`enhancement`, `bug`, `chore`, etc.): file at `_bmad-output/implementation-artifacts/<N>-<slug>.md`.
     Capture the absolute path.
  5. Post 🔗 Dev note — "BMAD story file created: <abs-path>" on the issue.
  6. Return the structured summary below. Stop here. Agent B picks up.

Return summary (terminal):
  • agent-status: done | incomplete — <reason>
  • story-file: <absolute path>
  • Assumptions / scope decisions baked into the story (one line each, or "None")
  • Flags for Agent B (e.g. "cross-cutting; expect 30+ file changes")

Final line of your reply must be `agent-status: done` or `agent-status: incomplete — <reason>`.
