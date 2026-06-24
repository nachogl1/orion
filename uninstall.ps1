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

# Status line: remove our copy and, if the statusLine setting points at it, the setting
$statusLink = Join-Path $HOME '.claude\statusline-orion'
if (Test-Path $statusLink) {
    if (Test-Path -LiteralPath (Join-Path $statusLink $markerName)) {
        Remove-Item -LiteralPath $statusLink -Recurse -Force
        Write-Host "  -    statusline-orion"
    } else {
        Write-Host "  skip statusline-orion (not an orion copy)"
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
