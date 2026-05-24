---
name: clear-resources-orion
description: List and remove all local branches, git worktrees, and remote branches the current user created (anything that is not the default branch whose first/divergent commit is authored by `git config user.email`). Presents three lists for ONE consolidated confirmation before deleting anything. Use when the user says "/clear-resources-orion", "clean up my branches", "remove my worktrees", "tidy my git resources", or wants to clear out finished feature branches.
---

# clear-resources-orion

> [!NOTE]
> **Thinking of editing this skill?** Prefer creating a *new version* — copy it to a new skill name (e.g. bump a `-vN` suffix) — and leave this one as-is. People and automated workflows may rely on the current behaviour, so versioning beats editing in place.

Cleans up the user's own git resources after a stretch of work: local branches, git worktrees, and remote branches that they authored. Never touches the default branch. Always confirms the full list with the user before deleting anything.

Works in any git repository on any platform. Everything is derived at runtime — the default branch, the remote name, and the user's identity are all detected, never hard-coded.

## What counts as "created by me"

A branch (local or remote) is "mine" only if **I created it** — not merely if I have commits on it. Git does not store a branch creator natively, so the proxy is the **author of the first commit unique to the branch** (the commit where it diverged from the default branch):

- It is **not** the default branch (`main`, `master`, `develop`, or whatever the repo uses — detect dynamically; see Phase 1).
- The **author email of its first/divergent commit** (the oldest commit in `<default_branch>..<branch>`) matches `git config user.email`.

This is robust across machines and naming conventions (it does not rely on reflog, which is local-only and expires). It deliberately excludes:
- The default branch (never deletable).
- Branches with zero commits beyond the default branch (would be a no-op delete — skip silently).
- **Branches I did not create** — someone else authored the first/divergent commit — **even if I have since committed to them.** Pushing a fix onto a colleague's branch no longer makes it "mine".

For worktrees: any worktree whose HEAD is NOT on the default branch is in scope. The main worktree (cwd, on the default branch) is always preserved.

## Safety contract

- **Never delete the default branch.** Detected once in Phase 1 and protected everywhere.
- **Never delete a branch with unpushed commits** that aren't reachable from any remote — the user would lose work. Detect via `git log <branch> --not --remotes --format=%H`. If non-empty → exclude with a warning in the report.
- **Never delete the worktree the skill is running in** — `git worktree list --porcelain` lists the main worktree (cwd) first; preserve it.
- **One single confirmation** before any deletion, listing all three categories. No partial deletes without re-confirm.
- **Idempotent** — re-running after a successful clean produces an empty list and exits.

## Variables resolved at runtime

Resolve these first; every later command references them. Notation below uses `<var>` placeholders — substitute the detected value.

| Variable | How to resolve |
|---|---|
| `<default_branch>` | See Phase 1 step 1. |
| `<remote>` | See Phase 1 step 2 (do not assume `origin`). |
| `<my_email>` | `git config user.email`. |

## Phase 1 — Discovery

1. **Determine the default branch.** Probe in order, stop at the first that succeeds:
   - `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` (if `gh` is installed and authenticated for this repo).
   - `git symbolic-ref refs/remotes/<remote>/HEAD --short` → strip the `<remote>/` prefix.
   - Look for a conventional default among local branches in priority order: `main`, `master`, `develop`, `trunk`.
   - If none can be determined, **stop and ask the user** for the default branch name. Do not guess.
   Store as `<default_branch>`.

2. **Determine the remote.** Do not assume `origin`:
   - `git remote` → if exactly one remote, use it.
   - If multiple, prefer the one `<default_branch>`'s upstream tracks (`git rev-parse --abbrev-ref <default_branch>@{upstream}` → take the part before `/`), else prefer `origin` if present, else ask the user.
   - If there are **no** remotes, skip all remote-branch handling (Phase 1 step 7 and Phase 3 step 13) and note "no remote configured — local-only cleanup" in the report.
   Store as `<remote>`.

