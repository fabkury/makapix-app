// Makapix Club app — Flutter entry point. Kept deliberately thin (Flutter requires
// lib/main.dart as the default build target); the neutral app root lives in app.dart
// and the two co-equal pillars in lib/editor/ and lib/club/.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'club/api/club_user_agent.dart';
import 'dev/battery_stats.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  BatteryStats.start(); // battery debug counters — compiled out of release builds
  // The Club User-Agent (`MakapixClub/<version> (<platform>; …)`) resolves through platform
  // plugins, and the Dio clients capture it synchronously when built — so it is awaited here,
  // before any provider can construct one. Never throws; a plugin failure leaves the fallback.
  await ClubUserAgent.init();
  // ProviderScope hosts the Riverpod state (Club social layer + the editor↔Club bridge).
  runApp(const ProviderScope(child: MakapixApp()));
}
