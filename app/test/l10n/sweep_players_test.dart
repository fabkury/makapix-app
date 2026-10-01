// T4 sweeps: My Players — the list, its empty and signed-out states, the per-player menu,
// the rename and delete dialogs, and the register sheet with an error showing (batch C8).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/ui/my_players_page.dart';

import 'club_fixtures.dart';
import 'sweep.dart';

String _ago(Duration d) => DateTime.now().toUtc().subtract(d).toIso8601String();

// Device names are the user's own text; the model and firmware are the device's.
const _fixture = <Pattern>['Desk Matrix', 'Shelf Panel', 'Attic', 'p3a', 'v1.4.2'];

FakeBackend _backend({bool empty = false}) => fixtureBackend()
  ..on('GET', r'/u/[^/]+/player', (_) => {
        'items': empty
            ? const <Map<String, dynamic>>[]
            : [
                {...fixturePlayersJson().first, 'firmware_version': '1.4.2'},
                {
                  ...fixturePlayersJson().last,
                  'connection_status': 'offline',
                  'last_seen_at': _ago(const Duration(hours: 5)),
                },
                // No name and no model: the generic "Player" fallback; never seen.
                {'id': 'pl9', 'player_key': 'key9', 'connection_status': 'offline'},
              ],
      });

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert).first);
  await settleOpen(tester);
}

void main() {
  sweepScreen(
    'My Players',
    build: () => const MyPlayersPage(),
    backend: _backend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
  );

  sweepScreen(
    'My Players, none registered',
    build: () => const MyPlayersPage(),
    backend: () => _backend(empty: true),
    overrides: (b) => clubOverrides(backend: b),
  );

  sweepScreen(
    'My Players, signed out',
    build: () => const MyPlayersPage(),
    backend: _backend,
    overrides: (b) => clubOverrides(signedIn: false, backend: b),
  );

  sweepScreen(
    'My Players, player menu',
    build: () => const MyPlayersPage(),
    backend: _backend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
    act: _openMenu,
  );

  sweepScreen(
    'My Players, rename dialog',
    build: () => const MyPlayersPage(),
    backend: _backend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
    act: (tester) async {
      await _openMenu(tester);
      await tester.tap(find.byIcon(Icons.edit_outlined));
    },
  );

  sweepScreen(
    'My Players, delete dialog',
    build: () => const MyPlayersPage(),
    backend: _backend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
    act: (tester) async {
      await _openMenu(tester);
      await tester.tap(find.byIcon(Icons.delete_outline));
    },
  );

  sweepScreen(
    'My Players, register sheet with an error',
    build: () => const MyPlayersPage(),
    backend: _backend,
    overrides: (b) => clubOverrides(backend: b),
    // The example code in the empty field.
    allowLatin: [..._fixture, 'A3F8X2'],
    act: (tester) async {
      await tester.tap(find.byIcon(Icons.add).first);
      await settleOpen(tester);
      // Submit empty: the "enter the code" error appears under the fields.
      await tester.tap(find.byType(FilledButton).last);
    },
  );
}
