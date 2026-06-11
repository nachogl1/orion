#!/usr/bin/env bash
# orion status line for Claude Code
#
# Segments (left to right):
#   - session alive time (cyan)
#   - context usage % (green/yellow/red)
#   - git branch + state indicators (stashes / untracked / modified / ahead)
#   - PR status for the current branch (cached, background-refreshed via `gh`)
#   - cost: API-equivalent USD for the open session (green) + rolling last
#     30 days across all projects (blue), aggregated from local transcripts
#     by ccusage (cached, background-refreshed via `npx`)
#   - model name (cyan)
#   - reasoning effort (color-coded by level; omitted when unsupported)
#   - second line: current working directory
#
# Requirements: bash (Git Bash on Windows), jq. Optional: gh (PR segment),
# node/npx (30-day cost segment — shows "$..." until available).
# Caches live under ~/.cache/claude-statusline/.
#
# Install: linked to ~/.claude/statusline-orion by this repo's installer; see
# statusline/README.md for the settings.json entry that activates it.

input=$(cat)

used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
cwd=$(echo "$input" | jq -r '.cwd // empty')
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')
model_name=$(echo "$input" | jq -r '.model.display_name // empty')
effort_level=$(echo "$input" | jq -r '.effort.level // empty')

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
# rolling-30-day total aggregated from local transcripts by ccusage.
# The 30d figure is cached (10-min TTL) and refreshed in the background — same
# pattern as the PR segment — so the status line never blocks on npx.
# ---------------------------------------------------------------------------
cost_segment=""
session_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
if [ -n "$session_cost" ]; then
  session_cost_fmt=$(printf '%.2f' "$session_cost" 2>/dev/null)
  cost_segment="\033[0;32m\$${session_cost_fmt}\033[0m"
fi

month_cache="$HOME/.cache/claude-statusline/cost-30d.txt"
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
    _since=$(date -d '30 days ago' +%Y%m%d 2>/dev/null || date -v-30d +%Y%m%d 2>/dev/null)
    _total=$(npx -y ccusage daily --json --since "$_since" 2>/dev/null | jq -r '.totals.totalCost // empty')
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

# Get current git branch (skip optional locks to avoid contention)
git_branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)

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

  ctx_segment="${color}ctx: ${used_pct}%%${reset}"
else
  ctx_segment="ctx: --"
fi

# Build git state indicators (only when inside a git repo, i.e. branch is known)
git_indicators=""
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
    _num=$(printf '%s' "$_gh_json" | jq -r '.number')
    _state=$(printf '%s' "$_gh_json" | jq -r '.state')
    _draft=$(printf '%s' "$_gh_json" | jq -r '.isDraft')

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
    ' 2>/dev/null)

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

if [ -n "$alive_segment" ]; then
  prefix="\033[0;36m${alive_segment}\033[0m  |  "
else
  prefix=""
fi

if [ -n "$git_segment" ]; then
  if [ -n "$pr_segment" ]; then
    printf "${prefix}${ctx_segment}  |  ${git_segment}  |  ${pr_segment}${cost_suffix}\n${cwd}"
  else
    printf "${prefix}${ctx_segment}  |  ${git_segment}${cost_suffix}\n${cwd}"
  fi
else
  printf "${prefix}${ctx_segment}${cost_suffix}\n${cwd}"
fi
