# Plan: Artwork persistence — autosave, crash-recovery & a local working library

> **Status:** ✅ Tier 1 landed (A+B+C+D) — built & installed on device 2026-06-28. Future: Tier 2
> (write-ahead journal) / Tier 3 (cloud drafts) remain deferred by decision.
> **Owner:** editor pillar · **Scope:** Tier 1 (A+B+C+D) from the persistence discussion.

## Goal

Users draw for hours; they must **never lose work to a crash**. The app should be "ready to
crash at any time": at any moment the on-disk copy of every drawing is at most ~10 s behind the
in-memory state, and writes can never corrupt the last good copy. On relaunch, the last drawing is
silently restored.

## Agreed decisions (from discussion)

1. **Working library** — many independent drawings, each persisted on its own.
2. **Loss tolerance ≈ 10 s** — periodic autosave at a cadence comfortably under 10 s.
3. **Local only** — no cloud drafts this round.
4. **Silent auto-restore** — relaunch reopens the last drawing with no prompt.

## Scope

- **A. Continuous atomic autosave** — debounced/periodic `.mkpx` snapshot of the current drawing,
  written atomically with a retained backup generation.
- **B. Lifecycle flush** — flush immediately when the app backgrounds (`inactive`/`paused`/`hidden`)
  and when the editor is left (dispose), because Android can kill a backgrounded app with no further
  callback.
- **C. Recovery on launch** — the current drawing is just reopened from disk; `.bak` is the
  corruption fallback.
- **D. Working library** — each drawing is a folder under app storage with its doc, backup,
  metadata and thumbnail; a gallery lists them; New / Open / Delete / Club-edit each target a
  distinct drawing so nothing is clobbered.

### Non-goals (explicitly deferred)
- No cloud/draft sync (device-loss + uninstall remain unprotected — by decision).
- No write-ahead journal / per-stroke zero-loss (10 s tolerance accepted).
- No true `fsync` durability against power-loss (see Limitations). App-crash / OS-kill **are**
  covered because the OS page cache survives process death.
- No persistence of the undo/redo stack across launches (document state only).

## Threat model → mitigation

| Failure | Covered? | How |
|---|---|---|
| Rust `panic = abort` / native crash | ✅ | Disk copy is ≤10 s old; atomic write keeps last good copy |
| Android OS-kill (backgrounded) | ✅ | Lifecycle flush on pause + periodic autosave |
| Leaving editor → Club | ✅ | Dispose flush to disk (replaces in-memory snapshot) |
| Torn write / crash mid-save | ✅ | tmp → replace → `.bak` sequence; recovery falls back to `.bak` |
| Storage full / write error | ✅ | Surface non-blocking warning, keep in-memory, retry next tick |
| Power loss / battery pull | ⚠️ best-effort | No `fsync` in `dart:io`; OS may not have flushed. Documented limitation |
| Uninstall / device loss | ❌ by decision | Would need cloud (out of scope) |

## Architecture

The engine already produces compact `.mkpx` bytes (`engine.save()`) and restores them
(`engine.load(bytes) → bool`). Persistence is therefore a **Dart-shell-only** feature — no engine
or FFI changes.

### Dirty detection (no engine change)
A periodic controller, every **~5 s** (well under the 10 s budget), does: if there has been *any*
activity since the last check, `serialize → hash → write only if the hash changed`. Serializing
RLE `.mkpx` every few seconds is negligible. Activity is a coarse flag set by `_send()` and pointer
input and cleared after a successful check; it only gates the (cheap) serialize to avoid work while
idle — the **hash** is the source of truth for "did the document actually change", so no mutation
path can be missed. Worst-case loss = one tick interval + write latency ≈ ≤6 s.

### Atomic write (cross-platform: Android = POSIX, Windows = dev)
`dart:io` `rename` overwrites atomically on POSIX but **throws on existing target on Windows**, so
use a sequence that is safe and keeps a backup on both:

```
1. write   <dir>/doc.mkpx.tmp           (writeAsBytes, flush)
2. delete  <dir>/doc.mkpx.bak           (if present)
3. rename  <dir>/doc.mkpx → doc.mkpx.bak   (if doc.mkpx present)
4. rename  <dir>/doc.mkpx.tmp → doc.mkpx
```
At every crash point at least one of `doc.mkpx` (old or new) or `doc.mkpx.bak` (old) is a complete
file. Recovery loads `doc.mkpx`, validating via `engine.load`; on failure it loads `doc.mkpx.bak`.
A single-flight guard prevents overlapping writes to the same drawing.

