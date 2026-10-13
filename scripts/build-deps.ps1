<#
.SYNOPSIS
Builds the prebuilt dependencies in third_party\<arch> from the sources pinned
in third_party\deps.json.

.DESCRIPTION
Steps (sources and build trees live in deps\, ignored by Git):
  1. SDL2              CMake, WindowsStore, OpenGL ES only
  2. vcpkg libraries   FreeType, Ogg/Vorbis/Theora, OpenAL Soft, zlib
                       (overlay triplets/ports in third_party\vcpkg-*)
  3. LÖVE + LuaJIT     love-xbox-uwp with third_party\patches\love-uwp-player.patch
  4. ANGLE             depot_tools + gn + ninja (skip with -SkipAngle)
  5. copy the results to third_party\<arch>, copy licence texts, record hashes

The first ANGLE checkout is about 10 GB; plan for 30 GB of free space.

.EXAMPLE
scripts\build-deps.ps1 -Arch x86

.EXAMPLE
scripts\build-deps.ps1 -Arch x64 -SkipAngle
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet('x64', 'x86')]
    [string]$Arch,
    [switch]$SkipAngle
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LoveUwp.psm1') -Force

$config = Read-DepsConfig
$src = $config.sources
$platform = $Platforms[$Arch]
$triplet = $Triplets[$Arch]

$work = Join-Path $RepoRoot 'deps'
$out = Join-Path $work "build\$Arch"
$dirs = @{
    love       = Join-Path $work 'love-src'
    luajit     = Join-Path $work 'luajit-src'
    sdl2       = Join-Path $work 'sdl2-src'
    vcpkg      = Join-Path $work 'vcpkg'
    angle      = Join-Path $work 'angle-src'
    depotTools = Join-Path $work 'depot_tools'
}
$target = Join-Path $ThirdParty $Arch

# Git for Windows' curl: it gets through firewalls that block vcpkg.exe,
# python and the system curl (and handles broken IPv6).
$gitExe = (Get-Command git).Source
$curl = @('mingw64\bin\curl.exe', '..\mingw64\bin\curl.exe') |
    ForEach-Object { Join-Path (Split-Path (Split-Path $gitExe)) $_ } |
    Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $curl) { $curl = (Get-Command curl.exe).Source }

function Step([string]$Text) { Write-Host "`n### $Text" -ForegroundColor Cyan }

function Get-Checkout([string]$Path, $Source) {
    <# Shallow checkout of one pinned revision. Line endings are kept exactly
       as in the upstream repository so patches apply. #>
    if (-not (Test-Path -LiteralPath (Join-Path $Path '.git'))) {
        Write-Host "cloning $($Source.git) @ $($Source.rev)"
        New-Folder $Path
        Invoke-Exe git -C $Path init -q
        Invoke-Exe git -C $Path config core.autocrlf false
        Invoke-Exe git -C $Path remote add origin $Source.git
    }
    $head = (& git -C $Path rev-parse --verify -q HEAD) -as [string]
    if ($head -ne $Source.rev) {
        Invoke-Exe git -C $Path fetch -q --depth 1 origin $Source.rev
        Invoke-Exe git -C $Path checkout -q --force --detach FETCH_HEAD
    }
}

