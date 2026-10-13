<#
.SYNOPSIS
Drives an Xbox in Dev Mode through its Device Portal REST API.

.DESCRIPTION
  info                          console type and OS
  apps [filter]                 installed packages (name, family, full name)
  install <file.msix>           upload and install; dependencies are taken from
                                <file folder>\Dependencies\x64\*.appx (or -Dependencies)
  uninstall <identity>          remove the package (also deletes its LocalState)
  launch <identity>             start the app
  stop <identity>               stop the app
  ps [filter]                   processes (CPU, private working set)
  perf                          console CPU, memory, GPU load
  screenshot [file.png]         capture the screen (default: xbox-screenshot.png)
  files <identity> [path]       list files under LocalAppData\<package>\<path> (default \LocalState)
  pull <identity> <path> [dir]  download a file (path relative to the package's LocalAppData,
                                e.g. \LocalState\picolove\schifahren.log)

<identity> is the identityName from player.json (e.g. Rostok.Schifahren).
The console address comes from -Device or the LOVE_UWP_XBOX environment
variable. Device Portal uses a self-signed certificate; it is not verified.
If Device Portal authentication is enabled, pass -User and -Password.

Requests go through Git for Windows' curl.exe (works behind restrictive
firewalls; Windows PowerShell 5.1 cannot skip certificate checks).

.EXAMPLE
scripts\xbox.ps1 -Device 192.168.0.229 install C:\games\mygame\release\uwp\MyCompany.MyGame_1.0.0.0_x64.msix

.EXAMPLE
$env:LOVE_UWP_XBOX = '192.168.0.229'; scripts\xbox.ps1 launch MyCompany.MyGame
#>
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('info', 'apps', 'install', 'uninstall', 'launch', 'stop', 'ps', 'perf', 'screenshot', 'files', 'pull')]
    [string]$Command,
    [Parameter(Position = 1)][string]$Arg1,
    [Parameter(Position = 2)][string]$Arg2,
    [Parameter(Position = 3)][string]$Arg3,
    [string]$Device = $env:LOVE_UWP_XBOX,
    [string[]]$Dependencies,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LoveUwp.psm1') -Force

if (-not $Device) { throw 'Pass -Device <address> or set LOVE_UWP_XBOX.' }
$base = if ($Device -match '^https?://') { $Device.TrimEnd('/') } else { "https://${Device}:11443" }
$curl = Find-Curl
$jar = Join-Path ([IO.Path]::GetTempPath()) "love-uwp-xbox-$($Device -replace '[^\w.-]', '_').cookies"

function Invoke-Portal {
    <# Calls the API; returns the response body as text. Writes to -OutFile instead when given. #>
    param(
        [string]$Method = 'GET',
        [Parameter(Mandatory)][string]$Path,
        [string[]]$Extra = @(),
        [string]$OutFile
    )
    $curlArgs = @('-sk', '--max-time', '600', '-X', $Method, '-c', $jar, '-b', $jar, '-w', '\n%{http_code}')
    if ($User) { $curlArgs += @('--anyauth', '-u', "${User}:$Password") }
    if ($Method -ne 'GET') {
        # Device Portal wants the CSRF token from its cookie on every change.
        if (-not (Test-Path -LiteralPath $jar)) { [void](Invoke-Portal -Path '/api/os/info') }
        $token = (Get-Content -LiteralPath $jar | Where-Object { $_ -match '\tCSRF-Token\t' } |
            Select-Object -Last 1) -replace '.*\t', ''
        $curlArgs += @('-H', "X-CSRF-Token: $token")
        if ($Extra -notcontains '-F') { $curlArgs += @('-H', 'Content-Length: 0') }
    }
    if ($OutFile) { $curlArgs += @('-o', $OutFile) }
    $raw = & $curl @curlArgs @Extra "$base$Path"
    if ($LASTEXITCODE -ne 0) { throw "curl failed ($LASTEXITCODE) for $Method $Path" }
    $lines = @($raw)
    $status = [int]$lines[-1]
    $body = ($lines[0..([Math]::Max(0, $lines.Count - 2))] -join "`n")
    if ($lines.Count -eq 1) { $body = '' }
    if ($status -ge 400) { throw "$Method $Path -> HTTP $status $body" }
    return $body
}

function ConvertFrom-PortalJson([string]$Text) {
    if (-not $Text) { return $null }
    $Text.TrimStart([char]0xFEFF) | ConvertFrom-Json
}

function To-Base64([string]$Text) { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text)) }
function To-Query([string]$Text) { [Uri]::EscapeDataString($Text) }

function Get-Package([string]$Identity) {
    if (-not $Identity) { throw 'Pass the package identity (identityName from player.json).' }
    $packages = (ConvertFrom-PortalJson (Invoke-Portal -Path '/api/app/packagemanager/packages')).InstalledPackages
    $match = @($packages | Where-Object {
        $_.PackageFamilyName -eq $Identity -or $_.PackageFullName -eq $Identity -or
        $_.PackageFullName -like "${Identity}_*" })
    if ($match.Count -eq 0) { throw "No installed package '$Identity'." }
    $match[0]
}

