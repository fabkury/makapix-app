// The neutral application root. Hosts the two-pillar app shell; neither the editor
// nor the Club social layer is "the app" — both are co-equal pillars under the shell.
import 'package:flutter/material.dart';

import 'dev/memlab.dart';
import 'shell/app_shell.dart';

/// Android overscroll uses the classic glow, NOT the Material-3 stretch effect.
///
/// The stretch effect is the app's only consumer of Impeller's backdrop-texture
/// path, and on PowerVR GPUs (Pixel 10 / Tensor G5) that path aborts the raster
/// thread once the driver's fixed-rate-compression pool is exhausted by normal
/// art browsing (VK_ERROR_COMPRESSION_EXHAUSTED_EXT → FML_CHECK(back_texture)).
/// Upstream fix: flutter/flutter#187586, not yet in a stable release. Full
/// investigation: docs/reacted-tab-investigation/REPORT.md. Revisit once the
/// pinned Flutter carries the fix — until then, don't reintroduce stretch and
/// don't add other backdrop consumers (BackdropFilter, advanced blend modes).
class GlowOverscrollBehavior extends MaterialScrollBehavior {
  const GlowOverscrollBehavior();

  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    switch (getPlatform(context)) {
      case TargetPlatform.android:
        return GlowingOverscrollIndicator(
          axisDirection: details.direction,
          color: Theme.of(context).colorScheme.secondary,
          child: child,
        );
      default:
        return super.buildOverscrollIndicator(context, child, details);
    }
  }
}

class MakapixApp extends StatelessWidget {
  const MakapixApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Makapix Club',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const GlowOverscrollBehavior(),
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
