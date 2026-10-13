# Helpers shared by the love-uwp scripts.  Import-Module "$PSScriptRoot\LoveUwp.psm1"

Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ThirdParty = Join-Path $RepoRoot 'third_party'
$DepsFile = Join-Path $ThirdParty 'deps.json'

# Architecture name -> Visual Studio platform / vcpkg triplet.
$Platforms = @{ x64 = 'x64'; x86 = 'Win32'; arm64 = 'ARM64' }
$Triplets = @{ x64 = 'x64-uwp'; x86 = 'x86-uwp'; arm64 = 'arm64-uwp' }

function Invoke-Exe {
    <# Runs a native program; throws if it exits non-zero. Arguments are passed
       through untouched (no PowerShell parameter binding). #>
    if ($args.Count -eq 0) { throw 'Invoke-Exe: no program given' }
    $exe = $args[0]
    $rest = @(if ($args.Count -gt 1) { $args[1..($args.Count - 1)] })
    & $exe @rest
    if ($LASTEXITCODE -ne 0) {
        throw "'$exe $($rest -join ' ')' exited with code $LASTEXITCODE"
    }
}

function New-Folder([string]$Path, [switch]$Empty) {
    if ($Empty -and (Test-Path -LiteralPath $Path)) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Read-DepsConfig {
    Get-Content -Raw -LiteralPath $DepsFile | ConvertFrom-Json
}

function Save-DepsConfig($Config) {
    $text = ($Config | ConvertTo-Json -Depth 12) + "`r`n"
    [IO.File]::WriteAllText($DepsFile, $text, [Text.UTF8Encoding]::new($false))
}

function Get-DepHash([string]$RelativePath) {
    <# SHA-256 of a file under third_party. Headers are hashed with LF line
       endings so a checkout with core.autocrlf still matches. #>
    $full = Join-Path $ThirdParty $RelativePath
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        if ($RelativePath -like '*.h') {
            $text = [IO.File]::ReadAllText($full) -replace "`r`n", "`n"
            $digest = $sha.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($text))
        } else {
            $stream = [IO.File]::OpenRead($full)
            try { $digest = $sha.ComputeHash($stream) } finally { $stream.Dispose() }
        }
    } finally {
        $sha.Dispose()
    }
    -join ($digest | ForEach-Object { $_.ToString('x2') })
}

function Find-SdkTool([string]$Name) {
    <# Newest x64 copy of a Windows SDK tool (signtool.exe, makeappx.exe, ...). #>
    $bin = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $found = Get-ChildItem -LiteralPath $bin -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -as [version] } |
        Sort-Object { [version]$_.Name } -Descending |
        ForEach-Object { Join-Path $_.FullName "x64\$Name" } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
    if (-not $found) { throw "$Name not found in the Windows SDK ($bin)" }
    $found
}

function Find-Curl {
    <# Git for Windows' curl.exe: it gets through firewalls that block vcpkg.exe,
       python and the system curl, and falls back from broken IPv6. #>
    $gitExe = (Get-Command git -ErrorAction SilentlyContinue).Source
    if ($gitExe) {
        $gitRoot = Split-Path -Parent (Split-Path -Parent $gitExe)
        foreach ($rel in 'mingw64\bin\curl.exe', '..\mingw64\bin\curl.exe') {
            $candidate = Join-Path $gitRoot $rel
            if (Test-Path -LiteralPath $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
        }
    }
    (Get-Command curl.exe -ErrorAction Stop).Source
}

function Resolve-GameDir([string]$Game) {
    foreach ($dir in @($Game, (Join-Path $RepoRoot "games\$Game"))) {
        if ($dir -and (Test-Path -LiteralPath (Join-Path $dir 'player.json'))) {
            return (Resolve-Path -LiteralPath $dir).Path
        }
    }
    throw "Game '$Game' not found (expected games\$Game\player.json)"
}

function Read-PlayerJson([string]$GameDir) {
    Get-Content -Raw -LiteralPath (Join-Path $GameDir 'player.json') | ConvertFrom-Json
}

function Get-CertFileName([string]$Publisher) {
    <# 'CN=Foo Bar, O=Baz' -> 'Foo_Bar': file name for a test certificate. #>
    $cn = if ($Publisher -match 'CN=([^,]+)') { $Matches[1] } else { $Publisher }
    $cn.Trim() -replace '[^\w.-]', '_'
}

Export-ModuleMember -Function * -Variable RepoRoot, ThirdParty, DepsFile, Platforms, Triplets
