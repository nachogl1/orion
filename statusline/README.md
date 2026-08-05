# orion status line

A shared [Claude Code status line](https://docs.anthropic.com/en/docs/claude-code/statusline) showing, on one line:

| Segment | Color | Source |
|---|---|---|
| Session alive time (`1h23m`) | cyan | transcript file creation time |
| Context usage (`ctx: 42.5%`) | green / yellow ≥70% / red ≥90% | Claude Code stdin JSON |
| Git branch + state (`[branch] ◆stashes ◯untracked ●modified ▲ahead`) | per-indicator | `git` in the session's cwd |
| PR status for the branch (`#12 ok` / `wait` / `fail` / `draft` / `merged` / `no PR`) | per-state | `gh pr view`, cached 5 min, refreshed in background |
| **Session cost** (`$1.23`) | green | `cost.total_cost_usd` from Claude Code stdin JSON |
| **Month-to-date cost** (`$345.67`) | blue | [ccusage](https://github.com/ryoppippi/ccusage) over local transcripts, current calendar month to date (resets on the 1st), cached 10 min, refreshed in background |
| **Model** (`Opus`) | cyan | `model.display_name` from Claude Code stdin JSON |
| **Reasoning effort** (`effort:high`) | green low/medium, yellow high, red xhigh/max | `effort.level` from Claude Code stdin JSON; omitted when the model exposes no effort level |
| **Jobs flag** (`⚑2` active / `⚑0` idle) | bold yellow when ≥1, dim when 0 | `claude agents --json`, cached 20 s, refreshed in background |
| **5-hour usage** (`5h:23% ↻2h14m`) | bright magenta | `rate_limits.five_hour` from Claude Code stdin JSON |
| **Weekly usage** (`7d:41% ↻3d5h`) | bright blue | `rate_limits.seven_day` from Claude Code stdin JSON |

Second line: the session's working directory.

The **jobs flag** (`⚑N`) is a heads-up that background work is running: it counts the dispatched/background agent sessions reported by `claude agents --json`, excluding the current interactive session, and shows `⚑0` (dimmed) when nothing is running. It does **not** count cloud routines created via `/schedule` — those live server-side and are only reachable through the CLI's internal authenticated client, so there is no supported, distribution-safe way to list them from a shell script. If a routine is firing *right now* it dispatches a background agent, which the flag will pick up; a routine merely scheduled for later will not appear.

The two **usage-limit segments** are the subscription rate-limit windows: how much of the 5-hour rolling window and of the 7-day (weekly) window has been consumed, each followed by `↻` and the time until that window refreshes (`3d5h` / `2h14m` / `12m` / `now`). They come straight from the stdin JSON, so they cost nothing to draw and never block. Each window has its own colour so the two are never confused. They appear **only on a Claude.ai subscription (Pro/Max) session, and only after the first response of the session** — Claude Code omits `rate_limits` for API-key sessions, and either window can be absent on its own, in which case that segment is simply not drawn.

Both cost figures are **API-equivalent USD** — what the usage would cost at API list prices. On a subscription plan this is a value measure, not a bill. The month-to-date figure spans **all projects on the machine**, and can only see transcripts still on disk (Claude Code prunes them after `cleanupPeriodDays`, ~30 days by default).

## Requirements

- `bash` (on Windows: Git Bash, normally present with Git) and `jq` — required.
- `gh` (GitHub CLI) — optional; without it the PR segment is omitted.
- `node`/`npx` — optional; powers the month-to-date cost segment via `npx -y ccusage`. Without it the segment shows `$...`.

Cache files live under `~/.cache/claude-statusline/` — delete the folder to force a refresh.

## Install

The repo installers **copy** this folder to `~/.claude/statusline-orion` (marked `.orion-managed`, like skills), so `-Update` / `--update` re-copies the status line like any skill (a plain `git pull` is not enough — the install must re-copy). Activating it in `~/.claude/settings.json` is **opt-in**:

```powershell
.\install.ps1 -StatusLine          # Windows
```
```sh
./install.sh --statusline           # macOS / Linux
```

(The interactive installer also offers it as a y/N prompt.)

Or configure manually — point `statusLine` at the copied script in `~/.claude/settings.json`:

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

`uninstall.ps1` / `uninstall.sh` remove the managed copy and, if the `statusLine` setting points at it, remove that setting too.
