# `assess-project-docs-orion` — guidelines corpus

These files are the **benchmark the skill scores a repository's docs against.** They
are read at run time by the per-doc assessors; they are not copied into the target
repo.

## The two-layer model

Every doc is assessed against the **union** of two layers, scored separately in the
report:

1. **Consensus layer** — [`consensus-resources.md`](consensus-resources.md). Widely
   cited, independent, vendor-/community-authoritative guidance (none owned by the
   skill author). This is the "what does the field agree on" baseline. The skill
   **re-validates these links at run time** before citing them.
2. **Orion layer** — the per-doc guideline files below. Opinionated guidelines
   collected from real projects and **generalized for reuse** (no project, person,
   org, stack, or path specifics). Stricter than consensus; never contradicts it.

## Files

| File | Assesses | Consensus §s |
|---|---|---|
| [`consensus-resources.md`](consensus-resources.md) | (the external benchmark + runtime re-validation rules) | — |
| [`claude-md.md`](claude-md.md) | `CLAUDE.md`, `.claude/CLAUDE.md`, `CLAUDE.local.md`, `.claude/rules/*`, imported `AGENTS.md` | §1 |
| [`project-readme.md`](project-readme.md) | `README.md` (root + per-package) | §2 |
| [`contributing-and-governance.md`](contributing-and-governance.md) | `CONTRIBUTING`, `CODE_OF_CONDUCT`, `SECURITY`, CI/test docs, runbook, ADR index, decision log | §3, §5 |
| [`pr-template.md`](pr-template.md) | `PULL_REQUEST_TEMPLATE.md` / `.github/…` / `PULL_REQUEST_TEMPLATE/` | §4 |

Each orion guideline file ends with a **0–5 scoring rubric** the assessor fills in,
and instructs the assessor to attach a **concrete fix** (and a suggested rewrite
snippet where useful) to every dimension scoring under 3.

## Extending the corpus

- To assess a **new kind of doc**, add a `<doc>.md` here following the same shape
  (Consensus baseline → Orion layer → Smells → 0–5 rubric), add a row above, list its
  benchmark sources in `consensus-resources.md`, and register the assessor in
  `../SKILL.md`.
- To add a **consensus source**, see the "Adding to this list" note in
  `consensus-resources.md` — primary/canonical URLs only, and never a source the
  skill author owns.

## Distribution-safety reminder

This repo is publicly distributable. Everything here must stay **general**: no
person/org/product/repo/stack/locale/path specifics, in prose, examples, or rubric
items. The orion guidelines were distilled from real CLAUDE.md / PR-template files
**with all identifying detail stripped** — keep it that way when you edit.
