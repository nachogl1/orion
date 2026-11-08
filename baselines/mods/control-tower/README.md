# Orion Control Tower

A Claude Code mod: a pane docked on the right of the fullscreen layout that shows, at a glance, what is still running and what is waiting for you.

- **Show or hide:** `/control-tower`, or Ctrl+X then P once that chord is bound to `command:control-tower` in `~/.claude/keybindings.json`.
- **Scroll:** Ctrl+X then Tab moves into the pane, then the arrow keys.
- **Right-side dock:** needs Claude Code's fullscreen layout (`/tui fullscreen`) and a wide terminal; otherwise the pane sits above the prompt.

## What it shows

1. **This session:** on the left, a short summary of unresolved errors and what you must still do, written after each reply (one small, low-effort model call), or that the terminal can be closed; on the right, the activities the session caused outside the chat (helpers sent and finished, pushes, pull requests opened, waiting for CI with its check count, merges).
2. **dev-next runs on this computer:** each issue in flight, its pull request and stage, and the terminal and sub-agents working on it when dev-next reports them in its in-flight entry (`terminal`, `step`, `agents`); otherwise "not reported yet".
3. **Open pull requests:** every one, with the issues it closes, its checks and the run working on it.

It reads the in-flight file beside the worktrees (its folder is the `Worktree root` the project's `CLAUDE.md` names) and GitHub through `gh`, every 20 seconds. It changes nothing.

## Develop

`claude plugin validate .` checks the manifest and module; `claude plugin test .` runs `hooks/control-tower.test.tsx`; `tsc -p .` type-checks once Claude Code has loaded the mod and written its types.

orion carries this folder; installing it on a computer is the person's choice, offered by orion.
