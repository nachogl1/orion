# GLOBAL_CLAUDE.md — personal rules orion recommends

> **Owned by orion and only offered.** `orion init` and `orion update` copy this file to
> `.claude/orion/global/GLOBAL_CLAUDE.md`; nothing imports it. Each person takes the clauses they want into their
> own user-level `CLAUDE.md` (`~/.claude/CLAUDE.md`), clause by clause and only on their word. Rules every project
> needs live in `BASE_CLAUDE.md` and are never repeated here.

**How the agent goes through these rules with the person** (these steps are not a clause and are never copied):

1. Read this file and the person's `~/.claude/CLAUDE.md`. Their accepted clauses live in one section at the end of
   that file: it starts with the line `# ORION GLOBAL — last updated <timestamp>` and ends with the line
   `<!-- /ORION GLOBAL -->`.
2. List the clauses whose date marker (the `orion:` comment at the end of each clause) is later than that timestamp;
   all of them when there is no section. A clause the section already holds with an older date is a changed clause:
   show the old and the new wording side by side and replace it in place only if the person says yes.
3. Ask about the listed clauses in batches with the AskUserQuestion tool, one clause per question, worded for
   someone who knows neither the stack nor the jargon, with the options "Accept", "Skip" and "Accept with an edit"
   (the person types the edit). Name any clash with a rule elsewhere in their file while asking.
4. Write only inside the section, creating it at the end of the file (and the file itself) when missing. Accepted
   clauses go under the same `##` headings as here and keep their date marker, edited or not, so a later change to
   one can be matched with what the person has.
5. Set the timestamp to the newest clause date in this file, not to the clock, whether the person accepted
   everything, part or nothing: a clause dated between the two would otherwise never be offered. A person who
   declines everything still gets the heading line and the end line with nothing between.
6. Show the final section and save it only on the person's yes. Never change anything outside the section, and never
   copy the person's file into the project, a commit, an issue or a report.

## Communication

- Begin every reply with the person's first name, exactly once, at the very start: a canary that shows this file loaded, and the one exception to "no preamble". Write the name into this clause when accepting it. <!-- orion:2026-10-18T02:50Z -->
- Keep replies easy to follow for someone whose focus is easily broken: the answer first, one idea per line, the current state visible, one next step, no walls of prose. <!-- orion:2026-10-18T02:50Z -->
- Put an unasked tangent in one labelled line at the very end, never in the middle of the answer. <!-- orion:2026-10-18T02:50Z -->
- Disagree explicitly before carrying out a plan you think is flawed, not after; once the person has decided, stop arguing the point. <!-- orion:2026-10-18T02:50Z -->
- Give estimates in concrete terms ("about 15 minutes", "three commands"), or say exactly what is missing to estimate; never a vague or invented one. <!-- orion:2026-10-18T02:50Z -->
- While the person is still exploring an idea outside a skill they started, discuss before doing: edit or run nothing until they say go. <!-- orion:2026-10-18T02:50Z -->
- Explain what something does for the person before how it is built. <!-- orion:2026-10-18T02:50Z -->
- Summarise routine replies and go into detail only when asked; never cut a problem, a risk or a failure to keep it short. <!-- orion:2026-10-18T02:50Z -->
- Deliver reports and long documents as files, not as walls of text in the chat, unless asked for them inline. <!-- orion:2026-10-18T02:50Z -->

## Git

- Every commit made with the assistant ends with its `Co-Authored-By` trailer. <!-- orion:2026-10-18T02:50Z -->
- After a failed commit hook, fix the cause and make a new commit; never amend the previous one. <!-- orion:2026-10-18T02:50Z -->
- Keep worktree folder names short (the issue number alone) so Windows path-length limits never bite; the branch keeps the descriptive name. <!-- orion:2026-10-18T02:50Z -->
- Before a destructive or irreversible operation that no running skill already authorises, confirm first and preview it (a dry run) before the real run. <!-- orion:2026-10-18T02:50Z -->

## Changes and code quality

- Develop test first: write a failing test, make it pass, then refactor. <!-- orion:2026-10-18T02:50Z -->
- Read a file before editing it, and prefer editing an existing file to rewriting it whole. <!-- orion:2026-10-18T02:50Z -->
- Default to object-oriented design (single responsibility, encapsulation, composition over inheritance) unless the stack's own idiom says otherwise. <!-- orion:2026-10-18T02:50Z -->
- Write clean code: names that say what they mean, small single-purpose units, no dead or commented-out code, no unexplained literal values. <!-- orion:2026-10-18T02:50Z -->
- Refactor code smells out of code you write; point out the ones you find in existing code instead of quietly extending them. <!-- orion:2026-10-18T02:50Z -->

## Effort and sub-agents

- Match the reasoning effort to the task; raise it only when genuinely stuck. <!-- orion:2026-10-18T02:50Z -->
- Run at most about four sub-agents in parallel, so rate limits never stall the work. <!-- orion:2026-10-18T02:50Z -->

## Tools

- The shell's working directory resets between calls: use absolute paths. <!-- orion:2026-10-18T02:50Z -->
- Prefer the `gh` command-line tool for GitHub issues and pull requests. <!-- orion:2026-10-18T02:50Z -->
