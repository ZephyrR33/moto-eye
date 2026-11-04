#requires -Version 5.1
<#
.SYNOPSIS
  Capture Android's logical display using ADB and save a valid PNG on Windows.
.DESCRIPTION
  Uses adb shell screencap and adb pull; avoids Windows PowerShell 5.1 binary redirection.
.EXAMPLE
  .\Save-A133Screenshot.ps1
.EXAMPLE
  .\Save-A133Screenshot.ps1 -OutputPath 'C:\Temp\a133-screen.png'
#>
[CmdletBinding()]
param(
    [string]$AdbPath,
    [string]$Serial,
    [string]$OutputPath = 'captures\a133-screen.png'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($AdbPath)) {
    $candidate = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($candidate) { $AdbPath = $candidate.Source }
    else { $AdbPath = Join-Path $env:USERPROFILE 'AndroidTools\platform-tools\adb.exe' }
}
if (-not (Test-Path -LiteralPath $AdbPath -PathType Leaf)) {
    throw "adb.exe not found: $AdbPath"
}

$target = [IO.Path]::GetFullPath($OutputPath)
$parent = [IO.Path]::GetDirectoryName($target)
if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
}

$adbPrefix = @()
if (-not [string]::IsNullOrWhiteSpace($Serial)) { $adbPrefix += @('-s', $Serial) }
$remote = '/sdcard/moto-eye-capture.png'

& $AdbPath @adbPrefix shell screencap -p $remote
if ($LASTEXITCODE -ne 0) { throw 'screencap failed on Android.' }

& $AdbPath @adbPrefix pull $remote $target
if ($LASTEXITCODE -ne 0) { throw 'adb pull failed.' }

$file = Get-Item -LiteralPath $target -ErrorAction Stop
$stream = [IO.File]::OpenRead($target)
try {
    $header = New-Object byte[] 8
    if ($stream.Read($header, 0, 8) -ne 8) { throw 'PNG is empty or truncated.' }
    $expected = [byte[]](137,80,78,71,13,10,26,10)
    for ($i=0; $i -lt 8; $i++) {
        if ($header[$i] -ne $expected[$i]) { throw 'Downloaded file is not a valid PNG.' }
    }
}
finally { $stream.Dispose() }

Write-Host "PNG captured: $($file.FullName) ($($file.Length) bytes)" -ForegroundColor Green
