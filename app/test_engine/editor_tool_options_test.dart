// T4-E (docs/i18n/TESTING.md): the tool options row and the help band of the REAL editor, for
// every tool, in every language, at three phone sizes and a landscape tablet.
//
// One mount per language and size (a mount costs about 1.5 s). Inside it, every tool is
// selected in turn and checked twice: as it opens, and with every chip in its options row
// switched on, which is what reveals the controls a chip hides (the Ratio slider behind Lock
// Ratio, the precision buttons behind the precision toggle, and so on).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

final _row = find.byKey(const ValueKey('editor-options-row'));
final _band = find.byKey(const ValueKey('editor-help-band'));

// Latin text that is right in every language: the AA chip, the cleanEdge algorithm, the HSV
// letters, single-letter axis labels, and pattern names (extracted in batch E5).
const _allowLatin = <Pattern>['cleanEdge'];

void main() {
  for (final locale in allLocales) {
    for (final size in _sizes.entries) {
      testWidgets('tool options — $locale @ ${size.key}', (tester) async {
        // Every tool in the grid, including the two hidden by default.
        await pumpEditor(tester, locale, size: size.value, prefs: {'tool_hidden_v1': <String>[]});
        final l = l10nFor(locale);
        final lang = locale.languageCode;
        final problems = <String>[];

        void check(String where) {
          final err = tester.takeException();
          if (err != null) problems.add('$where: ${err.toString().split('\n').first}');
          // The options row scrolls sideways, so nothing in it is cut off by the screen edge;
          // a cut-off text here is a label that does not fit its own control.
          for (final t in truncatedTexts(tester, within: _row)) {
            problems.add('$where: cut off in the options row: $t');
          }
          // The help band is two lines on a 360 px phone (tool_tip_fit_test); the 320 px
          // phone shows an ellipsis on the longest tips in every language, English included.
          if (size.value.width >= 360) {
            for (final t in truncatedTexts(tester, within: _band)) {
              problems.add('$where: cut off in the help band: $t');
            }
          }
          for (final part in [_row, _band]) {
            final left = switch (lang) {
              'ru' || 'ja' || 'zh' => leftoverLatin(tester, allow: _allowLatin, within: part),
              'en' => const <String>[],
              _ => leftoverEnglish(tester, lang, within: part),
            };
            for (final t in left) {
              problems.add('$where: not translated: "$t"');
            }
          }
        }

        for (final tool in tools) {
          final tile = find.byWidgetPredicate((w) => w is ToolTile && w.tool.dsl == tool.dsl);
          if (tile.evaluate().isEmpty) continue; // the pinned slot holds it instead of the grid
          await tester.ensureVisible(tile.first);
          await tester.pump();
          await tester.tap(tile.first);
          await settleReal(tester, rounds: 1);
          check(tool.dsl);
          expect(find.descendant(of: _band, matching: find.text(toolTip(l, tool.dsl))),
              tool.dsl == 'Onion' ? findsNothing : findsOneWidget,
              reason: 'the help band shows the tip of ${tool.dsl}');

          // Switch on every chip the row offers, one at a time; a chip can reveal more chips.
          final tapped = <String>{};
          for (var guard = 0; guard < 12; guard++) {
            final chips = find.descendant(of: _row, matching: find.byType(FilterChip));
            final next = chips.evaluate().map((e) => e.widget as FilterChip).where((c) {
              final label = c.label is Text ? (c.label as Text).data ?? '' : 'icon';
              return !c.selected && c.onSelected != null && !tapped.contains(label);
            }).toList();
            if (next.isEmpty) break;
            final chip = next.first;
            tapped.add(chip.label is Text ? (chip.label as Text).data ?? '' : 'icon');
            final finder = find.byWidget(chip);
            await tester.ensureVisible(finder);
            await tester.pump();
            await tester.tap(finder);
            await settleReal(tester, rounds: 1);
          }
          check('${tool.dsl}, every chip on');
          // One picture per tool and language for the visual review (T6).
          if (size.key == 'phone') {
            await screenshot(tester, 'editor-tool-${tool.dsl.toLowerCase()}_$lang');
          }
        }

        await closeEditor(tester);
        expect(problems, isEmpty);
      });
    }
  }
}
