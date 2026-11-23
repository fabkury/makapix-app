# Text is shell-side fonts and a generic engine mask stamp

**Decided 2026-11-19** in a design interview (the choices are the user's). **Implemented 2026-11-23.**
Engine: `crates/engine/src/session/mask.rs` (`MaskDraft`, `MaskDraftMove`, `MaskDraftCancel`,
`MaskStamp`). Shell: `app/lib/editor/text/` and `app/lib/editor/editor_page.text.dart`; the journal
filter is `JournalRecorder._isPlaybackVerb`. Fonts: `tools/fonts/build_fonts.py` →
`app/assets/pixel_fonts/`.
Vocabulary (Text Draft, Wrap width, Font, Native size, Missing-glyph marker) is in `CONTEXT.md`;
every product decision is in `docs/text-tool/DESIGN.md`. This is inventory item B13
(`docs/editor-gaps/INVENTORY.md`), and it retires the "no text tool" non-goal.

**What.** The Text tool is split across the FFI seam so that the engine never learns what text is:

- **The shell owns fonts and layout.** Bundled bitmap Fonts ship as Flutter assets in one compact
  1-bit format. A pure-Dart layout module turns words into a 1-bit mask (advances, kerning,
  letter and line spacing, alignment, the Wrap width).
- **The engine gets a generic mask stamp.** It colors a 1-bit mask with the primary color and
  writes it through the ordinary paint path, so the selection, the Pattern gate and Symmetry
  apply as they do to a stroke.
- **The preview is not journaled; the commit is self-contained.** While a Text Draft is open the
  shell sends the mask to the engine for a true preview, and those verbs are filtered out of the
  Journal the way Play, Pause and AdvanceClock already are. The commit is one journaled verb
  that carries its own position and mask, so replay never needs the Draft that preceded it.

**Why.** Three designs were on the table.

- **Fonts inside the engine, a `Text(font, …)` verb** (the inventory's original sketch). It keeps
  the Journal self-contained, but it turns font data into a replay contract: a corrected glyph or
  an updated CJK release would change what old Journals replay, so every font version would have
  to ship forever. It also puts megabytes of font data in each ABI's engine library and adds a
  string-quoting scheme to a DSL that has none.
- **The shell draws pixels and they enter like an Import.** No engine work, but each text costs a
  chapter cut with a full snapshot, and replay loses the step.
- **Shell fonts and a mask stamp (chosen).** The Journal stays self-contained because the mask is
  inline, the way `SetPattern(w,h,hexbits)` carries its tile. Fonts can be added, fixed or
  replaced without touching a single old Journal.

The preview had to be engine-side once text was made to obey Symmetry and Patterns: only the
engine can show the mirrored copies and the pattern gaps exactly as the commit will write them.
Journaling that preview verbatim, as the other Draft families do, would write a whole mask per
keystroke for lines that are invisible in replay anyway. Hence the split between an unjournaled
preview and a self-contained commit.

**Consequences.**

- The Text Draft is a **fifth Draft family** under ADR 0011: it dies at any context change. It
  is not bound to a layer's content, so like the figure and paste families it survives a blank
  layer (ADR 0016). What makes it different is in the shell only: the Text tool remembers the
  words, so a killed Draft costs a tap, not a retyped paragraph.
- This is the first Draft whose verbs are not journaled. The filter in `JournalRecorder.record()`
  grows, dropped lines must not advance the action count or the last-event clock, and the commit
  verb must leave no trace of the Draft behind (replay will run it with no Draft open).
- The commit joins the Repeat set; that is ADR 0040.
- Text layout cannot be exercised from the `mkpx` harness. It is covered by Dart golden tests
  that need neither the engine nor the network; the mask stamp itself is covered from Rust.
- Off-canvas pixels are kept in the gutter, as Paste and Move keep them (ADR 0030), not clipped
  as paint strokes are.
