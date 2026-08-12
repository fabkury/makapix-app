# Aseprite files: layered Open only, faithful-or-refuse

Opening an `.ase`/`.aseprite` file creates a new layered Makapix drawing through the Open
gesture (a sibling of Open `.mkpx`) — never through the flat Import-image path, and there is
no Aseprite export. Structural over-limits (canvas >256×256, >64 layers, >1024 frames) refuse
with a message naming the actual size and the cap; representational gaps degrade instead:
tilemaps rasterize to pixels, groups flatten with path-prefixed names, and the 8 blend modes
the engine lacks fall back to Normal behind a single look-changed toast — so a file either
opens true to the source or not at all, and silent misrepresentation is never on the menu.
The parser is hand-rolled clean-room in `crates/codec` from the published spec over the
already-present `miniz_oxide` (Aseprite has been proprietary source-available since 2016, so
its code may never be ported; the spec and permissively licensed references are the only
inputs), with `asefile` as a dev-dependency differential-fuzzing oracle only. We rejected
shipping `asefile` (hostile-input allocation behavior and release cadence outside our
control), downscale-on-open and layer/frame truncation (both misrepresent the artist's work),
refusing files for unsupported blend modes or tilemaps (bounces perfectly renderable art),
and implementing the missing Tier-2 blend modes as part of this feature (doubles scope,
touches the `.mkpx` format).

Decided 2026-08-12 during the Aseprite-import design grilling; full record in
`docs/aseprite-import/DESIGN.md`. Not yet implemented.