function Set-Pristine([string]$Path, [string]$PatchFile) {
    <# Brings a checkout to "upstream + PatchFile" (or plain upstream).
       A marker file remembers which patch is applied. #>
    $marker = Join-Path $Path '.love-uwp-patch'
    $wanted = if ($PatchFile) { (Get-FileHash -LiteralPath $PatchFile -Algorithm SHA256).Hash } else { 'none' }
    $current = if (Test-Path -LiteralPath $marker) { (Get-Content -Raw -LiteralPath $marker).Trim() } else { $null }
    $dirty = [bool](& git -C $Path status --porcelain --untracked-files=no)
    if ($current -eq $wanted -or (-not $dirty -and -not $PatchFile)) {
        Set-Content -LiteralPath $marker -Value $wanted
        return
    }
    if ($dirty) {
        Write-Host "resetting $Path"
        Invoke-Exe git -C $Path checkout -q --force HEAD -- .
    }
    if ($PatchFile) {
        Write-Host "applying $(Split-Path -Leaf $PatchFile)"
        Invoke-Exe git -C $Path apply --ignore-whitespace $PatchFile
    }
    Set-Content -LiteralPath $marker -Value $wanted
    $exclude = Join-Path $Path '.git\info\exclude'
    if (-not (Select-String -LiteralPath $exclude -SimpleMatch '.love-uwp-patch' -Quiet -ErrorAction SilentlyContinue)) {
        Add-Content -LiteralPath $exclude -Value '.love-uwp-patch'
    }
}

function Copy-Built([string]$From, [string]$To) {
    if (-not (Test-Path -LiteralPath $From)) { throw "build output missing: $From" }
    New-Folder (Split-Path -Parent $To)
    Copy-Item -LiteralPath $From -Destination $To -Force
}

# --- 1. SDL2 -----------------------------------------------------------------
Step "SDL2 ($Arch)"
Get-Checkout $dirs.sdl2 $src.sdl2
Set-Pristine $dirs.sdl2 $null
$sdlInstall = Join-Path $out 'sdl2-install'
Invoke-Exe cmake --fresh -S $dirs.sdl2 -B (Join-Path $out 'sdl2') -G 'Visual Studio 17 2022' -A $platform `
    '-DCMAKE_SYSTEM_NAME=WindowsStore' '-DCMAKE_SYSTEM_VERSION=10.0' "-DCMAKE_INSTALL_PREFIX=$sdlInstall" `
    '-DSDL_SHARED=ON' '-DSDL_STATIC=OFF' '-DSDL_OPENGL=OFF' '-DSDL_OPENGLES=ON' '-DSDL_VULKAN=OFF'
Invoke-Exe cmake --build (Join-Path $out 'sdl2') --config Release --target INSTALL --parallel

# --- 2. vcpkg ----------------------------------------------------------------
Step "vcpkg libraries ($triplet)"
Get-Checkout $dirs.vcpkg $src.vcpkg
$vcpkg = Join-Path $dirs.vcpkg 'vcpkg.exe'
if (-not (Test-Path -LiteralPath $vcpkg)) {
    # Fetch the tool binary the pinned vcpkg expects, then let its bootstrap verify it.
    Invoke-Exe (Join-Path $dirs.vcpkg 'bootstrap-vcpkg.bat') -disableMetrics
}
if (-not $env:X_VCPKG_ASSET_SOURCES) {
    $env:X_VCPKG_ASSET_SOURCES = "x-script,`"$curl`" -sSL --fail --retry 3 -o `"{dst}`" `"{url}`""
}
$overlays = @("--overlay-triplets=$(Join-Path $ThirdParty 'vcpkg-triplets')",
              "--overlay-ports=$(Join-Path $ThirdParty 'vcpkg-ports')")
