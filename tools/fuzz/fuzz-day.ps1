# Daytime companion fuzz run (see fuzz/README.md).
#
# Tuned to coexist with document reading and light browsing on this machine: 8 of 16
# cores, every worker at nice 19 inside WSL. Runs for -Hours (default 4) and stops
# itself; Ctrl+C also works — the WSL runner traps it and still syncs the corpus,
# artifacts, and a summary back into the repo.
#
#   ./tools/fuzz/fuzz-day.ps1                 # both targets, 8 workers, 4 h
#   ./tools/fuzz/fuzz-day.ps1 -Hours 2 -Targets fuzz_load_mkpx

param(
    [int]$Workers = 8,
    [double]$Hours = 4,
    [string]$Targets = 'fuzz_load_mkpx fuzz_session_actions',
    [string]$Distro = 'Ubuntu-24.04'
)

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$wslRepo = (wsl -d $Distro -- wslpath -a ($repo -replace '\\', '/')) | Select-Object -First 1
if (-not $wslRepo) { Write-Error "could not resolve the repo path inside WSL distro '$Distro'"; exit 2 }
$minutes = [int][math]::Round($Hours * 60)

Write-Host "Daytime fuzz: $Workers workers, $Hours h, targets: $Targets" -ForegroundColor Cyan
wsl -d $Distro -- bash "$wslRepo/tools/fuzz/run_fuzz.sh" `
    --label day --workers $Workers --minutes $minutes --targets "$Targets"
exit $LASTEXITCODE
