# Overnight burst fuzz run (see fuzz/README.md).
#
# Launch before bed; it runs 14 of 16 cores for -Hours (default 9), stops itself,
# minimizes the corpus (cargo fuzz cmin), syncs everything back into the repo, and
# leaves a morning summary at fuzz/logs/summary-<stamp>-night.md (also printed here).
# The machine is configured to never sleep on AC, so no power handling is done.
#
#   ./tools/fuzz/fuzz-night.ps1
#   ./tools/fuzz/fuzz-night.ps1 -Hours 6 -NoCmin

param(
    [int]$Workers = 14,
    [double]$Hours = 9,
    [string]$Targets = '',   # default: all five targets, weighted (below)
    [switch]$NoCmin,
    [string]$Distro = 'Ubuntu-24.04'
)

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$wslRepo = (wsl -d $Distro -- wslpath -a ($repo -replace '\\', '/')) | Select-Object -First 1
if (-not $wslRepo) { Write-Error "could not resolve the repo path inside WSL distro '$Distro'"; exit 2 }
$minutes = [int][math]::Round($Hours * 60)
# Default to all five targets, weighted toward the two engine targets (the 2026-08-28
# overnight recipe, scaled to -Hours): actions 40%, loader 30%, envelope, webp, and import 10% each.
if (-not $Targets) {
    $a = [int]($minutes * 0.40); $l = [int]($minutes * 0.30); $o = [int]($minutes * 0.10)
    $Targets = "fuzz_session_actions:$a fuzz_load_mkpx:$l fuzz_mkpx_open:$o fuzz_webp_differential:$o fuzz_codec_import:$o"
}

# Build the argument list as an explicitly-typed array. Do NOT write
# `$a = if (...) { @('--cmin') }` and splat it: an `if` returns its single-element array
# through the pipeline, which unwraps it to a STRING, and splatting a string passes it one
# character at a time (`-` `-` `c` `m` `i` `n` — run_fuzz.sh then dies on "unknown
# argument: -"). Typing the variable [string[]] keeps it an array.
[string[]]$wslArgs = @(
    '--label', 'night',
    '--workers', "$Workers",
    '--minutes', "$minutes",
    '--targets', "$Targets"
)
if (-not $NoCmin) { $wslArgs += '--cmin' }

Write-Host "Overnight fuzz: $Workers workers, $Hours h, targets: $Targets" -ForegroundColor Cyan
wsl -d $Distro -- bash "$wslRepo/tools/fuzz/run_fuzz.sh" @wslArgs
exit $LASTEXITCODE
