// Makapix Club app — Flutter entry point. Kept deliberately thin (Flutter requires
// lib/main.dart as the default build target); the neutral app root lives in app.dart
// and the two co-equal pillars in lib/editor/ and lib/club/.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // ProviderScope hosts the Riverpod state (Club social layer + the editor↔Club bridge).
  runApp(const ProviderScope(child: MakapixApp()));
}
