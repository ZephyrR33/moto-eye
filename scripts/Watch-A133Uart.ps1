#requires -Version 5.1
<#
.SYNOPSIS
  Monitor A133 bootloader/kernel messages from an existing USB-UART COM port.
.DESCRIPTION
  Read-only serial monitor. Counts BOOT0 banners and highlights Android readiness.
  First BOOT0 may be a cold boot or a reboot, depending on when monitoring started.
  Any log file is LOCAL and may contain device identifiers: do not publish raw logs.
.EXAMPLE
  .\Watch-A133Uart.ps1 -Port COM6 -DurationSeconds 120
.EXAMPLE
  .\Watch-A133Uart.ps1 -Port COM6 -LogPath '.\logs\a133-serial.txt'
#>
[CmdletBinding()]
param(
    [string]$Port = 'COM6',
    [int]$BaudRate = 115200,
    [int]$DurationSeconds = 0,
    [string]$LogPath,
    [switch]$ShowAllLines
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($BaudRate -le 0 -or $DurationSeconds -lt 0) {
    throw 'BaudRate must be positive and DurationSeconds cannot be negative.'
}

$serial = [System.IO.Ports.SerialPort]::new($Port, $BaudRate, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$serial.DtrEnable = $false
$serial.RtsEnable = $false
$serial.ReadTimeout = 200
$serial.Encoding = [System.Text.Encoding]::ASCII
$writer = $null
$pending = ''
$boots = 0
$start = Get-Date

try {
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        $path = [IO.Path]::GetFullPath($LogPath)
        $dir = [IO.Path]::GetDirectoryName($path)
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $writer = [IO.StreamWriter]::new($path, $true, [Text.UTF8Encoding]::new($false))
        $writer.AutoFlush = $true
    }

    $serial.Open()
    $serial.DiscardInBuffer()
    Write-Host "UART active: $Port / $BaudRate, Ctrl+C to stop" -ForegroundColor Cyan

    while ($true) {
        if ($DurationSeconds -gt 0 -and ((Get-Date)-$start).TotalSeconds -ge $DurationSeconds) { break }
        $chunk = $serial.ReadExisting()
        if (-not [string]::IsNullOrEmpty($chunk)) {
            if ($writer) { $writer.Write($chunk) }
            $pending += $chunk

            $newline = $pending.IndexOf("`n")
            while ($newline -ge 0) {
                $line = $pending.Substring(0, $newline).TrimEnd("`r")
                $pending = $pending.Substring($newline + 1)
                if ($ShowAllLines) { Write-Host $line }

                if ($line.Contains('HELLO! BOOT0 is starting!')) {
                    $boots++
                    Write-Host ("[" + (Get-Date -Format 'HH:mm:ss') + "] BOOT0 detected (observed count=$boots)") -ForegroundColor Red
                    if ($boots -gt 1) { Write-Host 'Multiple BOOT0 banners: repeated boot confirmed.' -ForegroundColor Yellow }
                }
                if ($line.Contains('sys.boot_completed=1')) {
                    Write-Host ("[" + (Get-Date -Format 'HH:mm:ss') + '] Android reported boot_completed=1') -ForegroundColor Green
                }
                if ($line -match 'Kernel panic|watchdog|reboot: Restarting system') {
                    Write-Host ("[" + (Get-Date -Format 'HH:mm:ss') + '] ' + $line) -ForegroundColor Yellow
                }
                $newline = $pending.IndexOf("`n")
            }
            if ($pending.Length -gt 16384) {
                # Protect RAM if a corrupt UART stream has no newline for a long time.
                $pending = $pending.Substring($pending.Length - 4096)
            }
        }
        Start-Sleep -Milliseconds 50
    }
}
finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
    if ($writer) { $writer.Dispose() }
    Write-Host "Monitoring finished. BOOT0 banners: $boots" -ForegroundColor Cyan
}
