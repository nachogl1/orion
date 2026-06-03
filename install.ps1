#requires -Version 5.1
<#
.SYNOPSIS
  Installs the skills in this repo as user-level Claude Code skills via junctions.

.DESCRIPTION
  For each subdirectory of .\skills\, creates a directory junction in the target
  agent's user skills directory (default: ~/.claude/skills). On scheduled runs
  it can also git-pull and link any newly added skills (-Update mode).

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
  Non-interactive mode used by the scheduled task: git pull, then link any new
  skills. Skips schedule registration and never overwrites existing entries.

.PARAMETER StatusLine
  Also configure the orion status line in ~/.claude/settings.json (points the
  statusLine setting at the linked statusline script). Without this switch the
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

$skillDirs = Get-ChildItem -Path $skillsSource -Directory
$added = 0; $skipped = 0; $existing = 0; $pruned = 0

# Prune dangling junctions pointing into our repo (skills removed upstream)
$sourcePrefix = $skillsSource.TrimEnd('\','/')
Get-ChildItem -Path $targetDir -Force -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.LinkType -notin 'Junction','SymbolicLink') { return }
    $tgt = @($_.Target)[0]
    if (-not $tgt) { return }
    $tgtTrim = $tgt.TrimEnd('\','/')
    if (-not $tgtTrim.StartsWith($sourcePrefix, [System.StringComparison]::OrdinalIgnoreCase)) { return }
    if (-not (Test-Path -LiteralPath $tgtTrim)) {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
        Write-Host "  -    $($_.Name) (pruned dangling)"
        $pruned++
    }
}

foreach ($skill in $skillDirs) {
    $linkPath = Join-Path $targetDir $skill.Name
    if (Test-Path $linkPath) {
        $item = Get-Item $linkPath -Force
        $isOurLink = $item.LinkType -in 'Junction','SymbolicLink' -and `
                     ($item.Target -contains $skill.FullName -or $item.Target -contains "$($skill.FullName)\")
        if ($isOurLink) {
            Write-Host "  ok   $($skill.Name)"
            $existing++
            continue
        }
        if ($Update) {
            Write-Host "  skip $($skill.Name) (exists, not our link)"
            $skipped++
            continue
        }
        if (-not $Force) {
            $resp = Read-Host "  !  $($skill.Name) exists and is not our link. Overwrite? [y/N]"
            if ($resp -notmatch '^[Yy]') { Write-Host "  skip $($skill.Name)"; $skipped++; continue }
        }
        Remove-Item $linkPath -Recurse -Force
    }
    New-Item -ItemType Junction -Path $linkPath -Target $skill.FullName | Out-Null
    Write-Host "  +    $($skill.Name)"
    $added++
}

Write-Host ""
Write-Host "[$added added, $existing already linked, $pruned pruned, $skipped skipped] -> $targetDir"

# ---------------------------------------------------------------------------
# Status line - link ./statusline to ~/.claude/statusline-orion (same junction
# pattern as skills, so git pull updates it), then optionally point the
# statusLine setting in ~/.claude/settings.json at it (opt-in; never in -Update).
# ---------------------------------------------------------------------------
$statusSource = Join-Path $repoRoot 'statusline'
$statusLink   = Join-Path $HOME '.claude\statusline-orion'

if (Test-Path $statusSource) {
    $linkOk = $false
    if (Test-Path $statusLink) {
        $item = Get-Item $statusLink -Force
        $isOurLink = $item.LinkType -in 'Junction','SymbolicLink' -and `
                     ($item.Target -contains $statusSource -or $item.Target -contains "$statusSource\")
        if ($isOurLink) {
            Write-Host "  ok   statusline-orion"
            $linkOk = $true
        } elseif ($Update) {
            Write-Host "  skip statusline-orion (exists, not our link)"
        } else {
            $doReplace = $Force
            if (-not $doReplace) {
                $resp = Read-Host "  !  statusline-orion exists and is not our link. Overwrite? [y/N]"
                $doReplace = $resp -match '^[Yy]'
            }
            if ($doReplace) {
                Remove-Item $statusLink -Recurse -Force
                New-Item -ItemType Junction -Path $statusLink -Target $statusSource | Out-Null
                Write-Host "  +    statusline-orion"
                $linkOk = $true
            } else {
                Write-Host "  skip statusline-orion"
            }
        }
    } else {
        New-Item -ItemType Junction -Path $statusLink -Target $statusSource | Out-Null
        Write-Host "  +    statusline-orion"
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
            if (Test-Path $settingsPath) {
                $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
            } else {
                $settings = New-Object PSCustomObject
            }
            $slValue = [PSCustomObject]@{ type = 'command'; command = "bash `"$slScript`"" }
            if ($settings.PSObject.Properties['statusLine']) {
                $settings.statusLine = $slValue
            } else {
                $settings | Add-Member -NotePropertyName statusLine -NotePropertyValue $slValue
            }
            # WriteAllText -> UTF-8 without BOM (a BOM breaks Claude Code's JSON parse)
            [System.IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 32))
            Write-Host "statusLine configured in $settingsPath"
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