3. **Get my git identity:**
   - `git config user.email` → `<my_email>`.
   - If empty, stop and ask the user to set `git config --global user.email`.

4. **Fetch remote so the data is current** (skip if no remote):
   - `git fetch --all --prune` (the `--prune` removes local refs to deleted remote branches).

5. **List candidate local branches** (everything except the default branch), then classify each.

   List the refs:
   - `git for-each-ref --format='%(refname:short)' refs/heads/` and drop `<default_branch>`.
   - *PowerShell:* `git for-each-ref --format='%(refname:short)' refs/heads/ | Where-Object { $_ -ne '<default_branch>' }`
   - *bash:* `git for-each-ref --format='%(refname:short)' refs/heads/ | grep -vx '<default_branch>'`

   For each candidate, classify:
   - **Mine (I created it)** — compare the author email of the branch's **first/divergent commit** (the oldest commit unique to the branch) to `<my_email>`. Get that author email:
     - *PowerShell:* `git log <default_branch>..<branch> --reverse --format='%ae' | Select-Object -First 1`
     - *bash:* `git log <default_branch>..<branch> --reverse --format='%ae' | head -1`
     - If it equals `<my_email>` → **mine**. If it's someone else → **not mine**, even if I have later commits on the branch. If the command returns nothing (no commits beyond `<default_branch>`) → skip silently (no-op delete).
   - **Safe to delete** if `git log <branch> --not --remotes --format=%H` is empty (every commit on this branch is reachable from at least one remote ref — no local-only work to lose). If there is no remote, treat unpushed-detection as "all branches are unsafe unless the user opts in" and say so in the report.
   - Mark each branch as `(mine ✓ | mine ✗)` and `(safe ✓ | unsafe ✗)`.

6. **List candidate worktrees:**
   - `git worktree list --porcelain`
   - Parse into records: `worktree path`, `HEAD`, `branch`. Filter out the one whose `branch` is `refs/heads/<default_branch>` (the main repo cwd). The remaining worktrees are candidates. For each, also record its branch name so it can be correlated with local-branch deletion.

7. **List candidate remote branches** (skip entirely if no remote):
   - `git for-each-ref --format='%(refname:short)' refs/remotes/<remote>/` and drop `<remote>/<default_branch>` and `<remote>/HEAD`.
   - Strip the `<remote>/` prefix to get branch names. For each, check who created it — the author email of its first/divergent commit, same rule as local branches:
     - *PowerShell:* `git log <remote>/<default_branch>..<remote>/<branch> --reverse --format='%ae' | Select-Object -First 1`
     - *bash:* `git log <remote>/<default_branch>..<remote>/<branch> --reverse --format='%ae' | head -1`
     - Equals `<my_email>` → mine. Someone else → not mine, even if I have later commits on it.

## Phase 2 — Present the lists for ONE confirmation

8. Build three tables. Each row should be a single line so the user can scan quickly. Use a clear visual format.

   Print exactly (substituting the resolved variables):

   ```
   ╔══════════════════════════════════════════════════════════════════╗
   ║ /clear-resources-orion — proposed cleanup                          ║
   ╚══════════════════════════════════════════════════════════════════╝

   Identity: <my_email>
   Default branch: <default_branch> (preserved)
   Remote: <remote> (fetched + pruned)   [or: none configured]

   ── Worktrees to remove (not on <default_branch>) ──────────────────
     • <path1>            (branch: <branch1>, HEAD: <short-sha>)
     • <path2>            (branch: <branch2>, HEAD: <short-sha>)
     [or: none]

   ── Local branches to delete (yours, fully pushed) ─────────────────
     • <branch1>          (last commit: <short-sha> "<subject>")
     • <branch2>          (last commit: <short-sha> "<subject>")
     [or: none]

   ── Remote branches to delete (yours, on <remote>) ─────────────────
     • <branch1>
     • <branch2>
     [or: none]

   ── Excluded (with reason) ─────────────────────────────────────────
     • <branch>           reason: has unpushed commits (would lose work)
     • <branch>           reason: not yours (created by <other-author>; you only have later commits)
     [or: none excluded]

   ────────────────────────────────────────────────────────────────────
   Total to clean: <W worktrees, B local branches, R remote branches>
   ────────────────────────────────────────────────────────────────────
   ```

