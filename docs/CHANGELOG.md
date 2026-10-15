# Changelog

Newest first. One line per pull request: what changed and why it matters to someone using orion.

- The orion repo's own `CLAUDE.md` drops a second round of repeats: the gate and definition of done, the harvest, QA, reconcile and issue-shape rules the imported `BASE_CLAUDE.md` already states, and three lines that said the same thing twice inside the file, so the skills' wiring is stated once as file names and couplings.
- The status line now shows the session or agent name (from `--agent`, `--name`, `/rename` or the AI title) so parallel sessions are told apart, and the pull-request segment is gone: it cost a `gh` call per branch and told nothing the session needed.
- New skill `clear-git-resources`: lists the stale worktrees, local and remote branches and leftover files in the worktree root in plain words, says what deleting each would lose, and deletes only what you agree to; the session-start hook offers it once the project has `branchLimit` branches (20 by default, in `.claude/orion/config.json`).
- The status line's git state now reads as words (`stashed:0 untracked:2 modified:5 unpushed:1`) instead of icons, so nothing on the line has to be remembered; the background-jobs flag is gone, as it never counted scheduled routines and earned its space poorly.
- The orion repo's own `CLAUDE.md` no longer repeats rules the imported `BASE_CLAUDE.md` already states (merge-on-green, GitHub Issues only, the harvest and QA thresholds, the drift probe, the parallel-planning rule), and its leak-scrub step no longer tells an agent to force-push, so one rule now has one home.
- BASE_CLAUDE.md now says a PRD is never created automatically: an agent stops and asks, drafts only on request, and the draft is the PRD only once the person approves it, so no big change gets ticketed or built on an unread PRD.
- The orion repo now runs on its own baseline: `CLAUDE.md` imports `baselines/BASE_CLAUDE.md` directly, so every edit to the baseline changes the repo's own rules in the same commit; CI runs the build, lint, typecheck and round-trip suite on every pull request so "merge on green" means something here too.
