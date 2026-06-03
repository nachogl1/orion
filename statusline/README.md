# orion status line

A shared [Claude Code status line](https://docs.anthropic.com/en/docs/claude-code/statusline) showing, on one line:

| Segment | Color | Source |
|---|---|---|
| Session alive time (`1h23m`) | cyan | transcript file creation time |
| Context usage (`ctx: 42.5%`) | green / yellow ≥70% / red ≥90% | Claude Code stdin JSON |
| Git branch + state (`[branch] ◆stashes ◯untracked ●modified ▲ahead`) | per-indicator | `git` in the session's cwd |
| PR status for the branch (`#12 ok` / `wait` / `fail` / `draft` / `merged` / `no PR`) | per-state | `gh pr view`, cached 5 min, refreshed in background |
| **Session cost** (`$1.23`) | green | `cost.total_cost_usd` from Claude Code stdin JSON |
| **Last-30-days cost** (`$345.67`) | blue | [ccusage](https://github.com/ryoppippi/ccusage) over local transcripts, cached 10 min, refreshed in background |

Second line: the session's working directory.

Both cost figures are **API-equivalent USD** — what the usage would cost at API list prices. On a subscription plan this is a value measure, not a bill. The 30-day figure spans **all projects on the machine**, and can only see transcripts still on disk (Claude Code prunes them after `cleanupPeriodDays`, ~30 days by default).

## Requirements

- `bash` (on Windows: Git Bash, normally present with Git) and `jq` — required.
- `gh` (GitHub CLI) — optional; without it the PR segment is omitted.
- `node`/`npx` — optional; powers the 30-day cost segment via `npx -y ccusage`. Without it the segment shows `$...`.

Cache files live under `~/.cache/claude-statusline/` — delete the folder to force a refresh.

## Install

The repo installers link this folder to `~/.claude/statusline-orion` (junction on Windows, symlink elsewhere), so `git pull` / `-Update` updates the status line like any skill. Activating it in `~/.claude/settings.json` is **opt-in**:

```powershell
.\install.ps1 -StatusLine          # Windows
```
```sh
./install.sh --statusline           # macOS / Linux
```

(The interactive installer also offers it as a y/N prompt.)

Or configure manually — point `statusLine` at the linked script in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"<absolute path to home>/.claude/statusline-orion/statusline.sh\""
  }
}
```

> The command must be an absolute path (Claude Code does not expand `~` on all platforms). The installers write the correct per-user path for you.

## Uninstall

`uninstall.ps1` / `uninstall.sh` remove the link and, if the `statusLine` setting points at it, remove that setting too.
