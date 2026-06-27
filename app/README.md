# makapix_club

The Flutter shell for the **Makapix Club** app — the two-pillar native client (Rust engine + Flutter)
for the `makapix.club` pixel-art social network. See the repo root [`README.md`](../README.md),
[`CLAUDE.md`](../CLAUDE.md), [`SPEC.md`](../SPEC.md) (editor engine), and [`SPEC-CLUB.md`](../SPEC-CLUB.md)
(social layer) for the full picture.

## Structure (`lib/`)

- `main.dart` — thin Flutter entry point.
- `app.dart` — the neutral root `MaterialApp`.
- `shell/` — `app_shell.dart`, the two-pillar shell (Club + Editor) hosting both in a keep-alive
  `IndexedStack`; opens on Club, with the editor one ⊕ tap away (no login required).
- `editor/` — the **Makapix Editor** pillar (animated pixel-art editor) over the Rust engine via FFI.
- `club/` — the **Makapix Club** social layer (Dart-only): `api/ auth/ models/ state/ publish/ edit/ ui/ config/`.
- `engine_ffi.dart` — the `dart:ffi` wrapper around the Rust engine DLL/`.so`.

## Build & run

From the repo root: `./build.ps1 -Run` (Windows) or `./build_android.ps1 -Install` (Android).
Tests: `flutter test`; lint: `flutter analyze`.
