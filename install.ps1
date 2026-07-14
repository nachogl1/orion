#requires -Version 5.1
<#
.SYNOPSIS
  Installs the skills in this repo as user-level Claude Code skills via file copies.

.DESCRIPTION
  For each subdirectory of .\skills\, copies the folder into the target agent's
  user skills directory (default: ~/.claude/skills) and drops an `.orion-managed`
  marker so later runs can recognise and refresh its own copies. On scheduled
  runs it can also git-pull and re-copy every skill (-Update mode). Copies are
  used instead of junctions/symlinks: every update re-copies the skill content.

.PARAMETER Target
  Which agent to install for. Default: claude.

.PARAMETER Schedule
  daily | hourly | none | prompt. Default: none. Manual updates via
  `install.ps1 -Update` are the recommended workflow (lower supply-chain
  risk than auto-pulling executable skill content). Pass `-Schedule daily`
  if you explicitly want the old auto-pull behaviour.

.PARAMETER Force
  Overwrite existing entries in the target dir without asking.

.PARAMETER Update
  Non-interactive mode used by the scheduled task: git pull, then re-copy every
  skill (refreshing managed copies). Skips schedule registration and never
  overwrites entries that are not ours (no `.orion-managed` marker).

.PARAMETER StatusLine
  Also configure the orion status line in ~/.claude/settings.json (points the
  statusLine setting at the copied statusline script). Without this switch the
  interactive install offers it as a y/N prompt; -Update never touches settings.

.PARAMETER Help
  Show this usage and exit.

.EXAMPLE
  .\install.ps1
  .\install.ps1 -Target claude -Schedule daily
  .\install.ps1 -Update     # called by scheduled task
  .\install.ps1 -Help
#>
[CmdletBinding()]
param(
    [ValidateSet('claude')]
    [string]$Target = 'claude',

    [ValidateSet('daily','hourly','none','prompt')]
    [string]$Schedule = 'none',

    [switch]$Force,
    [switch]$Update,
    [switch]$StatusLine,
    [switch]$Help
)

if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
    return
}

$ErrorActionPreference = 'Stop'
$repoRoot     = Split-Path -Parent $MyInvocation.MyCommand.Path
$skillsSource = Join-Path $repoRoot 'skills'

if (-not (Test-Path $skillsSource)) {
    Write-Error "Source skills directory not found: $skillsSource"
    exit 1
}

switch ($Target) {
    'claude' { $targetDir = Join-Path $HOME '.claude\skills' }
    default  { Write-Error "Target '$Target' not yet supported."; exit 1 }
}

# Update mode: pull first
if ($Update) {
    Write-Host "[update] git pull --ff-only in $repoRoot"
    & git -C $repoRoot pull --ff-only 2>&1 | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) { Write-Host "[update] git pull failed (exit $LASTEXITCODE)"; exit $LASTEXITCODE }
}

if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

# Marker file dropped into every copied folder so later runs recognise their
# own copies (copies are otherwise indistinguishable from a user's own skills).
$markerName = '.orion-managed'

function Copy-Managed {
    param([string]$Source, [string]$Dest)
    if (Test-Path $Dest) {
        $destItem = Get-Item -LiteralPath $Dest -Force
        if ($destItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            # Stale junction/symlink from the old link-based install: delete the
            # link itself, never recurse through it (a recursive delete would
            # descend into the link target - i.e. this repo's source folder).
            $destItem.Delete()
        } else {
            Remove-Item -LiteralPath $Dest -Recurse -Force
        }
    }
    # The marker goes in FIRST so an interrupted copy still looks orion-managed
    # and gets overwritten (not skipped as "not ours") by the next run.
    New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $Dest $markerName) -Value $Source -NoNewline -Encoding ASCII
    Copy-Item -Path (Join-Path $Source '*') -Destination $Dest -Recurse -Force
}

$skillDirs = Get-ChildItem -Path $skillsSource -Directory
$skillNames = $skillDirs.Name
$added = 0; $skipped = 0; $updated = 0; $pruned = 0

# Prune managed copies whose source skill no longer exists (removed/renamed upstream)
Get-ChildItem -Path $targetDir -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
    if (-not (Test-Path -LiteralPath (Join-Path $_.FullName $markerName))) { return }
    if ($skillNames -notcontains $_.Name) {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
        Write-Host "  -    $($_.Name) (pruned removed skill)"
        $pruned++
    }
}

foreach ($skill in $skillDirs) {
    $destPath = Join-Path $targetDir $skill.Name
    $isOurs = (Test-Path $destPath) -and (Test-Path -LiteralPath (Join-Path $destPath $markerName))
    if ((Test-Path $destPath) -and -not $isOurs) {
        if ($Update) {
            Write-Host "  skip $($skill.Name) (exists, not ours)"
            $skipped++
            continue
        }
        if (-not $Force) {
            $resp = Read-Host "  !  $($skill.Name) exists and is not an orion copy. Overwrite? [y/N]"
            if ($resp -notmatch '^[Yy]') { Write-Host "  skip $($skill.Name)"; $skipped++; continue }
        }
    }
    Copy-Managed -Source $skill.FullName -Dest $destPath
    if ($isOurs) { Write-Host "  ~    $($skill.Name) (updated)"; $updated++ }
    else         { Write-Host "  +    $($skill.Name)";           $added++ }
}

