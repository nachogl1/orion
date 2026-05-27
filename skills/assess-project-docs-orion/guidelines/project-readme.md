# Orion guidelines — `README.md`

The orion layer for assessing a repository's README (root `README.md`, and any
per-package READMEs in a monorepo). Pair with the consensus baseline in
[`consensus-resources.md`](consensus-resources.md) (section 2).

> File named `project-readme.md` (not `readme.md`) on purpose: this corpus's own
> index is `README.md`, and on case-insensitive filesystems (Windows/macOS) the two
> would collide.

The README is the project's **handshake** and its **map**: a newcomer should learn
what the project is, why it exists, how to run it, and where to go next — fast.

---

## A. Consensus baseline

- Answers **what / why / who-for / how** in the first screenful.
- A working **quick start**: prerequisites → install → run → first successful result.
- **Copy-pasteable** usage examples, not just prose.
- Scannable structure (headers, lists, short paragraphs); no walls of text.
- Honest **status signals** (CI/build, version, license) where they apply.
- Links out to deeper docs instead of inlining everything.

## B. Orion layer

### B1. Onboarding tone
- Written for a reader **new to the stack and the domain** — the same plain-language,
  business-first posture the CLAUDE.md asks the agent to use (see
  [`claude-md.md`](claude-md.md) §B4). Gloss jargon on first use; don't assume the
  reader knows the toolchain.

### B2. Reference, don't duplicate
- The README and the CLAUDE.md / architecture doc should **not** restate each other.
  The README orients humans; CLAUDE.md instructs the agent; architecture docs hold
  the depth. Each should **link** the others. Flag large copy-paste overlap.

### B3. Runnable & current
- The quick-start commands should **actually match** the repo's manifests
  (`package.json` scripts, `*.sln`/`Makefile`/`pyproject.toml`/…). Flag drift between
  documented commands and what the project actually exposes.
- Prerequisites (runtimes, services, env vars) are listed *before* the run step.

### B4. Map to the rest of the docs
- A short "where things live / where to go next" section linking CONTRIBUTING,
  architecture/ADRs, the changelog, and (for this kind of repo) the agent
  instruction file.

### B5. Status honesty
- If the README advertises status/coverage/feature claims, they must be **true and
  maintained**, not aspirational. An out-of-date status badge is worse than none.

### B6. Safety & licensing surfaced
- License stated; any "use at your own risk", security-contact, or
  data-handling caveats surfaced near the top if the project warrants them.

---

## C. Smells to flag

- No quick start, or a quick start that can't possibly work (missing prereqs, stale
  commands).
- "TODO" / placeholder / default-generator boilerplate left in.
- A wall-of-text intro with no headers; burying the "what is this" below the fold.
- Duplicates CLAUDE.md / architecture content instead of linking.
- Stale badges, broken links, screenshots that no longer match the app.
- Internal-only links or identifiers leaked into a public README.

## D. Scoring rubric (per dimension, 0–5)

Same 0–5 scale as the CLAUDE.md rubric.

1. **Orientation** — what/why/who-for clear in the first screenful (§A).
2. **Quick start works** — prereqs → install → run, matching real manifests (§A, §B3).
3. **Usage examples** — concrete and copy-pasteable (§A).
4. **Structure & scannability** (§A).
5. **Onboarding tone** for newcomers (§B1).
6. **Reference-not-duplicate** discipline with the other docs (§B2, §B4).
7. **Status honesty & links current** (§B5, and broken-link check).
8. **License / safety surfaced** (§B6).

For every dimension under 3, give a concrete fix and, where useful, a suggested
snippet (e.g. a corrected quick-start block).
