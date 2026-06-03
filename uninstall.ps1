#requires -Version 5.1
<#
.SYNOPSIS
  Removes skill junctions created by install.ps1 and the scheduled auto-pull task.
.PARAMETER Target
  Which agent's skills directory to clean. Default: claude.
#>
[CmdletBinding()]
param(
    [ValidateSet('claude')]
    [string]$Target = 'claude'
)

$ErrorActionPreference = 'Stop'
$repoRoot     = Split-Path -Parent $MyInvocation.MyCommand.Path
$skillsSource = Join-Path $repoRoot 'skills'

switch ($Target) {
    'claude' { $targetDir = Join-Path $HOME '.claude\skills' }
}

if (Test-Path $skillsSource) {
    Get-ChildItem -Path $skillsSource -Directory | ForEach-Object {
        $linkPath = Join-Path $targetDir $_.Name
        if (Test-Path $linkPath) {
            $item = Get-Item $linkPath -Force
            $isOurLink = $item.LinkType -in 'Junction','SymbolicLink' -and `
                         ($item.Target -contains $_.FullName -or $item.Target -contains "$($_.FullName)\")
            if ($isOurLink) {
                Remove-Item $linkPath -Recurse -Force
                Write-Host "  -    $($_.Name)"
            } else {
                Write-Host "  skip $($_.Name) (not our link)"
            }
        }
    }
}

# Status line: remove the link and, if the statusLine setting points at it, the setting
$statusSource = Join-Path $repoRoot 'statusline'
$statusLink   = Join-Path $HOME '.claude\statusline-orion'
if (Test-Path $statusLink) {
    $item = Get-Item $statusLink -Force
    $isOurLink = $item.LinkType -in 'Junction','SymbolicLink' -and `
                 ($item.Target -contains $statusSource -or $item.Target -contains "$statusSource\")
    if ($isOurLink) {
        Remove-Item $statusLink -Recurse -Force
        Write-Host "  -    statusline-orion"
    } else {
        Write-Host "  skip statusline-orion (not our link)"
    }
}
$settingsPath = Join-Path $HOME '.claude\settings.json'
if (Test-Path $settingsPath) {
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    if ($settings.PSObject.Properties['statusLine'] -and `
        "$($settings.statusLine.command)" -match 'statusline-orion') {
        $settings.PSObject.Properties.Remove('statusLine')
        # WriteAllText -> UTF-8 without BOM (a BOM breaks Claude Code's JSON parse)
        [System.IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 32))
        Write-Host "statusLine setting removed from $settingsPath"
    }
}

$taskName = 'OrionSkillsAutoPull'
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Scheduled task '$taskName' removed"
}

Write-Host "Uninstall complete."
