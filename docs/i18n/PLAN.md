# i18n work plan and live tracker

**Read this first when resuming.** It says where the work stands, what is next, and how to do one
unit of work. The decisions are in [DESIGN.md](DESIGN.md), the test layers in
[TESTING.md](TESTING.md), the terminology in [GLOSSARY.md](GLOSSARY.md).

Started 2026-10-01. Update the status table and the session log at the end of every session.

## Goal

The whole app in eight languages: English, Spanish, Portuguese (pt-BR), French, German, Russian,
Japanese, Simplified Chinese. The language follows the device by default; the user can pick
another in Settings → Language. Nobody tests this by hand: the automated layers in TESTING.md
are the acceptance test.

## Where things stand

| Phase | What | Status |
|---|---|---|
| L0 | Infrastructure, test harness, pilot (Settings, language picker, tool names) | **done 2026-10-01** |
| L1 | Club pillar: extract + translate + sweep, batch by batch | **done 2026-10-01** (C1–C9) |
| L2 | Editor pillar: extract + translate + sweep, batch by batch | **done 2026-10-01** (E0–E8) |
| L3 | Independent translation review (one agent per language), fixes, layout hardening | **done 2026-10-02** |
| L4 | Seams and periphery, then flip `kTranslationsShipped` | in progress (engine and server text done) |

**Next steps (2026-10-02):** the live pass and the store slides are done. Left: release notes,
the App Store listing (blocked on the expired agreement), and the flip, which also uploads the
eight Play listings and the per-language slides (files ready in `docs/i18n/flip/`,
`distribution/listings/` and `docs/marketing/out/<lang>/`). Gates on the current code: analyzer
clean, `flutter test` 7,817 passed, every sweep passes at 1.3×, `flutter test test_engine` 72 of
72 at 1.0× and at 1.3×.

The lowercase pass (`scan.dart --list --lower`, 239 words) is done: every one is a wire
value, a menu or tool id, a file format, a font name, or the fallback handle "unknown"
(shown as "@unknown" only if the server omits a handle). None is prose on screen.

**Progress number:** the total on line 5 of `app/test/l10n/hardcoded_baseline.txt` — the
hardcoded strings the scanner still finds. 2,683 after L0 (scanner as tightened in C1); 2,516
after C1; 2,334 after C2; 2,253 after C3; 2,125 after C4; 2,000 after C5; 1,856 after C6; 1,709 after C7; 1,654 after C8; 1,598 after C9 (all in `lib/editor`); 1,048 after E1 + E8; 877 after E2; 363 after E3 + E4; 141 after E5; **0 after E6 + E7 (2026-10-01)**: extraction is
complete. From here the baseline file stays empty, and `hardcoded_strings_test.dart` fails on
any new hardcoded string.

**Release safety while this is in progress:** `kTranslationsShipped` is `false`
(`app/lib/l10n/app_locale.dart`), so a release build offers English only and hides the language
row. Releases cut from `main` mid-workstream are unaffected. Debug builds and tests see all eight.
To try a release build with every language: `--dart-define=L10N_PREVIEW=true`.

## One unit of work (a batch)

A batch is a group of related files from the lists below. For each batch:

1. `cd app && dart run tool/l10n/scan.dart --list <file>` — the strings to move.
2. Read the file. For every string decide: **message** (goes to the ARB files), **non-UI**
   (engine DSL name, wire value, log text: add `// l10n-ignore: <why>`), or **server/engine text**
   (stays English for now; add it to the seam list in L4).
3. Write a patch file (Python, see `app/tool/l10n/patch.py`) that edits the source and adds each
   message **in all eight languages** with its description:
   `python tool/l10n/patch.py <patchfile>` then `flutter gen-l10n`.
   Follow GLOSSARY.md for terms and tone. Write the patch file with the Write tool, using raw
   strings (`r'''…'''`); the Bash tool mangles backslashes and apostrophes in heredocs.
4. Add or extend a sweep test for the screens touched (`app/test/l10n/sweep_*_test.dart` for
   Club and shared screens, `app/test_engine/` for anything inside the real editor page). Club
   screens run on the real providers over `FakeBackend` (`club_fixtures.dart`): add a route per
   endpoint the screen calls — a missing one fails the sweep by name. Look at the pictures the
   sweep writes to `app/build/l10n_shots/` for the screens touched.
   Also audit `dart run tool/l10n/scan.dart --list --lower <files>` once per batch: lowercase
   single words are not gated (mostly wire values), so UI ones among them need an eye.
5. Gates, in this order (never two `flutter` commands at once):
   `flutter analyze --fatal-infos` · `flutter test` · `flutter test test_engine`.
6. `dart run tool/l10n/scan.dart --write-baseline`, tick the batch below, commit
   (`feat(i18n/L1): …` / `feat(i18n/L2): …`). Commits go straight to `main`; no push.

Rules that keep the batches consistent:

- Widgets read strings with `context.l10n.key`. Code with no `BuildContext` (controllers,
  validators, API error mappers) uses `appL10n.key`, at the moment the message is produced.
- Never store a translated string in a `const`, a `static`, or a long-lived field. Data tables
  that held labels (tool catalog, blend modes, patterns, keyboard commands) hold a key or an id,
  and a function maps it to the string at build time — the pattern is `editor/tool_l10n.dart`.
- No sentence is assembled from fragments. Counts use ICU plurals (`{n, plural, …}`); a value
  that changes the wording uses `select`; everything else is one message with placeholders.
- A string that doubles as a state value or an engine name (`'Dots'`, `'Rectangle'`) is split:
  the value stays as it is, the label comes from the ARB.
- Key names are `areaThing` in camelCase with the prefixes in DESIGN.md §3. Reuse a `common*`
  key only when the meaning is identical, not merely the English word.
- Keep English wording unchanged unless it is wrong; existing tests assert on it.

## L1 — Club pillar (≈1,050 findings)

Counts are scanner findings on 2026-10-01; the live number per file is in the baseline.

