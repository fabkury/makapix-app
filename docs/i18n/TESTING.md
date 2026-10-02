# How i18n is tested

Nobody checks eight languages by hand. These layers are the acceptance test: each one exists
because there is a specific way a translated app goes wrong that nothing else would catch.

Run everything (from `app/`, one command at a time — two `flutter` commands at once deadlock):

```powershell
flutter gen-l10n                 # after editing any .arb (flutter test does NOT regenerate)
flutter analyze --fatal-infos
flutter test                     # T1–T5 and the Club sweeps; no engine, no network
cargo build -p makapix-ffi --release   # once, and after engine changes (run from the repo root)
flutter test test_engine         # the real editor, in every language
```

| Layer | Catches | Where |
|---|---|---|
| T1 String files | A missing or orphaned key, a translation with different placeholders, a plural without the language's categories (Russian needs one / few / many / other), malformed ICU, a missing translator description, generated code older than its ARB | `test/l10n/arb_integrity_test.dart` |
| T2 Hardcoded strings | UI text written straight into Dart instead of the ARB files | `tool/l10n/scan.dart`, `test/l10n/hardcoded_strings_test.dart`, `test/l10n/hardcoded_baseline.txt` |
| T3 Language choice | Wrong language for a device locale, the override not winning, the pick not surviving a restart, the picker not switching live | `test/l10n/app_locale_test.dart` |
| T4 Screen sweep | Overflow, cut-off text, and leftover English, per screen × language × screen size | `test/l10n/sweep.dart` + `sweep_*_test.dart`; editor screens in `test_engine/` |
| T5 Tool tile fit | A toolbar label wider than its 54 px tile | `test/l10n/tool_label_fit_test.dart` |
| T5b Tool tip fit | A help tip longer than the two lines the help band shows on a 360 px phone | `test/l10n/tool_tip_fit_test.dart` |
| T6 Screenshots | What only eyes catch: awkward wraps, misaligned rows, illegible small type | `screenshot()` in the harness → `app/build/l10n_shots/*.png` |
| T7 Live pass | What only the real binary shows: device-language pickup, system font fallback | Windows build, Pixel over adb (PLAN.md L4) |
| T8 Translation review | Wrong meaning, wrong register, inconsistent terms | One independent agent per language (PLAN.md L3) |

## The harness

`test/l10n/l10n_test_support.dart`:

- **Real font metrics.** `flutter_test` draws every glyph as a 1-em square, which makes Latin
  text about twice its real width and every overflow check useless. The harness loads Roboto
  from the Flutter SDK cache (the widths an Android phone lays out) and a CJK font from the
  operating system as glyph fallback (`makapixTheme(fontFamilyFallback: …)`). The CJK font must
  exist — Microsoft YaHei ships with Windows — and the tests fail loudly if none is found.
  Without it, Chinese and Japanese glyphs measure as Roboto's narrow "missing glyph" box and
  every fit check passes vacuously.
- **`pumpLocalized(tester, locale, widget, size:)`** — the app's theme and delegates, one
  language, one screen size.
- **`truncatedTexts(tester)`** — every laid-out text that ran past its last line, is wider than
  its single-line box, is taller than its box (lines squeezed into a fixed height, which the
  paragraph cuts), or wraps with one word wider than the box (a number and its unit split
  across two lines). The last one is skipped for Chinese and Japanese, where the test engine
  reports a whole sentence as one unbreakable run. Each finding says whether the text ends in
  "…" (`ellipsized`), which the large-text run accepts.
- **`clippedTexts(tester)`** — every text that a clipping ancestor cuts: it fits its own box,
  but that box sticks out of the nearest clip (a two-line label in a one-line button). A scroll
  view's edge is not a cut. Added 2026-10-02 after the screenshot review found a German crop
  label cut this way that every other check passed.
- **`leftoverLatin` / `leftoverEnglish`** — untranslated text. On Japanese, Chinese, and Russian
  screens any Latin word outside the never-translated list (brands, formats, units) is a miss.
  On Spanish, Portuguese, French, and German screens a text is a miss when it equals an English
  message whose translation differs.
- **`screenshot(tester, name)`** — a 2× PNG of the pumped screen.
- **`harness_selfcheck_test.dart`** feeds the detectors known-bad and known-good input. A
  detector that never fires proves nothing; this is what found that CJK was being measured wrong.

