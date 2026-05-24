---
name: assign-issues-orion
description: Analyse the current repository's open issues and produce a ~2-day work plan for ONE engineer — the person running the skill — then assign the chosen issues to them. Asks for the engineer's username and how many issues they want (1–6); counts issues already assigned to them toward that target; gathers context epic-first (not by brute-forcing every open issue); and prefers a cluster of issues in a single feature slice that is isolated from what teammates are actively working on, so the work is parallelizable and collision-free. Use when the user says "/assign-issues-orion", "plan my next 2 days", "what should I work on next", "assign me N issues", or "pick my next stories".
---

# assign-issues-orion

You are a technical project manager. Analyse this repository's open issues on the project's issue host (GitHub via `gh` in the examples below — substitute your host's CLI/API if different) and produce a **~2-day work plan for one engineer: the person running this skill.** Then assign the chosen issues to them.

The window is fixed at **2 days of work.** Within that window the engineer wants a specific *number* of issues assigned. Your job is to decide whether that number is feasible, pick the best-fitting issues, and keep the engineer **in their own lane** — clustered in a single feature slice that teammates are not actively touching, so the work is parallelizable and low-collision.

There is no team roster and no cross-engineer coordination: exactly one engineer is in scope — the one whose username the user provides.

## Key variables (resolve at runtime; never hard-code identities or project names)

| Variable | Meaning | How to resolve |
|---|---|---|
| `<engineer_username>` | The one engineer in scope | Ask in Step 0. |
| `<requested_count>` | How many issues they want assigned **in total** | Ask in Step 0; clamp to 1–6. |
| `<count_mode>` | Whether `<requested_count>` is a *total* or *additional* | Default **total** (existing assignments count toward it) unless the user says "additional / on top / new". |
| `<already_assigned>` | Open issues already assigned to them | Step 1. |
| `<to_assign>` | How many new issues to add | Computed in Step 1. |
| `<work_window>` | Planning horizon | Fixed at 2 days. |

## Step 0 — Inputs (MANDATORY — ask before any analysis)

Use `AskUserQuestion` to collect:

1. **The engineer's username** on the issue host → `<engineer_username>`. This is the only identity used for the whole run. Do not ask about or plan for anyone else.
2. **How many issues** they want assigned → `<requested_count>`. **Maximum 6** — if they ask for more, clamp to 6 and tell them. If they give no number, default to a 2-day-fittable target (≈4) and say so.
3. Note whether they framed it as a *total* or as *additional* issues → `<count_mode>` (default: total).

Echo back: "Planning for **<engineer_username>** — target **<requested_count>** issue(s) (<count_mode>), 2-day window."

## Step 1 — Count what's already on their plate

The requested count is a **target**, and (unless the user said "additional") issues already assigned to them count toward it.

- List their current open, assigned issues:
  `gh issue list --assignee <engineer_username> --state open --json number,title,labels`
- `<already_assigned>` = that set.
- Compute how many new issues to add:
  - **total mode** (default): `<to_assign> = max(0, <requested_count> − count(<already_assigned>))`.
  - **additional mode**: `<to_assign> = min(<requested_count>, 6 − count(<already_assigned>))`.
- Tell the user explicitly, e.g. *"You already have 1 open issue assigned; you asked for 4 total → I'll add 3 more."*
- If `<to_assign>` is 0 (already at/over target): don't assign anything new. Summarise the existing load and offer to (a) plan around the existing issues, or (b) raise the target. Wait for their call.

## Step 2 — Gather context epic-first (be smart, not brute-force)

Do **not** just dump the first 100 open issues. Work top-down so you spend your reads where the value is:

1. **Find the epic / milestone structure.** Look for epics (an `epic`-style label, milestones, parent/tracking issues, or "Epic N / Story X.Y" naming). List the epics and, for each, its child stories.
2. **Assess each epic's completeness & momentum.** For every epic, count closed vs. open stories, note how recently work landed, and judge how much of the *remaining* work is independent (parallelizable) vs. a forced sequence. An epic that is ~half done with several independent leaf stories is high-value; a barely-started epic full of chained stories is not.
3. **Build the "occupied lanes" set — what teammates are actively touching.** Assignee alone is a weak signal; combine several, strongest first:
   - **Open PRs and their changed files** — the most precise signal of what someone is editing right now: `gh pr list --state open --json number,headRefName,files,author`. Drafts count (they get finished).
   - **Unmerged remote feature branches** — work that has a branch but no PR yet: list them (`git ls-remote --heads origin` / your branch convention) and diff each against the default branch for changed files (`git diff origin/<default_branch>...origin/<branch> --name-only`). An **empty** branch is not a claim — ignore it.
   - **Open issues assigned to anyone other than `<engineer_username>`**, and any issue carrying an **in-progress label** (e.g. `wip`) regardless of assignee.
   Union these into a set of **claimed paths / areas**. Any candidate whose likely footprint intersects this set is an occupied lane the engineer should avoid — don't race teammates.
4. **Understand the code's slices.** Read the README/docs/architecture and the directory tree to identify isolated modules / feature slices and the high-risk shared files. Map epics → code areas.
5. **Pick the target lane.** Choose the epic/slice that maximises **value × isolation × parallelizability**: meaningful remaining work, few or no other active assignees, footprint disjoint from the claimed-paths set, and several independent leaf stories in the same area. Same-slice issues parallelize well and minimise context-switching.

Only after this top-down pass do you pull the full bodies of the specific candidate issues you actually care about (`gh issue view <n> --json body,comments` for deps/detail).

### Footprint estimation — predicting which files a candidate touches

To judge isolation/disjointness, estimate each candidate's file footprint (heuristic — say so when unsure):
- **Area labels → code paths.** If the project uses `area:*`-style labels, map each to its directory globs (derive the mapping from *this* repo's layout — do not assume another project's paths). Two candidates with disjoint area labels are almost certainly safe.
- **Body / linked spec.** Scan the issue body and any linked epic/story spec for explicit file paths, entity names (→ their model/migration files), endpoint names (→ their handler files), and test names. These pin the footprint concretely.
When you can't be sure two footprints are disjoint, **flag it** rather than claiming certainty.

## Step 3 — Dependency & feasibility check

For each candidate in the target lane:

- **Dependencies.** Extract upstream deps from the body and host metadata — "depends on / blocked by / requires / after #N", native blocking links, referenced PRs that must merge first, epic ordering (Story 2.5 implicitly follows 2.4), and dependency-implying labels (adapt the names to your project, e.g. `blocked`, `needs-design`, `needs-spec`, `needs-decision`).
  - **A dependency is only satisfied if it is truly done — closed AND merged AND landed.** Do not treat a merely-`closed` issue as done (it may have been closed manually, by a draft, or "won't do"). Verify the chain:
    1. `gh issue view <dep> --json state,closedByPullRequestsReferences` → state is `CLOSED` and capture the closing PR(s).
    2. `gh pr view <pr> --json state,mergeCommit` → `state == "MERGED"`, grab `mergeCommit.oid`.
    3. `git merge-base --is-ancestor <merge-sha> origin/<default_branch>` → the merge is actually reachable from the default branch HEAD.
    Cache these lookups within the run. If any step fails, the upstream is **not** satisfied.
  - Never pick an issue with an unsatisfied upstream dep. If the blocker is itself unassigned (or assigned to `<engineer_username>`), **promote the blocker** into the candidate pool instead and record a "Substitution". Walk the chain (if #2 depends on #1, promote #1).
- **Size.** Estimate S = ½ day, M = 1 day, L = 2 days.
- **Feasibility vs. the 2-day window.** The window caps total work at 2 days. If `<to_assign>` issues of realistic size won't fit, the count is **not feasible** — surface this, propose the number that *does* fit, and let the user confirm before assigning.
- **Isolation.** Drop candidates in a lane another active assignee occupies (collision risk) unless the user accepts it; note these in Problems Found.

## Step 4 — Select the issues

- Pick up to `<to_assign>` issues so the engineer's **total** assigned reaches `<requested_count>` (capped at 6, capped by the 2-day budget).
- **Cluster in one slice/feature/epic** wherever possible — same-lane work is more parallelizable, lower-collision, and lower context-switch.
- Every picked issue must be independently shippable; no dependency chain *within* the picked set.
- If fewer suitable issues exist than requested, pick fewer and record **under-allocation** with the reason. Never oversize, and never pick blocked or occupied work just to hit the number.

## Step 5 — Output the plan

Print, in this order:

1. **Problems Found** (only if non-empty — show FIRST):
   - **Dependency substitutions** — `Chose #<root> instead of #<downstream> because #<root> is its open blocker.`
   - **Dependency chains** found in the graph; **cycles / contradictions** in the metadata.
   - **Feasibility shortfalls** — requested N but only M fit the 2-day window.
   - **Collision risks** — lane shared with `<other_assignee>`.
   - **Under-allocation** — picked fewer than asked, with the reason.
   - **Suspected-but-unverified dependencies** — ambiguous text where you made a conservative call.
2. **Already assigned** (counted toward `<requested_count>`): the `<already_assigned>` list.
3. **Allocation table** for the new picks:

   | Issue # | Title | Size | Epic / Slice | Why workable now | Isolation |
   |---------|-------|------|--------------|------------------|-----------|

   "Why workable now" = no open upstream deps, isolated module/files, no coordination needed. "Isolation" = no other active assignee in this lane (or the risk if there is one).
4. **Per picked issue**: expected touched directories / files, key implementation notes, risks to avoid, validation / testing expectations.
5. **Excluded** candidates with reasons: upstream dep open · assigned to another engineer · teammate active in this lane · too large for the window · unclear scope · shared-infra / cross-cutting · high merge-conflict risk.

## Step 6 — Assign (autonomous, new issues only)

After the plan is printed and any feasibility / collision trade-off is confirmed:

1. Assign **only the newly-picked** issues (never re-assign the ones already on their plate):
   `gh issue edit <number> --add-assignee <engineer_username>`
2. Confirm each assignment; if the host returns an error for any issue, list the failures at the end.

Produce **no** artifact files (no HTML report, no Gantt chart). The deliverables are the printed plan and the host assignments. When uncertain whether an issue is workable or whether a dependency exists, treat it as **not** workable and record it in Problems Found / Excluded — never guess.

## Edge cases

- **`gh` (or your host CLI) not authenticated** → say so and abort; nothing to plan without issue access.
- **A claimed remote branch exists but its diff is empty** (someone just created it) → the branch alone is not a claim; ignore it unless the issue is also assigned / in-progress-labeled.
- **A predecessor was squashed or force-pushed** so the merge SHA isn't an ancestor of the default branch → treat the dependency as **unverifiable**, exclude the candidate, and flag it rather than assuming done.
- **A dependency reference points to a non-existent / deleted issue number** → soft warning in Problems Found, not a hard block.
- **No epic/milestone structure exists at all** → fall back to flat issue analysis, but say the epic-aware ranking is degraded.
- **Every ready candidate sits in an already-occupied lane** → there may be no collision-free pick; tell the user plainly instead of racing a teammate, and offer to either accept the collision or lower the count.
- **Issue host is not GitHub** → the logic is identical; substitute the equivalent CLI/API calls for listing issues/PRs/branches and assigning.
