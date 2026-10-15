# orion.ps1 - Windows launcher for orion.sh (the real logic lives in orion.sh).
#
# orion needs Git for Windows: its Git Bash runs orion.sh, and git fetches updates.
# (Claude Code itself uses Git Bash for its shell on Windows, so you most likely have it.)
#
# First-time bootstrap (run inside the project, in PowerShell; a throwaway shallow clone):
#   git clone -q --depth 1 https://github.com/nachogl1/orion.git $env:TEMP\orion; & $env:TEMP\orion\orion.ps1 init; Remove-Item -Recurse -Force $env:TEMP\orion
#   (the raw-URL form 'irm .../orion.ps1 | iex' only works if the repo is public)
#
# From a clone of this repo:
#   .\orion.ps1 init [--statusline] [--force]
#   .\orion.ps1 update | check | status | uninstall
#
# Pure ASCII, Windows PowerShell 5.1 compatible.

$OrionRawBase = 'https://raw.githubusercontent.com/nachogl1/orion/main'

function Find-GitBash {
    if ($env:CLAUDE_CODE_GIT_BASH_PATH -and (Test-Path $env:CLAUDE_CODE_GIT_BASH_PATH)) { return $env:CLAUDE_CODE_GIT_BASH_PATH }
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        $root = Split-Path (Split-Path $git.Source -Parent) -Parent
        foreach ($c in @((Join-Path $root 'bin\bash.exe'), (Join-Path $root 'usr\bin\bash.exe'))) {
            if (Test-Path $c) { return $c }
        }
    }
    foreach ($c in @("$env:ProgramFiles\Git\bin\bash.exe", "${env:ProgramFiles(x86)}\Git\bin\bash.exe", "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe")) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    return $null
}

function Invoke-Orion {
    param([string[]]$OrionArgs)

    if (-not $OrionArgs -or $OrionArgs.Count -eq 0) { $OrionArgs = @('init') }

    $bash = Find-GitBash
    if (-not $bash) {
        Write-Error 'orion needs Git for Windows (Git Bash). Install it from https://git-scm.com/download/win and run this again.'
        exit 1
    }

    # Running from a checkout (orion.sh beside this file) or from `irm | iex` (download orion.sh first)?
    $script = $null
    $here = $null
    if ($MyInvocation.MyCommand.Path) { $here = Split-Path $MyInvocation.MyCommand.Path -Parent }
    if ($PSScriptRoot) { $here = $PSScriptRoot }
    if ($here -and (Test-Path (Join-Path $here 'orion.sh'))) {
        $script = Join-Path $here 'orion.sh'
    } else {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('orion-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp | Out-Null
        $script = Join-Path $tmp 'orion.sh'
        Invoke-WebRequest -UseBasicParsing -Uri "$OrionRawBase/orion.sh" -OutFile $script
    }

    # Git Bash takes Windows paths as-is; forward slashes avoid escaping surprises.
    $scriptPosix = $script -replace '\\', '/'
    & $bash $scriptPosix @OrionArgs
    exit $LASTEXITCODE
}

Invoke-Orion -OrionArgs $args