switch ($Command) {
    'info' {
        (ConvertFrom-PortalJson (Invoke-Portal -Path '/ext/xbox/info')) |
            Select-Object ConsoleType, OsVersion, DevMode | Format-List
    }
    'apps' {
        (ConvertFrom-PortalJson (Invoke-Portal -Path '/api/app/packagemanager/packages')).InstalledPackages |
            Where-Object { -not $Arg1 -or $_.PackageFullName -like "*$Arg1*" -or $_.Name -like "*$Arg1*" } |
            Select-Object Name, PackageFamilyName, PackageFullName | Format-Table -AutoSize
    }
    'install' {
        $file = (Resolve-Path -LiteralPath $Arg1).Path
        if (-not $Dependencies) {
            $Dependencies = @(Get-ChildItem -Path (Join-Path (Split-Path $file) 'Dependencies\x64') -Filter *.appx -ErrorAction SilentlyContinue |
                ForEach-Object FullName)
        }
        $form = @('-F', "$(Split-Path -Leaf $file)=@$file")
        foreach ($dep in $Dependencies) { $form += @('-F', "$(Split-Path -Leaf $dep)=@$dep") }
        Write-Host "uploading $(Split-Path -Leaf $file) + $($Dependencies.Count) dependencies..."
        [void](Invoke-Portal -Method POST -Path "/api/app/packagemanager/package?package=$(To-Query (Split-Path -Leaf $file))" -Extra $form)
        # 204 while the installation runs, 200 when it has finished.
        for ($i = 0; $i -lt 300; $i++) {
            Start-Sleep -Seconds 2
            $state = & $curl -sk -o NUL -w '%{http_code}' -c $jar -b $jar "$base/api/app/packagemanager/state"
            if ($state -ne '204') { break }
        }
        $result = Invoke-Portal -Path '/api/app/packagemanager/state'
        if ($result) { Write-Host $result }
        Write-Host 'installed'
    }
    'uninstall' {
        $pkg = Get-Package $Arg1
        [void](Invoke-Portal -Method DELETE -Path "/api/app/packagemanager/package?package=$(To-Query $pkg.PackageFullName)")
        Write-Host "removed $($pkg.PackageFullName)"
    }
    'launch' {
        $pkg = Get-Package $Arg1
        [void](Invoke-Portal -Method POST -Path "/api/taskmanager/app?appid=$(To-Query (To-Base64 $pkg.PackageRelativeId))&package=$(To-Query (To-Base64 $pkg.PackageFullName))")
        Write-Host "launched $($pkg.PackageRelativeId)"
    }
    'stop' {
        $pkg = Get-Package $Arg1
        [void](Invoke-Portal -Method DELETE -Path "/api/taskmanager/app?package=$(To-Query (To-Base64 $pkg.PackageFullName))")
        Write-Host "stopped $($pkg.PackageFullName)"
    }
    'ps' {
        (ConvertFrom-PortalJson (Invoke-Portal -Path '/api/resourcemanager/processes')).Processes |
            Where-Object { -not $Arg1 -or $_.ImageName -like "*$Arg1*" } |
            Sort-Object PrivateWorkingSet -Descending |
            Select-Object ImageName, ProcessId, CPUUsage,
                @{ n = 'PrivateMB'; e = { [int]($_.PrivateWorkingSet / 1MB) } },
                @{ n = 'WorkingSetMB'; e = { [int]($_.WorkingSetSize / 1MB) } } |
            Format-Table -AutoSize
    }
    'perf' {
        $p = ConvertFrom-PortalJson (Invoke-Portal -Path '/api/resourcemanager/systemperf')
        $gpu = $p.GPUData.AvailableAdapters | Select-Object -First 1
        [pscustomobject]@{
            CpuLoadPercent = $p.CpuLoad
            MemoryUsedMB   = [int](($p.TotalPages - $p.AvailablePages) * $p.PageSize / 1MB)
            MemoryTotalMB  = [int]($p.TotalPages * $p.PageSize / 1MB)
            GpuEngine0     = $gpu.EnginesUtilization[0]
            GpuMemoryMB    = [int]($gpu.DedicatedMemoryUsed / 1MB)
        } | Format-List
    }
    'screenshot' {
        $out = if ($Arg1) { $Arg1 } else { 'xbox-screenshot.png' }
        [void](Invoke-Portal -Path '/ext/screenshot?download=false&hdr=false' -OutFile $out)
        Write-Host "saved $((Resolve-Path -LiteralPath $out).Path)"
    }
    'files' {
        $pkg = Get-Package $Arg1
        $path = if ($Arg2) { $Arg2 } else { '\LocalState' }
        (ConvertFrom-PortalJson (Invoke-Portal -Path "/api/filesystem/apps/files?knownfolderid=LocalAppData&packagefullname=$(To-Query $pkg.PackageFullName)&path=$(To-Query $path)")).Items |
            Select-Object Name, @{ n = 'Size'; e = { $_.FileSize } }, @{ n = 'Folder'; e = { [bool]($_.Type -band 16) } } |
            Format-Table -AutoSize
    }
    'pull' {
        $pkg = Get-Package $Arg1
        $remote = $Arg2 -replace '/', '\'
        $folder = Split-Path -Parent $remote
        $name = Split-Path -Leaf $remote
        $dir = if ($Arg3) { $Arg3 } else { '.' }
        New-Folder $dir
        $out = Join-Path $dir $name
        [void](Invoke-Portal -Path "/api/filesystem/apps/file?knownfolderid=LocalAppData&packagefullname=$(To-Query $pkg.PackageFullName)&path=$(To-Query $folder)&filename=$(To-Query $name)" -OutFile $out)
        Write-Host "saved $((Resolve-Path -LiteralPath $out).Path)"
    }
}
