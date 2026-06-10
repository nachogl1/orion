# Prerequisites — fable-sequential-gh-orion-v1

## Hard requirements

1. **GitHub repository + `gh` CLI authenticated** — `gh auth status` and `gh repo view` must
   succeed. GitHub Issues are the source of truth for all work items.
2. **Claude Code with Workflow (ultracode) support** — the per-issue pipeline is a Workflow
   script; invoking this skill is your opt-in to multi-agent orchestration.
3. **Open, agent-ready issues** — concrete scope, acceptance criteria present or inferable, no
   unresolved human-decision banners. Issues produced by `/fable-prd-orion` or
   `/fable-project-updates-orion` meet this bar by construction; `/assign-issues-orion`
   describes the six-point gate.
4. **NO BMAD required** — this is the BMAD-free successor of the sequential-bmad family. If
   your project still runs on BMAD story files, use `sequential-bmad-github-orion-v4` instead.

## Strongly recommended before the FIRST unattended (overnight) run

- **Permission allowlist**: run `/fewer-permission-prompts` (or hand-edit the project's
  `.claude/settings.json`) so `git`, `gh`, and the project's build/test commands don't prompt.
  An unattended run that hits a permission prompt stalls silently until you return.
- **Machine stays awake**: local runs need the machine on for the whole batch — check power/
  sleep settings. (Cloud-scheduled runs are a separate, later concern.)
- **A small trust-building batch first**: 2–3 well-understood issues while you watch, before
  queueing a whole night.
- **CI on the repo**: the merge gate is strongest when the repo has CI. No-CI repos fall back
  to full local build + full test suite as merge evidence — works, but slower and weaker.

## Nice to have

- A `CLAUDE.md` in the target repo documenting build/test commands and conventions — agents
  detect the toolchain from project files, but documented commands remove guesswork.
- Locale/i18n conventions documented if the project is localized (implementers add strings for
  user-facing text when locales are detected).