- [x] **C1 Shared widgets** — done 2026-10-01: comments, feed filter, feed grid, player bar and
  picker, mention field, badges, download sheet, moderator hashtags sheet (+ `edit/mod_hashtag_edit`,
  `config/monitored_hashtags`), external links, and the shared `timeAgo` / `formatFileSize` /
  `compactCount` helpers. Sweeps: `sweep_widgets_test.dart`; formats: `formatting_test.dart`.
- [x] **C2 Sign-in and onboarding** — done 2026-10-01: sign-in form and account page
  (`club_account_page`), create account, forgot password, verify email, account management, delete
  account, onboarding wizard, welcome and resolving pages, the auth controllers and validators.
  Sweeps: `sweep_auth_test.dart`; `behavior_test.dart` (the delete-account confirmation word is each
  language's own).
- [x] **C3 Home, feeds, search, notifications** — done 2026-10-01: Club home (top bar, menu, feed
  names, offline strip), search, hashtag feed, notifications (one message per notification type),
  Contribute, About, comments page. Sweeps: `sweep_home_test.dart`. Report notifications
  (`newReportText` / `reportResolvedText` in `models/safety_copy`) are batch C7.
- [x] **C4 Profile and account** — done 2026-10-01: profile page (header, tabs, block flow,
  highlights), profile editor, follows, reactions, remixes of my works, artist dashboard, post
  statistics. Sweeps: `sweep_profile_test.dart`. The Private tab's drawing grid is batch E3.
- [x] **C5 Artwork** — done 2026-10-01: the artwork page (meta line, remix line, hashtags, the
  full ⋮ menu for visitor / owner / moderator, every confirmation dialog and toast, layers-file
  flows) and the lineage page. Sweeps: `sweep_artwork_test.dart`.
- [x] **C6 Publish and manage** — done 2026-10-01: the publish page (conformance banner, remix
  notes, layers sharing, license), edit post details, My Posts (bulk bar, delete / license /
  request-download dialogs, downloads sheet), the approval queue, the community-rules gate.
  New `lib/l10n/rich.dart` (`boldSpans`): a bold phrase inside one message, marked `<b>…</b>`.
  Sweeps: `sweep_publish_test.dart`. Not swept (plain dialogs, low risk): the "publish
  without remix claim" dialog and the "Posted" success page.
- [x] **C7 Moderation and safety** — done 2026-10-01: report form and its sent dialog, blocked
  users, Mentions and Monitored hashtags settings, moderation hub, user management (trust,
  hide, ban, reveal email, reputation) with every dialog, and the report notifications'
  sentences (`models/safety_copy.dart`). Report reasons: the app's own translation of a
  known code wins outside English; the server's English label still wins in English.
  `ReportTarget.label` is now composed when read (it was a stored sentence).
  Sweeps: `sweep_safety_test.dart`.
- [x] **C8 Players** — done 2026-10-01: My Players (list, empty and signed-out states, player
  menu, rename and delete dialogs, register sheet and its errors), the generic "Player" and
  "Artwork" fallback names, "Not signed in." `api/player_api.dart` holds only URL paths
  (`l10n-ignore-file`). Sweeps: `sweep_players_test.dart`.
- [x] **C9 Errors and context-free text** — done 2026-10-01: network / timeout / fallback
  errors (`ClubError`), sign-in errors thrown by the GitHub and Apple flows, mention-picker
  reason labels, reaction / comment / follow failures, and the size dialog shared by Export
  and Share (`lib/share/image_share.dart`; `share: true` replaces the title / action strings
  so "… anyway" is a whole message). Wire values are marked `l10n-ignore`. The lower-case
  tier (`scan.dart --lower`) was read through for everything outside `lib/editor`: wire
  values and menu ids only. **Nothing outside `lib/editor` is left in the baseline.**
  Sweeps: `sweep_share_test.dart`; behavior tests in `behavior_test.dart`.

## L2 — Editor pillar (≈1,600 findings, many of them engine names to mark, not translate)

- [x] **E0 Tool names** — short tile label + full name per tool (`tool_l10n.dart`), done in L0
- [x] **E1 Tool help and row-1 options** — done 2026-10-01: the 28 help-band tips (moved
  from `tools.dart` to `tool_l10n.dart`, `toolTip(l10n, dsl)`) and all of
  `editor_page.controls.dart`: the per-tool options row, palette strip, gradient and palette
  swatch menus, mirror chip and sheet, pattern swatch, replace-color and color-name dialogs.
  Labels are separate from the engine values they control (the Select-by-alpha buttons used
  their label as the DSL argument). `AA` and `cleanEdge` stay as they are in every language.
  Tests: `test/l10n/tool_tip_fit_test.dart` (T5b), `test_engine/editor_tool_options_test.dart`.
  (Pattern and dither names in the swatch tooltip followed in E5.)
- [x] **E2 Editor chrome** — done 2026-10-01: the ☰ menu and its five submenus, the timeline
  tooltips, the layer and frame sheets, the pinned-tool and Show/hide tools sheets, the
  New document dialog, the floating selection and commit menus. **Language…** is in the ☰
  menu (shown when more than one language ships). Default names:
  - a drawing's default title is `defaultDrawingTitle` (the current language's "Untitled");
    a stored title that is any language's default reads as the current one
    (`persistence/drawing_meta.dart`);
  - the engine names layers "Layer N" / "… copy" in the document; `layers/layer_names.dart`
    (`shownLayerName`) translates those when shown. Applied in the layer sheet here; the
    Layers page, the layer-name picker, and the strip are batch E4.
  Test: `test_engine/editor_chrome_test.dart`.
