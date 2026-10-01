// T4-E (docs/i18n/TESTING.md): the REAL editor's chrome in every language — the main screen,
// the ☰ menu and its five submenus, the Show/hide tools sheet, the New document dialog, the
// layer and frame sheets, the blend mode list, the duration and Resize canvas dialogs, the
// rename dialog, My Drawings, and the keep-or-discard question.
//
// One mount per language and size; the walk through the menus happens inside it, and every
// stop is checked: nothing overflows, no text is cut off, nothing is left untranslated.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:makapix_club/editor/gallery/gallery_page.dart';
import 'package:makapix_club/editor/replay/replay_page.dart';
import 'package:makapix_club/editor/tap_again.dart';
import 'package:makapix_club/editor/tool_l10n.dart';
import 'package:makapix_club/editor/tools.dart';
import 'package:makapix_club/editor/widgets/tool_tile.dart';

import 'editor_harness.dart';

const _sizes = <String, Size>{
  'phone-small': Size(320, 568),
  'phone': Size(360, 740),
  'phone-large': Size(412, 915),
  'tablet-landscape': Size(1280, 800),
};

void main() {
  for (final locale in allLocales) {
    for (final size in _sizes.entries) {
      testWidgets('editor chrome — $locale @ ${size.key}', (tester) async {
        WidgetController.hitTestWarningShouldBeFatal = true;
        addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
        await pumpEditor(tester, locale, size: size.value);
        final l = l10nFor(locale);
        final lang = locale.languageCode;
        final problems = <String>[];
        final tips = {for (final t in tools) toolTip(l, t.dsl)};

        Future<void> check(String where) async {
          await settleReal(tester, rounds: 2);
          final err = tester.takeException();
          if (err != null) problems.add('$where: ${err.toString().split('\n').first}');
          for (final t in truncatedTexts(tester)) {
            // The help band's tip is two lines from 360 px up (tool_tip_fit_test); on a 320 px
            // phone the longest tips end in an ellipsis in every language.
            if (size.value.width < 360 && tips.contains(t.text)) continue;
            problems.add('$where: cut off: $t');
          }
          final left = switch (lang) {
            'ru' || 'ja' || 'zh' => leftoverLatin(tester),
            'en' => const <String>[],
            _ => leftoverEnglish(tester, lang),
          };
          for (final t in left) {
            problems.add('$where: not translated: "$t"');
          }
          if (size.key == 'phone') {
            final slug = where.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
            await screenshot(tester, 'editor-chrome-${slug}_$lang');
          }
        }

        Future<void> dismiss() async {
          await tester.tapAt(const Offset(4, 4)); // the modal barrier, away from every sheet
          await settleReal(tester, rounds: 9);
        }

        Future<void> openMenu() async {
          await tester.tap(find.byIcon(Icons.menu));
          await settleReal(tester, rounds: 9);
        }

        await check('main screen');

        await openMenu();
        await check('menu');
        await dismiss();

        // The five submenus, each a bottom sheet.
        for (final (name, icon) in const [
          ('social', Icons.groups_outlined),
          ('file', Icons.folder_outlined),
          ('import and export', Icons.import_export),
          ('canvas', Icons.crop_rotate),
          ('view', Icons.visibility_outlined),
        ]) {
          await openMenu();
          await tester.tap(find.byIcon(icon).last);
          await settleReal(tester, rounds: 9);
          await check('menu, $name');
          await dismiss();
        }

        // View → Show/hide tools…
        await openMenu();
        await tester.tap(find.byIcon(Icons.visibility_outlined).last);
        await settleReal(tester, rounds: 9);
        await tester.tap(find.byIcon(Icons.checklist));
        await settleReal(tester, rounds: 9);
        await check('show-hide tools');
        await dismiss();

        // File → New: the dialog, then with a size the Club does not accept.
        await openMenu();
        await tester.tap(find.byIcon(Icons.folder_outlined).last);
        await settleReal(tester, rounds: 9);
        await tester.tap(find.byIcon(Icons.insert_drive_file_outlined));
        await settleReal(tester, rounds: 9);
        await check('new document');
        await tester.enterText(find.byType(TextField).at(1), '100');
        await check('new document, not a Club size');
        await tester.enterText(find.byType(TextField).at(1), '0');
        await check('new document, size out of range');
        // Inside the dialog: in French "Annuler" is also the Undo tile's label.
        await tester.tap(
            find.descendant(of: find.byType(AlertDialog), matching: find.text(l.commonCancel)));
        await settleReal(tester, rounds: 9);

        // The layer sheet (long-press the layer tile) and the frame sheet.
        await tester.longPress(find.byIcon(Icons.visibility).first);
        await settleReal(tester, rounds: 9);
        await check('layer sheet');
        // Its blend mode list (the row shows the current mode, Normal).
        await tester.tap(find.text(l.blendNormal).last);
        await settleReal(tester, rounds: 9);
        await check('layer sheet, blend list');
        await dismiss();
        await dismiss();

        await tester.longPress(find.text('1').first);
        await settleReal(tester, rounds: 9);
        await check('frame sheet');
        await dismiss();

        // The frame sheet's duration dialog.
        await tester.longPress(find.text('1').first);
        await settleReal(tester, rounds: 9);
        await tester.tap(find.byIcon(Icons.timer_outlined));
        await settleReal(tester, rounds: 9);
        await check('frame duration');
        await dismiss();

        // Canvas → Resize canvas…, then with a size the Club does not accept.
        await openMenu();
        await tester.tap(find.byIcon(Icons.crop_rotate).last);
        await settleReal(tester, rounds: 9);
        await tester.tap(find.byIcon(Icons.aspect_ratio).last); // the Resize tool's tile wears it too
        await settleReal(tester, rounds: 9);
        await check('resize canvas');
        await tester.tap(find.text('32²'));
        await tester.pump();
        await tester.tap(find.byIcon(Icons.north_west));
        await check('resize canvas, anchored');
        await dismiss();

        // Rename drawing (the first row of the menu).
        await openMenu();
        await tester.tap(find.byIcon(Icons.edit).last);
        await settleReal(tester, rounds: 9);
        await check('rename drawing');
        await dismiss();

        // File → My Drawings, its per-drawing menu, and back.
        await openMenu();
        await tester.tap(find.byIcon(Icons.folder_outlined).last);
        await settleReal(tester, rounds: 9);
        await tester.tap(find.byIcon(Icons.collections_bookmark_outlined));
        await settleReal(tester, rounds: 12);
        await check('my drawings');
        await tester.tap(find.byIcon(Icons.more_vert).first);
        await settleReal(tester, rounds: 9);
        await check('my drawings, drawing menu');
        await dismiss();
        // Leave My Drawings the way the system back gesture does.
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await settleReal(tester, rounds: 12);
        expect(find.byType(GalleryPage), findsNothing);

        // Add a layer so the drawing is worth keeping (a one-layer, never-painted document is
        // replaced without a question), then File → New → Create: the keep-or-discard
        // question, and the second confirmation behind Discard.
        await tester.longPress(find.byIcon(Icons.visibility).first);
        await settleReal(tester, rounds: 9);
        await tester.ensureVisible(find.byIcon(Icons.add_box_outlined).last);
        await tester.tap(find.byIcon(Icons.add_box_outlined).last);
        await settleReal(tester, rounds: 3);
        // With two layers Delete layer is live: one tap arms it ("Tap again to confirm").
        await tester.ensureVisible(find.byType(TapAgainDeleteButton).last);
        await tester.pump();
        await tester.tap(find.byType(TapAgainDeleteButton).last);
        await check('layer sheet, delete armed');
        await dismiss();
        await openMenu();
        await tester.tap(find.byIcon(Icons.folder_outlined).last);
        await settleReal(tester, rounds: 9);
        await tester.tap(find.byIcon(Icons.insert_drive_file_outlined));
        await settleReal(tester, rounds: 9);
        await tester.tap(find.descendant(
            of: find.byType(AlertDialog), matching: find.text(l.commonCreate)));
        await settleReal(tester, rounds: 9);
        if (find.text(l.outgoingKeep).evaluate().isNotEmpty) {
          await check('keep or discard');
          await tester.tap(find.text(l.outgoingDiscard));
          await settleReal(tester, rounds: 9);
          await check('discard, are you sure');
          await tester.tap(find.descendant(
              of: find.byType(AlertDialog), matching: find.text(l.commonCancel)));
          await settleReal(tester, rounds: 9);
        } else {
          problems.add('the keep-or-discard dialog did not open');
        }

        // ☰ → Watch replay: the Replay page on a real journal, then the timelapse options.
        await openMenu();
        await tester.ensureVisible(find.byIcon(Icons.replay).last);
        await tester.pump();
        await tester.tap(find.byIcon(Icons.replay).last);
        await settleReal(tester, rounds: 20);
        if (find.byType(ReplayPage).evaluate().isNotEmpty) {
          if (find.byIcon(Icons.pause).evaluate().isNotEmpty) {
            await tester.tap(find.byIcon(Icons.pause).first); // stop the sweep
            await settleReal(tester, rounds: 2);
          }
          await check('replay page');
          final share = find.text(ReplayPage.shareLabel(defaultTargetPlatform));
          if (share.evaluate().isNotEmpty) {
            await tester.tap(share);
            await settleReal(tester, rounds: 9);
            await check('timelapse options');
            await tester.tap(find.descendant(
                of: find.byType(AlertDialog), matching: find.text(l.commonCancel)));
            await settleReal(tester, rounds: 9);
          } else {
            problems.add('the Replay page has no share button');
          }
          tester.state<NavigatorState>(find.byType(Navigator).first).pop();
          await settleReal(tester, rounds: 12);
        } else {
          problems.add('Watch replay did not open the Replay page');
        }

        // The Play tool's options row: Go to… and its dialog. (Last: it changes the tool.)
        final playTile = find.byWidgetPredicate((w) => w is ToolTile && w.tool.dsl == 'PlayPause');
        if (playTile.evaluate().isNotEmpty) {
          await tester.ensureVisible(playTile.first);
          await tester.pump();
          await tester.tap(playTile.first);
          await settleReal(tester, rounds: 2);
          final goTo = find.text(l.optGoTo);
          await tester.ensureVisible(goTo);
          await tester.pump();
          await tester.tap(goTo);
          await settleReal(tester, rounds: 9);
          await check('go to frame');
          await tester.tap(find.descendant(
              of: find.byType(AlertDialog), matching: find.text(l.commonCancel)));
          await settleReal(tester, rounds: 9);
        } else {
          problems.add('the Play tool is not in the grid');
        }

        await closeEditor(tester);
        expect(problems, isEmpty);
      });
    }
  }
}