### On-disk layout
```
<app-documents>/makapix/drawings/
  <id>/
    doc.mkpx          # authoritative artwork
    doc.mkpx.bak      # previous generation (corruption fallback)
    doc.mkpx.tmp      # transient in-flight write
    meta.json         # { schema, id, title, createdAt, updatedAt, w, h, frameCount }
    thumb.png         # gallery thumbnail (regenerated on content writes)
```
- `id` = `dwg_<base36 microseconds>_<rand>` (no uuid dep).
- Per-drawing folder ⇒ delete = remove folder; list = scan subfolders' `meta.json`.
- Current drawing id persisted in `shared_preferences` (`editor.currentDrawingId`).

### Modules (new)
- `app/lib/editor/persistence/drawing_meta.dart` — metadata model + JSON (de)serialize. Pure.
- `app/lib/editor/persistence/drawing_store.dart` — all disk I/O: resolve paths, atomic
  write/replace, load doc bytes (+`.bak` fallback), list/create/delete/rename, read/write meta &
  thumb. **Takes its base `Directory` by injection** (so unit tests pass a temp dir; the editor
  passes `path_provider`'s dir). No UI, no engine, no FFI → unit-testable.
- `app/lib/editor/persistence/autosave_controller.dart` — owns the `Timer`, the activity flag, the
  last-saved hash, single-flight, and the lifecycle/dispose flush. Constructed with: the target
  drawing id, the `DrawingStore`, and callbacks `Uint8List Function() serialize` +
  `Uint8List? Function() thumbnail` + `DrawingMeta Function() meta`. No direct engine/UI coupling →
  unit-testable with fakes.
- `app/lib/editor/gallery/gallery_page.dart` — the "My Drawings" gallery (grid of thumb+title+date;
  New / Open / Rename / Delete).

### Editor integration
A new part file `app/lib/editor/editor_page.persistence.dart` (keep `editor_page.dart` thin):
- State: `String? _drawingId`, `AutosaveController? _autosave`.
- `initState`: resolve base dir (path_provider) → `DrawingStore`; resolve current drawing id from
  prefs. If it exists, `engine.load` its bytes; else create a fresh tracked drawing for the default
  `64×64` doc. Start the controller. Register the `WidgetsBindingObserver`.
- `didChangeAppLifecycleState`: on `inactive`/`paused`/`hidden` → `_autosave.flushNow()`.
- `dispose`: capture bytes synchronously (before `engine.dispose()`), `_autosave.flushNow()`,
  unregister observer, stop the controller. **Replaces** the `EditorSession.docSnapshot` static.
- `_send()` (and pointer begin/continue/end): call `_autosave?.markActivity()`.
- New / Open / Club-edit / Import: flush the current drawing, switch `_drawingId` (New & Club-edit
  create a new id; Open selects an existing id), then load — so each is its own file and the prior
  WIP stays in the library.

### Behaviour changes to flag
- **`EditorSession.docSnapshot` (static in-memory) is removed**; pillar-switch restore now loads
  the current drawing from disk (authoritative, and crash-safe).
- **New** no longer just resets the in-memory doc — it creates a new library drawing and switches to
  it (old WIP remains in the library).
- **"Edit in Makapix" (Club)** loads into a **new** library drawing instead of overwriting the
  current document, so it can never clobber the user's WIP. (Title seeded from the artwork.)

## Recovery flow (silent)
1. Editor opens → read `currentDrawingId` from prefs.
2. If set and the folder loads (`doc.mkpx` validates) → restore silently.
3. Else try `doc.mkpx.bak`. Else (no/last drawing gone) → start a fresh default drawing.
No prompt either way (decision #4). A clean-exit marker is **not** needed for Tier 1 because restore
is unconditional.

## Edge cases & failure handling
- **Serialize/save failure** (full disk, perms): catch, `debugPrint`, set a throttled in-editor
  warning toast ("Couldn't autosave — free up space"), keep the in-memory doc, retry next tick. The
  old `doc.mkpx` is untouched (atomic sequence), so nothing is lost on disk.
- **Single-flight**: a tick that fires while a write is in progress is skipped; the next tick saves
  the newest bytes.
- **Empty/zero-byte serialize**: never write (guard on `bytes.isNotEmpty`), keep prior file.
- **Thumbnail regen**: only on actual content writes (≤ every 5 s while drawing), small size, best
  effort (failure doesn't block the doc save).
- **Concurrent editor instances**: not possible (single pillar, single engine).
- **Very large docs (256² × many frames)**: serialize is still ms-scale; the disk write is async off
  the UI event loop. If ever a problem, the journal (Tier 2) is the escalation — out of scope now.

## Testing
- `drawing_store` unit tests (temp dir, no FFI/network — fits existing pure-unit pattern):
  create/list/load/delete/rename; atomic replace keeps `.bak`; corrupt-primary → `.bak` fallback;
  tmp left over from a "crash" is ignored/cleaned.
- `autosave_controller` unit tests with a fake store + injected serialize: writes only on change;
  single-flight; `flushNow` writes immediately; activity gating.
- `drawing_meta` round-trip JSON test.
- `flutter analyze` clean; full `flutter test` green. Editor lifecycle wiring verified by build +
  manual on device (needs FFI, not unit-testable).

## Task checklist
- [x] Add deps: `path_provider`, `path`.
- [x] `drawing_meta.dart` (+ test).
- [x] `drawing_store.dart` with injected base dir + atomic write (+ tests).
- [x] `autosave_controller.dart` (+ tests).
- [x] `editor_page.persistence.dart`: current-drawing load/save, lifecycle, dispose, activity.
- [x] Wire `_send` activity; rework New / Open / Club-edit to switch drawings (Import stays an edit).
- [x] Remove `EditorSession.docSnapshot`; route pillar-switch restore through the store.
- [x] `gallery_page.dart` + ☰-menu entry ("My Drawings").
- [x] `flutter analyze` + `flutter test` green (53 tests); build APK; install if phone on USB.
- [x] Commit in logical chunks; keep this doc updated.

## Review notes (fresh-eyes pass)

Refinements found re-reading the draft critically; folded into the design above:

1. **Storage dir:** use `getApplicationSupportDirectory()`, **not** Documents — app-private on
   Android *and* not user-visible clutter on the Windows desktop. Explicit Save/Open (file picker)
   is unchanged and still lets users put `.mkpx` anywhere.
2. **`flushNow()` ordering vs. engine lifetime:** `flushNow()` must call `serialize()`
   (= `engine.save()`) **synchronously** and capture the bytes, then do the file write `async`. So
   `dispose()` is: `flushNow()` (sync-serialize, async-write) → `stop()` (cancels the *timer* only,
   never an in-flight write) → `engine.dispose()`. The async write touches only captured bytes, so
   freeing the engine right after is safe. Lifecycle `paused` uses the same `flushNow()`.
3. **Single-flight is shared:** the dispose/lifecycle flush goes **through the controller's**
   `flushNow()` (same single-flight + same target), never a side path — no double-writer race.
4. **Change hash:** inline **FNV-1a 64-bit** over the bytes (no `crypto` dep, tiny, O(n)). Keeping a
   hash (not the previous full bytes) avoids 2× memory on large docs.
5. **Async editor init:** `initState` can't `await`, so it creates the sync default `64×64` engine
   (UI renders immediately), then an async `_initPersistence()` resolves the store + current id,
   `engine.load`s it, `setState`/redraws, and **only then** consumes any pending Club-edit (which
   creates its own new drawing). Sequencing avoids a Club-edit racing the restore.
6. **Create writes immediately:** creating a drawing does an initial `flushNow()` so the folder +
   `meta.json` + `doc.mkpx` + `thumb.png` exist at once (gallery shows it; first-5 s crash safe).
7. **Switch flow (New/Open/Club-edit):** `await` flush of the old drawing → `stop()` old controller
   → swap `_drawingId` + `engine.load`/`NewDocument` → new per-drawing controller. The old write
   targets the old folder, so no cross-talk.
8. **Thumb/meta cadence:** the **doc** is written every ~5 s on change; **thumb** regen (active→PNG)
   is heavier, so do it on `flushNow()` (leave/pause/switch/create) and throttle to ≤ once / ~30 s
   during continuous drawing. A slightly stale gallery thumbnail is fine; the doc is always current.
9. **`meta.json` is non-authoritative** (title/dates/dims) → a corrupt meta is rebuildable from the
   doc + file mtime; still written via tmp→rename for tidiness.
10. **No legacy migration:** the old `EditorSession.docSnapshot` was in-memory only (never on disk),
    so there is nothing to migrate; first launch just creates a fresh tracked drawing.

## Progress log
- **2026-06-28** — Chunk 1: deps (`path_provider`, `path`), `DrawingMeta`, `DrawingStore` (atomic
  tmp→bak→promote write, `.bak` recovery, list/create/delete/rename, thumb/meta). 13 unit tests
  green (`test/persistence_test.dart`).
- **2026-06-28** — Chunk 2: `AutosaveController` — 5 s periodic + activity-gated FNV-1a change
  detection, coalescing single-flight writer, `flushNow()` (sync-serialize then async-write for
  background/leave), non-fatal error reporting. 6 unit tests green. (Refined during integration:
  metadata is now captured synchronously too, and thumbnails moved out of the hot path — the gallery
  renders/serves them — so the async writer never touches a freed engine.)
- **2026-06-28** — Chunk 3: editor integration. `editor_page.persistence.dart` (init/restore,
  autosave wiring, drawing-identity transitions, gallery entry); `_EditorPageState` now a
  `WidgetsBindingObserver` (background flush) with dispose-flush; `_send` marks activity; New / Open
  (external) / Club-edit each open as their own library drawing (no clobber); `EditorSession`
  removed (restore is now from disk). `GalleryPage` ("My Drawings") + ☰ menu entry. `flutter
  analyze` clean (12 pre-existing infos), all 53 Dart tests green.
