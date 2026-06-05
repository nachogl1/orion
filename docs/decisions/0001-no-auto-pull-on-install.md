# 1. No auto-pull on install

Date: 2026-06-06

## Status

Accepted

## Context

The installer links each `skills/<name>/` folder into `~/.claude/skills/` via a
junction/symlink that points back at the clone. Because the linked file **is** the
repo file, a `git pull` propagates skill changes to every machine immediately.
Auto-pulling executable skill content is a supply-chain risk: anything pushed to
`origin/main` would run as the user, on every machine, with no review step.

## Decision

Updates are **manual** (`install.ps1 -Update` / `install.sh --update`). A scheduled
auto-pull is available but **disabled by default** and must be opted into explicitly.

## Consequences

- Users get a "did I really want this?" checkpoint before taking new code.
- The repo trades convenience (always-latest) for a review boundary on each update.
