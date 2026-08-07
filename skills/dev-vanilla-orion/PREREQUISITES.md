# Prerequisites — dev-vanilla-orion

- **GitHub CLI (`gh`)** authenticated against the repo's host (`gh auth status`), with
  permission to create branches, PRs, labels, and issue comments.
- **git** with worktree support (any modern git).
- **A GitHub-issues-driven repo** — issues are the source of truth; the skill validates
  the four triage labels and creates any that are missing on first run (no confirm — it
  runs unattended).
- **The project's own toolchain** installed (whatever builds/tests the repo — detected
  at run time from the repo's files).
- **Optional:** a local container runtime (only if the project's QA stack needs one) ·
  an e2e suite (only used when configured and the batch touches UI) · a private
  findings-store clone (only if you want cross-run process telemetry; without it,
  findings land in the session folder).
- **First run in a repo:** no interview. The skill derives its config (project name,
  boundary repos = this repo only, e2e location, review checklist, findings store, UI
  paths) from the repo itself, writes `.claude/dev-vanilla-orion.yaml` (kept out of git
  automatically), prints the assumed values, and carries on. Edit that file to change
  anything — including `autonomy: checkpointed` if you want it to confirm tracker writes.
- **What it will do without asking:** create the triage labels, label/relabel the issues
  you passed it, sharpen an issue body whose intent is unambiguous, branch, commit, open
  per-issue PRs and merge them into the *batch* branch, file deferral tracking issues,
  and open the batch PR. It never merges the batch PR — that is yours.
