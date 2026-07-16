# Memory-limit scaling matrix for the Makapix engine (see docs/memlab/REPORT.md).
#
# Runs the mkpx CLI over a grid of (frames x layers) documents whose every layer is FULL RANDOM
# NOISE (incompressible: defeats tile sparsity, COW dedup, .mkpx RLE/dict and DEFLATE), and records
# engine-accounted memory (mem probe) against OS truth (mem.os probe) into a CSV.
#
# Phases per point:
#   gen   - direct document construction (no undo history) + .mkpx save/write: the resting-doc
#           floor; its os_peak captures the save transient.
#   load  - fresh process loads the .mkpx: resting doc + load transient in os_peak.
#   edit  - the realistic path: scripted AddFrame/AddLayer/FillNoise; undo history retention
#           (history_table_bytes grows O(frames^2 x layers)) shows up here.
#   churn - N successive FillNoise on one layer: per-frame undo cap (128) retention of noise
#           generations.
#
# Usage: ./run_matrix.ps1 [-Exe path\to\mkpx.exe] [-WorkDir tempdir] [-OutCsv out.csv] [-Big]
param(
    [string]$Exe = "$PSScriptRoot\..\..\target\release\mkpx.exe",
    [string]$WorkDir = "$env:TEMP\mkpx-memlab",
    [string]$OutCsv = "$PSScriptRoot\results\windows.csv",
    [switch]$Big,          # add the 2-4 GiB doc points (needs ~16 GB free RAM)
    [switch]$SkipGen,
    [switch]$SkipEdit,
    [switch]$SkipChurn
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $WorkDir | Out-Null
New-Item -ItemType Directory -Force (Split-Path $OutCsv) | Out-Null

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

function Invoke-Point([string[]]$mkpxArgs) {
    $t0 = Get-Date
    $out = & $Exe @mkpxArgs 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    $elapsed = ((Get-Date) - $t0).TotalSeconds
    return @{ lines = $out; exit = $code; elapsed = $elapsed }
}

# ---- Matrix A: resting-document floor (gen + load) ----
# doc MiB at 256x256 = frames*layers/4
$genPoints = @(
    @(256,1,1), @(256,1,4), @(256,1,16), @(256,1,64),
    @(256,4,4), @(256,16,4), @(256,16,16),
    @(256,64,4), @(256,64,16),
    @(256,256,1), @(256,256,4), @(256,256,16),
    @(256,1024,1), @(256,1024,4),
    @(64,256,4), @(64,1024,4)          # small-canvas linearity spot checks
)
if ($Big) { $genPoints += @(@(256,1024,8), @(256,1024,16)) }

if (-not $SkipGen) {
    foreach ($p in $genPoints) {
        $canvas = $p[0]; $frames = $p[1]; $layers = $p[2]
        $mib = $frames * $layers * $canvas * $canvas * 4 / 1MB
        Write-Host ("gen  {0}x{0} F={1} L={2}  (~{3:f0} MiB doc)" -f $canvas, $frames, $layers, $mib)
        $file = Join-Path $WorkDir "noise_${canvas}_${frames}x${layers}.mkpx"
        $g = Invoke-Point @('gen', $canvas, $canvas, $frames, $layers, '1', $file, 'mem', 'mem.os')
        Add-Row 'gen' $canvas $frames $layers 0 $g.exit $g.elapsed (Parse-Run $g.lines)
        if ($g.exit -eq 0 -and (Test-Path $file)) {
            $l = Invoke-Point @('load', $file, 'mem', 'mem.os')
            Add-Row 'load' $canvas $frames $layers 0 $l.exit $l.elapsed (Parse-Run $l.lines)
        }
        Remove-Item -Force $file -ErrorAction SilentlyContinue
    }
}

# ---- Matrix B: realistic editing path (scripted, undo history retained) ----
$editPoints = @(
    @(256,16,1), @(256,64,1), @(256,128,1), @(256,256,1), @(256,512,1),
    @(256,16,16), @(256,64,4), @(256,64,8), @(256,128,4), @(256,256,4)
)

if (-not $SkipEdit) {
    foreach ($p in $editPoints) {
        $canvas = $p[0]; $frames = $p[1]; $layers = $p[2]
        Write-Host ("edit {0}x{0} F={1} L={2}" -f $canvas, $frames, $layers)
        $script = Join-Path $WorkDir "edit_${frames}x${layers}.txt"
        Set-Content -Path $script -Value (New-EditScript $frames $layers $canvas $canvas 1)
        $e = Invoke-Point @('run', $script, 'mem', 'mem.os')
        Add-Row 'edit' $canvas $frames $layers 0 $e.exit $e.elapsed (Parse-Run $e.lines)
        Remove-Item -Force $script -ErrorAction SilentlyContinue
    }
}

# ---- Matrix C: undo churn (N refills of one layer; per-frame cap = 128) ----
if (-not $SkipChurn) {
    foreach ($n in 16, 64, 128, 160) {
        Write-Host ("churn 256x256 refills={0}" -f $n)
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine('NewDocument(256,256)')
        for ($i = 0; $i -lt $n; $i++) { [void]$sb.AppendLine("FillNoise($($i + 1))") }
        $script = Join-Path $WorkDir "churn_$n.txt"
        Set-Content -Path $script -Value $sb.ToString()
        $c = Invoke-Point @('run', $script, 'mem', 'mem.os')
        Add-Row 'churn' 256 1 1 $n $c.exit $c.elapsed (Parse-Run $c.lines)
        Remove-Item -Force $script -ErrorAction SilentlyContinue
    }
}

Write-Host "done -> $OutCsv"
