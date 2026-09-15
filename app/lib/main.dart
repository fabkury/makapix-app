// Makapix Club app — Flutter entry point. Kept deliberately thin (Flutter requires
// lib/main.dart as the default build target); the neutral app root lives in app.dart
// and the two co-equal pillars in lib/editor/ and lib/club/.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'club/api/club_user_agent.dart';
import 'dev/battery_stats.dart';
import 'shell/launch_pillar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  BatteryStats.start(); // battery debug counters — compiled out of release builds
  // The Club User-Agent (`MakapixClub/<version> (<platform>; …)`) resolves through platform
  // plugins, and the Dio clients capture it synchronously when built — so it is awaited here,
  // before any provider can construct one. Never throws; a plugin failure leaves the fallback.
  await ClubUserAgent.init();
  // Which pillar to mount first: the editor if that is where the user was within the last
  // 24 h (ADR 0035), else the Club. Decided before the first frame so nothing flashes; a
  // preferences hiccup means the Club. Never throws, bounded at 2 s.
  final launchPillar = await LaunchPillarMemory.read();
  // ProviderScope hosts the Riverpod state (Club social layer + the editor↔Club bridge).
  runApp(ProviderScope(
    overrides: [launchPillarProvider.overrideWithValue(launchPillar)],
    child: const MakapixApp(),
  ));
}
