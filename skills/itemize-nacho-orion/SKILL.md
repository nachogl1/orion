---
name: itemize-nacho-orion
description: Walk through a user-supplied list of items, concerns, questions, or decisions ONE AT A TIME. For each item, treat the user as a junior developer with zero domain or tech-stack knowledge — restate the item plainly, present options/alternatives, give an explicit recommendation, then wait for the user's pick before moving to the next. If the choice requires action, take it. If not, just record the decision and continue. Use when the user says "/itemize-nacho-orion", "let's go through these one by one", "walk me through this list", or pastes a list of items to discuss.
---

# itemize-nacho-orion

A guided walk-through for a list of items the user wants to discuss or decide on. Each item is its own micro-session: explained at junior-dev level, options laid out, recommendation given, decision recorded, action taken if needed. Then move on.

## Why this exists

The user often has a list of mixed-bag items — concerns, design questions, code-review nits, configuration choices, refactor candidates, open questions about an approach. Forcing them into a single "what would you like first?" response wastes the energy. This skill takes the whole list as input, walks one item at a time, presents options + a recommendation, and only moves on when the user signals done with that item.

## Input

The list comes from the user, in one of these forms:

1. **As args to the slash command:**
   ```
   /itemize-nacho-orion
   - Should we use TanStack Query or SWR?
   - Why is the SignalR connection dropping after 30 min?
   - I don't understand how the audit interceptor works
   - Migration from npm to bun: worth it?
   ```

2. **Plain text after `/itemize-nacho-orion`** with no leading dashes — numbered list, paragraph with line-break-separated items, or just multi-line text:
   ```
   /itemize-nacho-orion
   1. EF Core migration timing
   2. Keycloak realm naming
   3. Whether to drop hangfire for native BackgroundService
   ```

3. **No args** — agent asks: *"What items would you like to walk through? Paste the list (one per line) and I'll take them one by one."*

## Parsing rules

When parsing the input into items:

- Lines starting with `-`, `*`, `•`, `1.`, `2.`, etc. → each is its own item.
- Plain multi-line text with no list markers → split on blank lines (paragraph-per-item). If there are no blank lines, split on newlines (one line per item).
- Strip leading list markers, numbers, and dots from the item text itself.
- If parsing produces just ONE item, that's fine — walk the single item using the same protocol.
- If parsing produces ZERO items, ask the user to clarify.

Echo back the parsed list before starting AND create a persistent task entry per item using `TaskCreate`. This is mandatory — see the next section.

## Persistent list (MANDATORY — use TaskCreate)

The user wants a list they can see at any time, not just in chat scroll-back. Use the `TaskCreate` tool to create ONE task per parsed item, in order. The tasks become the persistent backlog the user can refer to throughout the walkthrough — they stay visible in the UI even when chat scrolls.

Rules:

1. **Create all tasks up front, before walking any item.** Loop through parsed items and call `TaskCreate` once per item:
   - `subject`: a short imperative-form rendering of the item (max ~60 chars). E.g. user pasted "Should we use TanStack Query or SWR?" → subject `"Decide TanStack Query vs SWR"`. If the item is already a clean short statement, use it verbatim.
   - `description`: the full original item text as the user wrote it. This is the canonical record of what they meant.
   - `activeForm`: present-continuous form for the spinner (optional). E.g. `"Walking through TanStack vs SWR decision"`.

2. **Mark the current item as `in_progress`** with `TaskUpdate` right before you start sub-step A for that item. Only one task is `in_progress` at any time — never two.

