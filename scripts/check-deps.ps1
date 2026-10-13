<#
.SYNOPSIS
Verifies the prebuilt files in third_party\<arch> against the hashes in
third_party\deps.json. Runs automatically before every package build.

.EXAMPLE
scripts\check-deps.ps1 -Arch x86
#>
param(
    [ValidateSet('x64', 'x86', 'arm64')]
    [string[]]$Arch = @('x64', 'x86')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LoveUwp.psm1') -Force

$config = Read-DepsConfig
$bad = @()
$checked = 0
foreach ($a in $Arch) {
    $entry = $config.binaries.PSObject.Properties[$a]
    if (-not $entry) {
        throw "No $a binaries recorded in deps.json. Build them: scripts\build-deps.ps1 -Arch $a"
    }
    foreach ($file in $entry.Value.files.PSObject.Properties) {
        $checked++
        $path = Join-Path $ThirdParty $file.Name
        if (-not (Test-Path -LiteralPath $path)) {
            $bad += "missing  $($file.Name)"
        } elseif ((Get-DepHash $file.Name) -ne $file.Value) {
            $bad += "changed  $($file.Name)"
        }
    }
}
if ($bad) {
    $bad | ForEach-Object { Write-Host $_ }
    throw "$($bad.Count) of $checked dependency files do not match deps.json"
}
Write-Host "Dependencies OK ($($Arch -join ', '), $checked files)"
