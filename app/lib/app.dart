// The neutral application root. Hosts the two-pillar app shell; neither the editor
// nor the Club social layer is "the app" — both are co-equal pillars under the shell.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dev/memlab.dart';
import 'l10n/app_locale.dart';
import 'l10n/l10n.dart';
import 'shell/app_shell.dart';

/// Android overscroll uses the classic glow, NOT the Material-3 stretch effect.
///
/// The stretch effect is the app's only consumer of Impeller's backdrop-texture
/// path, and on PowerVR GPUs (Pixel 10 / Tensor G5) that path aborts the raster
/// thread once the driver's fixed-rate-compression pool is exhausted by normal
/// art browsing (VK_ERROR_COMPRESSION_EXHAUSTED_EXT → FML_CHECK(back_texture)).
/// Upstream fix: flutter/flutter#187586, not yet in a stable release. Full
/// investigation: docs/reacted-tab-investigation/REPORT.md (retired to git
/// history 2026-09-16). Revisit once the pinned Flutter carries the fix —
/// until then, don't reintroduce stretch and
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

/// The app's one theme (dark, Material 3). Shared with the l10n test harness so layout
/// checks measure text under the real styles.
ThemeData makapixTheme({List<String>? fontFamilyFallback}) => ThemeData(
      useMaterial3: true,
      // Null in the app (the OS supplies glyph fallback); the l10n tests name a CJK font here.
      fontFamilyFallback: fontFamilyFallback,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4080C0),
        brightness: Brightness.dark,
      ),
      sliderTheme: const SliderThemeData(trackHeight: 2),
    );

/// The localization delegates: the app's own strings plus Flutter's (Material, Cupertino,
/// and the text-direction basics).
const List<LocalizationsDelegate<dynamic>> kAppLocalizationsDelegates = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

class MakapixApp extends ConsumerWidget {
  const MakapixApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supported = availableLocales;
    return MaterialApp(
      title: 'Makapix Club', // l10n-ignore: brand name, never translated
      // The user's pick (Settings → Language), or null to follow the device.
      locale: ref.watch(appLocaleProvider),
      supportedLocales: supported,
      localizationsDelegates: kAppLocalizationsDelegates,
      localeListResolutionCallback: (preferred, _) => resolveAppLocale(preferred, supported),
      builder: (context, child) => L10nBinding(child: child ?? const SizedBox.shrink()),
      debugShowCheckedModeBanner: false,
      scrollBehavior: const GlowOverscrollBehavior(),
      theme: makapixTheme(),
      // MemLabGate is a pass-through unless the app was launched with the memlab intent extra
      // (adb-only memory stress lab, see lib/dev/memlab.dart) — no UI entry, no normal-start cost.
      home: const MemLabGate(child: AppShell()),
    );
  }
}
