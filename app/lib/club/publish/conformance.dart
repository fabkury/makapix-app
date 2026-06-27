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

/// Validates a document against the server's [UploadRules] (from `/config`).
/// The dimension rule mirrors `vault.py`: reject if either axis > max; ok if
/// both axes ≥ min (the 128–256 free-form band); else ok iff [w,h] is in the
/// small whitelist; otherwise reject.
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

    final dimsOk = _dimensionsOk(width, height);
    if (!dimsOk) {
      if (width > _u.freeFormMax || height > _u.freeFormMax) {
        issues.add(ConformanceIssue.overMax);
      } else {
        issues.add(ConformanceIssue.underMinNotWhitelisted);
      }
    }
    return ConformanceResult(
      ok: issues.isEmpty,
      issues: issues,
      nearestSize: dimsOk ? null : nearestConformantSize(width, height),
    );
  }

  bool _dimensionsOk(int w, int h) {
    if (w > _u.freeFormMax || h > _u.freeFormMax) return false;
    if (w >= _u.freeFormMin && h >= _u.freeFormMin) return true;
    return _u.smallWhitelist.any((p) => p.length == 2 && p[0] == w && p[1] == h);
  }

  /// A conformant [w,h] suggestion: scale-to-fit the free-form band when too big,
  /// else the closest whitelist entry (L1) for small art.
  List<int> nearestConformantSize(int w, int h) {
    if (w > _u.freeFormMax || h > _u.freeFormMax) {
      final longest = w > h ? w : h;
      final scale = _u.freeFormMax / longest;
      final nw = (w * scale).round().clamp(_u.freeFormMin, _u.freeFormMax);
      final nh = (h * scale).round().clamp(_u.freeFormMin, _u.freeFormMax);
      return [nw, nh];
    }
    var best = _u.smallWhitelist.isNotEmpty ? _u.smallWhitelist.first : [_u.freeFormMin, _u.freeFormMin];
    var bestDiff = 1 << 30;
    for (final p in _u.smallWhitelist) {
      if (p.length != 2) continue;
      final d = (p[0] - w).abs() + (p[1] - h).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = p;
      }
    }
    return best;
  }
}
