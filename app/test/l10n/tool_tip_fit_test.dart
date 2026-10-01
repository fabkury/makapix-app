// T5b (docs/i18n/TESTING.md): every tool's help tip fits the help band, in every language.
//
// The band under the tool buttons has a fixed height: two lines of 11 px text in portrait.
// A longer tip is cut with an ellipsis, and the part that is cut is usually the part that
// explains an option. This lays out every tip at the band's text width and counts its lines.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/tool_l10n.dart';
import 'package:makapix_club/editor/tools.dart';

import 'l10n_test_support.dart';

/// The band's text style (editor_page.canvas.dart, `_buildTooltipBand`).
const _style = TextStyle(fontSize: 11, color: Colors.white60, height: 1.25);
const double _lineHeight = 11 * 1.25;

/// The band's text width on a screen [screen] px wide: 12 px padding each side, the 13 px
/// tool icon, and the 8 px gap after it.
double _textWidth(double screen) => screen - 12 - 12 - 13 - 8;

/// The phone width every tip must fit in two lines. 360 px is the common small phone; the
/// 320 px phones still in use show an ellipsis on the longest tips, in English too.
const double _phone = 360;

void main() {
  test('every catalog tool has a tip, and no tip is orphaned', () {
    final catalog = {for (final t in tools) t.dsl};
    // Onion skin is a toggle with no options row; it has never had a tip.
    expect(catalog.difference(toolsWithTips.toSet()), {'Onion'});
    // Two tips are kept for engine tools that are reached through the Select tool's modes.
    expect(toolsWithTips.toSet().difference(catalog), {'SelectCircle', 'SelectPoly'});
  });

  for (final locale in allLocales) {
    testWidgets('tool tips fit two lines on a $_phone px phone — $locale', (tester) async {
      final l = l10nFor(locale);
      final width = _textWidth(_phone);
      await pumpLocalized(
        tester,
        locale,
        Scaffold(
          body: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final dsl in toolsWithTips)
                SizedBox(width: width, child: Text(toolTip(l, dsl), style: _style)),
            ]),
          ),
        ),
        size: const Size(412, 915),
      );
      final tooLong = <String>[];
      for (final ro in paragraphs(tester)) {
        final lines = (ro.size.height / _lineHeight).round();
        if (lines > 2) tooLong.add('$lines lines: "${ro.text.toPlainText()}"');
      }
      expect(tooLong, isEmpty, reason: 'tips cut off in the help band in $locale');
    });
  }
}
