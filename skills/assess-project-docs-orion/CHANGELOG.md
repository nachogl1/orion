# Changelog — assess-project-docs-orion

This skill follows **no `-vN` convention** — it is edited in place. Record notable
changes here.

## Initial version

- New skill: assess a repository's project documentation against a **two-layer
  benchmark** and emit a self-contained HTML report into the Downloads folder.
- **Consensus layer** (`guidelines/consensus-resources.md`) — independent, widely-cited
  best-practice resources (Claude Code memory & best-practices docs, Make a README /
  Standard Readme, GitHub community-health & PR-template docs, Conventional Commits /
  Keep a Changelog / SemVer / ADR), re-validated at run time.
- **Orion layer** — per-doc guideline files generalized from real projects:
  - `guidelines/claude-md.md` — agent instruction files (effort economy, change
    philosophy, end-to-end verification, communication & directness,
    discuss-before-doing, git guardrails, branch/worktree naming, multi-agent safety,
    source-of-truth & deferral discipline, doc maintenance, stack enforcement). Includes
    the collected guideline: **summarize and use clear language by default; let the
    user ask for more detail.**
  - `guidelines/project-readme.md` — README orientation, runnable quick-start,
    reference-don't-duplicate, status honesty.
  - `guidelines/contributing-and-governance.md` — contribution mechanics, merge/
    protection rules, deferral discipline, decision records, and the collected
    guideline: **agent-safe vs. needs-human-decision issue tagging** (flag the issues
    where an agent must stop and ask a human; apply narrowly).
  - `guidelines/pr-template.md` — PR-template *guidelines* (not a template):
    summary+issue link, work-item refs, out-of-scope **anchoring discipline**, real
    test-evidence, an enforcement checklist **generated from the repo**, human-owned
    merge.
- A **benchmark-confirmation step** (Phase 1): before assessing, the skill shows the
  user the exact consensus resource list it will use (re-validated for reachability)
  and asks whether to add more; user-added sources can optionally be persisted into
  `guidelines/consensus-resources.md` for future runs.
- Per-doc assessor pipeline (parallel, capped) and cross-doc synthesis
  (duplication/drift, coverage gaps, convention consistency).
- **Strictly read-only:** the skill reports and recommends only. It never edits any
  file, never writes a PR template into the repo, never commits, and does not offer to
  apply fixes — every recommendation lives in the HTML report for the user to apply.