Sizes swept (`kSweepSizes`): 320×568, 360×740, 412×915, 800×1280, 1280×800.

**Large text.** `flutter test test/l10n/ --dart-define=L10N_TEXT_SCALE=1.3` runs every sweep
with the system font size raised (the Android "large" setting is about 1.3); so does
`flutter test test_engine` with the same flag. The sweeps pass the scale to `pumpLocalized`;
other tests measure at 1.0. At 1.3 a text ending in "…" and a long word wrapping mid-word are
accepted (the designed fallbacks for big fonts); clipped text, overflow, and controls that
cannot be reached still fail. Large-text screenshots go to `build/l10n_shots_x1.3/`. A walk
that taps a control below the fold uses `tapVisible` (scroll, pump, tap): a tap right after
`ensureVisible` hits the old position. The tool tiles are checked at 1.3× and 2× in every run
(`tool_label_fit_test.dart`).

## Sweeping a Club or shared screen

```dart
sweepScreen(
  'Settings, signed in',
  build: () => const SettingsPage(),
  overrides: () => clubOverrides(signedIn: true),
);
```

That generates 40 tests (8 languages × 5 sizes), each holding the screen to three rules: it lays
out without overflow, no text is cut off, nothing is left in English. `act:` drives the screen to
a state (open a menu, switch a tab) before the checks. Inside `act:`, call `settleOpen(tester)`
after opening a menu, sheet, or dialog and before tapping what it shows; a tap that lands on
nothing fails the test (it used to be a warning, and the sweep then checked the wrong
screen). `drain:` unmounts the screen at the end and lets time pass, for screens that poll. `club_fixtures.dart` has the fake account
and a server config with every optional feature on; fixture text that legitimately appears in
Latin script is listed in `kFixtureText`.

## Sweeping the editor

The suite under `test/` never loads the engine (a repo rule), and the editor page cannot mount
without it. `test_engine/` is a second suite that mounts the **real** `EditorPage` against the
real engine DLL (`../target/release/makapix_ffi.dll`, which the engine loader already looks
for). `editor_harness.dart` fakes `path_provider` and `shared_preferences`, waits for the first
drawing to reach disk, and tears the editor down cleanly. One mount costs about 1.5 s, so an
editor sweep mounts once per language × size and walks through the tools and sheets inside that
one test. Pages that sit behind a host interface need no engine and are swept under `test/`
like any Club screen: the Frames and Layers pages (`sweep_frames_layers_test.dart`, on the
scripted hosts in `frames_test_support.dart` / `layers_test_support.dart`) and the crop and
place pages (`sweep_import_test.dart`, which runs each case inside `tester.runAsync`
because the pages decode real images; `screenshot(..., inRunAsync: true)` there).
A sweep can pass `allowEnglish:` for texts that read the same in every language but happen
to equal an English message (the key letter "W" on the Keyboard shortcuts page).
`editor_tool_options_test.dart` is the model for the real editor: it selects every tool, switches
every chip on, and checks the options row and the help band with `within:` (the part of the
page under test, found by a `ValueKey`), collecting problems and failing once at the end with
all of them.

## The tool tile budget

The row-3 tile is 54 px wide; its label is one line of 8.5 px type, clipped. Labels are held to
**48 px measured in Roboto** (`ToolTile.labelBudget`). The 6 px under the tile width is the
reserve for platform fonts that set wider than Roboto: San Francisco on iOS, Segoe UI on
Windows, OEM fonts on Android. In CJK that is five full-width characters. A label over budget
gets a shorter wording in that language's `tool…Short` message — never a smaller font.

## The hardcoded-string scanner

`dart run tool/l10n/scan.dart --list [path]` parses `lib/` and lists string literals that look
like display text, in three tiers: `sink` (reaches `Text(`, `tooltip:`, `labelText:` …),
`prose` (several words, anywhere), `word` (one capitalized word outside a known sink — a label
held in data, or an engine name). Structurally non-UI positions are skipped (comparisons, map
keys, `debugPrint`, `throw`, preference keys, routes). A literal that stays English is marked
`// l10n-ignore: <why>`; a file of engine names is marked `// l10n-ignore-file: <why>`.

While the extraction is in progress, `hardcoded_baseline.txt` pins each file to the number it
still has. The test fails if a file gains a string, and also if it loses one without the pin
being lowered (`--write-baseline`), so the baseline is always the exact remaining work.
