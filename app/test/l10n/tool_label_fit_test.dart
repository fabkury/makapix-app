// T5 (docs/i18n/TESTING.md): every row-3 tool label fits its tile, in every language.
//
// The tile is 54 px wide and its label is one line of 8.5 px type, clipped — the tightest
// text box in the app. A translation that is one glyph too long loses that glyph silently on
// a phone. This pumps the real [ToolTile] with real font metrics and fails on any clip.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/tool_l10n.dart';
import 'package:makapix_club/editor/tools.dart';
import 'package:makapix_club/editor/widgets/tool_tile.dart';

import 'l10n_test_support.dart';

/// Every tile the toolbar can show: the catalog plus the pinned Undo / Redo / Repeat faces.
const List<ToolDef> _allTiles = [...tools, undoToolDef, redoToolDef, repeatToolDef];

void main() {
  test('every tile face has names', () {
    expect({for (final t in _allTiles) t.face}.difference(toolFaces.toSet()), isEmpty);
    expect(toolFaces.toSet().difference({for (final t in _allTiles) t.face}), isEmpty,
        reason: 'names for a tool that is no longer in the catalog');
  });

  for (final locale in allLocales) {
    testWidgets('tool labels fit the tile — $locale', (tester) async {
      await pumpLocalized(
        tester,
        locale,
        Scaffold(
          body: SingleChildScrollView(
            child: Wrap(children: [
              for (final t in _allTiles) ToolTile(t, selected: false),
            ]),
          ),
        ),
        size: const Size(412, 915),
      );
      expect(find.byType(ToolTile), findsNWidgets(_allTiles.length));
      expect(truncatedTexts(tester), isEmpty, reason: 'clipped tile labels in $locale');
      // Fitting in Roboto is not enough: other platform fonts set wider. Hold each label to
      // the budget, which leaves that reserve.
      final overBudget = [
        for (final ro in paragraphs(tester))
          if (ro.getMaxIntrinsicWidth(double.infinity) > ToolTile.labelBudget)
            '"${ro.text.toPlainText()}" is ${ro.getMaxIntrinsicWidth(double.infinity).toStringAsFixed(1)} px',
      ];
      expect(overBudget, isEmpty,
          reason: 'tile labels over the ${ToolTile.labelBudget} px budget in $locale');
    });

    test('short labels are distinct, and no longer than the full name — $locale', () {
      final l = l10nFor(locale);
      final shorts = <String, String>{};
      final problems = <String>[];
      for (final face in toolFaces) {
        final short = toolShortLabel(l, face);
        final full = toolName(l, face);
        if (short.runes.length > full.runes.length) problems.add('$face: "$short" longer than "$full"');
        final clash = shorts[short];
        if (clash != null) problems.add('"$short" names both $clash and $face');
        shorts[short] = face;
      }
      expect(problems, isEmpty);
    });
  }
}
