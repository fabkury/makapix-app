# On-device (Android) twin of run_matrix.ps1: runs the SAME scaling matrix through the mkpx CLI
# cross-compiled for aarch64, executed on a USB-connected phone via adb — real device silicon and
# bionic allocator, no app plumbing. mem.os reads /proc/self/status (VmRSS/VmHWM) on-device.
#
# Prereqs:  cargo ndk -t arm64-v8a build -p makapix-cli --release
#           adb device connected + authorized
# Usage:    ./run_matrix_device.ps1 [-OutCsv out.csv] [-Big]
param(
    [string]$Bin = "$PSScriptRoot\..\..\target\aarch64-linux-android\release\mkpx",
    [string]$OutCsv = "$PSScriptRoot\results\android.csv",
    [string]$DeviceDir = '/data/local/tmp/memlab',
    [switch]$Big,
    [switch]$SkipGen,
    [switch]$SkipEdit,
    [switch]$SkipChurn
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force (Split-Path $OutCsv) | Out-Null

adb shell "mkdir -p $DeviceDir" | Out-Null
adb push $Bin "$DeviceDir/mkpx" | Out-Null
adb shell "chmod +x $DeviceDir/mkpx" | Out-Null

$columns = 'phase,canvas,frames,layers,refills,exit,elapsed_s,doc_bytes,doc_unique_bytes,tile_table_bytes,history_bytes,history_table_bytes,mask_bytes,total_bytes,undo_records,file_bytes,build_ms,save_ms,write_ms,load_ms,os_resident,os_peak'
if (-not (Test-Path $OutCsv)) { Set-Content -Path $OutCsv -Value $columns }

function Parse-Run([string[]]$lines) {
    $r = @{}
    foreach ($ln in $lines) {
        if ($ln -match '^# mem \{') {
            foreach ($k in 'doc_bytes','doc_unique_bytes','tile_table_bytes','history_bytes','history_table_bytes','mask_bytes','total_bytes','undo_records') {
                if ($ln -match ('"' + $k + '":(\d+)')) { $r[$k] = [int64]$Matches[1] }
            }
        } elseif ($ln -match '^# mem\.os resident_bytes=(\d+) peak_bytes=(\d+)') {
            $r['os_resident'] = [int64]$Matches[1]; $r['os_peak'] = [int64]$Matches[2]
        } elseif ($ln -match '^# gen .* build_ms=([\d.]+) save_ms=([\d.]+) write_ms=([\d.]+) file_bytes=(\d+)') {
            $r['build_ms'] = $Matches[1]; $r['save_ms'] = $Matches[2]; $r['write_ms'] = $Matches[3]; $r['file_bytes'] = [int64]$Matches[4]
        } elseif ($ln -match '^# load bytes=(\d+) ms=([\d.]+)') {
            $r['file_bytes'] = [int64]$Matches[1]; $r['load_ms'] = $Matches[2]
        }
    }
    return $r
}

function Add-Row($phase, $canvas, $frames, $layers, $refills, $exit, $elapsed, $r) {
    $vals = @($phase, $canvas, $frames, $layers, $refills, $exit, ('{0:f1}' -f $elapsed))
    foreach ($k in 'doc_bytes','doc_unique_bytes','tile_table_bytes','history_bytes','history_table_bytes','mask_bytes','total_bytes','undo_records','file_bytes','build_ms','save_ms','write_ms','load_ms','os_resident','os_peak') {
        $vals += if ($r.ContainsKey($k)) { $r[$k] } else { '' }
    }
    Add-Content -Path $OutCsv -Value ($vals -join ',')
}

function New-EditScript([int]$frames, [int]$layers, [int]$w, [int]$h, [int64]$seed) {
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("NewDocument($w,$h)")
    for ($f = 0; $f -lt $frames; $f++) {
        if ($f -gt 0) { [void]$sb.AppendLine('AddFrame()') }
        for ($l = 0; $l -lt $layers; $l++) {
            if ($l -gt 0) { [void]$sb.AppendLine('AddLayer()') }
            [void]$sb.AppendLine("FillNoise($seed)"); $seed++
        }
    }
    $sb.ToString()
}

function Invoke-Device([string]$cmd) {
    $t0 = Get-Date
    $out = adb shell $cmd 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    $elapsed = ((Get-Date) - $t0).TotalSeconds
    return @{ lines = $out; exit = $code; elapsed = $elapsed }
}

# ---- Matrix A: resting-document floor (gen + load) ----
$genPoints = @(
    @(256,1,1), @(256,1,4), @(256,1,16), @(256,1,64),
    @(256,4,4), @(256,16,4), @(256,16,16),
    @(256,64,4), @(256,64,16),
    @(256,256,1), @(256,256,4), @(256,256,16),
    @(256,1024,1), @(256,1024,4),
    @(64,256,4), @(64,1024,4)
)
if ($Big) { $genPoints += @(@(256,1024,8)) }

if (-not $SkipGen) {
    foreach ($p in $genPoints) {
        $canvas = $p[0]; $frames = $p[1]; $layers = $p[2]
        $mib = $frames * $layers * $canvas * $canvas * 4 / 1MB
        Write-Host ("gen  {0}x{0} F={1} L={2}  (~{3:f0} MiB doc)" -f $canvas, $frames, $layers, $mib)
        $file = "$DeviceDir/noise.mkpx"
        $g = Invoke-Device "$DeviceDir/mkpx gen $canvas $canvas $frames $layers 1 $file mem mem.os"
        Add-Row 'gen' $canvas $frames $layers 0 $g.exit $g.elapsed (Parse-Run $g.lines)
        if ($g.exit -eq 0) {
            $l = Invoke-Device "$DeviceDir/mkpx load $file mem mem.os"
            Add-Row 'load' $canvas $frames $layers 0 $l.exit $l.elapsed (Parse-Run $l.lines)
        }
        adb shell "rm -f $file" | Out-Null
    }
}

# ---- Matrix B: realistic editing path ----
$editPoints = @(
    @(256,16,1), @(256,64,1), @(256,128,1), @(256,256,1), @(256,512,1),
    @(256,16,16), @(256,64,4), @(256,64,8), @(256,128,4), @(256,256,4)
)

if (-not $SkipEdit) {
    foreach ($p in $editPoints) {
        $canvas = $p[0]; $frames = $p[1]; $layers = $p[2]
        Write-Host ("edit {0}x{0} F={1} L={2}" -f $canvas, $frames, $layers)
        $local = Join-Path $env:TEMP "memlab_edit.txt"
        Set-Content -Path $local -Value (New-EditScript $frames $layers $canvas $canvas 1)
        adb push $local "$DeviceDir/edit.txt" | Out-Null
        $e = Invoke-Device "$DeviceDir/mkpx run $DeviceDir/edit.txt mem mem.os"
        Add-Row 'edit' $canvas $frames $layers 0 $e.exit $e.elapsed (Parse-Run $e.lines)
    }
    adb shell "rm -f $DeviceDir/edit.txt" | Out-Null
}

# ---- Matrix C: undo churn ----
if (-not $SkipChurn) {
    foreach ($n in 16, 64, 128, 160) {
        Write-Host ("churn 256x256 refills={0}" -f $n)
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine('NewDocument(256,256)')
        for ($i = 0; $i -lt $n; $i++) { [void]$sb.AppendLine("FillNoise($($i + 1))") }
        $local = Join-Path $env:TEMP "memlab_churn.txt"
        Set-Content -Path $local -Value $sb.ToString()
        adb push $local "$DeviceDir/churn.txt" | Out-Null
        $c = Invoke-Device "$DeviceDir/mkpx run $DeviceDir/churn.txt mem mem.os"
        Add-Row 'churn' 256 1 1 $n $c.exit $c.elapsed (Parse-Run $c.lines)
    }
    adb shell "rm -f $DeviceDir/churn.txt" | Out-Null
}

Write-Host "done -> $OutCsv"