- [x] **E3 Files** — done 2026-10-01: open, save, import, export, and share toasts and
  dialogs (`editor_page.fileio`, `.persistence`, `open_file`), My Drawings (`gallery/`), the
  rename, duration, and Resize canvas dialogs, the crop page and the place page.
  - An overhang past the canvas is written with arrows (`←64 ↑64 →64 ↓64 px`), not words:
    four edges named in words did not fit two lines on a phone in any language.
  - Both pages keep fixed-height status slots (the panel height feeds the preview's fit
    scale), so a longer translation cannot grow them: the slots that hold a sentence are two
    lines now, and `PreviewStatusRow` puts the zoom cluster on its own line under 600 px.
  Tests: `test/l10n/sweep_import_test.dart` (crop and place pages, six states) and the
  second half of `test_engine/editor_chrome_test.dart` (duration, Resize canvas, rename,
  My Drawings, keep-or-discard).
- [x] **E4 Frames and layers** — done 2026-10-01: the Frames page and the Layers page with
  their menus, More sheets, dialogs, bottom bars, and status lines; the layer-name picker;
  the range-entry errors (`frame_set.dart`, `layer_model.dart`, through `appL10n`). Also the
  **blend modes** (moved up from E5, since both pages list them): `blend_l10n.dart` gives the
  name, the group heading, and the tile badge per language; `blend_modes.dart` keeps the
  engine tokens only.
  - `shownLayerName` is applied everywhere a layer name shows (rows, row menu, the merge
    report, the name picker). The picker shows the translated name and still hands the verb
    the stored one.
  - A literal `{n}` (the rename pattern) cannot sit in a message (`use-escaping` is off):
    the messages take it as a `{token}` placeholder.
  - "Every Nth frame" was a sentence with two fields inside it; it is two labeled fields now.
  - The scanner treats `frameSetDsl(` / `layerSetDsl(` arguments as engine verbs.
  Tests: `test/l10n/sweep_frames_layers_test.dart` (24 states, on the scripted hosts of the
  page tests), `test/blend_modes_test.dart` (names and badges unique in every language).
- [x] **E5 Color** — done 2026-10-01: the Palettes page, the Artwork colors page, the color
  dialog, the Patterns and Dither pages, the memory banner and refusal toasts, and the
  go-to-frame dialog (`editor_page.engine`).
  - Pattern, pattern-family, and dither names are computed in the current language, not
    stored as English text: `PatternEntry` holds what the tile depicts (`PatternShape` and two
    numbers) and `DitherKind` its shape; `name` / `hint` are getters over `appL10n`. The
    swatch tooltip in the options row follows.
  - The engine names a new drawing's palette "Default" inside the document;
    `PaletteInfo.shownName` shows it in the current language (as with layer names). A palette
    the app creates ("Artwork colors", "Palette") is named in the current language at
    creation: from then on it is the artist's name.
  - The color dialog's model and channel letters are messages (French: RVB / TSV, R V B,
    T S V; everyone else keeps RGB / HSV).
  - The preview-color labels ON / OFF are messages (de AN / AUS, ru ВКЛ / ВЫКЛ, ja オン / オフ,
    zh 开 / 关).
  - The scanner has a block form for lists of engine verbs: `// l10n-ignore-start: why` …
    `// l10n-ignore-end`.
  Tests: `test/l10n/sweep_color_test.dart` (20 states); the go-to-frame dialog is in the
  `test_engine/editor_chrome_test.dart` walk.
- [x] **E6 Keyboard** — done 2026-10-01: the Keyboard shortcuts page and the hold-Primary
  overlay.
  - `CommandDef` carries `labelOf(l10n)` (the cheat sheet asks per build, so a language
    change shows at once; `label` is the current-language shortcut) and a `CommandCategory`
    enum instead of an English category string. The L0 bridge is gone.
  - Key legends are messages, named as printed on that language's keyboards (`keyCtrl` =
    Strg, `keyShift` = Maj / Mayús / Umschalt, `keyDelete` = Entf / Suppr / Supr, `keySpace` =
    Leertaste / Пробел / スペース / 空格). `Chord.display()` uses them; `Chord.serialize()` (the
    bindings-file wire format) stays English.
- [x] **E7 Replay and timelapse** — done 2026-10-01: the Watch replay toasts, the Replay page
  (title, "Older recording" chip and its tip, the preparing state, the three failure
  messages through `appL10n`), the timelapse options, long-animation, and progress dialogs,
  and the default "Tap again to confirm" of the two-tap Delete button.
  Tests for E6 and E7: `test/l10n/sweep_keyboard_replay_test.dart`; the Replay page on a
  real journal, the timelapse options dialog, and the armed Delete are in the
  `test_engine/editor_chrome_test.dart` walk. Not reached by any test: the long-animation
  dialog (needs a cycle over 60 s) and the rendering dialog (needs an export to run); both
  are plain scrollable dialogs.
- [x] **E8 Engine-name files** — done 2026-10-01: `replay/visible_index.dart` holds only DSL
  verb and tool names (checked: 212 of 212) and is marked `l10n-ignore-file`.

## L3 — Review and hardening

- [x] Independent review, done 2026-10-02: 21 reviewers (seven languages, three parts of about
  550 messages each), each given only the English text with its context note, the
  translation, and the glossary; never my reasoning. Brief: `docs/i18n/review/BRIEF.md`;
  findings: `docs/i18n/review/<lang>-<part>.md`. About 560 findings in all; 6 high, all
  the same bug (below).
- [x] Fixes applied, 2026-10-02: about 620 messages reworded (es 97, pt 77, fr 76, de 78,
  ru 123, ja 92, zh 77). Not taken: style-only rewrites, gender-neutral rewording where the
  language's generic masculine is standard, and the Japanese spacing sweep (settled in the
  glossary instead). The term decisions are in GLOSSARY.md ("Decided in the L3 review").
  Code fixes the review found, outside translation:
  - **Decimal comma rejected** (the 6 high findings): the mirror-axis field and the slider's
    exact-value dialog parsed only a point, while German, French, Portuguese, and Russian
    labels say ",5", and those languages' decimal keyboards often offer only a comma. Both
    fields accept either now.
  - **Hashtags split only on the ASCII comma**: Chinese and Japanese keyboards type "，" or
    "、", so all tags merged into one. The edit page's parser and the publish request accept
    both now (test in `club_parity_test.dart`).
