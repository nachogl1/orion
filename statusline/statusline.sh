#!/usr/bin/env bash
# orion status line for Claude Code
#
# Segments (left to right):
#   - session alive time (cyan)
#   - context usage % (green/yellow/red)
#   - git branch + state indicators (stashes / untracked / modified / ahead)
#   - PR status for the current branch (cached, background-refreshed via `gh`)
#   - cost: API-equivalent USD for the open session (green) + current
#     calendar month to date across all projects (blue), aggregated from
#     local transcripts by ccusage (cached, background-refreshed via `npx`)
#   - model name (cyan)
#   - reasoning effort (color-coded by level; omitted when unsupported)
#   - jobs flag (bold yellow ⚑N when background jobs run; dim ⚑0 when idle)
#   - second line: current working directory
#
# Requirements: bash (Git Bash on Windows), jq. Optional: gh (PR segment),
# node/npx (month-to-date cost segment — shows "$..." until available).
# Caches live under ~/.cache/claude-statusline/.
#
# Install: copied to ~/.claude/statusline-orion by this repo's installer; see
# statusline/README.md for the settings.json entry that activates it.

input=$(cat)

# Parse every needed stdin field in ONE jq pass (one process per redraw, not
# six). Values are emitted one per line; none of them can contain a newline.
# tr strips the \r that native-Windows jq builds append to every output line.
_fields=$(echo "$input" | jq -r '
  (.context_window.used_percentage // ""),
  (.cwd // ""),
  (.transcript_path // ""),
  (.model.display_name // ""),
  (.effort.level // ""),
  (.cost.total_cost_usd // "")
' | tr -d '\r')
{
  read -r used_pct
  read -r cwd
  read -r transcript_path
  read -r model_name
  read -r effort_level
  read -r session_cost
} <<< "$_fields"

# Compute elapsed time since session start (transcript file birth/creation time)
alive_segment=""
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  # Use stat -c %W (birth time on Linux) or %Y (mtime fallback); on macOS use -f %SB
  # Try GNU stat first (Linux/Git-Bash/WSL), then BSD stat (macOS)
  birth=$(stat -c %W "$transcript_path" 2>/dev/null)
  # %W may return 0 if birth time is unsupported — fall back to mtime (%Y)
  if [ -z "$birth" ] || [ "$birth" = "0" ]; then
    birth=$(stat -c %Y "$transcript_path" 2>/dev/null)
  fi
  # BSD/macOS fallback
  if [ -z "$birth" ]; then
    birth=$(stat -f %B "$transcript_path" 2>/dev/null)
    if [ -z "$birth" ] || [ "$birth" = "0" ]; then
      birth=$(stat -f %m "$transcript_path" 2>/dev/null)
    fi
  fi

  if [ -n "$birth" ] && [ "$birth" != "0" ]; then
    now=$(date +%s)
    elapsed=$(( now - birth ))
    if [ "$elapsed" -lt 0 ]; then elapsed=0; fi

    hours=$(( elapsed / 3600 ))
    mins=$(( (elapsed % 3600) / 60 ))
    secs=$(( elapsed % 60 ))

    if [ "$hours" -gt 0 ]; then
      alive_segment="${hours}h${mins}m"
    elif [ "$mins" -gt 0 ]; then
      alive_segment="${mins}m"
    else
      alive_segment="${secs}s"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Cost segment — API-equivalent USD for this session (from stdin JSON) plus a
# current-calendar-month-to-date total aggregated from local transcripts by
# ccusage (e.g. on Jun 23 it sums Jun 1 → Jun 23, resetting on the 1st).
# The month figure is cached (10-min TTL) and refreshed in the background — same
# pattern as the PR segment — so the status line never blocks on npx.
# ---------------------------------------------------------------------------
cost_segment=""
if [ -n "$session_cost" ]; then
  session_cost_fmt=$(printf '%.2f' "$session_cost" 2>/dev/null)
  cost_segment="\033[0;32m\$${session_cost_fmt}\033[0m"
fi

month_cache="$HOME/.cache/claude-statusline/cost-mtd.txt"
mkdir -p "$(dirname "$month_cache")" 2>/dev/null

_month_fresh=false
if [ -f "$month_cache" ]; then
  _cmtime=$(stat -c %Y "$month_cache" 2>/dev/null)
  if [ -z "$_cmtime" ]; then
    _cmtime=$(stat -f %m "$month_cache" 2>/dev/null)
  fi
  if [ -n "$_cmtime" ]; then
    _cage=$(( $(date +%s) - _cmtime ))
    if [ "$_cage" -lt 600 ]; then
      _month_fresh=true
    fi
  fi
fi

if ! $_month_fresh; then
  # Bump mtime first so concurrent status-line refreshes don't stampede npx,
  # then recompute in the background (stale value keeps showing meanwhile).
  touch "$month_cache" 2>/dev/null
  (
    # First day of the current calendar month (YYYYMM01) — month-to-date, not
    # a rolling 30-day window. Pure strftime, so GNU and BSD `date` both work.
    _since=$(date +%Y%m01)
    _total=$(npx -y ccusage daily --json --since "$_since" 2>/dev/null | jq -r '.totals.totalCost // empty' | tr -d '\r')
    if [ -n "$_total" ]; then
      _tmp="${month_cache}.tmp.$$"
      printf '%.2f' "$_total" > "$_tmp" 2>/dev/null && mv "$_tmp" "$month_cache"
    fi
  ) &
  disown 2>/dev/null || true
fi

month_val=""
if [ -f "$month_cache" ]; then
  month_val=$(cat "$month_cache" 2>/dev/null)
fi
if [ -n "$month_val" ]; then
  month_part="\033[0;34m\$${month_val}\033[0m"
else
  month_part="\033[0;34m\$...\033[0m"   # first run — background refresh pending
fi
if [ -n "$cost_segment" ]; then
  cost_segment="${cost_segment} ${month_part}"
else
  cost_segment="${month_part}"
fi

# Build context segment with color coding
if [ -n "$used_pct" ]; then
  used_int=${used_pct%.*}

  if [ "$used_int" -ge 90 ]; then
    color="\033[0;31m"   # red
  elif [ "$used_int" -ge 70 ]; then
    color="\033[0;33m"   # yellow
  else
    color="\033[0;32m"   # green
  fi
  reset="\033[0m"

  ctx_segment="${color}ctx: ${used_pct}%${reset}"
else
  ctx_segment="ctx: --"
fi

# ---------------------------------------------------------------------------
# Git segment — branch + state indicators. The five git commands are cached
# per cwd (10s TTL) so redraw storms don't relaunch git every time; on a stale
# cache they are recomputed inline (git is local and fast enough once) and the
# cache is rewritten. Cache layout: line 1 = branch, line 2 = indicators.
# ---------------------------------------------------------------------------
git_branch=""
git_indicators=""
_git_cache_id=$(printf '%s' "$cwd" | cksum | tr -cd '0-9')
git_cache="$HOME/.cache/claude-statusline/git-${_git_cache_id}.txt"
mkdir -p "$(dirname "$git_cache")" 2>/dev/null

_git_fresh=false
if [ -f "$git_cache" ]; then
  _gmtime=$(stat -c %Y "$git_cache" 2>/dev/null)
  if [ -z "$_gmtime" ]; then
    _gmtime=$(stat -f %m "$git_cache" 2>/dev/null)
  fi
  if [ -n "$_gmtime" ] && [ "$(( $(date +%s) - _gmtime ))" -lt 10 ]; then
    _git_fresh=true
  fi
fi

if $_git_fresh; then
  git_branch=$(sed -n '1p' "$git_cache")
  git_indicators=$(sed -n '2p' "$git_cache")
else
  # Get current git branch (skip optional locks to avoid contention)
  git_branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)

  # Build git state indicators (only when inside a git repo, i.e. branch is known)
  if [ -n "$git_branch" ]; then
    # ANSI color codes
    _mag="\033[0;35m"   # magenta — stashes
    _yel="\033[0;33m"   # yellow  — untracked
    _red="\033[0;31m"   # red     — modifications
    _blu="\033[0;34m"   # blue    — ahead
    _rst="\033[0m"

    # 1. Stashes (magenta ◆N) — always shown
    stash_count=$(git -C "$cwd" --no-optional-locks stash list 2>/dev/null | wc -l | tr -d ' ')
    git_indicators="${git_indicators} ${_mag}◆${stash_count:-0}${_rst}"

    # 2. Untracked files (yellow ◯N) — always shown
    untracked_count=$(git -C "$cwd" --no-optional-locks ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
    git_indicators="${git_indicators} ${_yel}◯${untracked_count:-0}${_rst}"

    # 3. Uncommitted modifications — staged + unstaged tracked (red ●N) — always shown
    #    Count lines from `git status --porcelain` where the first two chars are NOT "??"
    mod_count=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null | grep -v '^??' | wc -l | tr -d ' ')
    git_indicators="${git_indicators} ${_red}●${mod_count:-0}${_rst}"

    # 4. Commits ahead of upstream (blue ▲N) — always shown; default to 0 when no upstream
    ahead_count=$(git -C "$cwd" --no-optional-locks rev-list --count '@{u}..HEAD' 2>/dev/null)
    git_indicators="${git_indicators} ${_blu}▲${ahead_count:-0}${_rst}"
  fi

  _tmp="${git_cache}.tmp.$$"
  printf '%s\n%s\n' "$git_branch" "$git_indicators" > "$_tmp" 2>/dev/null && mv "$_tmp" "$git_cache"
fi

# Build git segment (branch + indicators, no PR yet)
if [ -n "$git_branch" ]; then
  git_segment="[$git_branch]  | ${git_indicators# }"
else
  git_segment=""
fi

# ---------------------------------------------------------------------------
# PR segment — only when inside a git repo and `gh` is available
# ---------------------------------------------------------------------------
pr_segment=""
if [ -n "$git_branch" ] && command -v gh >/dev/null 2>&1; then

  # Sanitize branch name for use as a cache-file suffix
  safe_branch=$(printf '%s' "$git_branch" | tr -cs 'A-Za-z0-9._-' '_')
  cache_dir="$HOME/.cache/claude-statusline"
  cache_file="$cache_dir/pr-${safe_branch}.txt"

  # Helper: compute the formatted PR string from `gh` JSON output
  _compute_pr_string() {
    local _cwd="$1"
    local _gh_json
    # NOTE: `gh` has no `-C <dir>` flag (that's git). The caller already cd's into
    # the repo before invoking this, so a plain `gh pr view` resolves the branch.
    _gh_json=$(gh pr view --json number,state,isDraft,reviewDecision,statusCheckRollup 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$_gh_json" ]; then
      # No PR for this branch
      printf '\033[0;90mno PR\033[0m'
      return
    fi

    local _num _state _draft
    # tr strips the \r native-Windows jq appends (a bare \r resets the cursor
    # to column 0 mid-line and corrupts the rendered status line)
    _num=$(printf '%s' "$_gh_json" | jq -r '.number' | tr -d '\r')
    _state=$(printf '%s' "$_gh_json" | jq -r '.state' | tr -d '\r')
    _draft=$(printf '%s' "$_gh_json" | jq -r '.isDraft' | tr -d '\r')

    if [ "$_state" = "MERGED" ]; then
      printf '\033[0;35m#%s merged\033[0m' "$_num"
      return
    fi

    if [ "$_state" = "CLOSED" ]; then
      printf '\033[0;31m#%s closed\033[0m' "$_num"
      return
    fi

    if [ "$_draft" = "true" ]; then
      printf '\033[0;90m#%s draft\033[0m' "$_num"
      return
    fi

    # PR is open — inspect status checks
    # statusCheckRollup items have a .conclusion (when done) or .state (when pending)
    local _checks
    _checks=$(printf '%s' "$_gh_json" | jq -r '
      .statusCheckRollup[]?
      | if .conclusion != null and .conclusion != "" then .conclusion else .state end
    ' 2>/dev/null | tr -d '\r')

    if printf '%s' "$_checks" | grep -qiE '^(FAILURE|ERROR|CANCELLED|TIMED_OUT)$'; then
      printf '\033[0;31m#%s fail\033[0m' "$_num"
    elif printf '%s' "$_checks" | grep -qiE '^(PENDING|IN_PROGRESS|QUEUED)$'; then
      printf '\033[0;33m#%s wait\033[0m' "$_num"
    else
      printf '\033[0;32m#%s ok\033[0m' "$_num"
    fi
  }

  # Create cache dir if needed (silently)
  mkdir -p "$cache_dir" 2>/dev/null

  _cache_fresh=false
  if [ -f "$cache_file" ]; then
    # Check mtime — stat -c %Y on Linux/Git-Bash, stat -f %m on macOS/BSD
    _mtime=$(stat -c %Y "$cache_file" 2>/dev/null)
    if [ -z "$_mtime" ]; then
      _mtime=$(stat -f %m "$cache_file" 2>/dev/null)
    fi
    if [ -n "$_mtime" ]; then
      _now=$(date +%s)
      _age=$(( _now - _mtime ))
      if [ "$_age" -lt 300 ]; then
        _cache_fresh=true
      fi
    fi
  fi

  if $_cache_fresh; then
    # Cache hit — read directly
    pr_segment=$(cat "$cache_file")
  else
    # Cache miss or stale — show placeholder or stale value, refresh in background
    if [ -f "$cache_file" ]; then
      pr_segment=$(cat "$cache_file")   # show stale while refreshing
    else
      pr_segment="\033[0;90mpr ...\033[0m"  # first-time placeholder
    fi

    # Background refresh: cd to repo dir, compute, write atomically
    (
      cd "$cwd" 2>/dev/null || exit
      _fresh=$(_compute_pr_string "$cwd")
      _tmp="${cache_file}.tmp.$$"
      printf '%s' "$_fresh" > "$_tmp" && mv "$_tmp" "$cache_file"
    ) &
    disown 2>/dev/null || true
  fi
fi

# ---------------------------------------------------------------------------
# Model segment — current model display name (cyan)
# ---------------------------------------------------------------------------
model_segment=""
if [ -n "$model_name" ]; then
  model_segment="\033[0;36m${model_name}\033[0m"
fi

# ---------------------------------------------------------------------------
# Effort segment — reasoning effort level, color-coded by level.
# Absent from stdin JSON when the model doesn't support effort — omit entirely.
# ---------------------------------------------------------------------------
effort_segment=""
if [ -n "$effort_level" ]; then
  case "$effort_level" in
    low|medium) _ecol="\033[0;32m" ;;   # green
    high)       _ecol="\033[0;33m" ;;   # yellow
    *)          _ecol="\033[0;31m" ;;   # red — xhigh / max
  esac
  effort_segment="${_ecol}effort:${effort_level}\033[0m"
fi

# ---------------------------------------------------------------------------
# Jobs flag — a single leading indicator (⚑N) shown only when one or more
# background jobs are active. Cached (20s TTL) and background-refreshed, same
# non-blocking pattern as the PR/cost segments, so the status line never waits
# on the `claude` CLI.
#
# Source: `claude agents --json` — dispatched/background agent sessions. The
# current interactive session is excluded (kind == "interactive").
#
# NOTE: cloud routines created via `/schedule` are NOT counted here. They live
# server-side and are only reachable through the CLI's internal authenticated
# client — there is no supported, scriptable way to list them from a shell, and
# hard-coding an undocumented internal endpoint would be fragile and unsafe for
# a distributable status line. See statusline/README.md.
# ---------------------------------------------------------------------------
jobs_segment=""
jobs_cache="$HOME/.cache/claude-statusline/jobs.txt"
mkdir -p "$(dirname "$jobs_cache")" 2>/dev/null

_jobs_fresh=false
if [ -f "$jobs_cache" ]; then
  _jmtime=$(stat -c %Y "$jobs_cache" 2>/dev/null)
  if [ -z "$_jmtime" ]; then
    _jmtime=$(stat -f %m "$jobs_cache" 2>/dev/null)
  fi
  if [ -n "$_jmtime" ] && [ "$(( $(date +%s) - _jmtime ))" -lt 20 ]; then
    _jobs_fresh=true
  fi
fi

if ! $_jobs_fresh && command -v claude >/dev/null 2>&1; then
  # Bump mtime first so concurrent refreshes don't stampede the CLI, then
  # recompute in the background (stale value keeps showing meanwhile).
  touch "$jobs_cache" 2>/dev/null
  (
    _n=$(claude agents --json 2>/dev/null \
      | jq -r '[.[] | select(.kind != "interactive")] | length' 2>/dev/null | tr -d '\r')
    [ -n "$_n" ] || _n=0
    _tmp="${jobs_cache}.tmp.$$"
    printf '%s' "$_n" > "$_tmp" 2>/dev/null && mv "$_tmp" "$jobs_cache"
  ) &
  disown 2>/dev/null || true
fi

_jobs_n=""
if [ -f "$jobs_cache" ]; then
  _jobs_n=$(cat "$jobs_cache" 2>/dev/null)
fi
[ -n "$_jobs_n" ] || _jobs_n=0
if [ "$_jobs_n" != "0" ]; then
  jobs_segment="\033[1;33m⚑${_jobs_n}\033[0m"   # bold yellow ⚑N — jobs running
else
  jobs_segment="\033[0;90m⚑0\033[0m"            # dim ⚑0 — nothing running
fi

# ---------------------------------------------------------------------------
# Assemble output
# ---------------------------------------------------------------------------
if [ -n "$cost_segment" ]; then
  cost_suffix="  |  ${cost_segment}"
else
  cost_suffix=""
fi

# Model + effort sit to the right of cost: | modelname | effort:level
if [ -n "$model_segment" ]; then
  cost_suffix="${cost_suffix}  |  ${model_segment}"
fi
if [ -n "$effort_segment" ]; then
  cost_suffix="${cost_suffix}  |  ${effort_segment}"
fi
# Jobs flag sits rightmost, after effort
if [ -n "$jobs_segment" ]; then
  cost_suffix="${cost_suffix}  |  ${jobs_segment}"
fi

if [ -n "$alive_segment" ]; then
  prefix="\033[0;36m${alive_segment}\033[0m  |  "
else
  prefix=""
fi

if [ -n "$git_segment" ]; then
  if [ -n "$pr_segment" ]; then
    line1="${prefix}${ctx_segment}  |  ${git_segment}  |  ${pr_segment}${cost_suffix}"
  else
    line1="${prefix}${ctx_segment}  |  ${git_segment}${cost_suffix}"
  fi
else
  line1="${prefix}${ctx_segment}${cost_suffix}"
fi

# %b expands the \033 color literals in the segments; the cwd goes through %s
# verbatim, so a % or \ in a path (or branch name) can never be treated as a
# printf format directive and corrupt the line.
printf '%b\n%s' "$line1" "$cwd"
