# Consensus resources — the external benchmark layer

This file is the **first of two benchmark layers** the `assess-project-ai-infrastructure-orion`
skill scores a repository's docs against:

1. **Consensus layer (this file)** — widely-cited, vendor- or community-authoritative
   guidance on what each kind of project doc *should* contain. None of these are
   owned by the skill author; they are the "what does the field agree on" baseline.
2. **Orion layer (the sibling `*.md` guideline files)** — opinionated guidelines
   collected from real projects and generalized for reuse. The orion layer is
   stricter and more specific than consensus; it never contradicts it.

A doc is assessed against the **union** of both layers, and the HTML report keeps
the two scored separately so the reader can see "industry-baseline" vs
"orion-recommended" gaps.

## How the skill uses this list

- Treat each entry as a **source of assessment criteria**, not as something to copy
  into the target repo. Extract the *principles*; never paste a third party's prose.
- **Re-validate reachability at run time.** Links rot. Before citing a URL in a
  generated report, the skill should confirm it still resolves (a quick `WebFetch`
  / HEAD-style check). If a link is dead, cite the principle and note the source is
  currently unreachable rather than emitting a broken link.
- Prefer the **official / primary** source when one exists (the vendor's own docs,
  the spec's canonical site) over secondary commentary.

> **Verification status (as of 2026-05-27):** entries marked **✓** were fetched and
> confirmed reachable during authoring. Unmarked entries are long-standing canonical
> resources; the skill re-checks all of them at run time.

---

## 1. Agent instruction files (`CLAUDE.md`, `AGENTS.md`, `.claude/rules/`)

- **✓ How Claude remembers your project (official)** — <https://code.claude.com/docs/en/memory>
  Authoritative on file locations & load order (managed → user → project → local),
  the `@path` import syntax, `.claude/rules/` and path-scoped rules, the
  CLAUDE.md-vs-auto-memory split, and the "block-level HTML comments are stripped"
  behaviour. Headline guidance: keep a CLAUDE.md **under ~200 lines**; longer files
  consume context and *reduce* adherence.
- **✓ Claude Code best practices (official)** — <https://code.claude.com/docs/en/best-practices>
  The `/init` workflow, the "add it to memory when you'd otherwise re-explain it"
  trigger, and the general posture that instructions are *context*, not enforced
  config (use hooks for hard enforcement).
- **`/init` command** — generate or improve a starting CLAUDE.md from the codebase;
  see the official commands reference. Use it as the baseline, then refine with
  facts the agent could not discover on its own.
- **AGENTS.md interop** — if a repo already has an `AGENTS.md`, a `CLAUDE.md` that
  `@`-imports it keeps one source of truth for all agents (see the memory doc's
  AGENTS.md section). The skill should treat `AGENTS.md` as an equivalent target.

**Distilled consensus criteria for an agent instruction file:**

- Concise & signal-dense — only facts that *change* the agent's decisions; don't
  restate what the agent can read from the code.
- Direct, imperative voice ("Run `X` before committing", not "we generally try to…").
- Specific & verifiable ("2-space indent", "handlers live in `src/api/handlers/`")
  over vague ("format nicely", "keep it organized").
- Structured with headers/bullets; no contradictory rules across nested files.
- Reference the README / architecture doc instead of duplicating them.
- Right-sized and right-scoped (project vs user vs local; path-scoped rules for
  per-area instructions).

---

## 2. README

- **Make a README** — <https://www.makeareadme.com/> — the canonical "what every
  README needs and why" primer.
- **Standard Readme (spec)** — <https://github.com/RichardLitt/standard-readme> — a
  checkable section contract (Title, Background, Install, Usage, API, Contributing,
  License) for repos that want a consistent shape.
- **jehna/readme-best-practices** — <https://github.com/jehna/readme-best-practices>
  — a boilerplate template embodying the practices.
- **Awesome README** — <https://github.com/matiassingers/awesome-readme> — curated
  exemplars to benchmark tone and structure against.
- **freeCodeCamp: How to write a good README** — <https://www.freecodecamp.org/news/how-to-write-a-good-readme-file/>

**Distilled consensus criteria for a README:**

- Answers **what / why / how** in the first screenful; states who it's for.
- Quick-start: prerequisites → install → run → first successful result.
- Usage examples (copy-pasteable), not just prose.
- Structure scannable on the web: short paragraphs, headers, lists — no walls of text.
- Links out to deeper docs (architecture, contributing, license) rather than inlining
  everything.
- Status signals where relevant (build/CI, version, license) — but kept honest.

---

## 3. CONTRIBUTING & community health / governance

- **GitHub Docs: Setting guidelines for repository contributors** —
  <https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/setting-guidelines-for-repository-contributors>
- **Open Source Guides (by GitHub)** — <https://opensource.guide/> — especially
  *Starting* and *Best Practices for Maintainers*.
- **Contributor Covenant (Code of Conduct)** — <https://www.contributor-covenant.org/>
- **GitHub community-health files** — `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`,
  `SECURITY.md`, `SUPPORT.md` surface in dedicated repo tabs when present.

**Distilled consensus criteria for CONTRIBUTING / governance docs:**

- How to file a good issue and open a good PR (concrete steps, not "be helpful").
- Branch / commit / review conventions, and where CI runs and what it gates.
- How to set up the dev environment and run the tests.
- Behavioural expectations (link a code of conduct) and how decisions get made.
- Pointers to deeper docs (architecture, ADRs, runbook/troubleshooting).

---

## 4. Issue & PR templates

- **GitHub Docs: About issue and PR templates** —
  <https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/about-issue-and-pull-request-templates>
- **GitHub Docs: Creating a PR template** —
  <https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/creating-a-pull-request-template-for-your-repository>
- **GitHub Docs: Configuring issue templates / issue forms** —
  <https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/configuring-issue-templates-for-your-repository>
- **The GitHub Blog: Issue and PR templates** —
  <https://github.blog/developer-skills/github/issue-and-pull-request-templates/>

**Distilled consensus criteria for a PR template:**

- **Short.** An over-long template gets ignored; keep it to what a reviewer needs.
- A summary + a link to the issue it closes.
- A type-of-change indicator and a *concrete* test-evidence section (which tests, in
  which environment — not a bare "ran tests").
- Checklists for the things reviewers otherwise forget to check.
- Encourage screenshots / logs / links for UI or hard-to-describe changes.
- Lives in the repo root, `docs/`, or `.github/` (a `PULL_REQUEST_TEMPLATE/`
  subdirectory supports multiple templates).

**Distilled consensus criteria for an issue template:**

- **Short and per-type** — separate bug / feature / chore templates (or issue forms)
  where the tracker supports it; not one giant catch-all.
- A clear **what / why** (problem or goal), and for bugs **steps to reproduce +
  expected vs actual + environment.**
- **Acceptance criteria / definition of done** for feature work.
- Labels / type / area so the issue routes and can be filtered for triage.
- Enough structure to be actionable, little enough that people actually fill it in.

---

## 5. Cross-cutting standards (commits, changelog, versioning, decisions)

- **Conventional Commits** — <https://www.conventionalcommits.org/>
- **Keep a Changelog** — <https://keepachangelog.com/>
- **Semantic Versioning** — <https://semver.org/>
- **Architecture Decision Records (ADR)** — <https://adr.github.io/> and Michael
  Nygard's original write-up,
  <https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions>

These inform the *governance* and *PR-template* assessors (commit format checkbox,
changelog/ADR maintenance, "is there a decision log").

---

## 6. MCP servers, plugins & agent tooling

- **Model Context Protocol (spec & intro)** — <https://modelcontextprotocol.io/> — what
  an MCP server is, the client/server model, and the trust boundary (servers run with
  the client's privileges).
- **Claude Code — MCP** — <https://code.claude.com/docs/en/mcp> — configuring MCP
  servers at project (`.mcp.json`) vs user scope, and how secrets/env are passed.
- **Claude Code — plugins** — <https://code.claude.com/docs/en/plugins> — installing,
  scoping, and trusting plugins.

**Distilled consensus criteria for agent tooling:**

- Wire MCP servers at the **right scope** — project-shared in `.mcp.json`, personal at
  user scope; don't pin a personal preference into a shared repo file.
- **Trust boundary matters** — third-party servers/plugins run with the agent's
  privileges; use named/trusted sources, deliberate versions, and least scope.
- **No secrets in committed config** — credentials go in env / local (gitignored)
  settings, never a committed `.mcp.json`.
- Tooling should be **used**, not just installed — configuration nothing references is
  dead weight.

These inform the *tooling-mcps-plugins* assessor. (The specific tools an orion setup
recommends are illustrative and re-validated at run time — see
[`tooling-mcps-plugins.md`](tooling-mcps-plugins.md).)

---

## 7. Claude Code setup (settings, hooks, memory) — for the self-audit

- **Claude Code — settings** — <https://code.claude.com/docs/en/settings> — the
  `settings.json` schema, scopes (user / project / local), permissions, and env.
- **Claude Code — hooks** — <https://code.claude.com/docs/en/hooks> — hook events,
  when each fires, and that hooks run as the user (the safety + cost surface).
- **Claude Code — memory** — <https://code.claude.com/docs/en/memory> — user vs project
  `CLAUDE.md`, load order, and the keep-it-lean guidance (applies to the user file too).

**Distilled consensus criteria for a healthy setup:**

- Everything referenced **resolves and parses** — a dangling hook/skill/statusLine path
  or an unparseable `settings.json` fails silently every session.
- The user-level `CLAUDE.md` is **lean** (it loads on every prompt, every project).
- Hooks use the **right event**, exit cleanly, and don't do heavy work on a hot path.
- **No secrets** hardcoded in `settings.json` / `~/.claude.json`.
- Permissions match **real usage**; dead links and unused skills/plugins are prune
  candidates.

These inform the *claude-setup-audit* assessor (see
[`claude-setup-audit.md`](claude-setup-audit.md)).

---

## Adding to this list

When the user supplies a new authoritative source, add it under the right section
with a one-line "what to take from it" note, prefer the primary/canonical URL, and
mark it **✓** only after fetching it to confirm it resolves. Never add a resource the
skill author owns — this layer is specifically the *independent* benchmark.