9. **Ask the user** (single Y/N — or use `AskUserQuestion` with a confirmation question):

   > "Proceed with deleting all the above? Reply 'yes' to clean, 'no' to abort, or 'edit' to drop specific entries before deleting."

   - **yes** → Phase 3.
   - **no** → stop, print "No changes made.".
   - **edit** → ask which entries to drop, remove them from the deletion set, then re-confirm with the updated list. Same Y/N gate.

10. If both lists are empty (worktrees + branches), don't prompt — print "Nothing to clean. Your local + remote git state is already tidy." and exit.

## Phase 3 — Deletion (only after explicit yes)

Delete in this order — worktrees first, because removing a worktree releases the branch it had checked out, after which the local branch is deletable.

11. **Remove worktrees:**
    - `git worktree remove --force <path>`
    - The `--force` flag is required to delete worktrees with untracked artifacts (`node_modules`, `bin/`, `obj/`, `target/`, etc.). Belt-and-suspenders: if the directory still exists after `git worktree remove --force`, fall back to a recursive force-delete of the directory, then `git worktree prune`:
      - *PowerShell:* `Remove-Item -Recurse -Force '<path>'; git worktree prune`
      - *bash:* `rm -rf '<path>' && git worktree prune`
    - For each worktree: print `✅ removed <path>` or `❌ failed <path>: <error>`.

12. **Delete local branches:**
    - `git branch -D <branch>`
    - `-D` (capital) is required because squash-merged branches don't appear as merged into the default branch. For each: print `✅ deleted local <branch>` or `❌ failed local <branch>: <error>`.

13. **Delete remote branches** (skip if no remote):
    - `git push <remote> --delete <branch>`
    - Idempotent — if the remote ref doesn't exist (already deleted via a PR merge that auto-deletes the branch), suppress the "remote ref does not exist" error. For each: print `✅ deleted remote <remote>/<branch>` or `❌ failed remote <remote>/<branch>: <error>`.

14. **Final summary:**

    ```
    Cleanup complete:
      • <N> worktrees removed
      • <M> local branches deleted
      • <K> remote branches deleted
      • <X> excluded (still present — see Excluded list above)
    ```

    If any deletions failed (filesystem locks, antivirus holding handles, branch protection on the host), list them at the bottom with a one-line diagnosis and suggest the manual command the user can run.

## What this skill does NOT do

- Does NOT delete the default branch.
- Does NOT delete branches with unpushed commits.
- Does NOT delete branches I did not create — branches whose first/divergent commit is by someone else — **even if I have later commits on them.**
- Does NOT touch tags or stashes.
- Does NOT force-push to anything.
- Does NOT close pull/merge requests (a deleted branch may have an open PR — hosts typically auto-close it; the skill does not).
- Does NOT change git config (e.g. `user.email`).
- Does NOT run if `git config user.email` is unset.

## Failure modes

- **Default branch detection fails entirely**: stop and ask the user for the default branch name. Do not guess.
- **Worktree remove blocked by a file lock** (antivirus, open editor): fall back to the recursive force-delete shown in Phase 3 step 11. If that still fails, list it in the summary with the suggested manual fix (close the editor/process, try again).
- **Remote delete blocked by branch protection**: surface the host's error to the user. Do not retry.
- **`git fetch` fails** (network down): warn the user that the remote-branch list may be stale; offer to proceed with local-only cleanup or abort.

## Cleanup checklist (this skill, every run)

- [ ] Default branch detected and preserved.
- [ ] Remote detected (or local-only mode entered when none).
- [ ] No file written into the repo to track state (this skill is stateless).
- [ ] Final summary printed regardless of partial failures.
