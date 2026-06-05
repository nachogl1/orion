# Orion guidelines — MCP servers, plugins & agent tooling

The orion layer for assessing the **agent tooling wired into a project and the user's
environment** — MCP servers, Claude Code plugins, and helper repositories/CLIs an
agent benefits from. Pair with the consensus baseline in
[`consensus-resources.md`](consensus-resources.md) (section 6).

> **Recommend, never install.** This assessor is **read-only** like the rest of the
> skill. It detects what tooling is *already* configured at repo and user level, then
> lists **broadly-useful tooling that is missing** as a recommendation *in the report*.
> It never edits `.mcp.json`, `settings.json`, or installs anything.

The point is leverage: the right MCP/plugin turns work an agent would fake or do
badly (guessing at a running browser, hand-waving container state, re-deriving a
knowledge base, flooding its own context) into something it can actually *do*. More
capable tooling, applied to the right task, is more productivity.

---

## A. Where tooling lives (detect both scopes)

- **Repo scope** — `.mcp.json` at the repo root (project-shared MCP servers),
  `.claude/settings.json` / `.claude/settings.local.json`, a `.claude/plugins`
  reference, and any `.claude/` skills/agents the repo ships.
- **User scope** — `~/.claude.json` / `~/.claude/settings.json` (user MCP servers and
  enabled plugins), `~/.claude/skills/`, `~/.claude/plugins/`.
- A piece of tooling counts as **present** if it's configured at *either* scope and
  relevant to this project — don't recommend a repo-level server the user already has
  globally, and say which scope a recommendation belongs at.

## B. Assess by capability category (durable), name examples (illustrative)

Products change; the *capabilities a project benefits from* are stable. The assessor
scores whether each **relevant** category is covered, and names a concrete, publicly
available example the user can adopt. **Examples are illustrative — re-validate that
each still exists and is reachable at run time** (same rule as consensus links); a
category with no covered tooling is the finding, not the absence of one specific
product.

| Capability category | What it unlocks | Publicly-available examples |
|---|---|---|
| **Browser / UI automation** | Drive and screenshot the real app so "it works" is observed, not asserted (verification, e2e, visual QA). | Playwright MCP |
| **Container / runtime control** | Inspect and drive containers, images, logs, compose stacks — real infra state instead of guesses. | Docker MCP |
| **Knowledge base / docs sync** | Read & write the team's living knowledge base / spec so the source of truth isn't only in the repo. | Notion MCP |
| **Output / context compression** | Cut token spend and keep the main context alive on long sessions (compressed communication / subagent-output modes). | caveman MCP (compressed-communication mode) |
| **Token / context optimization** | Trim wasted tokens from prompts, transcripts, or generated artifacts so more budget goes to real work. | RTK — Rust Token Killer |
| **Issue-tracker / VCS integration** | Let the agent read/triage issues and PRs as the source of truth (only if a tracker is in use). | the tracker's official CLI / MCP (e.g. `gh`) |

Match the set to the project: a library with no UI doesn't need browser automation;
a repo with no container build doesn't need a container MCP. **Relevance gates the
recommendation** — don't pad the report with tooling this project can't use.

## C. Orion layer — what a well-tooled setup looks like

### C1. Coverage of the relevant categories
- Every capability the project's *actual* workflow needs has tooling wired up at the
  appropriate scope. Gaps in **relevant** categories are findings.

### C2. Right scope, no duplication
- Project-shared servers (everyone working the repo needs them) live in repo-level
  `.mcp.json`; personal/cross-project tooling lives at user scope. Flag a server
  pinned into a repo that's really a personal preference, and vice-versa.

### C3. Wired, not just installed
- A configured MCP/plugin that nothing references (no skill, no CLAUDE.md mention, no
  workflow uses it) is dead weight — note it. Tooling earns its place by being used.

### C4. Trust & supply-chain hygiene
- Third-party MCP servers and plugins run with the agent's privileges. The setup
  should pull from a **named, trusted source**, pin/track versions deliberately, and
  not auto-update executable tooling silently. Flag servers from unknown origins or
  with broad filesystem/network scope that the project doesn't justify.

### C5. Secrets handling
- MCP server config must not hardcode tokens/keys in a committed `.mcp.json`; secrets
  belong in env/`settings.local.json` (gitignored). A committed credential is a hard
  finding.

---

## D. Smells to flag

- A UI-heavy project with **no browser-automation tooling** — verification is almost
  certainly being asserted, not observed.
- A container-based project with no container MCP/CLI access — infra state is guessed.
- Long-session / multi-agent work with **no output/context-compression** tooling —
  context dies mid-turn and turns get truncated.
- An MCP server with a **hardcoded secret** in a committed file.
- Tooling **configured but never referenced** anywhere (dead weight).
- A third-party server/plugin from an **unverifiable source** running with broad scope.
- Recommending tooling the project has **no use for** (padding) — as bad as a gap.

## E. Scoring rubric (per dimension, 0–5; mark N/A where a category doesn't apply to
this project)

1. **Relevant-category coverage** — the capabilities this project's workflow needs are
   actually wired up (§C1) — *weighted highest.*
2. **Verification tooling** — browser/UI and/or container control where the project has
   a UI or runtime to observe (§B) — N/A for a pure library/CLI.
3. **Knowledge-base / source-of-truth integration** (§B) — N/A if the repo is the only
   source of truth.
4. **Output/context-economy tooling** (§B) — value scales with session length / agent
   fan-out; N/A for short one-shot use.
5. **Scope & no-duplication** — repo-vs-user placement is sensible (§C2).
6. **Wired, not dead weight** (§C3).
7. **Trust & secrets hygiene** (§C4–C5).

For every dimension under 3 (and not N/A), the report gives a concrete recommendation
— which tool, which scope, and a one-line "why it pays off here" — plus the
config/snippet the user could paste. The skill never writes it into the repo or the
user's settings.
