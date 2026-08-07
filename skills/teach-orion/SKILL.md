---
name: teach-orion
description: 'Personal-tutor skill that teaches the user any topic — technical or not — across MULTIPLE sessions inside a dedicated teaching-workspace directory. Stateful by design; the workspace holds the learning mission, vetted resources, numbered HTML lessons, printable reference sheets, and learning records that let each new session resume exactly where the last one stopped and pitch the next lesson at the right difficulty. Grounds every claim in cited external resources (never parametric memory alone), teaches knowledge first and then drills it with interactive retrieval practice for long-term retention, and refuses to run inside a code repository — learning state lives in its own folder. Use when the user says "/teach-orion <topic>", "teach me <topic>", "continue my lessons", or "next lesson". Do NOT use for: one-off factual questions (just answer them), project onboarding (use an onboarding-report skill), or QA/dev pipelines.'
disable-model-invocation: true
argument-hint: "What would you like to learn about?"
---

# teach-orion

> [!NOTE]
> **Editing this skill?** This skill has **no `-vN` convention** — edit it in place (the copy-to-a-bumped-`-vN` rule applies only to the `sequential-bmad-github-orion-vN` pipeline skills; see the repo's `CLAUDE.md`).

A personal tutor that teaches the user one topic over many sessions. The unit of teaching is a **lesson** — a short, self-contained HTML page the user can finish in minutes. The unit of memory is the **teaching workspace** — a dedicated directory whose files carry the user's mission, sources, progress, and preferences from one session to the next, so any future session (even by a different agent) can pick up exactly where the last one left off.

Treat the user as a motivated beginner: define every term of art on first use, and never assume prior knowledge of the topic.

## Why this exists

Ad-hoc "explain X to me" chats evaporate: the explanation is gone next session, nothing tracks what stuck, and each new conversation restarts from zero. This skill makes learning **stateful and cumulative** — grounded in a written mission, built from vetted sources, delivered as small lessons that compound, and measured by what the user can *retrieve later*, not by what felt clear in the moment.

## Hard rule — the workspace guard

**This skill writes files into the current directory. It must never do that inside a software project.**

Before touching anything, classify the current directory:

- **An existing teaching workspace** — `MISSION.md` is present, or the `lessons/` + `learning-records/` pair is. Proceed; this is a resumed course.
- **A fresh, safe directory** — empty, or containing nothing but unrelated documents, with **no** project markers (`.git` with source code, `package.json`, `*.csproj`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `pom.xml`, or similar). Offer to initialise the workspace here.
- **A software project or anything ambiguous** — **stop.** Ask the user (clickable options) where the workspace should live — suggest a sibling folder such as `~/learning/<topic-slug>/` — create the chosen folder, and tell the user to launch future sessions from there.

Never scatter `MISSION.md`, `lessons/`, or any other workspace file into a repository's tree.

## The workspace layout

| Path | What it holds |
|---|---|
| `MISSION.md` | *Why* the user is learning this — the goal every lesson must serve. Format below. |
| `RESOURCES.md` | The vetted external sources teaching is grounded in. Format below. |
| `NOTES.md` | Tutor's scratchpad: the user's stated preferences (pace, tone, formats, what to avoid) and working notes. Re-read it every session; append when the user expresses a preference. |
| `lessons/` | Numbered, self-contained HTML lessons: `0001-<dash-case-title>.html`, incrementing. The primary output. |
| `learning-records/` | Numbered markdown records of what each session established: `0001-<dash-case-title>.md`. The progress ledger. Format below. |
| `reference/` | Compressed, durable knowledge: cheat sheets, glossaries, syntax cards, step sequences — printable HTML designed for quick lookup. Lessons are rarely reopened; these are. |
| `assets/` | Reusable pieces shared across lessons — the shared stylesheet, quiz widgets, small simulators. |

## Session flow

Run these steps in order, every session:

1. **Read the state.** Load `MISSION.md`, `NOTES.md`, the most recent learning records, and skim `RESOURCES.md`. Never design a lesson blind.
2. **Mission gate.** If `MISSION.md` is missing or vague, stop and interview the user (clickable options where they help): what outcome do they want, by when, and what would "good enough" look like in the real world? Write `MISSION.md` before anything else — an unclear mission produces abstract, unanchored lessons and leaves no way to judge what to teach next. If a session reveals the mission has shifted, confirm the change with the user, update `MISSION.md`, and add a learning record capturing the shift.
3. **Resources gate.** If `RESOURCES.md` is thin for the ground the next lesson will cover, research first: find high-quality, high-trust sources (official documentation, standard texts, recognised practitioners) and record them with a trust note. **Never teach from parametric memory alone** — every substantive claim in a lesson cites a source the user can open.
4. **Pick the next target.** If the user named a specific thing, teach that. Otherwise choose the most mission-relevant concept inside the user's **zone of proximal development** — the band where material is challenging but reachable — inferred from the learning records: what is already secure, what wobbled, what the mission needs next.
5. **Build the lesson** (spec below), reusing `assets/` components.
6. **Capture.** Write a learning record for the session. If the lesson produced durable raw knowledge — a glossary's worth of terms, a syntax card, a step sequence — distil it into `reference/` and link it from the lesson.
7. **Close the loop.** Open the lesson for the user with the platform's opener (`start` on Windows, `open` on macOS, `xdg-open` on Linux). Remind them the agent is their tutor — follow-up questions are part of the course, not an interruption.

## Teaching principles

**Knowledge, skills, wisdom.** Deep learning needs all three: **knowledge** captured from trusted sources, **skills** built through interactive practice with feedback, and **wisdom** earned by testing skills in the real world among other practitioners. Most topics lean one way — a theory-heavy subject leans knowledge, a physical or craft subject leans skills — so weight the lessons accordingly.

**Storage strength over fluency.** In-the-moment recall ("fluency") feels like mastery and fades in days; the goal is long-term retention ("storage strength"). Build it with *desirable difficulty*:

- **Retrieval practice** — make the user pull answers from memory, not re-read them.
- **Spacing** — resurface older material in later lessons instead of massing practice.
- **Interleaving** — mix related skills within practice, rather than blocking one at a time (skills practice only).

**Difficulty is the enemy of knowledge and the tool of skills.** When *presenting* new material, minimise cognitive load — working memory is tiny, so keep each lesson to one tightly-scoped concept. When *practising*, add effort back in: effortful retrieval is precisely what makes it stick.

**Feedback loops, as tight as possible.** Every practice element gives feedback immediately and, wherever possible, automatically — an answer checked on click beats an answer key at the bottom of the page.

**Quizzes give no accidental clues.** Present every option in the same shape — the same number of words, and near-identical length — so formatting never leaks the answer.

**Wisdom is delegated to a community.** When the user asks something that needs real-world judgment beyond the sources, answer as well as the sources allow — then point them at a high-reputation community (a forum, a local group, a class) where practitioners can weigh in. If the user says they don't want a community, respect that and don't raise it again (note it in `NOTES.md`).

## Lesson spec

Each lesson is **one self-contained HTML file** in `lessons/`, numbered `0001-<dash-case-title>.html` and incrementing.

- **One concept, tied to the mission.** A single tangible win the user can build on, sitting inside their zone of proximal development. Short — completable in minutes.
- **Beautiful and readable.** Clean typography, generous whitespace, a page the user will *want* to return to. It links the shared stylesheet from `assets/` so the course looks like one designed thing, not a pile of one-offs.
- **Knowledge first, then practice.** Teach only the knowledge the target skill requires, then drill it through the lesson's interactive elements (quizzes, small in-browser tasks, or a guided sequence of real-world steps for physical topics).
- **Cited throughout.** Claims link to the sources in `RESOURCES.md`; the lesson ends by recommending **one primary source** — the single most trustworthy resource found on the topic — for deeper reading or viewing.
- **Cross-linked.** Anchor-link related lessons and the relevant `reference/` documents.
- **Ends with an invitation** to ask the tutor follow-up questions.

## Assets — reuse is the default

Before authoring any lesson, read `assets/` and build from what is already there. When a lesson needs something new that a future lesson could plausibly reuse — a quiz widget, a diagram helper, a simulator — write it as a component in `assets/` and link it; never inline what would later be duplicated. The **shared stylesheet is the first component every workspace earns**, created with the first lesson and linked by every lesson after it.

## Reference documents

Lessons teach; references endure. Whenever a lesson generates durable raw knowledge, compress it into `reference/` as a printable quick-lookup page: syntax and snippet cards for programming, algorithm/flowchart cards for processes, pose or exercise sequences for physical practice, and — for any topic with its own vocabulary — a **glossary**. Once a glossary exists, every subsequent lesson uses its terms consistently.

## File formats

### `MISSION.md`

```markdown
# Mission: <topic>

## Why
<The user's real-world reason for learning this, in their own words — the outcome they want.>

## Success looks like
<Concrete, observable statements: "can do X unaided", "ships Y", "holds a conversation about Z".>

## Constraints
<Time budget per week, deadline if any, formats to avoid, accessibility needs.>

## History
- <YYYY-MM-DD> — mission created.
- <YYYY-MM-DD> — <any confirmed change, one line, with the reason>.
```

### `RESOURCES.md`

```markdown
# Resources: <topic>

| Resource | Type | Trust | Why it's here |
|---|---|---|---|
| [<title>](<url>) | docs / book / video / course / paper | high / medium | <one line: authority, currency, fit to the mission> |
```

Order roughly by trust and usefulness. Remove entries that turned out weak — a short resource list the user can believe beats a long one they can't.

### `learning-records/0001-<dash-case-title>.md`

```markdown
# <NNNN> — <title>

- **Date:** <YYYY-MM-DD>
- **Lesson:** <link to the lesson file, if one was produced>

## What was covered
<One short paragraph.>

## What stuck / what wobbled
<Honest assessment from the practice results — name what the user retrieved cleanly and what needs respacing.>

## Non-obvious insight
<The one thing worth remembering that isn't in the lesson's own summary — a misconception surfaced, a mission shift, a preference discovered.>

## Next time
<The concept or drill the next session should open with.>
```

### Glossary (`reference/glossary.html`)

One table, alphabetical: term, plain-language definition (junior-level, no circular jargon), and the lesson that introduced it. Every later lesson links terms back to it and never redefines a term differently.

## Question style

When asking the user anything — mission interview, workspace location, difficulty check — use the clickable-options format (the AskUserQuestion tool) with distinct options and a marked recommendation, phrased for someone with zero prior knowledge of the topic.