Invoke-Exe $vcpkg install @($src.vcpkg.ports | ForEach-Object { "${_}:$triplet" }) `
    --recurse --clean-after-build "--vcpkg-root=$($dirs.vcpkg)" @overlays
$vcpkgOut = Join-Path $dirs.vcpkg "installed\$triplet"

# --- 3. LÖVE + LuaJIT ----------------------------------------------------------
Step "LÖVE + LuaJIT ($Arch)"
Get-Checkout $dirs.love $src.love
Set-Pristine $dirs.love (Join-Path $ThirdParty $src.love.patch)
Get-Checkout $dirs.luajit $src.luajit
Set-Pristine $dirs.luajit $null
$loveBuild = Join-Path $out 'love'
Invoke-Exe cmake --fresh -S $dirs.love -B $loveBuild -G 'Visual Studio 17 2022' -A $platform `
    '-DCMAKE_SYSTEM_NAME=WindowsStore' '-DCMAKE_SYSTEM_VERSION=10.0' `
    "-DCMAKE_TOOLCHAIN_FILE=$(Join-Path $dirs.vcpkg 'scripts\buildsystems\vcpkg.cmake')" `
    "-DVCPKG_TARGET_TRIPLET=$triplet" `
    "-DVCPKG_OVERLAY_TRIPLETS=$(Join-Path $ThirdParty 'vcpkg-triplets')" `
    "-DVCPKG_OVERLAY_PORTS=$(Join-Path $ThirdParty 'vcpkg-ports')" `
    "-DLOVE_UWP_SDL_ROOT=$sdlInstall" '-DLOVE_UWP_LUAJIT=ON' '-DLOVE_UWP_ANGLE=ON' `
    "-DFETCHCONTENT_SOURCE_DIR_LOVE_LUAJIT_SOURCE=$($dirs.luajit)"
Invoke-Exe cmake --build $loveBuild --config Release --parallel

