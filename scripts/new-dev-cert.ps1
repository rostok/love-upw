<#
.SYNOPSIS
Creates a self-signed code signing certificate for sideloading test packages.

.DESCRIPTION
The certificate subject must equal the "publisher" in the game's player.json.
The PFX and the public .cer are written to .certs\ (ignored by Git).

To install a package signed with it, trust the .cer once on each test
machine (elevated PowerShell):

    Import-Certificate -FilePath .certs\<name>.cer -CertStoreLocation Cert:\LocalMachine\TrustedPeople

.EXAMPLE
scripts\new-dev-cert.ps1 -Game schifahren
#>
[CmdletBinding()]
param(
    [string]$Game,
    [string]$Publisher,
    [string]$Password = "love-uwp-dev",
    [int]$Years = 3
)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "LoveUwp.psm1") -Force

if (-not $Publisher) {
    if (-not $Game) { throw "Pass -Game or -Publisher." }
    $Publisher = (Read-PlayerJson (Resolve-GameDir $Game)).publisher
}

$certRoot = Join-Path $RepoRoot ".certs"
New-Folder $certRoot
$baseName = Get-CertFileName $Publisher
$pfxPath = Join-Path $certRoot "$baseName.pfx"
$cerPath = Join-Path $certRoot "$baseName.cer"
if (Test-Path -LiteralPath $pfxPath) {
    throw "$pfxPath already exists. Delete it first to create a new certificate."
}

# EKU 1.3.6.1.5.5.7.3.3 = code signing; basic constraints: not a CA.
$certificate = New-SelfSignedCertificate `
    -Type Custom `
    -Subject $Publisher `
    -KeyUsage DigitalSignature `
    -FriendlyName "love-uwp test signing ($Publisher)" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -NotAfter (Get-Date).AddYears($Years) `
    -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}")

try {
    $securePassword = ConvertTo-SecureString -String $Password -Force -AsPlainText
    Export-PfxCertificate -Cert $certificate -FilePath $pfxPath -Password $securePassword | Out-Null
    Export-Certificate -Cert $certificate -FilePath $cerPath | Out-Null
} finally {
    Remove-Item -LiteralPath "Cert:\CurrentUser\My\$($certificate.Thumbprint)" -Force
}

Write-Host "Created $pfxPath (password: $Password)"
Write-Host "Created $cerPath"
Write-Host ""
Write-Host "Trust it once per test machine, from an elevated PowerShell:"
Write-Host "  Import-Certificate -FilePath `"$cerPath`" -CertStoreLocation Cert:\LocalMachine\TrustedPeople"
