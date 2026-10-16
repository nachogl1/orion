# orion.ps1 - Windows launcher for orion.sh (the real logic lives in orion.sh).
#
# orion needs Git for Windows: its Git Bash runs orion.sh, and git fetches updates.
# (Claude Code itself uses Git Bash for its shell on Windows, so you most likely have it.)
#
# First-time bootstrap, no clone needed (run inside the project, in PowerShell):
#   irm https://raw.githubusercontent.com/nachogl1/orion/main/orion.ps1 | iex            # = init
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/nachogl1/orion/main/orion.ps1))) init --statusline
#
# From a clone of this repo:
#   .\orion.ps1 init [--update-mode ask|auto|off] [--statusline] [--force]
#   .\orion.ps1 update | check | verify | status | uninstall
#
# Pure ASCII, Windows PowerShell 5.1 compatible.

$OrionRawBase = 'https://raw.githubusercontent.com/nachogl1/orion/main'

# Run as a script file, `exit` hands the caller a real exit code. Run through `irm | iex` or a script block,
# the code runs inside the user's own session, where `exit` would close their PowerShell window: there the
# code is only left in $LASTEXITCODE.
function Exit-Orion {
    param([int]$Code)
    if ($PSCommandPath) { exit $Code }
    $global:LASTEXITCODE = $Code
}

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
        Exit-Orion 1
        return
    }

    # Running from a checkout (orion.sh beside this file) or from `irm | iex` (download orion.sh first)?
    $script = $null
    $tmp = $null
    $here = $null
    if ($MyInvocation.MyCommand.Path) { $here = Split-Path $MyInvocation.MyCommand.Path -Parent }
    if ($PSScriptRoot) { $here = $PSScriptRoot }
    if ($here -and (Test-Path (Join-Path $here 'orion.sh'))) {
        $script = Join-Path $here 'orion.sh'
    } else {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('orion-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp | Out-Null
        $script = Join-Path $tmp 'orion.sh'
    }

    $code = 1
    try {
        if ($tmp) { Invoke-WebRequest -UseBasicParsing -Uri "$OrionRawBase/orion.sh" -OutFile $script -ErrorAction Stop }
        # Git Bash takes Windows paths as-is; forward slashes avoid escaping surprises.
        $scriptPosix = $script -replace '\\', '/'
        & $bash $scriptPosix @OrionArgs
        $code = $LASTEXITCODE
    } catch {
        Write-Error "orion failed: $($_.Exception.Message)"
    } finally {
        # the downloaded copy is needed for this one run only
        if ($tmp) { Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue }
    }
    Exit-Orion $code
}

Invoke-Orion -OrionArgs $args
