# Changelog — project-handover-orion

This skill has **no `-vN` convention** — it is edited in place. Record notable changes here.

## Reframe — neutral public/client handover, badged epics & stories

- **Audience widened to a broad public including clients and stakeholders** (not just a new
  joiner). Same zero-stack / zero-domain, plain-language baseline.
- **Tone made neutral and impersonal** — the document is addressed to **nobody, by nobody**.
  Removed the **offboarding / departing-engineer** framing entirely: no author identity,
  no successor name, no "areas I owned," no first-/second-person voice. Dropped the
  former **"My footprint & ownership"** section and the git-history footprint step, and
  removed the author/successor inputs.
- **No stale-prone content.** Removed open PRs, open branches, work-in-progress, stashes,
  and the "open threads / next steps / what to pick up" section — anything that flips within
  a day. The **only** status the doc now carries is a **dated epics-and-stories snapshot**.
- **No code internals.** Architecture, diagrams, glossary, and the build/run section now
  describe the system at **general product-behaviour / module / feature** level — **no class
  names, no file paths, no internal code wiring** (the code is often agent-generated, so that
  detail is neither known, stable, nor useful to the reader). Diagrams use **generic
  component/module names only**; dropped the "where files live" key-files map.
- **New heart section — Epics & Stories.** Lists **every epic and every story** with a short
  plain description and a **done/not-done badge** (green = done, red = not done; optional
  amber = in progress when the tracker distinguishes it) plus a per-epic roll-up. Status read
  from the project's actual **backlog source — BMAD story docs / GitHub Issues / Jira,
  detected at run time.**
- **Dropped** the "known issues / gotchas / traps" and "open questions / decisions pending"
  sections (code-specific and stale-prone) and the "resources & contacts" section (personal).
- Sections are now: cover, TL;DR/overview, product & domain context, architecture & mental
  model (conceptual diagrams), how it's built & run, epics & stories, glossary.

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
