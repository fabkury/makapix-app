// The neutral application root. Hosts the two-pillar app shell; neither the editor
// nor the Club social layer is "the app" — both are co-equal pillars under the shell.
import 'package:flutter/material.dart';

import 'dev/memlab.dart';
import 'shell/app_shell.dart';

class MakapixApp extends StatelessWidget {
  const MakapixApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Makapix Club',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4080C0),
          brightness: Brightness.dark,
        ),
        sliderTheme: const SliderThemeData(trackHeight: 2),
      ),
      // MemLabGate is a pass-through unless the app was launched with the memlab intent extra
      // (adb-only memory stress lab, see lib/dev/memlab.dart) — no UI entry, no normal-start cost.
      home: const MemLabGate(child: AppShell()),
    );
  }
}
