# Changelog — project-handover-orion

This skill has **no `-vN` convention** — it is edited in place. Record notable changes here.

## Initial

- New skill: generate a single self-contained dark-themed **HTML project-handover** document
  into the user's Downloads folder (`~/Downloads/<repo-name>-handover-<YYYY-MM-DD>.html`).
- Tuned for **offboarding**, written for a **brand-new junior developer who just joined** —
  assumes **zero tech-stack and zero domain knowledge**, plain language, every term defined on
  first use with a concrete example from the actual repo, **summarised and clear** (fast
  comprehension over exhaustiveness). Scrolling reference page with a sticky table-of-contents
  and scroll-spy (not a slide deck).
- Twelve sections: cover, TL;DR, product & domain context, architecture & mental model, repo &
  dev environment (auto-detected build/test/run), current state, **git-history footprint &
  ownership** (areas owned, open branches/PRs, WIP — the "in my head" context), prioritized
  open threads & next steps, known issues/gotchas/traps, open questions/decisions pending,
  resources & contacts, glossary.
- **General-level architecture diagrams**: §4 leads with a top-level **component / inter­connection
  diagram** (the major pieces and how they connect) and a **request/data-flow diagram** tracing one
  real user action end to end — ASCII art drawn from the actual repo, each with a legend and a
  plain-English caption.
- **Local + GitHub-if-available** data mode: uses `gh` for live issue/PR/CI data when a remote
  and authenticated `gh` are present; degrades gracefully to local-git-only and badges the mode
  on the cover.
- **Strictly read-only**: reads git + repo files + GitHub, writes one HTML file to Downloads —
  never edits the repo, never commits.
- Stack, build/test/run commands, and conventions detected from the target repo at run time —
  assumes no stack. Dark-theme palette shared with the other orion report skills.
