#requires -Version 5.1
<#
.SYNOPSIS
  Save read-only Android diagnostics via ADB to a local ignored directory.
.DESCRIPTION
  Exported logs can contain serial numbers, network state and app metadata.
  Scrub before publishing. No flash writes, property changes or remote restarts.
.EXAMPLE
  .\Export-A133Diagnostics.ps1
.EXAMPLE
  .\Export-A133Diagnostics.ps1 -OutputDir '.\logs\session-01'
#>
[CmdletBinding()]
param(
    [string]$AdbPath,
    [string]$Serial,
    [string]$OutputDir = (Join-Path (Get-Location).Path ('logs\a133-' + (Get-Date -Format 'yyyyMMdd-HHmmss')))
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

$dest = [IO.Path]::GetFullPath($OutputDir)
New-Item -ItemType Directory -Path $dest -Force | Out-Null
$adbPrefix = @()
if (-not [string]::IsNullOrWhiteSpace($Serial)) { $adbPrefix += @('-s', $Serial) }

function Save-CommandOutput {
    param([string]$Name,[string[]]$AdbArgs)
    $file = Join-Path $dest $Name
    try {
        $out = & $AdbPath @adbPrefix @AdbArgs 2>&1
        $exitCode = $LASTEXITCODE
        @("Command: adb $($AdbArgs -join ' ')", "Exit code: $exitCode", '', ($out | Out-String)) |
            Out-File -LiteralPath $file -Encoding utf8
        Write-Host "$Name : $exitCode"
    }
    catch {
        "FAILED: $_" | Out-File -LiteralPath $file -Encoding utf8
        Write-Warning "$Name failed: $_"
    }
}

Save-CommandOutput 'adb-devices.txt' @('devices','-l')
Save-CommandOutput 'properties.txt' @('shell','getprop')
Save-CommandOutput 'uptime.txt' @('shell','cat','/proc/uptime')
Save-CommandOutput 'display.txt' @('shell','wm','size')
Save-CommandOutput 'display-density.txt' @('shell','wm','density')
Save-CommandOutput 'identity.txt' @('shell','id')
Save-CommandOutput 'usb-state.txt' @('shell','dumpsys','usb')
Save-CommandOutput 'packages-user.txt' @('shell','pm','list','packages','-3')
Save-CommandOutput 'kernel-dmesg.txt' @('shell','dmesg')
Save-CommandOutput 'logcat-last-300.txt' @('logcat','-d','-t','300')

@'
LOCAL EVIDENCE ONLY. Review before publishing.
Potential sensitive fields: device serial, account identifiers, MAC addresses,
network names, USB descriptors, installed app metadata, debug logs.
No data were uploaded by this script.
'@ | Out-File -LiteralPath (Join-Path $dest 'DO-NOT-PUBLISH-RAW.txt') -Encoding utf8

Write-Host "Diagnostic bundle directory: $dest" -ForegroundColor Green
