import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/palette_io.dart';
import 'package:makapix_club/editor/palette_page.dart';

class FakePaletteHost implements PaletteHost {
  FakePaletteHost(this.palettes, {this.active = 0, this.usedColors = '{"colors":[]}'});
  List<PaletteInfo> palettes;
  int active;
  String usedColors;
  final List<String> scripts = [];

  @override
  ({List<PaletteInfo> palettes, int active}) readPalettes() => (palettes: palettes, active: active);

  @override
  String? run(String dsl) {
    scripts.add(dsl);
    return null;
  }

  @override
  String usedColorsJson() => usedColors;
}

const _red = Color(0xFFFF0000);
const _green = Color(0xFF00FF00);

/// Pushes the page over a base route so load-and-return pops are real.
Future<void> pumpPalettePage(
  WidgetTester t,
  FakePaletteHost host, {
  List<PaletteInfo> presets = const [],
}) async {
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: Brightness.dark),
    home: Builder(
      builder: (ctx) => Center(
        child: ElevatedButton(
          onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
            builder: (_) => PalettePage(host: host, presetLoader: () async => presets),
          )),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('renders a card per palette: name, count, active check, empty placeholder',
      (t) async {
    final host = FakePaletteHost([
      const PaletteInfo('Warm', [_red, _green]),
      const PaletteInfo('Blank', []),
    ]);
    await pumpPalettePage(t, host);
    expect(find.text('Warm'), findsOneWidget);
    expect(find.text('Blank'), findsOneWidget);
    expect(find.text('2 colours'), findsOneWidget);
    expect(find.text('0 colours'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget); // only the active card
    expect(find.text('empty'), findsOneWidget);
  });

  testWidgets('a palette too big for 3 rows is trimmed with a … cell', (t) async {
    final host = FakePaletteHost([
      PaletteInfo('Big', [for (var i = 0; i < 200; i++) Color(0xFF000000 + i)]),
    ]);
    await pumpPalettePage(t, host);
    expect(find.text('…'), findsOneWidget);
    expect(find.text('200 colours'), findsOneWidget);
  });

  testWidgets('tapping a palette loads it and returns to the editor', (t) async {
    final host = FakePaletteHost([
      const PaletteInfo('A', [_red]),
      const PaletteInfo('B', [_green]),
    ]);
    await pumpPalettePage(t, host);
    await t.tap(find.text('B'));
    await t.pumpAndSettle();
    expect(host.scripts, ['SetActivePalette(1)']);
    expect(find.byType(PalettePage), findsNothing); // popped back
  });

  testWidgets('delete always reconfirms; cancel sends nothing, confirm sends DeletePalette',
      (t) async {
    final host = FakePaletteHost([
      const PaletteInfo('Keep', [_red]),
      const PaletteInfo('Doomed', [_green]),
    ]);
    await pumpPalettePage(t, host);

    await t.longPress(find.text('Doomed'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ListTile, 'Delete'));
    await t.pumpAndSettle();
    expect(find.text('Delete "Doomed"?'), findsOneWidget);
    await t.tap(find.widgetWithText(TextButton, 'Cancel'));
    await t.pumpAndSettle();
    expect(host.scripts, isEmpty);

    await t.longPress(find.text('Doomed'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ListTile, 'Delete'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Delete'));
    await t.pumpAndSettle();
    expect(host.scripts, ['DeletePalette(1)']);
  });

  testWidgets('the last palette cannot be deleted (tile disabled)', (t) async {
    final host = FakePaletteHost([const PaletteInfo('Only', [_red])]);
    await pumpPalettePage(t, host);
    await t.longPress(find.text('Only'));
    await t.pumpAndSettle();
    final tile = t.widget<ListTile>(find.widgetWithText(ListTile, 'Delete'));
    expect(tile.enabled, isFalse);
  });

  testWidgets('clear reconfirms on a non-empty palette and is disabled on an empty one',
      (t) async {
    final host = FakePaletteHost([
      const PaletteInfo('Full', [_red, _green]),
      const PaletteInfo('Blank', []),
    ]);
    await pumpPalettePage(t, host);

    await t.longPress(find.text('Blank'));
    await t.pumpAndSettle();
    expect(t.widget<ListTile>(find.widgetWithText(ListTile, 'Clear')).enabled, isFalse);
    await t.tapAt(const Offset(400, 50)); // dismiss the sheet
    await t.pumpAndSettle();

    await t.longPress(find.text('Full'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ListTile, 'Clear'));
    await t.pumpAndSettle();
    expect(find.text('Clear "Full"?'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Clear'));
    await t.pumpAndSettle();
    expect(host.scripts, ['ClearPaletteAt(0)']);
  });

  testWidgets('rename sends a sanitised single-line RenamePaletteAt', (t) async {
    final host = FakePaletteHost([const PaletteInfo('Warm', [_red])]);
    await pumpPalettePage(t, host);
    await t.longPress(find.text('Warm'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ListTile, 'Rename'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'a;b "q"');
    await t.tap(find.widgetWithText(FilledButton, 'Rename'));
    await t.pumpAndSettle();
    expect(host.scripts, ["RenamePaletteAt(0, a b 'q')"]);
  });

  testWidgets('tapping a preset imports it as one batched script and returns', (t) async {
    final host = FakePaletteHost([const PaletteInfo('Mine', [_red])]);
    await pumpPalettePage(t, host, presets: [
      const PaletteInfo('Fake Preset', [_red, _green]),
    ]);
    expect(find.text('Presets'), findsOneWidget);
    await t.tap(find.text('Fake Preset'));
    await t.pumpAndSettle();
    expect(host.scripts, [
      'NewPalette(Fake Preset)\nAddPaletteColor(#FF0000FF)\nAddPaletteColor(#00FF00FF)',
    ]);
    expect(find.byType(PalettePage), findsNothing); // popped back
  });

  testWidgets('from-artwork over the colour limit shows the toast and sends nothing', (t) async {
    final host = FakePaletteHost(
      [const PaletteInfo('Mine', [_red])],
      usedColors: '{"over_limit":true}',
    );
    await pumpPalettePage(t, host);
    await t.tap(find.byTooltip('Add palette'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ListTile, 'From artwork colours'));
    await t.pumpAndSettle();
    expect(host.scripts, isEmpty);
    expect(find.textContaining('more than 256 colours'), findsOneWidget);
  });

  testWidgets('from-artwork with colours creates the Artwork colours palette', (t) async {
    final host = FakePaletteHost(
      [const PaletteInfo('Mine', [_red])],
      usedColors: '{"colors":["#FF0000FF","#00FF00FF"]}',
    );
    await pumpPalettePage(t, host);
    await t.tap(find.byTooltip('Add palette'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ListTile, 'From artwork colours'));
    await t.pumpAndSettle();
    expect(host.scripts, [
      'NewPalette(Artwork colours)\nAddPaletteColor(#FF0000FF)\nAddPaletteColor(#00FF00FF)',
    ]);
  });
}
