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
    [string]$Targets = '',   # default: all five targets, weighted (below)
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

# Explicitly-typed array, splatted — see the note in fuzz-night.ps1 about why a string
# must never be splatted into a native command.
[string[]]$wslArgs = @(
    '--label', 'day',
    '--workers', "$Workers",
    '--minutes', "$minutes",
    '--targets', "$Targets"
)

Write-Host "Daytime fuzz: $Workers workers, $Hours h, targets: $Targets" -ForegroundColor Cyan
wsl -d $Distro -- bash "$wslRepo/tools/fuzz/run_fuzz.sh" @wslArgs
exit $LASTEXITCODE