3. **Mark completed** with `TaskUpdate` (`status: completed`) at sub-step G (after the user's decision is recorded and any action taken). Don't batch — update immediately so the persistent list reflects reality.

4. **Skipped items** stay `pending` until the user explicitly says "we're done, drop the skipped ones" — then mark them `deleted`. Otherwise the user can revisit skipped items later in the same session by saying "back to item N" or "let's pick up the skipped ones".

5. **If the user adds items mid-walkthrough** (sub-step G or final summary), call `TaskCreate` for each new item, appended at the end of the list.

6. **If the user says "back to item K"**, set item K's task to `in_progress` (and the current one back to `pending` if not yet decided, OR leave it `completed` if already done). Re-walk sub-steps A-E for item K, ask if they want to change the decision. Then resume forward.

7. **Final summary** (after all items): leave completed tasks visible (do not delete) so the user has the audit trail for the session.

Then echo back the parsed list in chat too — the chat echo and the task list are both useful:

```
Parsed <N> items — created persistent task list. You can see all items in
the task panel anytime; they won't scroll out of view.

  1. <subject> — <one-line description>
  2. <subject> — <one-line description>
  ...

I'll walk through them one by one. For each, I'll explain it as if you were a
junior developer new to this project, lay out the options, give my pick, and
ask you to decide. Reply "back to item N" anytime to revisit, "skip" to leave
an item pending, or "add: <new item>" to append.

Starting with item 1.
```

## The per-item protocol (junior-dev framing)

Adopt this mental model verbatim for the duration of this skill:

> "The user is a junior developer with no knowledge of this project's tech stack or domain. I will not assume any framework, naming convention, or system in our codebase is familiar to them. I will explain what I'm explaining, why it matters, what the alternatives are, and what I'd recommend — without jargon, and with one specific recommendation."

For EACH item, walk these sub-steps:

### Sub-step A — Restate

State the item as you understand it, in 1-2 sentences. If the user's phrasing was ambiguous or there are multiple valid interpretations, pick the most likely one and flag the alternative:

> "Item 3: **'I don't understand how the audit interceptor works'**.
> I'm reading this as 'walk me through what the EF Core `AuditInterceptor` does and how it's wired in,' not 'I think the audit interceptor has a bug' — let me know if it's actually the second."

### Sub-step B — Context (junior-dev brief)

Explain the context as if introducing it for the first time. Cover:

- **What is this thing?** Name + plain-English summary. ("An ORM interceptor is a hook that runs in the middle of database operations.")
- **Why does it exist in this codebase?** ("Compliance requirement — every admin-driven write must be logged to a tamper-evident table.")
- **Where does it live?** File paths so they can read the code. ("`<module>/AuditInterceptor.<ext>` is the implementation; it's registered in the DI / service-registration entry point.")
- **What you'd see when it runs.** ("Every save triggers it; rows in the `audit_log` table appear with `actor`, `entity`, `before`, `after` columns filled.")

Keep this short — 4-6 sentences. The user is junior, not slow.

### Sub-step C — Options & alternatives

Lay out 2-4 options for what could be done with this item (only if it's a decision; for "explain this to me" items, this sub-step is replaced by a deeper walk-through with code excerpts).

For each option:
- **Label** (short, like "Option A — keep current").
- **What it means** (1 line).
- **Pros** (1-3 bullets).
- **Cons** (1-3 bullets).

Example:

> Options for migrating npm → bun:
>
> - **Option A — keep npm.** Status quo, no migration cost.
>   - Pros: zero risk; CI already wired; team knows it.
>   - Cons: slow installs; package-lock.json conflicts every PR.
>
> - **Option B — switch to bun for installs only, keep npm for scripts.**
>   - Pros: fast installs; minimal config change.
>   - Cons: dual-tool confusion; bun's lockfile vs. npm's lockfile drift.
>
> - **Option C — full switch (installs + scripts + workspaces).**
>   - Pros: fastest end-to-end; single tool; matches Vite default.
>   - Cons: need to migrate CI; risk of script incompatibility on Windows; team learning curve.

### Sub-step D — Recommendation

Give ONE specific recommendation with the reason. Don't waffle. Don't hedge with "depends on your priorities." Pick one and defend it briefly.

> **My pick: Option C (full switch).** The repo already uses bun for the frontend build (`apps/web/package.json` calls `bun run dev`), so we're paying the cost of mixed tooling already. Going all-in removes that drift and unlocks bun's workspace handling for future monorepo work. The CI cost is one workflow file change.

For "explain this to me" items, the "recommendation" is replaced by a "what I'd suggest doing with this knowledge" sentence — e.g. "I'd suggest opening `AuditInterceptor.cs` alongside this explanation; it's 80 lines, you'll spot the pattern fast."

### Sub-step E — Ask the user

Ask the user to choose, in plain language, and offer the easy paths:

> Which would you like?
>   • "go with A / B / C" → I'll do that.
>   • "let me think — explain X more" → I'll go deeper on a sub-aspect.
>   • "different option — <yours>" → tell me your version and I'll critique it.
>   • "skip" → record as undecided and move on.
>   • "back" → revisit a previous item.

### Sub-step F — Act on the choice (if applicable)

If the user picked an option that requires action right now (write code, change a config, file an issue):
- Confirm what you're about to do in one line.
- Do it.
- Report the result.

If the choice is informational only ("now I understand"), just acknowledge and move on.

If the choice requires action across the whole list (e.g. the user says "you know what, let's just do all of these recommendations"), confirm before bulk-applying — `AskUserQuestion` works well here.

### Sub-step G — Record the decision

Call `TaskUpdate` on the current item's task:
- `status: completed` if the user picked an option (decided or accepted explanation).
- `status: pending` (leave as-is) if the user said "skip" — they may return.
- Optionally update `description` to append the decision: original text + `\n\nDecision: <choice + 1-line summary>`.

Print one short line in chat confirming the update:

> **Item 3 done.** Decision recorded in task list: "Audit interceptor — explanation given; user understood." Moving to item 4.

The task list panel now reflects the new state — the user can see it at a glance without scrolling the chat.

## After all items

Once the last item is done, print a consolidated summary:

```
╔══════════════════════════════════════════════════════════════════╗
║ /itemize-nacho-orion — walkthrough complete                            ║
╚══════════════════════════════════════════════════════════════════╝

Items walked: <N>
Decisions taken: <list of decided items + outcomes>
Actions executed: <list of code/config changes>
Skipped: <list of items the user skipped>
Pending follow-ups: <items where user said 'let me think']

Anything else you want to add to the list?
```

If the user says "yes, also: ..." → append to the list and continue with the same protocol.
If the user says "done" / "no" / similar → exit cleanly with "Done. Have at it."

## What this skill does NOT do

- Does NOT bundle items — strictly one at a time, with the user's pick required to advance.
- Does NOT assume tech-stack familiarity even if prior conversation suggests otherwise. Junior-dev framing is the contract.
- Does NOT write any output file (no `decisions.md`, no `notes.md`). The conversation log is the artifact; if the user wants persistence, they'll ask.
- Does NOT create GitHub issues unless the chosen option for an item explicitly says "file this as an issue" — then it uses `gh issue create` after confirming title and body with the user.
- Does NOT make recommendations without a stated reason. If you cannot justify a pick in one sentence, the options aren't actually different enough — collapse them and re-present.

## Style guardrails

- **Tone**: patient, plain, specific. No "as you know" or "obviously". The user is junior in this framing.
- **Length per item**: aim for the whole context+options+recommendation+ask block to fit in roughly 200-400 words. Longer is fine for genuinely complex items; shorter for trivial ones.
- **Code excerpts**: if explaining code, paste 5-20 relevant lines with `file_path:line_number` reference. Don't paste whole files.
- **One recommendation per item**, never multi-pick suggestions in the "my pick" line.
- **No emojis unless the user uses them first** (per project convention).

## Failure modes

- **Item is ambiguous after re-reading**: ask one clarifying question in sub-step A. Don't guess on real ambiguity.
- **No valid options exist** (e.g. user's item is unanswerable as-stated): say so plainly, suggest how to reframe.
- **User wants to discuss two items together**: politely insist on one at a time, but offer "you can pick the same option for both later — just tell me."
- **User says "back"**: jump to the requested earlier item, re-present its choice + decision, ask if they want to change it. Then return to where we were.
- **User goes off-script** (asks unrelated question mid-walk): answer the question, then ask "back to item <K>?" — don't lose place.

## Cleanup checklist

- [ ] No files written.
- [ ] No git operations performed unless a specific item's chosen action required one.
- [ ] Persistent task list created at start (one task per item).
- [ ] Task statuses kept in sync with each item's progress (`in_progress` when walking, `completed` on decision, `pending` if skipped).
- [ ] Completed tasks left visible at end — do NOT bulk-delete the list; the user wants the session record.
- [ ] Final summary printed in chat in addition to the persistent task list.
