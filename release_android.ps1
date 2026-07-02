# One-command Play Store release for the Makapix Club app (internal testing by default).
#
# Pipeline:  preflight (clean tree, on main, key present)
#          → gates (cargo test, flutter analyze, flutter test)
#          → query Play for the next free versionCode (tools/play_publish.py next-code)
#          → write version to app/pubspec.yaml
#          → build the signed prod AAB (build_android.ps1 -Bundle; prod is the default backend)
#          → upload + roll out to the track (tools/play_publish.py publish)
#          → commit the version bump, tag v<name>+<code>, push with tags
#
# One-time setup (service account + key): docs/play-release.md.
#
# Usage:  ./release_android.ps1                      # full release to internal testing
#         ./release_android.ps1 -DryRun              # preflight + gates + print the plan; no changes
#         ./release_android.ps1 -VersionName 1.1.0   # bump the user-visible version too
#         ./release_android.ps1 -SkipGates           # only when the gates just ran
param(
  [string]$Track = "internal",
  [string]$VersionName,                                   # default: keep pubspec's current versionName
  [string]$NotesFile = "distribution/whatsnew/whatsnew-en-US",
  [switch]$SkipGates,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$pubspec = "$root\app\pubspec.yaml"
$keyFile = "$root\app\android\play-service-account.json"
$aab = "$root\app\build\app\outputs\bundle\release\app-release.aab"

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# ---- Preflight -------------------------------------------------------------
Step "Preflight"
$dirty = git -C $root status --porcelain
if ($dirty) { Fail "working tree is not clean — commit or stash first:`n$dirty" }
$branch = git -C $root rev-parse --abbrev-ref HEAD
if ($branch -ne "main") { Fail "releases are cut from main (current branch: $branch)" }
if (-not (Test-Path $keyFile) -and -not $DryRun) {
  Fail "service-account key missing: $keyFile`nOne-time setup: docs/play-release.md"
}

# Current version from pubspec ("version: 1.0.1+3").
$verLine = (Get-Content $pubspec) -match '^version:' | Select-Object -First 1
if ($verLine -notmatch '^version:\s*(\S+)\+(\d+)\s*$') { Fail "cannot parse '$verLine' in app/pubspec.yaml" }
$curName = $Matches[1]; $curCode = [int]$Matches[2]
$name = if ($VersionName) { $VersionName } else { $curName }

# ---- Gates -----------------------------------------------------------------
if ($SkipGates) {
  Write-Host "    (gates skipped)" -ForegroundColor Yellow
} else {
  Step "Gate: cargo test"
  cargo test
  if ($LASTEXITCODE -ne 0) { Fail "cargo test failed" }
  Push-Location "$root\app"
  Step "Gate: flutter analyze"
  # Infos are non-fatal: they're kept at zero in dev (see `flutter analyze --fatal-infos`), but a
  # stray info (e.g. a new deprecation after a Flutter upgrade) shouldn't block a release —
  # errors and warnings still do.
  flutter analyze --no-fatal-infos
  if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "flutter analyze failed" }
  Step "Gate: flutter test"
  flutter test
  if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "flutter test failed" }
  Pop-Location
}

# ---- Next versionCode from Play --------------------------------------------
Step "Next versionCode"
if ((Test-Path $keyFile)) {
  $code = python "$root\tools\play_publish.py" next-code
  if ($LASTEXITCODE -ne 0) { Fail "could not query Play for the next versionCode" }
  $code = [int]$code
} else {
  $code = $curCode + 1   # DryRun without a key: best guess from pubspec
  Write-Host "    (no key — guessing pubspec+1; the real run queries Play)" -ForegroundColor Yellow
}
Write-Host "    releasing as $name+$code (was $curName+$curCode)"

if ($DryRun) {
  Step "DryRun — stopping before any changes"
  Write-Host "Would: write 'version: $name+$code' to app/pubspec.yaml"
  Write-Host "Would: ./build_android.ps1 -Bundle   (prod backend — the default)"
  Write-Host "Would: upload $aab to '$Track' with notes from $NotesFile"
  Write-Host "Would: commit + tag v$name+$code + push origin main --follow-tags"
  return
}

# ---- Version bump + build ---------------------------------------------------
Step "Writing version: $name+$code"
(Get-Content $pubspec) -replace '^version:\s*\S+\s*$', "version: $name+$code" | Set-Content $pubspec -Encoding utf8

Step "Building signed prod AAB"
& "$root\build_android.ps1" -Bundle
if ($LASTEXITCODE -ne 0) { Fail "AAB build failed (pubspec already bumped — fix and rerun)" }

# ---- Upload -----------------------------------------------------------------
Step "Publishing to Play ($Track)"
$notesArg = @()
if (Test-Path "$root\$NotesFile") { $notesArg = @("--notes-file", "$root\$NotesFile") }
else { Write-Host "    (no notes file at $NotesFile — releasing without notes)" -ForegroundColor Yellow }
python "$root\tools\play_publish.py" publish --aab $aab --track $Track --release-name "$name ($code)" @notesArg
if ($LASTEXITCODE -ne 0) { Fail "upload failed (pubspec already bumped — fix and rerun; versionCode is re-queried)" }

# ---- Epilogue: commit, tag, push ---------------------------------------------
Step "Committing + tagging v$name+$code"
git -C $root add app/pubspec.yaml
git -C $root commit -m "chore(release): $name+$code to Play $Track"
if ($LASTEXITCODE -ne 0) { Fail "commit failed" }
git -C $root tag -a "v$name+$code" -m "Play $Track release $name ($code)"
if ($LASTEXITCODE -ne 0) { Fail "tag failed" }
git -C $root push origin main --follow-tags
if ($LASTEXITCODE -ne 0) { Fail "push failed (release IS live on Play; push manually)" }

Step "Done: $name ($code) is rolling out to '$Track'"
