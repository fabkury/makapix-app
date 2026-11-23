# The Text tool — design

**Decided 2026-11-19** in a research session and a design interview (every decision below is the
user's unless marked as an assumption). **Implemented 2026-11-23** (see "As built"). Doctrine: ADR 0039 (shell fonts and
an engine mask stamp) and ADR 0040 (text is repeatable). Vocabulary: `CONTEXT.md`, "Text
vocabulary". Inventory item B13.

The artist picks a Font, taps or drags on the canvas, types into a real text field, and sees a
Text Draft on the canvas. Commit turns it into ordinary pixels. There are no text layers and
nothing in `.mkpx` changes.

## As built (2026-11-23)

Where the implementation differs from, or adds to, the decisions below. None of these was put
to the user as a question; each is flagged so it can be reversed.

- **Glyph data is 3.1 MB, not the 2 MB estimated** (VEXED 0.7 MB with its kerning tables, Fusion
  Pixel 2.4 MB). It is compressed inside the APK and the IPA.
- **No Journal epoch bump** (ADR 0040 explains why none is needed).
- **A line is measured by its ink**, not by its last glyph's advance, so right-aligned and
  centered text is flush with the box edge instead of one side bearing short of it.
- **A tap marks the left edge of the first line, level with the middle of its capitals**, so the
  words appear beside the finger. A dragged box starts exactly at the drag's top-left corner.
- **The preview is exact**, with no "draft" wash: tiny text has to stay readable. The box outline
  (dashed while it follows the text, solid with a Wrap width) is what marks it as a Draft.
- **The pattern follows the existing per-tool On/Off rule** (ADR 0025): the Text tool has its own
  switch, Off until the artist turns it on, so a pattern left on for the Brush does not gate
  text. Symmetry stays one global setting, as it is for every mirroring tool.
- **While the on-screen keyboard is up, the palette, the tool grid and the help band give their
  room to it**; the frame strip, the layer strip, the options row and the text field stay. The
  swap happens at the moment the keyboard is exactly as tall as those strips, so the canvas only
  shrinks and grows smoothly with the keyboard. (First build, fixed 2026-11-23 after the user's
  report: every strip was hidden while the Draft was open and returned the instant it closed, so
  on commit the canvas was squeezed to a sliver until the keyboard finished leaving.) On a short
  screen, where the canvas would be left under 180 px, the frame and layer strips step aside too.
- **On a hidden or locked layer** the Draft still shows what is typed (painted plainly over the
  canvas), and a commit is refused with a message; the Draft stays open.
- **A commit with no ink** (empty text, only spaces, or only missing characters) closes the Draft
  and stamps nothing.
- **The Missing-glyph markers are a shell overlay**: they are not mirrored under symmetry.
- **The words are remembered for the app session**, including across a switch to Club and back;
  they are not saved to disk.
- **Shortcut:** Shift+A selects the tool (T and Shift+T were taken).
- **Korean:** the app has no Korean translation, so the first font is never a Korean one; the
  picker lists the Korean form under each CJK size like the other three.
- **Limits:** 2,000 characters; a mask side of 1,536 px (larger ink is cut).
- **Tests:** `crates/engine/src/session/mask.rs` (the stamp), `app/test/text_layout_test.dart`
  (fonts and layout against the real assets), `app/test_engine/editor_text_tool_test.dart` (the
  tool on the real editor, including "one commit, one journal line").
- **Not yet done:** a pass on a phone for the keyboard behavior and IME composition (the largest
  risk below), and the store release notes.

## Fonts

- **Native size only.** Every Font is drawn at its one pixel height, 1-bit, never anti-aliased.
  There is no size control; the artist resizes the committed pixels with the Resize tool.
- **Western: the VEXED pack, regular fonts only.** 59 Fonts, 4 to 28 px tall. Extras (Cutout,
  Monospaced, Bold, More Letter Gap and so on) are not shipped. `Party_Pack_Normal` stands for
  Party Pack; Enter Input (keycap pictures) is left out.
- **CJK: Fusion Pixel Font at 8, 10 and 12 px.** Each size appears as four Fonts, one per language
  form: 日本語, 简体中文, 繁體中文, 한국어. Hong Kong and Taiwan forms collapse into Traditional.
  Named in the picker and the credits as "Fusion Pixel 12 · 日本語".
- **About 71 picker rows in all.**

### Measured facts

- VEXED exports at 128 font units per pixel. Every regular font has all outline points on the
  pixel grid and no curves, so conversion to 1-bit bitmaps is lossless.
- The 60 regular TTFs are 28.5 MB. As packed 1-bit glyphs they are 304 KB (97 KB deflated) for
  13,258 glyphs, plus about 34,000 kerning pairs across 34 of the fonts.
- All have ASCII and Western European accents. 25 of 60 also have Cyrillic. None has Greek,
  Vietnamese or CJK.
- Fusion Pixel 12 px has 38,213 characters; every size has all 6,355 JIS kanji and all 11,172
  Hangul syllables. Estimated cost of the three sizes in four language forms, stored as a base
  plus deltas: about 2 MB (an estimate, not measured).

### Licenses

- **VEXED: CC BY 4.0.** The converted data is committed to this repository (user decision; asking
  VEXED first and keeping the fonts out of the repo were both declined). Credit in the app and in
  the repo: "Fonts by VEXED (v3x3d.itch.io), CC BY 4.0, converted to bitmap data".
- **Fusion Pixel: SIL OFL 1.1, no Reserved Font Name.** The license text ships in the app's
  licenses page. Its Korean glyphs come from Galmuri, whose author states that parts of it are not
  original designs; accepted.
