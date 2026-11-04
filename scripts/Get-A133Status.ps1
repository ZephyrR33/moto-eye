#requires -Version 5.1
<#
.SYNOPSIS
  Read the current A133 / Android status over USB ADB.
.DESCRIPTION
  Read-only diagnostic commands. Does not modify system properties or partitions.
.EXAMPLE
  .\Get-A133Status.ps1
.EXAMPLE
  .\Get-A133Status.ps1 -AdbPath 'C:\Android\platform-tools\adb.exe' -Serial '<DEVICE_SERIAL>'
#>
[CmdletBinding()]
param(
    [string]$AdbPath,
    [string]$Serial
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($AdbPath)) {
    $command = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($command) {
        $AdbPath = $command.Source
    } else {
        $AdbPath = Join-Path $env:USERPROFILE 'AndroidTools\platform-tools\adb.exe'
    }
}
if (-not (Test-Path -LiteralPath $AdbPath -PathType Leaf)) {
    throw "adb.exe not found: $AdbPath. Set -AdbPath or add platform-tools to PATH."
}

function Invoke-DeviceAdb {
    param([string[]]$CommandArgs)
    $callArgs = @()
    if (-not [string]::IsNullOrWhiteSpace($Serial)) {
        $callArgs += @('-s', $Serial)
    }
    $callArgs += $CommandArgs
    $output = & $AdbPath @callArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb failed ($LASTEXITCODE): $($CommandArgs -join ' ')`n$($output -join [Environment]::NewLine)"
    }
    return (($output | Out-String).Trim())
}

Write-Host '=== USB ADB enumeration ===' -ForegroundColor Cyan
& $AdbPath devices -l
if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate adb devices.' }

$probe = @(
    @{ Name='Android ready'; Args=@('shell','getprop','sys.boot_completed') },
    @{ Name='Android version'; Args=@('shell','getprop','ro.build.version.release') },
    @{ Name='Model'; Args=@('shell','getprop','ro.product.model') },
    @{ Name='Kernel uptime'; Args=@('shell','cat','/proc/uptime') },
    @{ Name='ADB service'; Args=@('shell','getprop','init.svc.adbd') },
    @{ Name='USB mode'; Args=@('shell','getprop','sys.usb.state') },
    @{ Name='Display size'; Args=@('shell','wm','size') },
    @{ Name='Display density'; Args=@('shell','wm','density') },
    @{ Name='Shell identity'; Args=@('shell','id') }
)

$rows = foreach ($item in $probe) {
    $value = Invoke-DeviceAdb -CommandArgs $item.Args
    [PSCustomObject]@{
        Check = $item.Name
        Value = $value
    }
}
$rows | Format-List
