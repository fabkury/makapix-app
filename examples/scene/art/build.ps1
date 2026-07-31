# Rebuilds the artistic Animator scenes from source: every drawn asset (assets-src/*.txt,
# editor DSL -> .mkpx) and then every scene (*.txt, scene DSL with @import -> .mkps), each
# verified with assert.det + assert.roundtrip. Output lands in target/art-scenes by default.
# Prereq: cargo build -p makapix-cli --release
param([string]$OutDir = (Join-Path $PSScriptRoot '..\..\..\target\art-scenes'))
$ErrorActionPreference = 'Stop'
$mkpx = Join-Path $PSScriptRoot '..\..\..\target\release\mkpx.exe'
New-Item -ItemType Directory -Force (Join-Path $OutDir 'assets') | Out-Null
Push-Location $OutDir
try {
  foreach ($f in Get-ChildItem (Join-Path $PSScriptRoot 'assets-src\*.txt')) {
    & $mkpx run $f.FullName "save:assets/$($f.BaseName).mkpx" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "asset '$($f.BaseName)' failed" }
  }
  foreach ($f in Get-ChildItem (Join-Path $PSScriptRoot '*.txt')) {
    & $mkpx scene run $f.FullName "save:$($f.BaseName).mkps" assert.det:10 assert.roundtrip | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "scene '$($f.BaseName)' failed" }
  }
  Write-Host "art scenes built into $OutDir"
} finally {
  Pop-Location
}
