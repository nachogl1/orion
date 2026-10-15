# Changelog

Newest first. One line per pull request: what changed and why it matters to someone using orion.

- New skill `clear-git-resources`: lists the stale worktrees, local and remote branches and leftover files in the worktree root in plain words, says what deleting each would lose, and deletes only what you agree to; the session-start hook offers it once the project has `branchLimit` branches (20 by default, in `.claude/orion/config.json`).
- The orion repo now runs on its own baseline: `CLAUDE.md` imports `baselines/BASE_CLAUDE.md` directly, so every edit to the baseline changes the repo's own rules in the same commit; CI runs the build, lint, typecheck and round-trip suite on every pull request so "merge on green" means something here too.
