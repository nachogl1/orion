---
name: clear-git-resources
description: ORION - Find the stale git resources a project collects — worktrees whose branch already landed, local branches already on main or whose remote branch is gone, remote branches whose pull request is merged or closed, dead folders and loose files in the worktree root — show them grouped in plain words with what deleting each costs, and delete exactly what the user says yes to. Never touches main, the audit branches, an open pull request, anything in flight, or work that is not on main without the user's word. Use when the user types /clear-git-resources, says "clean up my branches / worktrees / the worktree folder", or when the session-start hook reports that the project has reached its branch limit (20 by default; `branchLimit` in .claude/orion/config.json).
argument-hint: "(none) | --dry-run"
---

# /clear-git-resources

> [!NOTE]
> **Editing this skill?** Keep everything here **general**: no project, person, company or stack names. The scanner is `scripts/scan.sh` (portable bash, read-only); a change to what is found or how it is classified is a pull request on that file. The branch count it prints is the same one the session-start hook (`orion.sh check`) uses, so keep the two expressions identical.

Every skill that builds something leaves git resources behind: a worktree, a local branch, a remote branch, sometimes a
folder or a log file in the worktree root. `/dev-next` deletes its own when a story merges, but nothing cleans up after a
failed run, a human-merged pull request (`/harvest`, `/reconcile-issue-map`, `/prd-to-tickets`, `/wayfinder`), or a
person's own experiments. This skill is the sweep: it **lists** what looks stale, says **why** and **what deleting it
costs**, and deletes **only what the person says yes to**. It never decides on its own.

Read the project's `CLAUDE.md` first. It overrides this file where they disagree (the worktree root, the branch pattern,
the default branch).

## Who you are talking to

A developer who wants a tidy machine but has no time to inspect each branch. Everyday words: "a branch whose work is
already on main", not "an ancestor of origin/main"; "a folder git has forgotten about", not "a prunable worktree
entry". Name the thing (its branch name or folder) because they need it to decide, and say in one line why it is on the
list and what disappears if they say yes. Never ask twice about the same thing; never list anything that is kept
without saying it is kept.

## What counts as stale

The scanner sorts everything into three kinds. The group ids are the ones `scripts/scan.sh` prints.

| Kind | Groups | What it means | What deleting costs |
|---|---|---|---|
| **Safe** (`offer=yes`) | `wt-prunable` `wt-done` `wt-detached` `br-merged` `br-gone` `br-pr-closed` `rb-merged` `rb-pr-closed` `root-orphan` `root-file` | The work is already on the default branch, its pull request is merged or closed, its remote branch was deleted after a merge, the worktree is a clean temporary checkout, or the folder/file is not a worktree at all and is older than `--days` (default 2) | Nothing but the pointer: every commit is reachable from the default branch or was abandoned through a closed pull request |
| **Needs the person's word** (`offer=ask`) | `wt-active` `wt-dirty` `br-unmerged` `rb-unmerged` | Commits that are not on the default branch and have no pull request, or uncommitted changes in a worktree | Real work. A remote branch of this kind may be someone else's: the line says who made the last change |
| **Never offered** (`offer=no`) | `wt-open-pr` `br-open-pr` `rb-open-pr` `wt-protected` `br-protected` `rb-protected` `root-recent` `root-other` | The default branch, `audit/<login>` branches (`/dev-next` writes run reports there), the branch checked out in the main checkout, any worktree or branch of an issue-numbered entry in `<wt root>/in-flight.json`, any branch with an open pull request, folders changed in the last `--days` days, other repositories' checkouts in the shared worktree root | Listed under "kept" so the person knows they were seen; no command is ever run on them |

**A QA run's worktree is never safe.** `/harvest-qa` drives its checks in one detached, clean worktree named
`qa-<yyyymmdd-hhmmss>` in the worktree root. It has no branch and is not in `in-flight.json`, so the scanner lists it as
safe (`wt-detached`). Always move every `qa-*` worktree out of the safe groups into "needs the person's word", and say
in its line that `/harvest-qa` may be using it right now. A worktree with uncommitted changes is likewise always "needs
the person's word", never safe.

A **squash-merged** branch is not an ancestor of the default branch, so it is recognised through its pull request
(`gh`) or through its deleted remote branch (`[gone]`). Without `gh`, the scanner says so in a `NOTE` line and such a
branch lands in the "needs your word" kind instead of the safe one — it is never offered as safe on a guess.

## Steps

### 0 · Preflight

1. `git` on the path, and the current folder inside a git repository. Missing → stop and say what is missing.
2. Read the project's `CLAUDE.md`: the **worktree root** (the folder its worktree rules name; default `C:\wt` on
   Windows, `~/wt` elsewhere) and the branch pattern. Read the branch limit from `.claude/orion/config.json`
   (`branchLimit`, default 20) if that file exists.
