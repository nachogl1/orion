---
name: clear-resources-nacho-orion
description: List and remove all local branches, git worktrees, and remote branches authored by the current user (anything that is not `main` with at least one commit by `git config user.email`). Presents three lists for ONE consolidated confirmation before deleting anything. Use when the user says "/clear-resources-nacho-orion", "clean up my branches", "remove my worktrees", "tidy my git resources", or wants to clear out finished feature branches.
---

# clear-resources-nacho-orion

Cleans up the user's own git resources after a stretch of work: local branches, git worktrees, and remote branches that they authored. Never touches `main`. Always confirms the full list with the user before deleting anything.

## What counts as "authored by me"

A branch (local or remote) is "authored by me" if:
- It is **not** `main` (or `master`, or whatever the default branch is — detect dynamically).
- It has **at least one commit not on `main`** whose author email matches `git config user.email`.

This is robust across machines and naming conventions. It deliberately excludes:
- `main` / the default branch (never deletable).
- Branches with zero commits beyond `main` (would be a no-op delete — skip silently).
- Branches whose unique commits are all by other authors (someone else's work).

For worktrees: any worktree whose HEAD is NOT on `main` is in scope. The main worktree (cwd, on main) is always preserved.

## Safety contract

- **Never delete `main`.** Hard-coded.
- **Never delete a branch with unpushed commits** that aren't reachable from `origin/<branch>` — the user would lose work. Detect via `git log <branch> --not --remotes --format=%H`. If non-empty → exclude with a warning in the report.
- **Never delete the worktree the skill is running in** — `git worktree list --porcelain` lists `main` (cwd) first; preserve it.
- **One single confirmation** before any deletion, listing all three categories. No partial deletes without re-confirm.
- **Idempotent** — re-running after a successful clean produces an empty list and exits.

## Phase 1 — Discovery

1. **Determine the default branch.** Probe in order:
   - `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` (if `gh` is configured for this repo).
   - Fallback: `git symbolic-ref refs/remotes/origin/HEAD --short` → strip `origin/`.
   - Final fallback: assume `main`.
   Store as `$default_branch`.

2. **Get my git identity:**
   - `git config user.email` → `$my_email`.
   - If empty, stop and ask the user to set `git config --global user.email`.

3. **Fetch remote so the data is current:**
   - `git fetch --all --prune` (the `--prune` removes local refs to deleted remote branches).

4. **List candidate local branches** (everything except the default branch):
   ```
   git for-each-ref --format='%(refname:short)' refs/heads/ \
     | Where-Object { $_ -ne $default_branch }
   ```
   (or bash equivalent with `grep -v`).

   For each candidate, classify:
   - **Mine** if `git log $default_branch..<branch> --author="$my_email" --format=%H` returns non-empty.
   - **Safe to delete** if `git log <branch> --not --remotes --format=%H` is empty (every commit on this branch is reachable from at least one remote ref — no local-only work to lose).
   - Mark each branch as `(mine ✓ | mine ✗)` and `(safe ✓ | unsafe ✗)`.

5. **List candidate worktrees:**
   ```
   git worktree list --porcelain
   ```
   Parse into records: `worktree path`, `HEAD`, `branch`. Filter out the one whose `branch` is `refs/heads/$default_branch` (the main repo cwd). The remaining worktrees are candidates. For each, also record its branch name so we can correlate with local-branches deletion.

6. **List candidate remote branches:**
   ```
   git for-each-ref --format='%(refname:short)' refs/remotes/origin/ \
     | Where-Object { $_ -ne ('origin/' + $default_branch) -and $_ -ne 'origin/HEAD' }
   ```
   Strip the `origin/` prefix to get branch names. For each, check authorship:
   - `git log origin/$default_branch..origin/<branch> --author="$my_email" --format=%H` non-empty → mine.

## Phase 2 — Present the lists for ONE confirmation

7. Build three tables. Each row should be a single line so the user can scan quickly. Use a clear visual format.

   Print exactly:

   ```
   ╔══════════════════════════════════════════════════════════════════╗
   ║ /clear-resources-nacho-orion — proposed cleanup                        ║
   ╚══════════════════════════════════════════════════════════════════╝

   Identity: <my_email>
   Default branch: <default_branch> (preserved)
   Remote: origin (fetched + pruned)

   ── Worktrees to remove (not on <default_branch>) ──────────────────
     • <path1>            (branch: <branch1>, HEAD: <short-sha>)
     • <path2>            (branch: <branch2>, HEAD: <short-sha>)
     [or: none]

   ── Local branches to delete (yours, fully pushed) ─────────────────
     • <branch1>          (last commit: <short-sha> "<subject>")
     • <branch2>          (last commit: <short-sha> "<subject>")
     [or: none]

   ── Remote branches to delete (yours, on origin) ───────────────────
     • <branch1>
     • <branch2>
     [or: none]

   ── Excluded (with reason) ─────────────────────────────────────────
     • <branch>           reason: has unpushed commits (would lose work)
     • <branch>           reason: not yours (last 3 authors: <list>)
     • <branch>           reason: only commit by me is on main already
     [or: none excluded]

   ────────────────────────────────────────────────────────────────────
   Total to clean: <W worktrees, B local branches, R remote branches>
   ────────────────────────────────────────────────────────────────────
   ```

8. **Ask the user** (single Y/N — or use `AskUserQuestion` with a confirmation question):

   > "Proceed with deleting all the above? Reply 'yes' to clean, 'no' to abort, or 'edit' to drop specific entries before deleting."

   - **yes** → Phase 3.
   - **no** → stop, print "No changes made.".
   - **edit** → ask which entries to drop, remove them from the deletion set, then re-confirm with the updated list. Same Y/N gate.

9. If both lists are empty (worktrees + branches), don't prompt — print "Nothing to clean. Your local + remote git state is already tidy." and exit.

## Phase 3 — Deletion (only after explicit yes)

Delete in this order — worktrees first, because removing a worktree releases the branch it had checked out, after which the local branch is deletable.

10. **Remove worktrees:**
    ```powershell
    git worktree remove --force <path>
    ```
    The `--force` flag is required to delete worktrees with untracked artifacts (`node_modules`, `bin/`, `obj/`). Belt-and-suspenders: if the directory still exists after `git worktree remove --force`, fall back to:
    ```powershell
    Remove-Item -Recurse -Force <path>
    git worktree prune
    ```
    For each worktree: print `✅ removed <path>` or `❌ failed <path>: <error>`.

11. **Delete local branches:**
    ```
    git branch -D <branch>
    ```
    `-D` (capital) is required because squash-merged branches don't appear as merged into main. For each: print `✅ deleted local <branch>` or `❌ failed local <branch>: <error>`.

12. **Delete remote branches:**
    ```
    git push origin --delete <branch>
    ```
    Idempotent — if the remote ref doesn't exist (already deleted via PR merge `--delete-branch`), suppress the "remote ref does not exist" error. For each: print `✅ deleted remote origin/<branch>` or `❌ failed remote origin/<branch>: <error>`.

13. **Final summary:**

    ```
    Cleanup complete:
      • <N> worktrees removed
      • <M> local branches deleted
      • <K> remote branches deleted
      • <X> excluded (still present — see Excluded list above)
    ```

    If any deletions failed (filesystem locks, AV holding handles, GitHub branch protection), list them at the bottom with a one-line diagnosis and suggest the manual command the user can run.

## What this skill does NOT do

- Does NOT delete `main` or the repo's default branch.
- Does NOT delete branches with unpushed commits.
- Does NOT delete branches whose unique commits are all by other authors.
- Does NOT touch tags or stashes.
- Does NOT force-push to anything.
- Does NOT close PRs (a deleted branch may have an open PR — GitHub typically auto-closes it; the skill does not).
- Does NOT change git config (e.g. `user.email`).
- Does NOT run if `git config user.email` is unset.

## Failure modes

- **Default branch detection fails entirely**: fall back to `main`. If `main` doesn't exist locally, stop and ask the user for the default branch name.
- **Worktree remove blocked by file lock** (Windows AV, open editor): fall back to `Remove-Item -Recurse -Force`. If that still fails, list it in the summary with the suggested manual fix (close the editor, try again).
- **Remote delete blocked by branch protection**: surface the GitHub error to the user. Do not retry.
- **`git fetch` fails** (network down): warn the user that the remote-branch list may be stale; offer to proceed with local-only cleanup or abort.

## Cleanup checklist (this skill, every run)

- [ ] Default branch detected and preserved.
- [ ] No file written into the repo to track state (this skill is stateless).
- [ ] Stack lockfile not touched (different concern, owned by other skills).
- [ ] Final summary printed regardless of partial failures.
