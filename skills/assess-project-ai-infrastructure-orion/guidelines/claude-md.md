# Orion guidelines — `CLAUDE.md` (scope router)

A `CLAUDE.md` is judged **differently depending on where it lives**, because the two
scopes do different jobs. This file routes to the right rubric; it holds no scoring of
its own.

**Detect each file's scope from its path, then load exactly one guideline:**

| Scope | Files | Load |
|---|---|---|
| **User-level** — loaded into every session on every repo | `~/.claude/CLAUDE.md`, `~/.claude/CLAUDE.local.md`, `~/.claude/rules/*.md` | [`claude-md-user.md`](claude-md-user.md) |
| **Repo-level** — loaded only for that repo | `<repo>/CLAUDE.md`, `<repo>/.claude/CLAUDE.md`, `<repo>/CLAUDE.local.md`, `<repo>/.claude/rules/*.md`, an `AGENTS.md` imported by one of them | [`claude-md-repo.md`](claude-md-repo.md) |

Pair whichever you load with the consensus baseline in
[`consensus-resources.md`](consensus-resources.md) (section 1). A user-level file is
also covered by [`claude-setup-audit.md`](claude-setup-audit.md), which audits the whole
`~/.claude/` setup around it.

## Rules that hold at both scopes

1. **Assess every file independently, against the rubric for its own scope.** Never
   compare two `CLAUDE.md` files against each other.
2. **Never mark a rule "missing" when it correctly lives at the other scope.** The two
   rubrics are already disjoint where the scopes differ — if a criterion isn't in the
   scope's file, it isn't a gap at that scope.
   - A **user-level** file is not docked for lacking a project's stack rules,
     build/test commands, named tracker, or branch tables.
   - A **repo-level** file is not docked for lacking personal tone, a response shape, an
     AI canary, or a global default paradigm — note those as *"could hoist to user
     scope"*.
3. **Content at the wrong scope is scored down, not ignored.** One project's specifics
   in a user-level file pollute every other repo's session (a §C smell there); generic
   preferences duplicated into a repo file are a drift risk (noted, not a defect).
4. **Both rubrics score 0–5 per dimension and roll up as a weighted mean**, with
   **N/A** dropping out of numerator *and* divisor. Each file states its own weights.
5. **If both scopes are being assessed in one run, produce two separate scorecards** —
   never a blended score.

## If the scope is ambiguous

Judge by **where the file loads from**, not its contents: anything under the user's home
`~/.claude/` is user scope; anything inside the repository working tree is repo scope. A
repo-level file that is *mostly* generic preferences is still repo scope — assess it with
[`claude-md-repo.md`](claude-md-repo.md) and flag the hoist opportunity.
