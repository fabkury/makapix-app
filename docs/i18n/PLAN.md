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
| L1 | Club pillar: extract + translate + sweep, batch by batch | Club done (C1–C9); editor (L2) next |
| L2 | Editor pillar: extract + translate + sweep, batch by batch | not started (tool names done in L0) |
| L3 | Independent translation review (one agent per language), fixes, layout hardening | not started |
| L4 | Seams and periphery, then flip `kTranslationsShipped` | not started |

**Progress number:** the total on line 5 of `app/test/l10n/hardcoded_baseline.txt` — the
hardcoded strings the scanner still finds. 2,683 after L0 (scanner as tightened in C1); 2,516
after C1; 2,334 after C2; 2,253 after C3; 2,125 after C4; 2,000 after C5; 1,856 after C6; 1,709 after C7; 1,654 after C8; 1,598 after C9 (all in `lib/editor`); 1,048 after E1 + E8; 877 after E2. Zero means L1 + L2 are done.

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
  Still English inside this row until E5: pattern and dither names in the swatch tooltip.
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
- [ ] **E3 Files** — editor_page.fileio (103), .persistence (19), open_file (2), gallery (17),
  dialogs: crop (41), place (30), duration (4), rename (4), persistence/drawing_meta (4)
- [ ] **E4 Frames and layers** — frames/ (page 44, more_sheet 44, dialogs 22, action_bar 7,
  layer_name_picker 4, frame_set 4, tile 1, selection 1), layers/ (page 41, more_sheet 61,
  dialogs 27, action_bar 7, select_sheet 4, layer_model 13, row 2)
- [ ] **E5 Color** — palette_page (52), palette_io (7), artwork_colors_page (24),
  color_picker_dialog (6), blend_modes (38), patterns/ (gradient_dither 39, catalog 18, page 14, tile 2)
- [ ] **E6 Keyboard** — keyboard/commands (67; make `CommandDef.label` a per-build lookup —
  the L0 bridge `t.name(appL10n)` in commands.dart is marked TODO), cheat_sheet (18), chords (13)
- [ ] **E7 Replay and timelapse** — editor_page.replay (28), replay/ (page 9, host 4,
  journal_format 5, action_runner 2, timelapse_plan 2, timelapse_export 1), tap_again (1)
- [x] **E8 Engine-name files** — done 2026-10-01: `replay/visible_index.dart` holds only DSL
  verb and tool names (checked: 212 of 212) and is marked `l10n-ignore-file`.

## L3 — Review and hardening

- [ ] One independent review agent per language (7), each given only the English ARB (with
  descriptions), the glossary, and the translation: back-translate, flag meaning drift, wrong
  register, inconsistent terms, unnatural phrasing, plural errors. It never sees my reasoning.
- [ ] Apply the fixes; second pass on the changed messages only.
- [ ] Glossary conformance check as a tool (`tool/l10n/glossary_check.dart`).
- [ ] Full screenshot gallery (T6) reviewed per language: every sweep screen.
- [ ] Layout hardening for whatever the sweeps flag in German and Russian.
- [ ] Text scale 1.3× sweep on the phone sizes (accessibility font size).

## L4 — Seams, periphery, release

- [ ] **Engine error text at the FFI**: stable codes where `mkpx_run` and the load/import paths
  return English prose that reaches the user; Dart maps code → message. Inventory first.
- [ ] **Server text**: open `messages/0005-localized-text/` proposing codes + params for API error
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
- [ ] **Default names stored in documents** ("Layer 1", "Untitled"): decide display-time mapping
  vs. localized-at-creation; ADR.
- [ ] **Android**: `res/xml/locales_config.xml` + `android:localeConfig` (per-app language in
  system settings, Android 13+); confirm the app label stays "Makapix Club".
- [ ] **iOS**: `CFBundleLocalizations` in Info.plist; localized `NSPhotoLibraryUsageDescription` /
  `NSCameraUsageDescription` (`InfoPlist.strings`). First real check is the next Codemagic build
  on TestFlight — record the result here.
- [ ] **Windows**: smoke-test CJK and Cyrillic rendering in the real build (system font fallback).
- [ ] **Material's own strings** (date pickers, text-selection menu, back-button tooltip): confirm
  per language in a sweep.
- [ ] Add `flutter gen-l10n` and `flutter test test_engine` to `release_android.ps1` gates.
- [ ] **Live pass**: Windows build and the Pixel over wireless adb — per language, screenshot the
  key screens; confirm device-language pickup and the override surviving a restart.
- [ ] **Store listings**: title, short and full description, release notes for the seven
  languages (Play + App Store), as files under `docs/marketing/`.
- [ ] **Store screenshots** per language through the store-slide pipeline.
- [ ] Flip `kTranslationsShipped` to `true`; update README, STATUS.md, CLAUDE.md; release notes.

## Open questions and risks

- 8.5 px tile labels in Japanese and Chinese: legible in the 2× screenshots, but dense kanji at
  that size on a real phone is the first thing to look at in the live pass.
- Traditional Chinese devices currently get Simplified (no `zh_Hant` translation). Revisit if
  there is demand.
- `use-escaping` is off, so a message cannot contain a literal `{` or `}`.

## Findings outside i18n

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
