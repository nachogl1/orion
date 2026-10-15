# Changelog

Newest first. One line per pull request: what changed and why it matters to someone using orion.

- BASE_CLAUDE.md now says a PRD is never created automatically: an agent stops and asks, drafts only on request, and the draft is the PRD only once the person approves it, so no big change gets ticketed or built on an unread PRD.
- The orion repo now runs on its own baseline: `CLAUDE.md` imports `baselines/BASE_CLAUDE.md` directly, so every edit to the baseline changes the repo's own rules in the same commit; CI runs the build, lint, typecheck and round-trip suite on every pull request so "merge on green" means something here too.
