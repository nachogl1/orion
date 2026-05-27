Story file (from Agent A): <story-file-path>

Your ONE job: implement the code for the story Agent A wrote.

Steps:
  1. Post 📦 Batch status — "Agent B (implementation) started" on issue #<N>.
  2. Read the story file in full. It is your authoritative spec — ACs, scope decisions, task breakdown.
  3. **Worktree dep install preflight.** If the project uses a JS package manager (`package.json` + a lockfile like `bun.lockb`, `pnpm-lock.yaml`, `yarn.lock`, or `package-lock.json`), worktrees do NOT inherit `node_modules` — run the matching install command from the workspace root once now (`bun install` / `pnpm install` / `npm install` / `yarn install`). Without this, the first frontend test/build/typecheck command fails with "vitest not found" or similar. Skip if no JS package manager is present.
  4. Invoke `/bmad-dev-story` with the story file as input. Let it run to completion. Implement code, tests, i18n strings if relevant. Tick AC checkboxes in the issue body as you satisfy each.
  5. While implementing, refuse to write code that violates project conventions documented in CLAUDE.md / README / CONTRIBUTING. If BMAD generates a violation, fix it immediately.
  5b. **Opportunistic in-place fixes (Core Principle #10).** The story is your scope spec, but it is NOT a reason to leave an obvious small defect in code you're already editing. When you notice a nearby bug, missing guard, or stale comment while implementing, apply the cheap-and-safe test: **small · local (in code you're already touching) · covered by tests you're running · low blast-radius (no schema/migration, no shared-contract/public-API change, no new dependency) · scope-neutral.** If it passes, just fix it — note it as a 🔗 Dev note labelled *"opportunistic fix (CP#10)"*. If it fails (large, cross-cutting, needs a product/design call, or a different slice), do NOT fix it — record it as a deferred check in your handoff with the single failing criterion, so Agent C / Phase 2 can route it to a tracked `#N`. Do NOT go hunting for unrelated work; this covers only defects you cross while doing the story.
  6. Run TARGETED tests as you go (only the test projects/packages whose source you touched). Max 5 fix-and-retry cycles per command. Use whatever test runner the project uses (auto-detect from project files).
  7. Pre-handoff full build (mandatory): run the project's full build command (auto-detect: e.g. `dotnet build <solution>`, `npm run build`, `cargo build`, `make`). NOT the full test suite — just compile. If red, fix now. This shifts cross-project compile-break catches from the expensive Agent C step to the cheap Agent B step.
  8. Post 🔗 Dev notes IN REAL TIME (one per discovery, do NOT batch) for: dependencies discovered, assumptions baked in, decisions taken, deferred checks.
  9. When implementation is complete, post ONE 🤝 Dev → Review handoff comment with sections Dependencies / Assumptions / Decisions / Potential merge conflicts / Skipped checks. Always post (use "None" for empty sections) — it's the audit trail Agent C + Phase 2 batch QA will read.
  10. DO NOT commit, push, open a PR, or merge. Leave changes uncommitted for Agent C.

Return summary:
  • agent-status: done | incomplete — <reason>
  • Files changed (count + key file list, from `git status --porcelain`)
  • i18n keys added/changed (yes/no, list)
  • New endpoints / hubs / DB migrations / wire-protocol surface (Phase 2 QA cares)
  • Full build status: green / red+reason
  • Targeted tests run + result
  • Flags for Agent C (e.g. "I made a judgment call on X — please review that specifically")

Final line of your reply must be `agent-status: done` or `agent-status: incomplete — <reason>`.
