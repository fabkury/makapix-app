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
    [string]$Targets = 'fuzz_load_mkpx fuzz_session_actions',
    [switch]$NoCmin,
    [string]$Distro = 'Ubuntu-24.04'
)

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$wslRepo = (wsl -d $Distro -- wslpath -a ($repo -replace '\\', '/')) | Select-Object -First 1
if (-not $wslRepo) { Write-Error "could not resolve the repo path inside WSL distro '$Distro'"; exit 2 }
$minutes = [int][math]::Round($Hours * 60)

$cminArg = if ($NoCmin) { @() } else { @('--cmin') }
Write-Host "Overnight fuzz: $Workers workers, $Hours h, targets: $Targets" -ForegroundColor Cyan
wsl -d $Distro -- bash "$wslRepo/tools/fuzz/run_fuzz.sh" `
    --label night --workers $Workers --minutes $minutes --targets "$Targets" @cminArg
exit $LASTEXITCODE
