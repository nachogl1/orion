---
name: assign-gh-issue-orion
description: Analyse the current repository's open issues and produce a work plan of N issues — the number the engineer asks for, or 2 by default — for ONE engineer, the person running the skill, then assign the chosen issues to them. Every picked issue must be AGENT-READY: an autonomous coding agent can take it and ship it without a human decision mid-flight. When a promising issue needs a human decision (ambiguous scope, open design/product question, missing spec), the skill HALTS and asks the user to resolve it, records the answer on the issue, and only then treats it as eligible — otherwise it is excluded. Asks for the engineer's username and how many issues they want (default 2); counts issues already assigned to them toward that target; gathers context epic-first (not by brute-forcing every open issue); and prefers a cluster of issues in a single feature slice that is isolated from what teammates are actively working on, so the work is parallelizable and collision-free. Use when the user says "/assign-gh-issue-orion", "what should I work on next", "assign me N issues", or "pick my next stories".
---

# assign-gh-issue-orion

> [!NOTE]
> **Editing convention:** this skill has **no `-vN` version suffix** and is **edited in place** (per the repo's CLAUDE.md, only the `sequential-bmad-github-orion-vN` skills use the new-version convention). Make changes directly here.

You are a technical project manager. Analyse this repository's open issues on the project's issue host (GitHub via `gh` in the examples below — substitute your host's CLI/API if different) and produce a work plan for one engineer: **the person running this skill.** Then assign the chosen issues to them.

The plan is driven by a **count of issues**, not a time budget. The engineer says how many issues they want; if they don't, default to **2**. Your job is to find that many of the *best* issues, keep the engineer **in their own lane** (clustered in a single feature slice teammates aren't actively touching, so the work is parallelizable and low-collision), and — critically — make sure every issue you pick is **agent-ready**.

**Agent-ready is the headline requirement.** The issues you assign are expected to be executed autonomously by a coding agent (e.g. an orion sequential pipeline). So an issue only qualifies if an agent could pick it up and ship it **without a human making a decision partway through**. If a promising issue carries an open human decision, you do not silently drop it and you do not guess the answer — you **stop and ask the user** to resolve it, write the resolution onto the issue so the downstream agent has it, and only then count it as eligible (Step 3a).

There is no team roster and no cross-engineer coordination: exactly one engineer is in scope — the one whose username the user provides.

## Key variables (resolve at runtime; never hard-code identities or project names)

| Variable | Meaning | How to resolve |
|---|---|---|
| `<engineer_username>` | The one engineer in scope | Ask in Step 0. |
| `<requested_count>` | How many issues they want assigned **in total** | Ask in Step 0; **default 2** if unspecified; clamp to a 1–6 sanity range. |
| `<count_mode>` | Whether `<requested_count>` is a *total* or *additional* | Default **total** (existing assignments count toward it) unless the user says "additional / on top / new". |
| `<already_assigned>` | Open issues already assigned to them | Step 1. |
| `<to_assign>` | How many new issues to add | Computed in Step 1. |

## Step 0 — Inputs (MANDATORY — ask before any analysis)

Use `AskUserQuestion` to collect:

1. **The engineer's username** on the issue host → `<engineer_username>`. This is the only identity used for the whole run. Do not ask about or plan for anyone else.
2. **How many issues** they want assigned → `<requested_count>`. **If they give no number, default to 2** and say so. As a sanity guard, clamp to **1–6**; if they ask for more, clamp and tell them (the limit is a sanity guard on one batch, not a time budget).
3. Note whether they framed it as a *total* or as *additional* issues → `<count_mode>` (default: total).

Echo back: "Planning for **<engineer_username>** — target **<requested_count>** agent-ready issue(s) (<count_mode>)."

## Step 1 — Count what's already on their plate

The requested count is a **target**, and (unless the user said "additional") issues already assigned to them count toward it.

- List their current open, assigned issues:
  `gh issue list --assignee <engineer_username> --state open --json number,title,labels`
- `<already_assigned>` = that set.
- Compute how many new issues to add:
  - **total mode** (default): `<to_assign> = max(0, <requested_count> − count(<already_assigned>))`.
  - **additional mode**: `<to_assign> = min(<requested_count>, 6 − count(<already_assigned>))`.
- Tell the user explicitly, e.g. *"You already have 1 open issue assigned; you asked for 2 total → I'll add 1 more."*
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
5. **Pick the target lane.** Choose the epic/slice that maximises **value × isolation × parallelizability × agent-readiness**: meaningful remaining work, few or no other active assignees, footprint disjoint from the claimed-paths set, several independent leaf stories in the same area, and stories whose scope is concrete enough for an agent to execute unattended. Same-slice issues parallelize well and minimise context-switching.

Only after this top-down pass do you pull the full bodies of the specific candidate issues you actually care about (`gh issue view <n> --json body,comments` for deps/detail/decision points).

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
  - **Never pick an issue whose hard dependency is unsatisfied.** How you treat the blocker depends on who owns it — cross-reference it against the occupied-lanes set from Step 2:
    - **Blocker is free** (open, unassigned, no in-flight PR/branch) and itself workable → **promote it** into the candidate pool in place of the downstream issue, record a "Substitution", and walk the chain (if #2 depends on #1, promote #1). The promoted blocker must itself pass the agent-readiness gate.
    - **Blocker is owned or in-flight by someone else** (assigned to another person, has an open PR, or sits in an occupied lane) → do **not** promote it (you can't take their work) and do **not** pick the downstream issue. This is the worst case: the issue cannot start until another person finishes, on a timeline you don't control. Exclude it and raise it in Problems Found as a **hard cross-person dependency**.
    - **Blocker is yours** (assigned to `<engineer_username>` but not done) → the downstream isn't ready yet; prefer scheduling the blocker itself first if it is agent-ready.
  - Distinguish **hard** dependencies (the issue genuinely cannot proceed — code/data/contract it builds on) from **soft** ones (related but not strictly required). Hard + unsatisfied → exclude. Soft + unsatisfied → allow but flag the risk.
- **Size (informational, not a cap).** Estimate rough effort (S / M / L) so the engineer knows what they're taking on and so you can order picks — but there is **no time budget**: size never disqualifies an issue on its own. Feasibility is about *availability of enough agent-ready, unblocked, isolated issues*, not about fitting hours into a window.
- **Feasibility.** If fewer than `<to_assign>` issues clear the agent-readiness gate and the dependency/isolation checks, the count isn't fully feasible — surface it, assign the ones that do qualify, and record the shortfall as under-allocation (Step 4 / Step 5).
- **Isolation.** Drop candidates in a lane another active assignee occupies (collision risk) unless the user accepts it; note these in Problems Found.

## Step 3a — Agent-readiness gate (REQUIRED for every pick)

An issue is **agent-ready** only if an autonomous coding agent could take it and ship a mergeable result **without a human deciding anything partway through**. Check each candidate against all of:

- **Concrete, bounded scope.** It's clear *what* to build and *when it's done* — explicit acceptance criteria, or criteria an agent can confidently infer. Not a vague "improve X" or "investigate Y".
- **No open human decision.** No unresolved product/UX/design/architecture question; no "should we do A or B?" left hanging in the body or comments; no decision-implying labels (`needs-design`, `needs-decision`, `needs-spec`, `discussion`, `question`, `RFC`, or your project's equivalents).
- **All inputs present.** Any referenced spec, asset, API contract, schema, or copy/text the work needs is actually available (linked and reachable) — not "TBD", not "waiting on design", not an empty placeholder.
- **Verifiable.** There's a way for the agent to confirm done — tests it can run, acceptance criteria it can check, or a clear behavioural outcome.
- **No human-only step.** It doesn't require credentials the agent lacks, a manual approval, an external account, a deploy only a human can trigger, or a conversation with a third party.
- **Dependencies satisfied** (per Step 3).

**When a candidate fails only because of an open human decision or ambiguity** — but is otherwise valuable and isolated — do **not** silently exclude it and do **not** invent the answer. Instead:

1. **HALT and ask the user.** Use `AskUserQuestion` to put the specific decision(s) to them, plainly, with options and a recommendation (treat them as the decision-maker, not as someone who already knows the internals). Ask only the questions an agent would otherwise get stuck on. Batch a candidate's decisions together.
2. **Record the resolution on the issue** so the downstream agent actually has it: post the decision as a comment (`gh issue comment <n> --body "..."`), or, if it belongs in the spec, edit the body (`gh issue edit <n> --body ...`). Make the comment self-contained ("Scope decision for the implementing agent: …") so the agent doesn't need this conversation. Removing a now-stale `needs-decision`-style label is appropriate too (`gh issue edit <n> --remove-label <label>`).
3. **Only after the decision is recorded** does the issue count as agent-ready and become eligible to pick.

If the user can't or won't resolve a decision, the issue stays **not** agent-ready → exclude it and record it under Problems Found as "needs human decision (unresolved)". Never assign an issue that still hides an open decision — that just hands the agent a task it can't finish autonomously.

## Step 4 — Select the issues

- Pick up to `<to_assign>` issues so the engineer's **total** assigned reaches `<requested_count>` (capped at the 1–6 sanity range).
- **Every pick must be agent-ready** (Step 3a) — no exceptions. An issue made ready by a recorded user decision qualifies; one with an unresolved decision does not.
- **Cluster in one slice/feature/epic** wherever possible — same-lane work is more parallelizable, lower-collision, and lower context-switch.
- Every picked issue must be independently shippable; no dependency chain *within* the picked set.
- If fewer suitable issues exist than requested, pick fewer and record **under-allocation** with the reason. Never pad the count with ambiguous, blocked, or occupied work just to hit the number.

## Step 5 — Output the plan

Print, in this order:

1. **Problems Found** (only if non-empty — show FIRST):
   - **Resolved decisions** — issues that needed a human call, the question you asked, the answer chosen, and where you recorded it (`commented on #<n>` / `edited #<n> body`).
   - **Dependency substitutions** — `Chose #<root> instead of #<downstream> because #<root> is its open blocker.`
   - **Dependency chains** found in the graph; **cycles / contradictions** in the metadata.
   - **Not-agent-ready (unresolved)** — candidates excluded because an open human decision / missing input couldn't be resolved this run. Name the issue and the specific blocker.
   - **Feasibility shortfalls** — requested N but only M agent-ready, unblocked, isolated issues exist.
   - **Collision risks** — lane shared with `<other_assignee>`.
   - **Hard cross-person dependencies** — a candidate's hard dependency is unfinished and owned/in-flight by someone else; it can't start until they're done. Name the dependency, its owner, and the downstream issue.
   - **Under-allocation** — picked fewer than asked, with the reason.
   - **Suspected-but-unverified dependencies** — ambiguous text where you made a conservative call.
2. **Already assigned** (counted toward `<requested_count>`): the `<already_assigned>` list.
3. **Allocation table** for the new picks:

   | Issue # | Title | Size | Epic / Slice | Agent-ready | Why workable now | Isolation |
   |---------|-------|------|--------------|-------------|------------------|-----------|

   "Agent-ready" = ✅ ready as-is, or ✅* made ready by a recorded decision (note which). "Why workable now" = no open upstream deps, scope concrete, isolated module/files, no coordination needed. "Isolation" = no other active assignee in this lane (or the risk if there is one).
4. **Per picked issue**: expected touched directories / files, key implementation notes, any decision recorded for the agent, risks to avoid, validation / testing expectations.
5. **Excluded** candidates with reasons: not agent-ready (open decision / missing input) · upstream dep open · hard dependency owned / in-flight by another engineer · assigned to another engineer · teammate active in this lane · unclear scope · shared-infra / cross-cutting · high merge-conflict risk.

## Step 6 — Assign (autonomous, new issues only)

After the plan is printed and any feasibility / collision trade-off is confirmed:

1. Assign **only the newly-picked** issues (never re-assign the ones already on their plate):
   `gh issue edit <number> --add-assignee <engineer_username>`
2. Confirm each assignment; if the host returns an error for any issue, list the failures at the end.

Produce **no** artifact files (no HTML report, no Gantt chart). The deliverables are the printed plan, any decisions recorded onto issues, and the host assignments. When uncertain whether an issue is workable, whether a dependency exists, or whether an agent could finish it unattended, treat it as **not** workable / **not** agent-ready and record it in Problems Found / Excluded — never guess.

## Edge cases

- **`gh` (or your host CLI) not authenticated** → say so and abort; nothing to plan without issue access.
- **A claimed remote branch exists but its diff is empty** (someone just created it) → the branch alone is not a claim; ignore it unless the issue is also assigned / in-progress-labeled.
- **A predecessor was squashed or force-pushed** so the merge SHA isn't an ancestor of the default branch → treat the dependency as **unverifiable**, exclude the candidate, and flag it rather than assuming done.
- **A dependency reference points to a non-existent / deleted issue number** → soft warning in Problems Found, not a hard block.
- **No epic/milestone structure exists at all** → fall back to flat issue analysis, but say the epic-aware ranking is degraded.
- **Every ready candidate sits in an already-occupied lane** → there may be no collision-free pick; tell the user plainly instead of racing a teammate, and offer to either accept the collision or lower the count.
- **No issue clears the agent-readiness gate** (everything is vague or decision-blocked) → assign nothing, and report which decisions/inputs would unblock the best candidates so the user can resolve them and re-run.
- **The user resolves a decision but it has team-wide implications** (changes shared contracts, affects other epics) → record it, but flag in Problems Found that it may need broader sign-off before the agent runs.
- **Issue host is not GitHub** → the logic is identical; substitute the equivalent CLI/API calls for listing issues/PRs/branches, commenting, and assigning.