Write-Host ""
Write-Host "[$added added, $updated updated, $pruned pruned, $skipped skipped] -> $targetDir"

# ---------------------------------------------------------------------------
# Status line - copy ./statusline to ~/.claude/statusline-orion (same copy +
# marker pattern as skills, so -Update re-copies it), then optionally point the
# statusLine setting in ~/.claude/settings.json at it (opt-in; never in -Update).
# ---------------------------------------------------------------------------
$statusSource = Join-Path $repoRoot 'statusline'
$statusLink   = Join-Path $HOME '.claude\statusline-orion'

if (Test-Path $statusSource) {
    $linkOk = $false
    $statusIsOurs = (Test-Path $statusLink) -and (Test-Path -LiteralPath (Join-Path $statusLink $markerName))
    if ((Test-Path $statusLink) -and -not $statusIsOurs) {
        if ($Update) {
            Write-Host "  skip statusline-orion (exists, not ours)"
        } else {
            $doReplace = $Force
            if (-not $doReplace) {
                $resp = Read-Host "  !  statusline-orion exists and is not an orion copy. Overwrite? [y/N]"
                $doReplace = $resp -match '^[Yy]'
            }
            if ($doReplace) {
                Copy-Managed -Source $statusSource -Dest $statusLink
                Write-Host "  +    statusline-orion"
                $linkOk = $true
            } else {
                Write-Host "  skip statusline-orion"
            }
        }
    } else {
        Copy-Managed -Source $statusSource -Dest $statusLink
        if ($statusIsOurs) { Write-Host "  ~    statusline-orion (updated)" }
        else               { Write-Host "  +    statusline-orion" }
        $linkOk = $true
    }

    if ($linkOk -and -not $Update) {
        $configure = $StatusLine
        if (-not $configure -and -not $Force) {
            $resp = Read-Host "Configure the orion status line in ~/.claude/settings.json? [y/N]"
            $configure = $resp -match '^[Yy]'
        }
        if ($configure) {
            $settingsPath = Join-Path $HOME '.claude\settings.json'
            $slScript = (Join-Path $statusLink 'statusline.sh') -replace '\\','/'
            $settings = $null
            if (Test-Path $settingsPath) {
                try {
                    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
                } catch {
                    Write-Host "  !  $settingsPath is not valid JSON - skipping statusLine configuration."
                    Write-Host "     Fix (or delete) the file, then re-run .\install.ps1 -StatusLine"
                }
            } else {
                $settings = New-Object PSCustomObject
            }
            if ($null -ne $settings) {
            $slValue = [PSCustomObject]@{ type = 'command'; command = "bash `"$slScript`"" }
            if ($settings.PSObject.Properties['statusLine']) {
                $settings.statusLine = $slValue
            } else {
                $settings | Add-Member -NotePropertyName statusLine -NotePropertyValue $slValue
            }
            # WriteAllText -> UTF-8 without BOM (a BOM breaks Claude Code's JSON parse)
            [System.IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 100))
            Write-Host "statusLine configured in $settingsPath"

            # Pre-warm the month-to-date cost cache (the file the status line
            # actually reads) so the first render shows the real figure instead
            # of the "$..." placeholder. Without this the in-script background
            # refresh leaves it pending until the first npx ccusage run finishes.
            # Best-effort: needs bash + node/npx (same prerequisites as the
            # status line itself); ignored if absent.
            Write-Host "Warming the month-to-date cost cache (one-time, needs node/npx)..."
            $warm = @'
since=$(date +%Y%m01)
cache="$HOME/.cache/claude-statusline/cost-mtd.txt"
mkdir -p "$(dirname "$cache")" 2>/dev/null
total=$(npx -y ccusage daily --json --since "$since" 2>/dev/null | jq -r ".totals.totalCost // empty")
[ -n "$total" ] && printf "%.2f" "$total" > "$cache" && echo "  cost cache: $total"
'@
            try { $warm | bash 2>$null } catch { }
            }
        }
    }
}

if ($Update) { return }

# Scheduled auto-pull (opt-in; manual updates are the default)
if ($Schedule -eq 'prompt') {
    Write-Host ""
    Write-Host "Updates are manual by default - run '.\install.ps1 -Update' (or ask Claude to)"
    Write-Host "when you want to pull the latest skills."
    $resp = Read-Host "Register a scheduled auto-pull anyway? (daily/hourly/none) [none]"
    if ([string]::IsNullOrWhiteSpace($resp)) { $resp = 'none' }
    $Schedule = $resp.ToLower()
    if ($Schedule -notin 'daily','hourly','none') {
        Write-Host "Unknown choice '$Schedule', defaulting to none."
        $Schedule = 'none'
    }
}

if ($Schedule -ne 'none') {
    $taskName = 'OrionSkillsAutoPull'
    $thisScript = Join-Path $repoRoot 'install.ps1'
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$thisScript`" -Update"

    switch ($Schedule) {
        'daily'  { $trigger = New-ScheduledTaskTrigger -Daily -At 9am }
        'hourly' {
            $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
                -RepetitionInterval (New-TimeSpan -Hours 1) `
                -RepetitionDuration ([TimeSpan]::MaxValue)
        }
    }

    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
        -Description "Auto-pull skills from $repoRoot" -Force | Out-Null
    Write-Host "Scheduled task '$taskName' registered ($Schedule)"
}
