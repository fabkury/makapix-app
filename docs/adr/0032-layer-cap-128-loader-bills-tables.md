# The layer cap is 128 per frame; the loader bills tile tables and shares identical layouts

**Decided 2026-09-14.** Engine: `document::MAX_LAYERS` 64 → 128; `io::load_from_bytes_tolerant_budgeted`
refuses a file whose tile payload **plus tile-slot tables** would cross the hard budget (before the
crossing table is allocated) and gives layers with byte-identical ref-grids one shared table;
`Session::refuse_layer_cap` turns the cap no-ops of `AddLayer`, `AddLayerAt`, `DuplicateLayer` and
import-as-layer into refusals on the generic channel (`refusal_seq` / `last_refusal`, ADR 0031). Shell:
`kMaxLayers` mirrors the constant (Frames page pre-checks and the More sheet's hint), the layer-thumbnail
cache holds 160 entries instead of 60, and a refusal that is not a memory refusal toasts the engine's
reason (the Frames page keeps narrating its own on its status line). Pinned by
`io::tests::over_budget_tables_are_refused_at_load`, `io::tests::identical_layouts_share_one_table_on_load`
and `scenarios::layer_cap_refuses_with_a_reason`. Format spec caps updated (`docs/mkpx-format` §3, §12, §19,
§20); no format version bump.

The user asked for room above 64. As with the canvas (ADR 0021), the engine was already free-form up to
the cap, the `.mkpx` `layer_count` field was already `u16`, and the memory model is per-tile and per-table,
so the question was what the cap costs — analyzed before deciding, from the code and the memlab and
battery studies rather than new measurement.

**Memory holds by construction; the ceilings bite sooner.** Tile tables have been billed alongside the
payload since the memory audit (P-2/#7), so the 96 MiB history, 256/320 MiB document and 48 MiB
checkpoint budgets bound a 128-layer document exactly as they bound a 64-layer one, and the Android
~1 GiB allocator wall stays safe in-session. What changes is when the budgets bite: an empty 128-layer
frame is 2.36 MB of tables at 512² (1.18 MB at 64), so the hard budget holds about 142 such bare frames
instead of 284; a fully painted 512² frame is 128 MiB instead of 64, so the budget holds two of them
instead of five. **Budgets are kept as they are**, for the ADR 0021 reason: the refusals a 128-layer user
meets are the ones a 64-layer user meets later, already designed and tested.

**The loader gate was payload-only, and the cap was its only bound.** `load_from_bytes_budgeted` refused a
file by `tile_count × 4096` alone; the tables it then allocated — one per layer, `frames × layers` of them
— were invisible to it, and `adopt_loaded_doc` recalibrates without refusing. A crafted file of empty
layers could therefore allocate 1.2 GB of tables at 1024 × 64 × 512² (302 MB at 256², inside the fatal
~4 KiB allocator class) from a few hundred kilobytes on disk, and the raise would have doubled that. The
loader now bills tables with the payload against the same hard budget, checked before each new table is
allocated. Because a session dedupes COW-shared tables (a duplicated frame shares its predecessor's
tables until first write) while a naive loader would give every layer its own, billing alone would have
refused some documents a session had legitimately held near the budget. So the loader **shares one table
between layers whose ref-grids are byte-identical** — exactly the state `DuplicateFrame` leaves behind —
keyed by a 128-bit hash of the run list and verified by pointer comparison (a hash collision on untrusted
input would otherwise hand a layer the wrong pixels). Sharing is invisible to the writer (save → load →
save stays byte-identical) and to editing (the first write to a shared table de-shares it, as in a
session), and it makes held frames cost one table instead of one each on load.

**CPU cost doubles at the worst case and ships without new mitigation.** The compositor walks present
tiles only, so empty layers are free, but every display call re-blends every visible painted layer with
no caching: a fully painted 512² frame is 33.5 M pixel blends at 128 layers (16.8 M at 64), the HSV and
Brightness/Contrast previews iterate full storage per layer, and `state_json` still serializes every
layer of every frame after every action with a tile-table scan each (131,072 entries at the combined caps;
the memory audit's item #9, slim `state_json`, remains the remedy and is deliberately not folded in). The
SPEC §23 target restates as a 128-layer composite under 16 ms, linear in painted visible layers, still
uninstrumented.

**The cap refuses with a reason.** Adding, inserting, duplicating or importing a layer into a full frame
was a silent no-op; the generic refusal channel already existed for the Frames page, so the four paths
now register `"<Verb>: this frame already has 128 layers"` and the shell toasts it. A refusal is a pure
function of the document, so journals replay unchanged.

**Older readers refuse bigger files, and that is accepted** — the ADR 0021 doctrine, with a larger
exposure: Club layers-file attachments travel between users, so a remix source made on this version
fails as "corrupt" on an older app until it updates. A journal from a session that crossed 64 layers
replays *silently wrong* on an older engine (its `AddLayer` no-ops at 64 and `SetActiveLayer` past the
cap is ignored) rather than refusing; journals only leave a device as shared files, so this is accepted
too. Nothing else moves: the server validates the attachment by signature and size only (an opaque blob),
the website does not parse layers, the undo budgets, the AA-OFF pins and every golden are unaffected, and
Makapix Club's canvas rule stays at 256.

Consequences: README, STATUS, SPEC §12/§23, CLAUDE.md, the memlab report and the Frames and Aseprite
designs say 128; ADR 0005's ">64 layers refuses" reads as ">128" through this ADR; the three marketing
slides that read "64 LAYERS" are re-rendered (store upload rides the next release); the memlab reference
spreadsheet's per-layer columns stop at 64 (its "Any size" math applies unchanged). The Pixel pass decides
whether a 128-layer stroke needs a busy indicator; none is added here.