- [x] Second pass, done 2026-10-02 (its fixes then broke a few fits; the sweeps caught them
  and the texts were shortened: crop and place slots in es, de, fr, pt, ru, ja; the Russian
  New document title label, which lost "(optional)"): one fresh reviewer per language, given only the changed
  messages with their old text (`docs/i18n/review/<lang>-pass2.md`, brief in
  `BRIEF2.md`): 45 findings, 1 high (a German rewrite had dropped a line and two
  placeholders), all applied. One led to a code change: the Japanese notification
  honorific moved into its own message (`notifActor`), because the unknown-sender fallback
  read "誰か さん".
- [x] Glossary check, as a test rather than a tool: `test/l10n/glossary_test.dart` holds the
  pairs that must read differently (Flip / Invert, Redo / Repeat, Open / Import, Discard /
  Delete, the two place-page losses, …) and the pairs that must match. Writing it found two
  more collapses (below). A mechanical scan for "same English, different translation" was
  tried and dropped: 189 hits, nearly all legitimate (a tool's name is a noun, its option a
  verb, a tile label abbreviated).
- [x] Full screenshot gallery (T6) reviewed per language, done 2026-10-02: one contact sheet
  per screen with the eight languages side by side (script pattern: PIL, 4 × 2 grid at half
  scale, from `build/l10n_shots/`); all 221 sheets. Found and fixed: French "Réactions" named both the reacted-to tab and the received
  count (now "Réagi", and a glossary-test pair); German counts printed "78901" (intl's German
  compact form has no thousands step; five digits and up are now grouped, "78.901"); a number
  and its unit could break across lines in every language (no-break spaces, GLOSSARY.md); the
  Russian Move tile said "Сдвиг", the Layers and Frames pages' Shift (now "Перемещ.", and a
  glossary-test pair on the short labels); the Chinese Patterns hint spaced a Chinese tool
  name; the
  statistics showed the server's view types in English ("Intentional", "Listing"; now a
  translated select with an untranslated fallback); the French color dialog's title touched the
  swatch; German "Werk" in two editor messages (the editor's drawing is "Zeichnung"); Japanese
  and Chinese "unique (7 days)" broke inside the parenthesis; the German crop label "In
  Leinwand einpassen" wrapped and was cut by its segment, which no check could see, hence two
  new detectors (TESTING.md) that then found the crop result slot cutting CJK and large-font
  lines, the Frames tiles' captions (1 px), the palette "…" marker, and two long dialogs on a
  320 px phone (now scrollable); the editor's ☰ menu labels could not wrap (Japanese, 1.3×);
  decimals on screen always used a point ("100.0 ms", "Ratio 1.00", the Levels gamma, the
  ruler's angle, the scale label) — `fmtFixed` in `l10n.dart` now writes the language's
  separator, and is tested per language; lists joined with ", " in Japanese and Chinese (roles,
  removed hashtags, frame ranges) now use the language's separator (`listSeparator`, "、"), and
  the user-management roles are translated as on the account page; the German download sheet's
  subtitle repeated its title; the moderation page wrote dates as "2026-10-31" in every
  language (now the language's own medium date); the Russian "Edit profile" button wrapped
  ("Изменить профиль", as every other Russian edit action); "tag" where the glossary says
  hashtag in four moderation messages (de, ru, ja, zh; now a glossary test for every hashtag
  message); bare "Club" in five Russian messages (now "Makapix Club", and a test; the publish
  title became "Опубликовать", which fits a 320 px bar); the Russian
  Move group used the Shift word (the glossary row itself had it; corrected); percentages
  wrote "50 %" in English (a `percent` message with each language's spacing); "53687
  Millionen" ungrouped; the fps readout and presets ("10.0 fps", "60fps"); the layer opacity
  dialog stretched to the full screen height (a Slider takes all the height it is offered; in
  every language); a wrapped empty-state message ran edge to edge (shared `ClubEmpty`).
  Left as is: emoji and "✔" show as boxes only in the test fonts; single-character
  blend badges in ja/zh (as cryptic as English "Mu"); the Japanese timelapse title breaking
  inside a katakana word (ordinary CJK wrapping, permitted by Japanese line-breaking rules).
- [ ] Layout hardening for whatever the sweeps flag in German and Russian.
- [x] Text scale 1.3× sweep, run 2026-10-02 (`--dart-define=L10N_TEXT_SCALE=1.3`, TESTING.md):
  771 failing screen states of 5,946. Most are ellipsis truncation, the designed fallback; English
  fails on 35 states too, so this is large-font layout in general, not translation. The 320 px
  phone at 1.3× is the worst case (408 failures) and is accepted except where a fix is free.
- [x] Large-text fixes, done 2026-10-02. The harness now tells "…" (accepted at 1.3×) from
  clipping (never accepted); 771 failures became 57, and those were fixed: fixed heights that
  ignored the font size (color dialog sources strip, lineage strip, the editor's help band),
  menu labels that could not wrap (Club home, profile, My Players), the moderation chip, the
  onboarding buttons (now an `OverflowBar`), the player options sheet (now scrolls), and four
  sweep walks that tapped before a scroll landed (`tapVisible`). The row-3 tool tile labels were
  clipped under a large font in six languages: they now shrink to the tile past its room
  (ADR 0037 amendment), tested at 1.3× and 2× in every language. All sweeps pass at 1.3×.
  The original list, for the record:
  Color dialog with sources and Lineage (every size, English too), Artist dashboard and Post
  statistics (stat columns), User management (reputation row), Place page (parked line),
  Welcome and Resolving pages (title), Account management, Dither page end, Keyboard shortcuts
  (de), Club home and profile moderator menus (ja, ru), Publish (en, es, pt), Frames and Layers
  pages and their sheets (es, ja, ru), Search tabs (fr, ru), onboarding steps (de, pt), and
  single screens listed in the 2026-10-02 run output. Rerun the 1.3 sweep after.

## L4 — Seams, periphery, release

- [x] **Engine refusal text**, done 2026-10-02, without touching the engine (its state JSON and
  goldens stay byte-identical): `lib/editor/refusal_l10n.dart` recognizes each of the engine's
  refusal sentences by pattern and shows the translated message; an unknown sentence shows as
  is in English and as the generic message elsewhere. `test/refusal_l10n_test.dart` pins the
  engine's exact sentences, so a reworded engine message fails there first. Load, import, and
  memory refusals were already translated (`memBlocked`, the file-io toasts).
- [x] **Server text, app side**, done 2026-10-02: `ClubError` shows the app's own message for
  every specific server error code (26 codes plus `rate_limited`); email sign-in shows its own
  "Wrong email or password."; the handle check writes "available" and "already taken" itself.
  Thread opened: `messages/0005-localized-text/0001-app-localized-text-proposal.md`. Waiting on
  the reply (`0002-server-…`); nothing in it blocks the release.
- [ ] **Server text, server side** (the thread above) — the original item: proposing codes + params for API error
  `detail`, moderation report-reason labels (`report_reasons[].label`), and any notification text
  the server composes. The app ships without waiting; until the server answers, those stay English.
  Server prose found so far (add to this list as batches meet more):
  - `ClubError.message` — the API error `detail`, shown in toasts and banners across the app.
  - `POST /auth/check-handle-availability` → `message` ("Handle is available"), shown under the
    handle field in account management and onboarding.
  - `GET /config` → `moderation.report_reasons[].label`.
  - `GET /badge` → badge names and descriptions.
  - `quotas.uploads.window` on `/auth/me` (the quota period's name), shown on the account page.
  - `tag_badges[].label` on profiles.
  - The failure text of `POST /player/register`: the app matches its English wording
    ("invalid", "expired", "already registered", "maximum … player") to pick a translated
    message (`my_players_page.dart` `_friendly`). An error code would be sturdier.
  - `error_message` on a failed download request (`GET /pmd/bdr`), shown in the downloads sheet.
  - License `title` on `GET /license` (license names; proper names, probably stay as they are).
  - Statistics bucket names: `views_by_type` keys (shown capitalized) and country codes.
- [x] **Default names stored in documents**: display-time mapping, done in E4 and completed
  2026-10-02 with the "Import N" layers; recorded in the ADR 0037 amendment. Test:
  `test/layer_names_test.dart`.
- [ ] **Android**: `res/xml/locales_config.xml` + `android:localeConfig` (per-app language in
  system settings, Android 13+); confirm the app label stays "Makapix Club". Decided
  2026-10-02: lands in the same commit as the `kTranslationsShipped` flip, never before — it
  advertises the languages to the system, and a release build would list seven it does not show.
  The file is ready in `docs/i18n/flip/` (README there says where it goes).
- [ ] **iOS**: `CFBundleLocalizations` in Info.plist; localized `NSPhotoLibraryUsageDescription` /
  `NSCameraUsageDescription` (`InfoPlist.strings`). First real check is the next Codemagic build
  on TestFlight — record the result here. Same rule as Android: in the flip commit. The seven
  `InfoPlist.strings` are ready in `docs/i18n/flip/ios/` (reviewed, `review/infoplist.md`).
- [x] **Windows**: smoke-tested 2026-10-02 in the release build (`--dart-define=L10N_PREVIEW=true`):
  Japanese, Chinese, Russian, and German render correctly through the system font fallback
  (Japanese and Chinese each in their own font), and a saved language is applied at launch.
  Method: the language is preset in the app's preferences file (backed up and restored byte
  for byte) and the window captured with `PrintWindow` (a screen capture shows whatever window
  is on top).
- [x] **Material's own strings**, done 2026-10-02: the global delegates are wired, the app has
  no date or time pickers, and `test/l10n/material_strings_test.dart` checks the back tooltip,
  the text-selection menu, Close, and the sheet barrier label in every language.
- [x] Release gates, done 2026-10-02: `flutter gen-l10n` was already a gate (L0); `flutter test
  test_engine` now runs after `flutter test`, building the release DLL first (about 35 min;
  `-SkipGates` skips all gates). CLAUDE.md and `docs/play-release.md` updated.
- [x] **Live pass**, done 2026-10-02. Windows: see the Windows item. Pixel 10 Pro XL (Android
  17) over wireless adb, a release build with `--dart-define=L10N_PREVIEW=true`:
  - the app follows the device language (set through Android's per-app language,
    `adb shell cmd locale set-app-locales club.makapix.app --locales ja`, which is the language
    the app sees as the device's; the phone's own language list was not touched);
  - a language chosen in Settings applies live and survives a cold start, against a different
    device language; "System default" names the device language it follows;
  - the editor's main screen and ☰ menu in all eight languages: every row-3 tile label fits,
    menus wrap where needed, the phone's own fonts render every script;
  - Club menu, Settings, notifications (real server data: plurals, emoji, word order) and the
    Artist dashboard in several languages.
  Found and fixed: the statistics showed the device types `app`, `app_ios`, `app_android`
  (messages/0001-app-device-type) raw as "App_ios", in English too; they are now named in every
  language (test in `formatting_test.dart`). Still raw by design: country codes (US, VN).
  Afterwards the phone was put back: per-app language cleared, the app's own language left at
  System default, and the normal release build reinstalled (1.11.0 from `main`, translations
  off; the phone had 1.10.0 before). The PC had to be re-paired with the phone first (the
  phone had forgotten it: `SSLV3_ALERT_CERTIFICATE_UNKNOWN`).
- [ ] **Store listings**: Play drafted 2026-10-02 in `distribution/listings/play/` (eight
  languages, limits checked; README there), under independent review (`review/listing-<lang>.md`,
  brief `review/BRIEF-listing.md`). App Store blocked on the expired agreement (Findings outside
  i18n). Release notes per language: at the flip. User decision 2026-10-02: all eight Play
  languages go live together at the flip, the corrected English too.
- [x] **Store screenshots** per language (done 2026-10-02): `docs/marketing/out/<lang>/`
  (Play, App Store iPhone and iPad, feature graphic) from `docs/marketing/src/copy/<lang>.json`;
  mechanics and decisions in `docs/marketing/README.md`, Languages. Phone shots:
  `docs/marketing/shots/<lang>/`, six per language, all reviewed for third-party IP. Method: the
  preview build on the Pixel; `cmd locale set-app-locales` per language; a script per language
  that drives the editor with `input tap/swipe` (never start a swipe at a screen edge: that is
  Android's back gesture; never start one on a slider); option-row buttons found by their labels
  in `uiautomator dump`, the pattern swatch by its green color. User decisions: Noto Sans CJK
  (regular style) for ja/zh headlines; no replay phone panel. Found while building: Press Start
  2P draws accented capitals as small letters ("CóDIGO"), so the build lifts the mark above a
  full-size capital; the fit check now fails any store slide whose text wraps a word or
  overflows (it caught three latent English defects, fixed); copy reviewed per language by an
  independent agent, findings applied.
- [ ] Flip `kTranslationsShipped` to `true`; update README, STATUS.md, CLAUDE.md; release notes.

## Open questions and risks

- 8.5 px tile labels in Japanese and Chinese: legible in the 2× screenshots, but dense kanji at
  that size on a real phone is the first thing to look at in the live pass.
- Traditional Chinese devices currently get Simplified (no `zh_Hant` translation). Revisit if
  there is demand.
- `use-escaping` is off, so a message cannot contain a literal `{` or `}`.

## Findings outside i18n

- **App Store Connect refuses the API** (2026-10-02): every call returns 403
  `FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED` ("A required agreement is missing or has
  expired"). The account holder accepts it in App Store Connect → Business. Until then the
  App Store listing cannot be read or changed by API, and the Codemagic → TestFlight path
  (same key) will likely fail too. Needs the user.
- **The Play listing is out of date** (2026-10-02): it says canvases "up to 256×256" and "64
  layers"; the app does 512×512 (ADR 0021) and 128 layers (ADR 0032). Corrected in
  `distribution/listings/play/en-US.json`, which is not uploaded (uploading changes the live
  listing: the user's call, or at the flip).
- **Large system fonts** (2026-10-02, fixed; see L3): the app ignored the font size in fixed
  heights, and the row-3 tool labels were clipped under a large font in six languages. Most of
  the list was in English too.
- **Decimal comma and full-width comma** (found by the L3 review, 2026-10-02, fixed; see L3).
- **"Invert selection" meant two things** (found by the glossary test, 2026-10-02): the Invert
  tool's option inverts the colors inside the selection; the floating menu's item selects
  everything else. English spells both the same, and so did es, pt, fr, de. The option now
  says "invert the selection's colors" in those languages. The English label is unchanged:
  say so if it should become "Invert selection colors" too.
- **Layout, after the review's longer wording** (2026-10-02, fixed): the profile tab label and
  the "Trusted" switch title scale down instead of being cut on a 320 px phone; the timelapse
  shape choice scales down (it overflowed by 7 px in French).

- **Keyboard shortcuts page** (2026-10-01): the key column no longer uses the `monospace`
  family. Key names are words in the current language now, and a monospace face showed the
  Cyrillic and CJK ones in a fallback font of another width; in the tests that family is not
  loaded at all, so the sweep could not measure the rows. The keys are in the app font, bold.
  Command names may take two lines. English wording: "Replay: <title>" (was "Replay —
  <title>"); "This drawing has no replay yet. Draw something first!"; the keyboard command
  "Import & export" lost its ellipsis; the timelapse options dialog is titled "Export
  timelapse" on desktop (it said "Share timelapse" there too).

- **Dither page: the note beside a dither name** was one line with an ellipsis; it is two
  lines now (2026-10-01). English wording changed in the Palettes page confirmations, which
  no longer repeat the color count ("Reorders the colors into ramps: …", "Removes every
  color from this palette. …", "Deletes this palette and its colors. …"), and under the
  Patterns page's Off choice ("The tool paints every pixel", was "Pencil paints every
  pixel"). Say so if any of the old wordings should come back.

- **Crop and place pages on a phone** (found by `sweep_import_test`, 2026-10-01, in English
  too, all fixed):
  - crop page, import mode: the `W` / `H` chips and the "1:1 / Fit to canvas" choice
    overflowed their row by 26 px on a 360 px phone (66 px on 320). The choice has its own
    line under 600 px;
  - crop page, canvas mode: the title "Crop canvas" was cut off beside its four actions on a
    360 px phone (the actions sit closer now and the title scales down before it is cut);
  - both pages: the frame counter and the zoom cluster overflowed one row on a 320 px phone;
  - place page: the placement sentence named each overhanging edge in words and ran past its
    two lines; the X / Y chips and the nudge arrows overflowed by 4 px on 320 px with
    three-digit negative coordinates. The overhang text is arrows now: say so if the words
    should come back.

- **Frames and Layers pages on a phone** (found by `sweep_frames_layers_test`, 2026-10-01, in
  English too, all fixed):
  - the status line was one line, and the idle hint ("Tap or slide to select · hold for
    options · double-tap to go to") did not fit it on a 360 px phone; it is two lines (the
    page gives 8 px more to it);
  - More sheet: the "Not square…" note did not fit its one line; the note slots are two lines.

  English wording changed with the extraction, where a message had an em dash or was a
  fragment: "Every layer removed. One blank layer took their place."; "Merge needs
  neighboring layers: the selection has a gap."; "N selected layers are locked. Unlock them
  first."; "N selected layers are locked: these are unavailable"; "Duration of N frames";
  "In 2 of 3 selected frames" (under each name in the layer-name picker); "N frames pinned
  at 16.7 ms" for both ways of hitting the limit; "Shift frames" with a hint beside the
  field; "Copied to N frames".

- **Smaller ones** (same day, fixed): the frame duration dialog overflowed a 320 × 568 phone
  by 2 px in Japanese (it scrolls now); the My Drawings title was cut off in German on a
  320 px phone (it scales down).

- **Editor sheets and dialogs on small phones** (found by `editor_chrome_test`, 2026-10-01, all
  in English too, all fixed):
  - the ☰ submenu sheets did not scroll: Canvas overflowed by 124 px on a 320 × 568 phone and
    by 27 px on 360 × 740; Import & export and View by 9.5 px on the small one;
  - the New document dialog overflowed by 61 px when the Club-size warning showed;
  - in the layer sheet "Merge down" was cut off as a third button beside Up and Down (now its
    own row; sheet buttons may take two lines).

- **Copy & paste help tip cut off in English.** On a 360 px phone the tip needed three lines
  and the band shows two, so its last sentence ended in an ellipsis. Reworded shorter
  (2026-10-01): "Copy, Cut, Paste, or Clear the selection. Copy from the layer or the whole
  frame. Paste drops a movable draft." Say so if the old wording should come back.

- **Editor unmount during startup.** Unmounting `EditorPage` while `_initPersistence` is still
  restoring the drawing threw `Cannot use "ref" after the widget was disposed`
  (`editor_page.persistence.dart`), found by the engine-backed test harness on 2026-10-01. Fixed
  with a `mounted` guard. A narrower race remains: an unmount in the few milliseconds while
  `_createFreshDrawing` / `_loadDrawingIntoEngine` is awaiting can still run engine calls after
  `engine.dispose()`; in the harness that was a native crash. Not fixed (outside this workstream);
  the harness waits for the first drawing to reach disk before it unmounts.

- **Club home top bar on a 320 px phone.** The eight icon buttons overflowed the bar by 20 px in
  every language, English included (found by the sweep, 2026-10-01). Fixed: under 340 px the
  icons use tighter padding and the menu button drops Material's 48 px minimum.

- **My Posts: the bulk action bar covered the whole page.** Selecting a post replaced the list
  with a full-screen bar, in English too: the bar sat in a `CenteredContent`, whose `Align`
  takes all the height a bottom bar is offered (since the tablet width policy commit
  `9393ad7a`). Found in a sweep screenshot on 2026-10-01; fixed with `Center(heightFactor: 1)`.

- **My Posts downloads: "Expires now".** A ready download showed its expiry through `timeAgo`,
  which reads any future time as "now". It now says "Expires in 5 days" (hours on the last
  day). The request line read "Requested now ago" for a fresh request; now "Requested: now".

- **Layout defects that were already in English** (found by the sweeps on 2026-10-01, all fixed):
  the blocked-profile banner overflowed a 320×568 screen, and the tagline hint in the profile
  editor was cut off.

## Session log

- **2026-10-02** — Store slides in all eight languages (L4): per-language copy files, Noto Sans
  JP/SC subsets, lifted accents for Press Start 2P capitals, grayscale text rendering, a fit check
  that fails store slides, Spanish price as GRATIS (one set serves es-419 and es-ES).
- **2026-10-02** — Selected option chips showed two check marks ("✓ AA ✔": Material's plus a
  "✔" the editor added to the label). User decisions: keep Material's only; Lock Ratio keeps its
  words when on (it shortened to "Ratio ✔"); the Pencil's pattern swatch shows the same check
  before its tile; the hero store shot has the pattern Off. Test: `editor_check_mark_test.dart`.
  Re-shot `hero_senna`, `row1_pattern`, `row1_aa` in all eight languages.
- **2026-10-02** — Live pass on the Pixel (L4): language pickup, override and restart, the
  editor in all eight languages, real Club data. One fix (statistics device names).
- **2026-10-02** — Screenshot review (first ~50 sheets) and the store listings. Fixes listed
  under L3. Play listings drafted in eight languages and reviewed (`review/listing-*.md`; no
  high findings, all mediums applied). Two harness detectors added (squeezed and clipped
  text). The editor at 1.3× had two problems: the ☰ menu labels could not wrap (Japanese, every
  size) and a walk tap behind the Resize dialog's buttons on 320 px phones.
- **2026-10-02** — Large text. The 1.3× sweep now separates "…" from clipping; every sweep
  passes at 1.3× after the fixes listed under L3, and the tool tiles are tested at 1.3× and 2×.
  Also: "Import N" layer names, Material-strings test, the editor suite as a release gate, ADR
  0037 amended. 7,794 Dart tests pass.
- **2026-10-02** — L4 begins. Engine refusals and server error codes now show in the user's
  language (22 new messages); the server thread `0005-localized-text` is open. The 1.3×
  large-text sweep ran: 771 of 5,946 states fail, most of them ellipsis or 320 px; the real
  overflows at 360 px and wider are listed under L3. 7,778 Dart tests pass.

- **2026-10-02** — L3 review: 21 reviewer parts, about 560 findings, about 620 messages
  reworded, two input bugs fixed. The engine-backed suite, run on the pre-review text, passed
  68 of 72: the four failures (320 px) were the walk's help-band allowance, too narrow once
  the walk selects the Play tool, and the timelapse shape choice overflowing by 7 px in
  French. Both fixed.

- **Review packs for L3** (one JSON line per message: `n`, `key`, `context`, `en`, the
  translation, `placeholders`): for each language, read `app/lib/l10n/app_en.arb` and
  `app_<lang>.arb`, take the keys that do not start with `@` in file order, use the
  `description` of `@key` as `context`, and split the lines 550 / 550 / the rest. The
  reviewer brief is in the git history of this session; its rules are the eight checks
  listed under L3 plus "report only real problems, do not rewrite for taste".

- **2026-10-01** — E6 + E7 (keyboard, replay, timelapse): 64 messages. The scanner finds
  nothing: **L1 and L2 are done.** 1,645 messages in eight languages. Next is L3 (the
  independent review per language, the glossary check tool, the text-scale sweep), then L4.
  Before L3, one manual pass is still owed: `dart run tool/l10n/scan.dart --list --lower`
  (lowercase single words, which the scanner does not count by default).

- **2026-10-01** — E5 (color, palettes, patterns, dither, memory warnings): 113 messages.
  Baseline 363 → 141; what is left is E6 (keyboard) and E7 (replay and timelapse).

- **2026-10-01** — E3 + E4 (files; Frames and Layers pages; blend modes): 158 messages in E4,
  about 190 in E3. Baseline 877 → 363. Two new sweep files (`sweep_import_test.dart`, 240
  runs; `sweep_frames_layers_test.dart`, 960 runs) and a longer walk in
  `test_engine/editor_chrome_test.dart`. What is left in the baseline is E5 (color, palette,
  patterns), E6 (keyboard), E7 (replay), and `editor_page.engine.dart` (unassigned: 68
  findings, mostly engine values to mark).

- **2026-10-01** — E2 (editor chrome): 82 messages. `test_engine/editor_chrome_test.dart`
  walks the real editor through the menu, every submenu, the sheets, and the New document
  dialog (32 runs). It found five layout defects on small phones that English had too, all
  fixed (see "Findings outside i18n"), and one Russian label too long for its field.
  Blend mode names ("Normal") are still English in the layer sheet until E5.
- **2026-10-01** — E1 + E8 (tool tips, the options row, engine-name file): 187 messages.
  - The help band shows two lines. A new fit test lays every tip out at the band's width on
    a 360 px phone: seven languages had tips needing a third line, and so did English (the
    Copy & paste tip, reworded shorter). All fit now.
  - The real editor is swept by `test_engine/editor_tool_options_test.dart`: one mount per
    language and size, every tool selected, every chip switched on (32 runs, about 4 min).
    It writes one screenshot per tool and language (`editor-tool-<tool>_<lang>.png`).
  - `l10n_test_support.dart`: the text checks take `within:` to look at one part of a page.
  - `patch.py`: `setv(key, de='…')` rewords an existing message.
  - Scanner: literals inside `_send(...)` / `_act(...)` are engine values, not display text.
  - 5,485 Dart tests + 40 engine-backed tests pass.
- **2026-10-01** — C9 (errors, context-free text, image share): 41 messages. Scanner fix: a
  message inside `throw ClubError(...)` was skipped as developer text, but screens print it;
  the scanner now reads it (found 10 sign-in errors). Sweep finding fixed: the Export / Share
  size dialog overflowed a small phone when its warning showed, in English too (it scrolls
  now). 5,476 Dart tests pass. **L1 (Club) is complete.**
- **2026-10-01** — C8 (players): 30 messages. **Test-harness defect found and fixed:** a tap
  that lands on nothing was only a warning, so eight "dialog" sweeps (three artwork dialogs,
  the profile block dialog, the comment moderator-delete dialog, and three new player ones)
  had been checking the menu behind the dialog instead. Missed taps are now fatal in every
  sweep (`hitTestWarningShouldBeFatal`), and `settleOpen()` lets a menu finish opening before
  the next tap. The dialogs, once really reached, showed one defect: "permanentemente" is
  wider than a dialog title on a 320 px phone (Spanish and Portuguese titles reworded).
  5,353 Dart tests pass.
- **2026-10-01** — C7 (moderation and safety): 117 messages. Sweep findings fixed: the report
  form's notes question and the reputation reason label were cut off on phones in every
  language, English included (the question moved above the field; the requirement moved to
  helper text); the monitored-hashtag badge overflowed in German (row is now a Wrap); a long
  "Unban" squeezed the ban status to 25 px (it is its own row now); the blocked-users row
  left 49 px for the handle in German. Russian "Blocked users" is now «Чёрный список»
  (the long form did not fit a top bar). 5,073 Dart tests pass.
- **2026-10-01** — C6 (publish, post details, My Posts, approval queue, rules gate): 121
  messages. Sweep findings fixed: the "no license" dropdown option and the hashtags label were
  cut off on phones in six languages (shorter wording; the comma hint moved to helper text);
  the request-download dialog overflowed a small phone (now scrolls). Lesson for ja / zh: a
  plural message whose text does not print `{count}` must still be written
  `{count, plural, other{…}}`, or the placeholder check fails. 4,550 Dart tests pass.
- **2026-10-01** — C5 (artwork page, lineage): 104 messages. Sweep finding fixed: the ⋮ menu
  rows overflowed the menu in French and Japanese (labels now wrap). 3,989 Dart tests pass.
- **2026-10-01** — C4 (profiles, statistics): 92 messages. The harness gained a third detector —
  a word split across lines ("78,9 тыс" / ".") — after a screenshot of the Russian dashboard
  showed what the truncation check could not see; compact numbers in stat cards and table cells
  now scale to fit. Also fixed: profile stats row and tabs on small phones, blocked banner.
  3,469 Dart tests pass.
- **2026-10-01** — C3 (home, search, notifications, Contribute, About): 72 messages. Sweep
  findings fixed: home top bar overflow at 320 px (pre-existing, all languages), search tab
  labels cut off in Russian and Japanese. 2,869 Dart tests pass.
- **2026-10-01** — C2 (sign-in, account creation, onboarding, account management): 136 messages.
  Sweep findings fixed: the onboarding and resolving top-bar titles were truncating on phones
  (in English too); several field labels shortened per language. patch.py path bug fixed (it
  dropped new messages from an ARB edited in the same run — T1 would have caught it).
- **2026-10-01** — C1 (Club shared widgets): 123 messages × 8 languages; fake Club backend for
  sweeps; the sweeps found and fixed real overflows (comment action row, filter sheet buttons)
  and over-long field labels. 1,620 Dart tests pass.
- **2026-10-01** — L0. gen-l10n wired (`l10n.yaml`, eight ARB files, `lib/l10n/`), language
  resolution + saved override + picker, pilot extraction (Settings page, tool names with short
  tile labels), test layers T1–T6 built and self-checked, engine-backed editor test suite
  (`app/test_engine/`), scanner + baseline ratchet. 1,252 Dart tests + 8 engine-backed pass.
