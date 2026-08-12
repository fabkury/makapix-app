# Battery measurement session (docs/battery/RECOMMENDATIONS.md, Phase 0).
#
# Whole-phone energy per scenario window via the fuel gauge's charge counter
# (/sys/class/power_supply/battery/charge_counter, uAh) plus a batterystats reset/dump for
# per-app attribution, plus the app's [battery] counter lines from logcat. (The Pixel's raw
# ODPM rail accumulators are not readable via dumpsys on this build - powerstats dumps only
# the channel catalog - so the fuel gauge is the ground truth here; Perfetto's android.power
# datasource is the upgrade path if per-rail numbers are ever needed.)
# Run one session per scenario (see README.md), phone UNPLUGGED, over Wi-Fi adb.
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
Invoke-Adb @('shell', 'dumpsys', 'batterystats', '--reset') | Out-Null
$chargeBefore = (Invoke-Adb @('shell', 'cat', '/sys/class/power_supply/battery/charge_counter') |
    Out-String).Trim()
$voltBefore = (Invoke-Adb @('shell', 'cat', '/sys/class/power_supply/battery/voltage_now') |
    Out-String).Trim()
"charge_counter_uAh: $chargeBefore`nvoltage_now_uV: $voltBefore" |
    Set-Content (Join-Path $outDir 'power_before.txt')
$batt | Set-Content (Join-Path $outDir 'battery_before.txt')
$started = Get-Date

Write-Host "Recording. Perform the scenario now; do not touch the phone otherwise."
for ($m = 1; $m -le $Minutes; $m++) {
    Start-Sleep -Seconds 60
    Write-Host "  $m/$Minutes min"
}

$chargeAfter = (Invoke-Adb @('shell', 'cat', '/sys/class/power_supply/battery/charge_counter') |
    Out-String).Trim()
$voltAfter = (Invoke-Adb @('shell', 'cat', '/sys/class/power_supply/battery/voltage_now') |
    Out-String).Trim()
"charge_counter_uAh: $chargeAfter`nvoltage_now_uV: $voltAfter" |
    Set-Content (Join-Path $outDir 'power_after.txt')
Invoke-Adb @('shell', 'dumpsys', 'battery') | Set-Content (Join-Path $outDir 'battery_after.txt')
Invoke-Adb @('shell', 'dumpsys', 'batterystats') | Set-Content (Join-Path $outDir 'batterystats.txt')
Invoke-Adb @('logcat', '-d', '-v', 'time') | Select-String -SimpleMatch '[battery]' |
    ForEach-Object { $_.Line } | Set-Content (Join-Path $outDir 'counters.txt')

if ($chargeBefore -match '^\d+$' -and $chargeAfter -match '^\d+$') {
    $deltaUah = [long]$chargeBefore - [long]$chargeAfter
    $hours = $Minutes / 60.0
    $avgV = (([long]$voltBefore + [long]$voltAfter) / 2.0) / 1e6
    $avgMw = [math]::Round(($deltaUah / 1000.0) / $hours * $avgV, 0)
    Write-Host ("Drain: {0} uAh over {1} min at ~{2:N2} V  =>  ~{3} mW average" -f
        $deltaUah, $Minutes, $avgV, $avgMw)
}

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
