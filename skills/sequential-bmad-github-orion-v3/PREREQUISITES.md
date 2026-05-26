# Prerequisites

## Hard requirements (skill halts at Phase 0 if missing)

- **BMAD methodology installed** — specifically the slash commands `/bmad-create-story`, `/bmad-dev-story`, `/bmad-code-review`. Agents A, B, C invoke them directly; without BMAD the pipeline fails at Agent A.
- **`gh` CLI installed and authenticated** — `gh auth status` must succeed. The skill uses `gh` for issue listing, PR creation, CI polling, and post-merge issue close.
- **GitHub Issues as the project's source of truth** — every issue in the queue must exist in GitHub. The skill posts milestone comments on each issue throughout the run.
- **git ≥ 2.25** for worktree support — each per-issue agent runs in its own worktree under `<worktree-parent>/<repo-name>-<N>/`.
- **Default branch is `main` or `master`** — auto-detected via `gh repo view --json defaultBranchRef`. The orchestrator must be invoked from the default branch.
- **Clean working tree** — `git status --porcelain` must show no STAGED changes. Modified tracked files BLOCK. Untracked files outside the run scope are OK (logged, not blocked).
- **Fast-forwardable main** — `git fetch && git pull --ff-only` must succeed at Phase 0. Non-fast-forward stops the run.

## Soft requirements (skill handles absence; presence enables features)

- **Playwright MCP** for the Phase 2 live-stack QA gate (Gate 3). Without it, the batch-QA test-and-fix agent uses headless equivalents or, via the environmental escape hatch, substitutes equivalent coverage (`WebApplicationFactory` + Testcontainers, supertest + ephemeral DB, etc.) and documents the substitution in the handoff block.
- **`project_target_date.md` memory file** at `~/.claude/projects/<harness-project-key>/memory/project_target_date.md` enables the target-rate analysis section in the Phase 4 stats report. Format:
  ```yaml
  target_date: 2026-05-27
  description: "MVP feature-complete deadline"
  ```
  Without this file, the stats report omits the target-rate section and prints a one-line configuration hint.
- **`project_skill_repo_name.md` memory file** at the same memory path enables a custom repo-name override (keyed by `git remote get-url origin`). Useful when your local clone basename is generic (e.g. `src`, `repo`, `code`, `work`, `project`, `dev`, `tmp`, etc. — Phase 0 step 6 will prompt for a name and offer to save it if you don't pre-populate this file).

## Project-side conventions the skill respects

- **`CLAUDE.md` / `README.md` / `CONTRIBUTING.md`** are read by sub-agents to detect build/test commands, project conventions, and persona/role definitions for the Junior-tester QA gate.
- **Build/test auto-detection** works for: `dotnet build` / `dotnet test`, `npm run build` / `npm test`, `bun run build` / `bun run test`, `pnpm build` / `pnpm test`, `pytest`, `cargo build` / `cargo test`, `make` / `make test`. Anything more exotic should be documented in `CLAUDE.md` so Agents B and D find it.
- **i18n conventions** — if your project uses `/locales/<lang>/` files or a documented i18n config, the Junior-tester QA gate covers each supported locale.

## Environment variables (optional overrides)

- **`BATCH_PIPELINE_SIZE_PROMPT_THRESHOLD`** — integer, default `4`. Queue size above which Phase 0 step 5c surfaces a single `AskUserQuestion` to confirm proceed-all / limit-to-N / cancel. Set higher to suppress the prompt for routine large batches; set lower to be prompted more aggressively.

## What the skill writes to

- `~/Downloads/batch-<repo-name>-<timestamp>-<issue-suffix>/` — session folder (preserved on success for inspection; contains `run.jsonl`, `lessons-learned.md`, `qa-report.html`, `manifest.md`, optional `failures/<N>-<slug>/`, optional `scratch/`).
- `~/Downloads/<repo-name>-stats-<DD_MM_YYYY>-<HH_MM>.html` — one fresh stats report per run.
- `~/.claude/dev-stack.lock` — transient lock file claimed/released by the Phase 2 live-stack QA gate.
- **The user's GitHub repo** — issue comments (📦 status, 🔗 dev notes, 🤝 dev→review handoff, 🔍 review notes, 🐛 batch-QA findings, 🚧 failure comments, ✅ shipped audit comment in Phase 4), PR creation + merge, branch creation + delete. **Deferral tracking (v3):** in Phase 2 (and as a Phase 4 pre-close backstop) the skill **finds-or-reuses** a tracking issue for each distinct deferred item (pre-existing baseline failures, carry-forward gaps) — searching open issues first, never duplicating per run — and **edits per-issue PR bodies** to link the resulting `#N`. It creates the labels `baseline-failure` and `recovered-scope` if your repo doesn't already have them (tolerated if they exist).
- **The user's git worktrees** — one per active issue under `<worktree-parent>/<repo-name>-<N>/`, plus one batch-QA worktree under `<worktree-parent>/<repo-name>-batch-<timestamp>/`. All cleaned up after Phase 4 merge.

The skill **never** writes to your long-lived `<repo-name>-status-*.html` deck, your `_bmad-output/` folder beyond the per-issue story file that BMAD itself creates, or any path outside `~/Downloads/` and your repo.
