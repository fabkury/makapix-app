# "Protect pixels" is retired from the editor UI; the engine keeps the verb for replay

**Decided 2026-09-04.** Shell: the "Protect pixels" chip, its `_protectPixels` state, and the Wrap
chip's mutual-exclusion logic are gone from the Move tool's row 1 (`editor_page.controls.dart`,
`editor_page.dart`); the settings baseline `_pushToolSettings` (`editor_page.engine.dart`) no longer
emits `SetProtectPixels`. Engine: **unchanged in behavior** — `ToolSettings::protect_pixels`, the
`SetProtectPixels` verb, and the per-axis clamp in the four move paths (Move drag, arrow nudge, move
draft, selection-mask move) stay exactly as they are, including the same-day fix that made a
larger-than-canvas bounding box hold its axis still instead of panicking in `i32::clamp`.

Protect pixels clamped a layer or selection-mask move so no opaque pixel could leave the canvas for
the overscan gutter. It was the only edge mode besides Wrap, and the one that had just crashed the
app (commit a7f5f952). The crash was fixed first, deliberately, to make sure it was a local clamp
bug and not a symptom in the move machinery; it was local. With that settled, the mode is not worth
its row-1 slot: moving pixels off-canvas is not destructive in this editor (the gutter keeps them,
and Undo brings them back), so "protection" mostly meant a drag that stopped short of where the
finger went.

**Removal is shell-only, on purpose.** Journals recorded since 1.2.0 may carry
`SetProtectPixels(true)` followed by moves whose recorded outcome depended on the clamp. Making the
verb a no-op (the `SetSpacing` pattern) would replay those moves at full distance, and every later
frame of that timelapse would drift. Keeping the engine honoring the verb costs a few dozen tested
lines and keeps every old journal byte-identical on replay. The verb is therefore neither retired
nor aliased: it is a fully functional engine setting that the shell can no longer reach. The
engine default is off, and nothing in the app turns it on.

Consequences: the Move tool's edge modes are Wrap or Regular (pixels leaving the canvas clip off
and are recoverable from the gutter or by Undo). DSL scripts and tests may still set
`SetProtectPixels(true)`; the `visible_index` replay table keeps listing the verb as invisible.
Anyone tempted to delete the engine code later must accept replay drift for old journals first,
and say so in a new ADR. The Wrap doc-comment in `tool.rs` now describes precedence instead of
UI-enforced exclusivity: where a script sets both, Wrap wins, as it always did in the code.
