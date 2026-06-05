# Orion guidelines — Claude Code setup self-audit (`~/.claude/`)

The orion layer for auditing the **user's own Claude Code setup** — the home
configuration the agent runs under on every project. Where the other assessors look at
a target *repo*, this one points Claude at its **own environment** and reports what's
**stale, broken, or wasteful**. Pair with the consensus baseline in
[`consensus-resources.md`](consensus-resources.md) (section 7).

> **Read-only, and it's the user's machine.** This assessor reads home-level config and
> reports findings; it **never edits `settings.json`, removes a hook, or changes a
> skill.** Treat the contents as potentially sensitive (they may contain the user's own
> paths/keys) — findings go in the **local** report, and nothing from here is copied
> into this publicly-distributable skill repo.

A bigger, cleaner setup compounds: a broken hook fails silently every turn, a stale
rule misleads every session, a wasteful always-on context burns tokens on every
prompt. Auditing it occasionally is high-leverage — more working tooling, less dead
weight, more of the budget spent on real work.

---

## A. What to read (user scope)

- `~/.claude/settings.json` and `~/.claude/settings.local.json` — model, permissions,
  env, hooks, statusLine, MCP enablement.
- `~/.claude/CLAUDE.md` (user-level memory) and any `~/.claude/rules/`.
- `~/.claude.json` — user-scope MCP servers and per-project overrides.
- `~/.claude/skills/`, `~/.claude/plugins/`, `~/.claude/agents/` — installed/linked
  skills, plugins, subagents (note junction/symlink targets that no longer resolve).
- Hook scripts the settings reference (resolve each path; a referenced-but-missing
  script is a hard finding).

## B. Orion layer — what a healthy setup looks like

### B1. Broken / dangling references (hard findings)
- A hook command, statusLine command, skill/plugin link, or `@`-imported path that
  **doesn't resolve** — it fails or is ignored every session. List each with its
  source line.
- A `settings.json` that **doesn't parse** (a BOM, trailing comma, or a stray edit
  breaks the whole file) — the single highest-severity finding.

### B2. Stale rules & memory
- User-level `CLAUDE.md` rules that contradict current tooling, name skills/commands
  that no longer exist, or describe a workflow the user has moved off. Cross-check
  named skills/commands against what's actually installed.
- Duplicated guidance between user `CLAUDE.md` and project files that has drifted.

### B3. Wasteful / token-heavy config
- Large always-loaded user `CLAUDE.md` (the ~≤200-line guidance applies here too) —
  every token loads on every prompt across every project.
- Hooks that run heavy work on a hot path (e.g. every prompt-submit) when they could be
  scoped or cached.
- A statusLine or context-injecting hook that emits a lot of text each turn.
- Permissions far broader than the user actually relies on (re-validate against real
  usage; over-broad allow-lists are a safety *and* noise cost).

### B4. Hooks: correct mechanism & safety
- Each hook resolves, exits cleanly, and is the right event for the job; a hook doing
  what a skill or rule should do (or vice-versa) is a mechanism smell.
- No hook silently swallows failures it should surface; no destructive action runs in a
  hook without the user's intent.

### B5. Skills / plugins / MCP hygiene (overlaps `tooling-mcps-plugins.md`)
- Dead links (junction/symlink whose target was moved or deleted) — prune candidates.
- Installed-but-never-used skills/plugins; third-party tooling from unverifiable
  sources running with broad scope.
- Secrets hardcoded in `settings.json` / `~/.claude.json` instead of env /
  `settings.local.json`.

### B6. Versions & freshness
- Note tooling pinned to clearly old versions where it matters, and config referencing
  deprecated keys/flags. Don't chase upgrades for their own sake — flag only where it
  causes breakage or waste.

> **Tip — no status line, or no cost visibility?** If the user has no `statusLine`
> configured (or one that doesn't surface context-usage and spend), suggest the
> **orion status line** this repo ships: one line per session with alive-time,
> color-coded context %, git/PR state, and **cost** (this session + rolling 30 days).
> It installs with the same link-back mechanism as the skills and is opt-in:
> `install.ps1 -StatusLine` (Windows) / `install.sh --statusline` (macOS/Linux), or
> the y/N prompt during an interactive install. See the repo's `statusline/README.md`.

---

## C. Smells to flag

- A hook/statusLine/skill reference that **doesn't resolve** (silently dead every turn).
- `settings.json` that won't parse, or has a BOM (breaks Claude Code's JSON read).
- A bloated user `CLAUDE.md` loaded on every prompt for marginal value.
- Heavy work on a per-prompt hook hot path.
- Secrets committed into a settings file.
- Dangling skill/plugin links and installed-but-unused tooling.
- Over-broad permissions that don't match real usage.

## D. Scoring rubric (per dimension, 0–5; N/A where the user has no such config)

1. **Integrity** — everything referenced resolves and parses (§B1) — *weighted
   highest; a single hard break dominates the score.*
2. **Freshness of rules/memory** — no stale or contradictory user-level guidance (§B2).
3. **Token economy** — user `CLAUDE.md` and per-turn hooks/statusLine are lean (§B3).
4. **Hook correctness & safety** (§B4).
5. **Skills/plugins/MCP hygiene** — no dead links, dead weight, or hardcoded secrets
   (§B5).
6. **Versions & freshness** (§B6) — N/A if nothing is meaningfully out of date.

For every dimension under 3 (and not N/A), the report names the exact file + line and
gives a concrete fix (what to remove, scope, or rewrite) — as a recommendation the
user applies themselves. The skill changes nothing under `~/.claude/`.