# --- 4. ANGLE --------------------------------------------------------------------
$angleOut = Join-Path $dirs.angle "out\uwp-$Arch"
if (-not $SkipAngle) {
    Step "ANGLE ($Arch)"
    Get-Checkout $dirs.depotTools $src.depot_tools
    # depot_tools wants its own git wrapper; point it at Git for Windows.
    $gitBat = Join-Path $dirs.depotTools 'git.bat'
    if (-not (Test-Path -LiteralPath $gitBat)) {
        [IO.File]::WriteAllText($gitBat, "@echo off`r`n`"$gitExe`" %*`r`n", [Text.Encoding]::ASCII)
    }
    Get-Checkout $dirs.angle $src.angle
    $savedPath = $env:PATH
    try {
        $env:PATH = "$($dirs.depotTools);$savedPath"
        $env:DEPOT_TOOLS_UPDATE = '0'
        $env:DEPOT_TOOLS_WIN_TOOLCHAIN = '0'
        $gclientFile = Join-Path $dirs.angle '.gclient'
        if (-not (Test-Path -LiteralPath $gclientFile)) {
            $spec = "solutions = [{ 'name': '.', 'url': '$($src.angle.git)', 'deps_file': 'DEPS', 'managed': False }]`ntarget_os = ['winuwp']`n"
            [IO.File]::WriteAllText($gclientFile, $spec, [Text.Encoding]::ASCII)
        }
        $gn = Join-Path $dirs.angle 'buildtools\win\gn.exe'
        $ninja = Join-Path $dirs.angle 'third_party\ninja\ninja.exe'
        if (-not ((Test-Path -LiteralPath $gn) -and (Test-Path -LiteralPath $ninja))) {
            Push-Location $dirs.angle
            try { Invoke-Exe (Join-Path $dirs.depotTools 'gclient.bat') sync -D --nohooks --jobs 4 }
            finally { Pop-Location }
        }
        # The only hook output the build needs: the resource compiler, stored
        # in Google Storage under its SHA-1.
        $rc = Join-Path $dirs.angle 'build\toolchain\win\rc\win\rc.exe'
        if (-not (Test-Path -LiteralPath $rc)) {
            $sha1 = (Get-Content -Raw -LiteralPath "$rc.sha1").Trim()
            Invoke-Exe $curl -sSL --fail --retry 3 -o $rc "https://storage.googleapis.com/chromium-browser-clang/rc/$sha1"
            if ((Get-FileHash -LiteralPath $rc -Algorithm SHA1).Hash -ne $sha1.ToUpper()) { throw 'rc.exe checksum mismatch' }
        }
        $gnArgs = (@($src.angle.gnArgs) + "target_cpu = `"$Arch`"") -join ' '
        Push-Location $dirs.angle
        try { Invoke-Exe $gn gen $angleOut "--args=$gnArgs" }
        finally { Pop-Location }
        Invoke-Exe $ninja -C $angleOut libEGL libGLESv2
    } finally {
        $env:PATH = $savedPath
    }
}

# --- 5. Stage into third_party\<arch> ---------------------------------------------
Step "Staging third_party\$Arch"
$loveBin = Join-Path $loveBuild 'Release'
New-Folder (Join-Path $target 'love') -Empty
New-Folder (Join-Path $target 'sdl2') -Empty
New-Folder (Join-Path $target 'runtime') -Empty
foreach ($f in 'love.dll', 'lua51.dll') { Copy-Built (Join-Path $loveBin $f) (Join-Path $target "love\bin\$f") }
foreach ($f in 'liblove.lib', 'lovestatic.lib', 'lua51.lib') { Copy-Built (Join-Path $loveBin $f) (Join-Path $target "love\lib\$f") }
Copy-Built (Join-Path $sdlInstall 'bin\SDL2.dll') (Join-Path $target 'sdl2\bin\SDL2.dll')
Copy-Built (Join-Path $sdlInstall 'lib\SDL2.lib') (Join-Path $target 'sdl2\lib\SDL2.lib')
Copy-Item -LiteralPath (Join-Path $sdlInstall 'include\SDL2') -Destination (Join-Path $target 'sdl2\include\SDL2') -Recurse
foreach ($f in $src.vcpkg.dlls) { Copy-Built (Join-Path $vcpkgOut "bin\$f") (Join-Path $target "runtime\bin\$f") }
if (-not $SkipAngle) {
    New-Folder (Join-Path $target 'angle') -Empty
    foreach ($f in 'libEGL.dll', 'libGLESv2.dll', 'd3dcompiler_47.dll') {
        Copy-Built (Join-Path $angleOut $f) (Join-Path $target "angle\bin\$f")
    }
} elseif (-not (Test-Path -LiteralPath (Join-Path $target 'angle\bin\libGLESv2.dll'))) {
    throw "-SkipAngle, but third_party\$Arch\angle has no ANGLE build yet"
}

$licenses = Join-Path $ThirdParty 'licenses'
New-Folder $licenses
Copy-Built (Join-Path $dirs.love 'license.txt') (Join-Path $licenses 'love.txt')
Copy-Built (Join-Path $dirs.luajit 'COPYRIGHT') (Join-Path $licenses 'luajit.txt')
Copy-Built (Join-Path $dirs.sdl2 'LICENSE.txt') (Join-Path $licenses 'sdl2.txt')
if (Test-Path -LiteralPath (Join-Path $dirs.angle 'LICENSE')) {
    Copy-Built (Join-Path $dirs.angle 'LICENSE') (Join-Path $licenses 'angle.txt')
}
foreach ($port in $src.vcpkg.licenses.PSObject.Properties) {
    Copy-Built (Join-Path $vcpkgOut "share\$($port.Name)\copyright") (Join-Path $licenses $port.Value)
}

# --- Record hashes -------------------------------------------------------------------
$files = [ordered]@{}
Get-ChildItem -LiteralPath $target -Recurse -File | Sort-Object FullName | ForEach-Object {
    $rel = $_.FullName.Substring($ThirdParty.Length + 1).Replace('\', '/')
    $files[$rel] = Get-DepHash $rel
}
$record = [pscustomobject]@{
    built = (Get-Date).ToString('yyyy-MM-dd')
    angle = if ($SkipAngle) { 'kept from an earlier build' } else { "built from $($src.angle.rev)" }
    files = [pscustomobject]$files
}
if ($config.binaries.PSObject.Properties[$Arch]) {
    $config.binaries.$Arch = $record
} else {
    $config.binaries | Add-Member -NotePropertyName $Arch -NotePropertyValue $record
}
Save-DepsConfig $config
& (Join-Path $PSScriptRoot 'check-deps.ps1') -Arch $Arch
Write-Host "`nthird_party\$Arch is up to date." -ForegroundColor Green
