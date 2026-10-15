#requires -Version 5.1
<#
.SYNOPSIS
  Removes skill copies created by install.ps1 and the scheduled auto-pull task.
.PARAMETER Target
  Which agent's skills directory to clean. Default: claude.
#>
[CmdletBinding()]
param(
    [ValidateSet('claude')]
    [string]$Target = 'claude'
)

$ErrorActionPreference = 'Stop'
$markerName = '.orion-managed'

switch ($Target) {
    'claude' { $targetDir = Join-Path $HOME '.claude\skills' }
}

# Remove every managed copy (any folder carrying our marker)
if (Test-Path $targetDir) {
    Get-ChildItem -Path $targetDir -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if (Test-Path -LiteralPath (Join-Path $_.FullName $markerName)) {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force
            Write-Host "  -    $($_.Name)"
        }
    }
}

# Status line: the baseline copy at ~/.claude/statusline is the user's (they may
# have edited it), so it is left in place; only the settings entry pointing at
# it is removed. A pre-baseline managed copy (statusline-orion) is removed.
$legacyDest = Join-Path $HOME '.claude\statusline-orion'
if (Test-Path -LiteralPath (Join-Path $legacyDest $markerName)) {
    Remove-Item -LiteralPath $legacyDest -Recurse -Force
    Write-Host "  -    statusline-orion (old managed copy)"
}
$statusDest = Join-Path $HOME '.claude\statusline'
if (Test-Path -LiteralPath (Join-Path $statusDest '.orion-baseline')) {
    Write-Host "  =    statusline left in place (your copy of the baseline; delete $statusDest by hand if unwanted)"
}
$settingsPath = Join-Path $HOME '.claude\settings.json'
if (Test-Path $settingsPath) {
    $settings = $null
    try {
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    } catch {
        Write-Host "  !  $settingsPath is not valid JSON - leaving it untouched."
    }
    if ($null -ne $settings -and $settings.PSObject.Properties['statusLine'] -and `
        "$($settings.statusLine.command)" -match 'statusline-orion|/\.claude/statusline/statusline\.sh') {
        $settings.PSObject.Properties.Remove('statusLine')
        # WriteAllText -> UTF-8 without BOM (a BOM breaks Claude Code's JSON parse)
        [System.IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 100))
        Write-Host "statusLine setting removed from $settingsPath"
    }
}

$taskName = 'OrionSkillsAutoPull'
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Scheduled task '$taskName' removed"
}

Write-Host "Uninstall complete."
