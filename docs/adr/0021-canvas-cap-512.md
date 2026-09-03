# The canvas cap is 512×512; the byte budgets, not the cap, bound memory

**Decided 2026-09-03.** Engine: `geom::MAX_DIM` 256 → 512 and `io::MAX_SEL_BYTES` derived from it
(1536² storage plane). Shell: `Engine.minDim` / `Engine.maxDim` in `app/lib/engine_ffi.dart`, used by
the New-document and Resize-canvas dialogs (512² preset chip added) and the share gate in
`app/lib/share/image_share.dart`. Pinned by `io::tests::roundtrips_a_max_canvas_with_a_bits_selection`.
Format spec caps updated (`docs/mkpx-format`, §3/§5/§19/§20); no format version bump.

Users asked for room above 256. The engine was already free-form up to the cap, every `.mkpx` wire
field for a dimension was already `u16`, and the memory model is tile-based, so the question was only
what the cap costs — measured headlessly with a temporary `MAX_DIM = 512` before deciding.

**Memory is area-linear, so the existing budgets hold.** A 512² document with the same tile count as
a 256² one is byte-identical in the engine census, in the save transient, and in load time. The
96 MiB history, 256/320 MiB document, and 48 MiB checkpoint budgets (the memlab enforcement work of
2026-07) are byte budgets, so the Android ~1 GiB allocator wall stays safe by construction.
What changes is *when* they bite: a full 512² frame-layer is 1 MiB instead of 256 KiB, so the hard
document budget holds 320 painted frame-layers instead of 1,280, and full-canvas undo depth falls
from the 128 count cap to about 47 records (the byte budget takes over). **Budgets are kept as they
are** rather than re-tuned or made size-dependent: the ceilings a 512 user meets are the same
refusals a 256 user meets four times later, already designed and tested.

**CPU is the other cost, and it ships without new feedback.** Per-pixel tools scale with area:
full-layer Scale (cleanEdge) went ~83 → ~385 ms and Rotate ~26 → ~108 ms on the workstation, about a
second on a phone. Brush, fill, undo, composite, thumbnails, save and load stay in the low
milliseconds per byte. No busy indicator is added in this change; the device pass decides whether
one is needed.

**Older readers refuse bigger files, and that is accepted.** The loader gate follows `MAX_DIM`, so
every shipped app version rejects a >256 file as `Corrupt("canvas size out of range")`, and journals
from 512 sessions do not replay there. Files at or under 256 are byte-identical under both readers
(a cap loosening is not a format version bump — spec §20). Local drawings only leave the device as
shared `.mkpx`, so exposure is small; no version gate or header flag was added.

**Makapix Club publishing stays at 256.** The server hard-codes `MAX_CANVAS_SIZE = 256`, and
`ClubSizeRules` mirrors it. A 512 artwork gets the existing "scale to fit" suggestion in the publish
flow; the editor is deliberately not limited to publishable sizes (same stance as the small-size
whitelist). Raising the Club limit is a separate, cross-repo decision.

Consequences: the memlab reference spreadsheet's per-size sheets stop at 256 (the ¼ rule and a
measured table are in `docs/memlab/REPORT.md`); the 24-hash AA-OFF pins and every golden are
unaffected because nothing changes for documents at or under 256; the fit zoom for 512 on a phone
drops below 1 px per pixel, where the nearest-neighbor painter shimmers on non-integer zoom (the
0.25 zoom floor already allowed it).
