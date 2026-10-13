<#
.SYNOPSIS
Builds the UWP packages of one game.

.DESCRIPTION
-Game is a folder with player.json, or the name of one under games\.

For each architecture: configure build\<identity>-<arch> with CMake, build,
and take the .msix that the Visual Studio packaging step produces. Then:
  <out>\<identity>_<version>_<arch>.msix   one per architecture
  <out>\<identity>_<version>.msixbundle    all architectures
  <out>\Dependencies\<arch>\               VCLibs framework packages
  -Store  <out>\<identity>_<version>.msixupload  (unsigned, for Partner Center)
  -Sign   signs the .msix/.msixbundle and adds the public .cer

<out> is -OutDir (default: dist\<identity> in this repository). Earlier
packages of the same game in <out> are replaced; other files there stay.

The dependencies come from third_party\<arch> (committed, prebuilt). Rebuild
them from source with scripts\build-deps.ps1.

.EXAMPLE
scripts\build.ps1 -Game hello -Sign

.EXAMPLE
scripts\build.ps1 -Game C:\projects\lua\mygame\uwp -OutDir C:\projects\lua\mygame\release\uwp -Version 1.2.0 -Store
#>
param(
    [Parameter(Mandatory)][string]$Game,
    [ValidateSet('x64', 'x86', 'arm64')][string[]]$Arch,
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [switch]$Sign,
    [string]$Pfx,
    [string]$PfxPassword = 'love-uwp-dev',
    [switch]$Store,
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LoveUwp.psm1') -Force

$gameDir = Resolve-GameDir $Game
$player = Read-PlayerJson $gameDir
$gameName = $player.identityName
if (-not $Version) { $Version = if ($player.PSObject.Properties['version']) { $player.version } else { '1.0.0' } }
$fullVersion = "$Version.0"
if (-not $Arch) { $Arch = @((Read-DepsConfig).binaries.PSObject.Properties.Name) }
if (-not $Arch) { throw 'No architectures in third_party\deps.json; run scripts\build-deps.ps1 first.' }

if ($Sign) {
    if (-not $Pfx) { $Pfx = Join-Path $RepoRoot ".certs\$(Get-CertFileName $player.publisher).pfx" }
    if (-not (Test-Path -LiteralPath $Pfx)) {
        throw "No certificate $Pfx. Create one: scripts\new-dev-cert.ps1 -Game `"$Game`""
    }
    $cert = [Security.Cryptography.X509Certificates.X509Certificate2]::new($Pfx, $PfxPassword)
    if ($cert.Subject -ne $player.publisher) {
        throw "Certificate subject '$($cert.Subject)' differs from publisher '$($player.publisher)' in player.json"
    }
}

# A game can ship sources instead of a .love ("source" in player.json).
$loveOverride = ''
if ($player.PSObject.Properties['source']) {
    $sourceDir = Join-Path $gameDir $player.source
    if (-not (Test-Path -LiteralPath (Join-Path $sourceDir 'main.lua'))) { throw "No main.lua in $sourceDir" }
    New-Folder (Join-Path $RepoRoot 'build')
    $loveOverride = Join-Path $RepoRoot "build\$gameName.love"
    Remove-Item -LiteralPath $loveOverride -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($sourceDir, $loveOverride)
    Write-Host "zipped $sourceDir -> $loveOverride"
}

$dist = if ($OutDir) { [IO.Path]::GetFullPath($OutDir) } else { Join-Path $RepoRoot "dist\$gameName" }
New-Folder $dist
# Replace only this game's earlier packages: the folder may hold other files.
Get-ChildItem -LiteralPath $dist -File -Filter "$($player.identityName)_*" | Remove-Item -Force
foreach ($old in 'Dependencies', '.bundle') {
    Remove-Item -LiteralPath (Join-Path $dist $old) -Recurse -Force -ErrorAction SilentlyContinue
}
$stem = "$($player.identityName)_$fullVersion"
$toBundle = Join-Path $dist '.bundle'
New-Folder $toBundle

foreach ($a in $Arch) {
    $buildDir = Join-Path $RepoRoot "build\$gameName-$a"
    Write-Host "`n### $gameName $Version ($a)" -ForegroundColor Cyan
    Invoke-Exe cmake --fresh -S $RepoRoot -B $buildDir -G 'Visual Studio 17 2022' -A $Platforms[$a] `
        '-DCMAKE_SYSTEM_NAME=WindowsStore' '-DCMAKE_SYSTEM_VERSION=10.0' `
        "-DGAME_DIR=$gameDir" "-DGAME_VERSION=$Version" "-DGAME_LOVE_OVERRIDE=$loveOverride"
    Invoke-Exe cmake --build $buildDir --config Release --parallel

    # Visual Studio names the folder and file after its platform (Win32 for x86).
    $msix = Get-ChildItem -LiteralPath (Join-Path $buildDir 'AppPackages') -Recurse -File `
            -Filter "LovePlayer_${fullVersion}_$($Platforms[$a]).msix" |
        Sort-Object LastWriteTime | Select-Object -Last 1
    if (-not $msix) { throw "No .msix produced in $buildDir\AppPackages" }
    Copy-Item -LiteralPath $msix.FullName -Destination (Join-Path $dist "${stem}_$a.msix")
    Copy-Item -LiteralPath $msix.FullName -Destination $toBundle
    $framework = Join-Path $msix.DirectoryName "Dependencies\$a"
    if (Test-Path -LiteralPath $framework) {
        New-Folder (Join-Path $dist "Dependencies\$a")
        Copy-Item -Path (Join-Path $framework '*') -Destination (Join-Path $dist "Dependencies\$a")
    }
}

$bundle = Join-Path $dist "$stem.msixbundle"
Invoke-Exe (Find-SdkTool 'makeappx.exe') bundle /o /bv $fullVersion /d $toBundle /p $bundle
Remove-Item -LiteralPath $toBundle -Recurse -Force

if ($Store) {
    # A .msixupload is a zip holding the bundle. Made before signing: the Store
    # signs packages itself.
    $zip = Join-Path $dist "$stem.zip"
    Compress-Archive -LiteralPath $bundle -DestinationPath $zip -Force
    Move-Item -LiteralPath $zip -Destination (Join-Path $dist "$stem.msixupload") -Force
}

if ($Sign) {
    $signtool = Find-SdkTool 'signtool.exe'
    Get-ChildItem -LiteralPath $dist -File | Where-Object Extension -in '.msix', '.msixbundle' | ForEach-Object {
        Invoke-Exe $signtool sign /q /fd SHA256 /f $Pfx /p $PfxPassword $_.FullName
    }
    $cerFile = Join-Path $dist "$(Get-CertFileName $player.publisher).cer"
    [IO.File]::WriteAllBytes($cerFile, $cert.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert))
}

Write-Host "`n$dist" -ForegroundColor Green
Get-ChildItem -LiteralPath $dist -Recurse -File | ForEach-Object { "  " + $_.FullName.Substring($dist.Length + 1) }