- **Source TTF and BDF files stay out of the repo.** Only the converted data and the conversion
  script are committed.
- Paid CJK fonts were examined and rejected: Zpix is $1,000 per product, has no Korean, and forbids
  conversion.

### The font picker

- Sorted by height, smallest first.
- Each row is drawn in the Font's own glyphs and shows the artist's current text (the Font's name
  when the field is empty), with its height in px.
- A strip of recently used Fonts on top; filter chips for Latin, Cyrillic and CJK.
- Fonts that cannot draw the current text sink to the bottom, dimmed.
- First use: Everyday Standard (6 px, has Cyrillic), or Fusion Pixel 12 in 日本語 or 简体中文 when
  the app runs in Japanese or Chinese.
- The last used Font, alignment and spacing are remembered across launches. The words are not.

## Starting and shaping a Text Draft

- **A tap** starts a Text Draft at that point; it grows as the artist types.
- **A drag** starts one with a Wrap width. A drag of only a few screen pixels counts as a tap.
- **The Wrap width constrains width only.** Lines break at it and the Draft grows downward;
  nothing is ever hidden.
- A handle on the Draft's edge changes the Wrap width. A "Wrap" chip in the options row removes or
  restores it.
- Lines break at spaces, anywhere between CJK characters, and inside a word only when the word is
  wider than the Wrap width.
- There is one kind of Text Draft, with or without a Wrap width. No separate nouns.

## Typing

- **A real text field docked above the keyboard** (in the options area on desktop). The system
  owns the caret, selection, paste and IME composition. The Draft on the canvas updates as the
  field changes.
- **Enter is a new line on every platform.** On desktop, Ctrl/Cmd+Enter commits and Esc cancels.
- Closing the keyboard keeps the Draft open for positioning.
- A check button beside the field commits; the usual Commit/Cancel pill works too.
- Text length is capped at about 2,000 characters, and the mask at the storage size.

## While a Text Draft is open

- **A one-finger drag moves it** (the Slow chip gears the drag, ADR 0020). Dragging the handle
  changes the Wrap width.
- **A tap on the canvas does nothing.** Nothing on the canvas commits or relocates the Draft by
  accident. (A tap that re-places the Draft was offered and declined.)
- Two-finger pan and zoom keep working.
- Changing the primary color recolors the Draft live.
- Options row: Font, alignment (left, center, right), letter spacing, line spacing, the Wrap chip,
  and the shared Pattern, Mirror and Slow controls. Kerning from the Font is always applied; there
  is no kerning toggle.

## Characters the Font cannot draw

- The Draft shows a **Missing-glyph marker** (a hollow box). There is no substitution from another
  Font: one text is always one Font at its Native size.
- **Commit drops the markers.** Real glyphs are drawn and a blank advance is left where a marker
  was; the box never becomes pixels. The Commit control shows an amber dot while markers exist.

## Commit

- Lands on the **active layer**. A Text Draft survives adding a blank layer and commits onto it
  (ADR 0016), which is the way to put text on its own layer.
- Uses the **primary color**.
- Obeys the **selection, the Pattern gate and Symmetry**, like a stroke. Mirrored copies read
  backwards; that was chosen knowingly over "selection only".
- **Off-canvas pixels are kept** in the gutter, as Paste and Move keep them.
- One undo step. One journal line (ADR 0039). In Watch replay the text appears in one step.
- **Repeatable** (ADR 0040): the mask, position and color are snapshotted; the target, selection,
  Symmetry and Pattern are live.

## Lifecycle

- A Text Draft dies at any context change, like every Draft (ADR 0011).
- **The Text tool remembers the words** until the app closes. After a killed Draft, and equally
  after a successful commit, the next Text Draft starts with the same words, fully selected:
  typing replaces them, committing again stamps them again. A clear button empties the field.

## The tool tile

Shown by default for new and existing users. It can be hidden like any tool (ADR 0018).

## Not in the first version

Each was offered and declined for v1:

- Re-editing text after commit (by design: there are no text layers).
- Font scaling, bold and italic variants.
- Stamping one text onto a frame set (Repeat, or a fresh layer plus the Layers page's "copy to
  frames", covers it).
- Loading the artist's own font files.
- Vertical CJK text, right-to-left scripts, emoji.

## Implementation outline (as planned; "As built" above is the record)

1. **Font pipeline** in `tools/fonts/`: VEXED TTFs and Fusion BDFs to one compact binary format
   plus a manifest (name, height, scripts, credit), written to Flutter assets.
2. **Dart layout module**: words to a 1-bit mask. Pure Dart, golden-tested without the engine.
3. **Engine**: the mask Draft verbs (set, move, cancel; not journaled) and the self-contained
   stamp verb, generically named, on the existing `plot` path; a `RepeatOp` variant.
4. **Shell**: the tool tile, options row, docked field, on-canvas Draft with its handle, the font
   picker, and the journal filter.
5. **Housekeeping**: strings in all eight ARBs, the credits and licenses entries, and striking
   "text tool" from the SPEC non-goals.

## Risks named in the interview

- **Mobile text entry** is the largest design risk: the keyboard covers half the screen, canvases
  can be smaller than one glyph, and IME composition has intermediate states.
- **Row crowding**: the options row carries up to eight controls.
- **A long commit line**: a mask near the storage size is hundreds of kilobytes of hex in one
  journal line. A tight bounding box keeps ordinary text to a few kilobytes.
- **CC BY gray areas** (app-store DRM against the "no technological measures" clause; no explicit
  carve-out for artwork made with the fonts) were noted and accepted without asking VEXED.
