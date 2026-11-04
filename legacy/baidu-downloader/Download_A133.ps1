#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

# BaiduPCS-Go v4.0.2, Windows PowerShell 5.1
# Download all files in the account's /REVB-A133资料 folder.
# Uses existing BaiduPCS-Go login; no password or cookies are requested/stored.

$exe = Join-Path $env:USERPROFILE 'Desktop\BaiduPCS-Go.exe'
$remoteRoot = '/REVB-A133资料'
$destRoot = 'E:\BaiduNetdiskDownload\REVB-A133资料'
$logFolder = 'E:\BaiduNetdiskDownload\_A133_downloader_logs'

try {
    [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(936)
    [Console]::InputEncoding = [Text.Encoding]::GetEncoding(936)
    $OutputEncoding = [Text.Encoding]::GetEncoding(936)
    & cmd.exe /c 'chcp 936 > nul'
} catch {
    Write-Host 'Cannot switch console to code page 936; Chinese names may display incorrectly.' -ForegroundColor Yellow
}
Remove-Item Env:BAIDUPCS_GO_VERBOSE -ErrorAction SilentlyContinue

if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    Write-Host "BaiduPCS-Go.exe was not found at $exe" -ForegroundColor Red
    Write-Host 'Copy BaiduPCS-Go.exe to your Desktop, then run the launcher again.'
    exit 1
}
if (-not (Test-Path -LiteralPath 'E:\')) {
    Write-Host 'Drive E: is unavailable. Connect the drive and run again.' -ForegroundColor Red
    exit 1
}
New-Item -ItemType Directory -Path $destRoot -Force | Out-Null
New-Item -ItemType Directory -Path $logFolder -Force | Out-Null

function Read-RemoteDirectory([string] $remote) {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $result = (& $script:exe ls $remote 2>&1 | Out-String -Width 8192)
        # Both markers are printed for a successful directory listing.
        if ($result -match '当前目录\s*:' -and $result -match '总\s*:') {
            return $result
        }
        Write-Host "Could not list directory (attempt $attempt/3): $remote" -ForegroundColor Yellow
        Start-Sleep -Seconds 3
    }
    throw "Failed to list $remote. Check BaiduPCS-Go login with the 'who' command."
}

function Parse-ApproxSize([string] $s) {
    if ($s -notmatch '^([\d.]+)\s*(B|KB|MB|GB|TB)$') { return [double]::NaN }
    $n = [double]::Parse($matches[1], [Globalization.CultureInfo]::InvariantCulture)
    $scale = switch ($matches[2]) {
        'B' { 1 } 'KB' { 1024 } 'MB' { 1048576 }
        'GB' { 1073741824 } 'TB' { 1099511627776 }
    }
    return $n * $scale
}

function Is-Complete([string] $path, [string] $sizeLabel) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    $actual = (Get-Item -LiteralPath $path).Length
    $approx = Parse-ApproxSize $sizeLabel
    if ([double]::IsNaN($approx)) { return $false }
    if ($sizeLabel -match '^([\d.]+)(B|KB|MB|GB|TB)$') {
        $unit = switch ($matches[2]) {
            'B' { 1 } 'KB' { 1024 } 'MB' { 1048576 }
            'GB' { 1073741824 } 'TB' { 1099511627776 }
        }
        # ls rounds to 2 decimals. This accounts for rounding, not missing data.
        $tolerance = if ($unit -eq 1) { 0 } else { [math]::Max(1, [math]::Ceiling(0.006 * $unit)) }
        return ([math]::Abs($actual - $approx) -le $tolerance)
    }
    return $false
}

Write-Host 'MOTO EYE / A133 - automated Baidu folder downloader' -ForegroundColor Cyan
Write-Host "Source: $remoteRoot"
Write-Host "Destination: $destRoot"
Write-Host 'Only one file at a time; no SVIP or third-party site.'
Write-Host ''

# Enumerate all nested directories, including those containing only other directories.
$pending = New-Object 'System.Collections.Generic.Stack[object]'
$pending.Push([pscustomobject]@{Remote = $remoteRoot; Relative = ''})
$items = New-Object 'System.Collections.Generic.List[object]'
$folders = 0
while ($pending.Count -gt 0) {
    $dir = $pending.Pop()
    $folders++
    Write-Host "Scanning folder $folders : $($dir.Remote)"
    $listing = Read-RemoteDirectory $dir.Remote
    foreach ($line in ($listing -split "`r?`n")) {
        # Example: 0   481.38MB  2026-11-01 10:36:27  file.zip
        if ($line -notmatch '^\s*\d+\s+(\S+)\s+\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\s+(.+?)\s*$') { continue }
        $size = $matches[1]
        $name = $matches[2]
        if ($name.EndsWith('/')) {
            $name = $name.TrimEnd('/')
            $nextRelative = if ($dir.Relative) { "$($dir.Relative)/$name" } else { $name }
            $pending.Push([pscustomobject]@{Remote = "$($dir.Remote)/$name"; Relative = $nextRelative})
        } else {
            $items.Add([pscustomobject]@{
                Remote = "$($dir.Remote)/$name"
                Relative = $dir.Relative
                Name = $name
                SizeLabel = $size
            })
        }
    }
}

if ($items.Count -eq 0) {
    Write-Host 'No files discovered. Nothing has been downloaded.' -ForegroundColor Red
    exit 2
}
$manifest = Join-Path $logFolder 'manifest.tsv'
$items | Select-Object Remote,Relative,Name,SizeLabel | Export-Csv -Delimiter "`t" -NoTypeInformation -Encoding UTF8 -Path $manifest
Write-Host "Found $($items.Count) files in $folders folders." -ForegroundColor Cyan
Write-Host "Manifest: $manifest"

$completed = 0
$skipped = 0
$failed = New-Object 'System.Collections.Generic.List[string]'
$number = 0
foreach ($item in $items) {
    $number++
    $dir = $destRoot
    if ($item.Relative) {
        $dir = Join-Path $destRoot ($item.Relative -replace '/', '\')
    }
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $localFile = Join-Path $dir $item.Name
    if (Is-Complete $localFile $item.SizeLabel) {
        $skipped++
        Write-Host "[$number/$($items.Count)] Already complete: $($item.Name)" -ForegroundColor DarkGreen
        continue
    }
    $success = $false
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Write-Host "[$number/$($items.Count)] Download ($attempt/3): $($item.Remote)" -ForegroundColor Cyan
        & $exe download $item.Remote --saveto ($dir -replace '\', '/') -p 1 --retry 4
        if (Is-Complete $localFile $item.SizeLabel) {
            $success = $true
            $completed++
            break
        }
        Write-Host "File not complete yet; will retry. Expected about $($item.SizeLabel)." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
    if (-not $success) {
        $failed.Add($item.Remote)
        Write-Host "FAILED after 3 tries: $($item.Remote)" -ForegroundColor Red
    }
}

$failedPath = Join-Path $logFolder 'failed.txt'
if ($failed.Count) {
    $failed | Set-Content -Encoding UTF8 -Path $failedPath
} elseif (Test-Path $failedPath) {
    Remove-Item $failedPath
}
Write-Host ''
Write-Host "FINISHED: $completed downloaded; $skipped already complete; $($failed.Count) failed." -ForegroundColor Cyan
Write-Host "Files: $destRoot"
if ($failed.Count) {
    Write-Host "Failed-file list: $failedPath" -ForegroundColor Yellow
    Write-Host 'You can launch this again; completed files will be skipped.'
}
