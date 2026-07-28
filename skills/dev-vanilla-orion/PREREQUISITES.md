# Prerequisites — dev-vanilla-orion

- **GitHub CLI (`gh`)** authenticated against the repo's host (`gh auth status`), with
  permission to create branches, PRs, labels, and issue comments.
- **git** with worktree support (any modern git).
- **A GitHub-issues-driven repo** — issues are the source of truth; the skill validates
  and (with your confirm) creates the four triage labels on first run.
- **The project's own toolchain** installed (whatever builds/tests the repo — detected
  at run time from the repo's files).
- **Optional:** a local container runtime (only if the project's QA stack needs one) ·
  an e2e suite (only used when configured and the batch touches UI) · a private
  findings-store clone (only if you want cross-run process telemetry; without it,
  findings land in the session folder).
- **First run in a repo:** expect a short interview (project name, boundary repos, e2e
  location, review checklist, findings store) — answers are saved to
  `.claude/dev-vanilla-orion.yaml` (kept out of git automatically) and never asked again.
