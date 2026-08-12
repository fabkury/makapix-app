# Battery measurement session (docs/battery/RECOMMENDATIONS.md, Phase 0).
#
# Snapshots the Pixel's ODPM power-rail accumulators (dumpsys android.hardware.power.stats)
# before and after a timed window, and captures the app's [battery] counter lines from
# logcat. Run one session per scenario (see README.md), phone UNPLUGGED, over Wi-Fi adb.
#
#   ./odpm_session.ps1 -Label idle-no-selection -Minutes 10 [-Device 192.168.0.42:5555]
#
# Results land in tools/battery/results/<timestamp>-<label>/ (git-ignored).
param(
    [Parameter(Mandatory = $true)][string]$Label,
    [int]$Minutes = 10,
    [string]$Device = '',
    [switch]$Force  # bypass the not-charging preflight (numbers will be unusable for power)
)

$ErrorActionPreference = 'Stop'
$adb = @('adb')
if ($Device -ne '') { $adb += @('-s', $Device) }

function Invoke-Adb { param([string[]]$AdbArgs)
    & $adb[0] @($adb[1..($adb.Count - 1)]) @AdbArgs 2>&1
}

# ---- preflight: device reachable ----
$devLine = & adb devices | Select-String -Pattern '\bdevice$'
if (-not $devLine) {
    Write-Error "No adb device connected. Pair/connect over Wi-Fi first (see README.md)."
}
if ($Device -ne '' -and -not ($devLine | Where-Object { $_ -match [regex]::Escape($Device) })) {
    Write-Error "Device '$Device' not in 'adb devices' output."
}

# ---- preflight: not charging (USB power corrupts the rail measurements) ----
$batt = Invoke-Adb @('shell', 'dumpsys', 'battery') | Out-String
$charging = ($batt -match 'USB powered: true') -or ($batt -match 'AC powered: true') -or
            ($batt -match 'Wireless powered: true')
if ($charging -and -not $Force) {
    Write-Error ("Device is charging - unplug it (use Wi-Fi adb) and re-run. " +
                 "A charging phone makes the power-rail numbers meaningless. (-Force to override.)")
}

# ---- session ----
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outDir = Join-Path $PSScriptRoot "results/$stamp-$Label"
New-Item -ItemType Directory -Force $outDir | Out-Null

Write-Host "Session '$Label': $Minutes min -> $outDir"
Invoke-Adb @('logcat', '-c') | Out-Null
Invoke-Adb @('shell', 'dumpsys', 'android.hardware.power.stats') |
    Set-Content (Join-Path $outDir 'power_before.txt')
$batt | Set-Content (Join-Path $outDir 'battery_before.txt')
$started = Get-Date

Write-Host "Recording. Perform the scenario now; do not touch the phone otherwise."
for ($m = 1; $m -le $Minutes; $m++) {
    Start-Sleep -Seconds 60
    Write-Host "  $m/$Minutes min"
}

Invoke-Adb @('shell', 'dumpsys', 'android.hardware.power.stats') |
    Set-Content (Join-Path $outDir 'power_after.txt')
Invoke-Adb @('shell', 'dumpsys', 'battery') | Set-Content (Join-Path $outDir 'battery_after.txt')
Invoke-Adb @('logcat', '-d', '-v', 'time') | Select-String -SimpleMatch '[battery]' |
    ForEach-Object { $_.Line } | Set-Content (Join-Path $outDir 'counters.txt')

@"
label:   $Label
device:  $(if ($Device -ne '') { $Device } else { 'default' })
started: $started
ended:   $(Get-Date)
minutes: $Minutes
commit:  $(git -C $PSScriptRoot rev-parse --short HEAD 2>$null)
"@ | Set-Content (Join-Path $outDir 'session.txt')

$counterLines = (Get-Content (Join-Path $outDir 'counters.txt') -ErrorAction SilentlyContinue |
    Measure-Object).Count
Write-Host "Done. $counterLines counter lines captured -> $outDir"
if ($counterLines -eq 0) {
    Write-Warning ("No [battery] lines in logcat - is the PROFILE build installed and the app " +
                   "in the foreground? (Release builds compile the counters out.)")
}
