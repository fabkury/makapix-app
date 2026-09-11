import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:package_info_plus/package_info_plus.dart';

/// The `User-Agent` every Club request carries.
///
/// Server contract (`messages/0001-app-device-type/0001`, 2026-09-09):
///
///     MakapixClub/<version>[+<build>] (<platform>[; <os version>][; <model>])
///
/// The product token plus the platform word are what the server keys on (`Android` →
/// `app_android`; `iOS` / `iPadOS` → `app_ios`; any other word, or none → `app`); everything after
/// the platform word is free-form context for the Moderator Dashboard's device metrics. Before this
/// header shipped every request carried dart:io's default `Dart/3.x (dart:io)`, which the server
/// maps to the platform-less `app` bucket permanently — so an unresolved value is harmless and
/// [init] can never break a request.
///
/// Resolved once at startup ([init], awaited in `main()` before the first Dio client is built,
/// because the clients capture the header synchronously in their `BaseOptions`). Until then — and
/// in tests, which have no platform channels — the value is the platform-only [fallback].
class ClubUserAgent {
  ClubUserAgent._();

  static const String product = 'MakapixClub';

  static String? _resolved;
  static bool _initStarted = false;

  /// The header value: the resolved string, or [fallback] until [init] completes.
  static String get value => _resolved ?? fallback;

  /// `{'User-Agent': value}` — passed as `BaseOptions.headers` by every Club Dio client.
  static Map<String, Object> get headers => {'User-Agent': value};

  /// `MakapixClub/unknown (<platform>)` — no version, no device details.
  static String get fallback => format(version: 'unknown', platform: platformWord);

  /// Resolve the version (`package_info_plus`) and the platform details (`device_info_plus`).
  /// Never throws and never hangs: any plugin failure (a missing channel in tests, a stalled call)
  /// leaves [fallback] in place. Idempotent.
  static Future<void> init() async {
    if (_initStarted) return;
    _initStarted = true;
    try {
      _resolved = await _resolve().timeout(const Duration(seconds: 3));
    } catch (_) {
      // Keep the fallback; the server's Dart-default mapping covers the rest.
    }
  }

  static Future<String> _resolve() async {
    final info = await PackageInfo.fromPlatform();
    final device = DeviceInfoPlugin();
    var platform = platformWord;
    String? os;
    String? model;
    if (Platform.isAndroid) {
      final a = await device.androidInfo;
      os = a.version.release; // "14"
      model = a.model; // "Pixel 8"
    } else if (Platform.isIOS) {
      final i = await device.iosInfo;
      // `systemName` reads "iPadOS" on some iPad builds; both words map to `app_ios`.
      platform = i.systemName == 'iPadOS' ? 'iPadOS' : 'iOS';
      os = i.systemVersion; // "18.5"
      model = i.utsname.machine; // "iPhone15,3"
    } else if (Platform.isWindows) {
      final w = await device.windowsInfo;
      os = '${w.majorVersion}.${w.minorVersion}.${w.buildNumber}'; // "10.0.26200"
    } else if (Platform.isMacOS) {
      final m = await device.macOsInfo;
      os = '${m.majorVersion}.${m.minorVersion}.${m.patchVersion}';
      model = m.model;
    } else if (Platform.isLinux) {
      final l = await device.linuxInfo;
      os = l.versionId;
    }
    return format(
        version: info.version,
        build: info.buildNumber,
        platform: platform,
        osVersion: os,
        model: model);
  }

  /// The platform word from dart:io alone (no plugin call): `Android` · `iOS` · `Windows` ·
  /// `macOS` · `Linux`, else dart:io's own name.
  static String get platformWord {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return Platform.operatingSystem;
  }

  /// Pure formatter: `format(version: '1.9.0', build: '36', platform: 'Android', osVersion: '14',
  /// model: 'Pixel 8')` → `MakapixClub/1.9.0+36 (Android 14; Pixel 8)`. Every part is reduced to
  /// printable ASCII without `(` `)` `;` (header-safe, unambiguous for the server's parser) and
  /// dropped when it comes out empty; an empty version reads `unknown`.
  static String format(
      {required String version,
      String? build,
      required String platform,
      String? osVersion,
      String? model}) {
    final ver = _clean(version);
    final bld = _clean(build ?? '');
    final token = '$product/${ver.isEmpty ? 'unknown' : ver}${bld.isEmpty ? '' : '+$bld'}';
    final plat = _clean(platform);
    final os = _clean(osVersion ?? '');
    final head = os.isEmpty ? plat : (plat.isEmpty ? os : '$plat $os');
    final parts = [head, _clean(model ?? '')].where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? token : '$token (${parts.join('; ')})';
  }

  static const int _maxPartLength = 64;

  static String _clean(String s) {
    final sb = StringBuffer();
    for (final c in s.codeUnits) {
      // Printable ASCII only, minus the three characters the grammar reserves; whitespace
      // controls become spaces (collapsed below), everything else outside the range is dropped.
      if (c == 0x09 || c == 0x0A || c == 0x0D) {
        sb.write(' ');
      } else if (c >= 0x20 && c <= 0x7E && c != 0x28 && c != 0x29 && c != 0x3B) {
        sb.writeCharCode(c);
      }
    }
    final out = sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return out.length > _maxPartLength ? out.substring(0, _maxPartLength).trimRight() : out;
  }

  @visibleForTesting
  static void resetForTest() {
    _resolved = null;
    _initStarted = false;
  }
}