3. `gh auth status` — optional. Missing or signed out → carry on; the scan will say that pull request states are unknown.
4. **Never work in the main checkout's files.** The skill runs `git -C <main checkout>` for ref operations only: it
   never checks out, switches, stashes, rebases, resets, force-pushes or edits a file. Deleting is the only write.

### 1 · Scan

```
bash .claude/skills/clear-git-resources/scripts/scan.sh --fetch --wt-root "<wt root>" --limit <branchLimit>
```

`--fetch` runs `git fetch --prune origin` first so remote branches deleted elsewhere drop out before anything is shown;
the `SCAN` line reports how many were pruned. With `--dry-run` as the skill's argument, run the scan without `--fetch`
and stop after step 2. The output is one record per line, tab-separated (`SCAN`, `COUNT`, `GROUP`, `ITEM`, `NOTE`,
`SUMMARY`; the header of `scan.sh` documents each). The `COUNT` line is the hook's count: local branches plus
remote-tracking branches, `HEAD` excluded.

### 2 · Show the list

One message, grouped as the scanner groups it, in this order: safe groups, then groups that need the person's word,
then one line per kept group (count only, no items). For each group: its title, then one line per item —
**the name, why it is here, and what goes away if deleted** — straight from the `ITEM` record, reworded into plain
language where the record is terse. Then the `NOTE` lines in plain words (pull request states unknown; issues in
flight; remote refs pruned by the fetch). End with the `COUNT` line as one sentence: how many branches the project has
and whether that is at or over the limit.

Nothing to offer and nothing to ask → say so in one line, with the count, and stop.

### 3 · Ask

Use the AskUserQuestion tool. **One question per group** that has items, safe groups first, each with the options
*Delete all <n>* (marked recommended for safe groups only), *Pick which to keep* and *Keep all* (marked recommended for
groups that need the person's word). *Pick which to keep* → the person types the names to keep in the free-text answer;
everything else in that group is deleted. Up to four questions per call; more groups → more calls. Never fold two
groups into one question, and never ask about a kept group.

A question gets a short plain answer — open the branch's log or the folder to back it — and the asking carries on where
it stopped. A decision changed before step 4 replaces the earlier one.

### 4 · Delete what was agreed

Run **exactly the command the `ITEM` record carries**, nothing else, in this order: worktrees (`wt-*`), then local
branches (`br-*`), then remote branches (`rb-*`), then the worktree root (`root-*`). Worktrees first because a branch
checked out in a worktree cannot be deleted before the worktree is gone; the `wt-*` commands already chain the
`branch -D` for that reason.

- A `worktree remove` that is refused with "contains modified or untracked files" on a **safe** item: run
  `git -C <worktree> status --porcelain`. **Empty** → the only files are gitignored (a local environment, build
  output); `worktree remove --force` is expected and fine. **Not empty** → the scanner's picture was stale; report the
  worktree as kept and move on. Never force a worktree the person did not approve as dirty.
- "not a working tree", "branch not found", "remote ref does not exist" → already gone; count it as done.
- Any other error → report it with the exact message, skip the item, carry on. Two items failing with the same error →
  stop deleting, report, and let the person decide; do not retry the same command.
- A `push --delete` is **the only command that touches the remote**; it is run only for `rb-*` items the person agreed to.

### 5 · Report

Run the scan again (no `--fetch`) and say, in one message: what was deleted (count per kind: worktrees, local
branches, remote branches, folders, files), what was refused and why, what was kept on the person's word, and the new
branch count against the limit. Still at or over the limit → one line saying the session-start hook will offer the
sweep again tomorrow unless `branchLimit` in `.claude/orion/config.json` is raised or set to `off`.

## Rules

- **The person's yes is the only trigger for a delete.** No default yes, no "I assumed you would want", no batch
  larger than what was agreed. `--dry-run` deletes nothing at all.
- **Never the default branch, never `audit/<login>`, never an open pull request, never anything in `in-flight.json`,
  never the branch the main checkout is on.** The scanner never prints a command for them; do not write one.
- **Never force-push, never stash, never switch branches, never reset, never rebase, never `--force` a worktree the
  person did not approve as dirty.** A worktree with real uncommitted changes is work in progress until the person
  says otherwise.
- **Other repositories' checkouts in the shared worktree root are not yours.** They are listed as kept and left alone,
  whatever their age.
- **Say what was kept.** Every item the scanner saw is either deleted, refused with its error, or listed as kept with
  the reason. Nothing disappears from the report.
- **No clever commands.** The command in the `ITEM` record, verbatim; one item at a time; output read before the next.

## The session-start hook

`orion.sh check` (the one `SessionStart` hook orion installs) counts the project's branches once a day — local plus
remote-tracking, `HEAD` excluded, no network — and when the count is at or above `branchLimit` (default 20; a number or
`off` in `.claude/orion/config.json`) it asks Claude Code to offer this skill before anything else. Saying "Not now"
ends it for the session; the next day asks again while the count stays at or above the limit. The hook only counts when
this skill is installed in the project; uninstalling the skill silences it.
