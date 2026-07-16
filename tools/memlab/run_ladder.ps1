# Drives the in-app memory stress lab (lib/dev/memlab.dart) on a USB-connected Android device.
#
# Launches the app with the memlab intent extra, samples PSS (dumpsys meminfo) while it runs,
# detects LMK kills (process gone before the checkpoint says done), records the killed rung, and
# relaunches with the remaining plan so one invocation walks the whole ladder even across kills.
#
# Outputs:
#   results/android_app.csv  - one row per rung: survived/killed + engine census + vmrss/vmhwm
#   results/android_pss.csv  - PSS samples over time (total/native/graphics), ~2s cadence
#
# Usage: ./run_ladder.ps1 [-Plan auto] [-AppId club.makapix.app]
param(
    [string]$Plan = 'auto',
    [string]$AppId = 'club.makapix.app',
    [string]$OutCsv = "$PSScriptRoot\results\android_app.csv",
    [string]$PssCsv = "$PSScriptRoot\results\android_pss.csv"
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force (Split-Path $OutCsv) | Out-Null
$ckpt = "/sdcard/Android/data/$AppId/files/memlab.json"

if (-not (Test-Path $OutCsv)) {
    Set-Content $OutCsv 'rung,outcome,progress_frames,thumbs,save_bytes,save_ms,doc_bytes,total_bytes,history_bytes,history_table_bytes,vmrss,vmhwm,ms'
}
if (-not (Test-Path $PssCsv)) {
    Set-Content $PssCsv 'time,rung,pss_total_kb,native_kb,graphics_kb'
}

# The auto ladder must mirror _autoLadder in lib/dev/memlab.dart (used to compute "remaining
# rungs" after a kill).
$autoLadder = 'edit:64:4+clear+thumbs,edit:256:1,edit:256:4+clear+thumbs,edit:512:1,' +
    'edit:1024:1+clear+thumbs,edit:256:4+clear+save,edit:1024:4+clear+thumbs,' +
    'edit:1024:4+clear+save,edit:1024:8+clear,edit:1024:16+clear,edit:1024:32+clear'
$fullPlan = if ($Plan -eq 'auto') { $autoLadder } else { $Plan }

function Get-Checkpoint {
    $raw = adb exec-out cat $ckpt 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }
    try { return ($raw -join "`n") | ConvertFrom-Json } catch { return $null }
}

function Get-Pss([string]$rung) {
    $mi = adb shell dumpsys meminfo $AppId -s 2>$null
    if ($LASTEXITCODE -ne 0) { return }
    $total = 0; $native = 0; $gfx = 0
    foreach ($ln in $mi) {
        if ($ln -match 'TOTAL PSS:\s+(\d+)') { $total = [int64]$Matches[1] }
        elseif ($ln -match 'Native Heap:\s+(\d+)') { $native = [int64]$Matches[1] }
        elseif ($ln -match 'Graphics:\s+(\d+)') { $gfx = [int64]$Matches[1] }
    }
    if ($total -gt 0) {
        Add-Content $PssCsv ('{0},{1},{2},{3},{4}' -f (Get-Date -Format o), $rung, $total, $native, $gfx)
    }
}

function Add-RungRow($r, [string]$outcome, $progress) {
    $e = $r.engine
    Add-Content $OutCsv (@(
        $r.rung, $outcome, $progress, $r.thumbs, $r.save_bytes, $r.save_ms,
        $e.doc_bytes, $e.total_bytes, $e.history_bytes, $e.history_table_bytes,
        $r.vmrss, $r.vmhwm, $r.ms
    ) -join ',')
}

$recorded = @{}
$plan = $fullPlan
$round = 0
while ($true) {
    $round++
    Write-Host "== launch (round $round): $plan"
    adb shell am force-stop $AppId | Out-Null
    adb shell rm -f $ckpt | Out-Null
    adb shell am start -n "$AppId/.MainActivity" -e memlab "`"$plan`"" | Out-Null
    Start-Sleep -Seconds 3

    $attempting = ''
    while ($true) {
        $pid_ = (adb shell pidof $AppId 2>$null) -join ''
        $ck = Get-Checkpoint
        if ($ck) {
            if ($ck.attempting) { $attempting = $ck.attempting }
            foreach ($r in @($ck.results)) {
                if ($r -and -not $recorded.ContainsKey($r.rung)) {
                    $recorded[$r.rung] = $true
                    $oc = if ($r.ok) { 'survived' } else { 'error' }
                    Add-RungRow $r $oc ''
                    Write-Host ("   {0}: {1}  (rss {2:f0} MiB, peak {3:f0} MiB)" -f $r.rung, $oc, ($r.vmrss/1MB), ($r.vmhwm/1MB))
                }
            }
            if ($ck.done) { Write-Host '== ladder complete'; return }
        }
        if (-not $pid_) { break }   # process died
        Get-Pss $attempting
        Start-Sleep -Seconds 2
    }

    # Process is gone and the checkpoint is not done: `attempting` is the rung that got killed.
    $ck = Get-Checkpoint
    $victim = if ($ck -and $ck.attempting) { $ck.attempting } else { $attempting }
    $prog = if ($ck -and $ck.progress_frames) { $ck.progress_frames } else { '' }
    if (-not $victim) { Write-Host '== app died before any rung started; aborting'; return }
    Write-Host ("   {0}: KILLED (progress {1} frames)" -f $victim, $prog)
    Add-Content $OutCsv ('{0},killed,{1},,,,,,,,,,' -f $victim, $prog)
    $recorded[$victim] = $true

    # Continue with the rungs after the victim.
    $rungs = $plan -split ','
    $i = [array]::IndexOf($rungs, $victim)
    if ($i -lt 0 -or $i -ge $rungs.Count - 1) { Write-Host '== no rungs left'; return }
    $plan = ($rungs[($i + 1)..($rungs.Count - 1)] -join ',')
}
