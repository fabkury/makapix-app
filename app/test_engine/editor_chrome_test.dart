// T4-E (docs/i18n/TESTING.md): the REAL editor's chrome in every language — the main screen,
// the ☰ menu and its five submenus, the Show/hide tools sheet, the New document dialog, and
// the layer and frame sheets.
//
// One mount per language and size; the walk through the menus happens inside it, and every
// stop is checked: nothing overflows, no text is cut off, nothing is left untranslated.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

        Future<void> check(String where) async {
          await settleReal(tester, rounds: 2);
          final err = tester.takeException();
          if (err != null) problems.add('$where: ${err.toString().split('\n').first}');
          for (final t in truncatedTexts(tester)) {
            // The help band's tip is two lines from 360 px up (tool_tip_fit_test); on a 320 px
            // phone the longest tips end in an ellipsis in every language.
            if (size.value.width < 360 && t.text == l.tipPencil) continue;
            problems.add('$where: cut off: $t');
          }
          final left = switch (lang) {
            'ru' || 'ja' || 'zh' => leftoverLatin(tester),
            'en' => const <String>[],
            _ => leftoverEnglish(tester, lang),
          };
          for (final t in left) {
            if (t == 'Normal') continue; // blend mode names: batch E5
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
        await dismiss();

        await tester.longPress(find.text('1').first);
        await settleReal(tester, rounds: 9);
        await check('frame sheet');
        await dismiss();

        await closeEditor(tester);
        expect(problems, isEmpty);
      });
    }
  }
}
