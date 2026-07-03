import '../models/server_config.dart';

enum ConformanceIssue { overMax, underMinNotWhitelisted, fileTooLarge, unsupportedFormat }

class ConformanceResult {
  final bool ok;
  final List<ConformanceIssue> issues;
  final List<int>? nearestSize; // [w,h] suggestion when dimensions are wrong
  const ConformanceResult({required this.ok, this.issues = const [], this.nearestSize});

  bool get hasDimensionIssue =>
      issues.contains(ConformanceIssue.overMax) ||
      issues.contains(ConformanceIssue.underMinNotWhitelisted);
}

/// Makapix Club's accepted artwork sizes, **hardcoded** by decision (2026-07-03): the server
/// enforces these on every upload (`vault.py`) and is the real gate — the app pre-checks with
/// this copy purely for UX, and if the server rules ever change the app is updated in tandem.
/// The dimension rule: reject if either axis > [freeFormMax]; ok if both axes ≥ [freeFormMin]
/// (the free-form band); else ok iff [w,h] is in the small whitelist; otherwise reject.
class ClubSizeRules {
  static const int freeFormMin = 128;
  static const int freeFormMax = 256;

  /// Both orientations spelled out, mirroring the server list.
  static const List<List<int>> smallWhitelist = [
    [8, 8], [8, 16], [16, 8], [8, 32], [32, 8], [16, 16], [16, 32], [32, 16],
    [32, 32], [32, 64], [64, 32], [64, 64], [64, 128], [128, 64],
  ];

  static bool accepted(int w, int h) {
    if (w > freeFormMax || h > freeFormMax) return false;
    if (w >= freeFormMin && h >= freeFormMin) return true;
    return smallWhitelist.any((p) => p[0] == w && p[1] == h);
  }

  /// An accepted [w,h] suggestion: scale-to-fit the free-form band when too big,
  /// else the closest whitelist entry (L1) for small art.
  static List<int> nearest(int w, int h) {
    if (w > freeFormMax || h > freeFormMax) {
      final longest = w > h ? w : h;
      final scale = freeFormMax / longest;
      final nw = (w * scale).round().clamp(freeFormMin, freeFormMax);
      final nh = (h * scale).round().clamp(freeFormMin, freeFormMax);
      return [nw, nh];
    }
    var best = smallWhitelist.first;
    var bestDiff = 1 << 30;
    for (final p in smallWhitelist) {
      final d = (p[0] - w).abs() + (p[1] - h).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = p;
      }
    }
    return best;
  }
}

/// Pre-upload validation: dimensions against the hardcoded [ClubSizeRules], file size and
/// format against the server's [UploadRules] (from `/config`). A pass here is advisory —
/// the server re-checks everything on upload and the publish flow surfaces its rejection.
class ClubConformance {
  final ClubServerConfig config;
  const ClubConformance(this.config);

  UploadRules get _u => config.upload;

  ConformanceResult check({
    required int width,
    required int height,
    required int frameCount,
    required int byteLength,
    required String format,
  }) {
    final issues = <ConformanceIssue>[];
    if (!_u.formats.contains(format.toLowerCase())) issues.add(ConformanceIssue.unsupportedFormat);
    if (byteLength > _u.maxFileBytes) issues.add(ConformanceIssue.fileTooLarge);

    final dimsOk = ClubSizeRules.accepted(width, height);
    if (!dimsOk) {
      if (width > ClubSizeRules.freeFormMax || height > ClubSizeRules.freeFormMax) {
        issues.add(ConformanceIssue.overMax);
      } else {
        issues.add(ConformanceIssue.underMinNotWhitelisted);
      }
    }
    return ConformanceResult(
      ok: issues.isEmpty,
      issues: issues,
      nearestSize: dimsOk ? null : ClubSizeRules.nearest(width, height),
    );
  }
}
