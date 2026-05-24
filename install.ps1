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
