# Changelog — generate-project-writeup-orion

This skill has **no `-vN` convention** — it is edited in place. Record notable changes here.

## Initial

- New skill: generate a single polished **Microsoft Word (`.docx`) project write-up / closure
  summary report** into the user's Downloads folder
  (`~/Downloads/<repo-name>-project-writeup-<YYYY-MM-DD>.docx`).
- **Audience: leadership / commercial stakeholders** — a closure/delivery write-up that marks
  a project as done, in clear business English (not a technical successor handover — that's
  `project-handover-orion`).
- **Economics-first, transparent, and honest.** Headlines a cost comparison: a defensible
  *traditional team × duration × blended-rate* baseline vs. the **actual observed delivery**
  (FTE × calendar months), with money/time/% savings. Uses the **COCOMO II Post-Architecture
  phase distribution** (Boehm 7/17/25/22/22/7) for the time-by-phase table, and allows a full
  COCOMO II effort estimate only with the honest caveat that its constants over-estimate
  modern framework delivery. Every figure traces back to a stated, user-confirmable assumption.
- **Contributor count + FTE split are always confirmed with the user** — git author lists
  (`git shortlog -sne`) are shown as a hint, but bots, AI-agent commits, and part-timers mean
  headcount and the full-time/part-time FTE split are explicitly asked for and recorded.
- **Invents no numbers** — every scale-of-work metric (LOC split production-vs-test, commits,
  duration, modules/models/endpoints, tests, docs) is **measured from the real repo** or
  marked "not measured." Revenue is only populated from a user-supplied business case, else
  "not provided."
- Mirrors a full executive report structure: title block, table of contents, Financial
  Summary (cost + phase tables), Project Overview, Scale of Work, Technical Architecture
  (backend/frontend/infra stack tables), Architecture Patterns, Security Implementation, Core
  Features, "The Invisible Excellence" (testing/quality/design-system), Comparison with
  Traditional, Value Delivered (risk + OPEX + optional revenue), and a Documentation Inventory.
- **Bundled zero-dependency `.docx` generator** (`assets/build_docx.py`): turns a JSON data
  file into a styled Word document using **only the Python standard library** (`zipfile` +
  OOXML templating) — no `python-docx`, no `pandoc`, no Word install required. Handles the
  cover/title block, coloured table headers, zebra rows, an emphasised savings/total row, and
  a live Word table-of-contents field. Fallbacks: pandoc (Markdown→docx), then a Word-openable
  HTML as last resort.
- **Strictly read-only**: reads git + repo files, writes one `.docx` (plus a sidecar JSON it
  can clean up) to Downloads — never edits the repo, never commits.
- Stack, build/test commands, module/model/endpoint counts, and test conventions detected from
  the target repo at run time — assumes no stack.
