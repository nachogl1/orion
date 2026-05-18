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

$taskName = 'OrionSkillsAutoPull'
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Scheduled task '$taskName' removed"
}

Write-Host "Uninstall complete."
