# The Journal is plain text with side-by-side .mkpx chapter bases

A drawing's Journal is an append-only UTF-8 file of verbatim, delta-timestamped DSL lines,
organized as Chapters: each chapter replays from an empty canvas or from an immutable base
`.mkpx` snapshot stored beside the journal in the drawing's directory, and **any** non-DSL
mutation (image import, Club remix, open-from-bytes, re-anchor) closes the chapter and captures
a post-mutation base. We rejected embedding base bytes inside the journal (binary framing ends
plain-text appends and trivial truncation — both load-bearing: crash repair is
trim-to-last-matching-marker), referencing the live autosave (rewritten every 5 s, so the
referenced base stops existing almost immediately), and recording imports as replayable events
with their source images (that pins bit-exact decode behavior across `image`-crate upgrades
forever — a determinism promise the codec never made). With chapter bases, replay determinism
rests only on `.mkpx` bytes and the engine's already-guaranteed DSL replay; text keeps the
parser's never-rename compatibility story (legacy aliases) as the journal's forward-compat
story for free.

Decided 2026-08-11 during the replay design grilling; costs and measurements in
`docs/replay/ANALYSIS.md`.
