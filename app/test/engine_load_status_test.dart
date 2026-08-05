// The rc ↔ LoadStatus mapping mirrors mkpx_load's return codes (crates/ffi/src/lib.rs).
// Pure Dart — no engine binary is loaded (loadStatusFromRc is a top-level function).
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/engine_ffi.dart';

void main() {
  test('every mkpx_load return code maps to its LoadStatus', () {
    expect(loadStatusFromRc(0), LoadStatus.ok);
    expect(loadStatusFromRc(1), LoadStatus.okWithWarnings);
    expect(loadStatusFromRc(-1), LoadStatus.failed);
    expect(loadStatusFromRc(-2), LoadStatus.notMkpx);
    expect(loadStatusFromRc(-3), LoadStatus.unsupportedVersion);
    expect(loadStatusFromRc(-4), LoadStatus.corrupt);
    expect(loadStatusFromRc(-5), LoadStatus.overBudget);
  });

  test('unknown codes fail closed — never map to success', () {
    for (final rc in [-7, -100, 2, 99]) {
      expect(loadStatusFromRc(rc), LoadStatus.failed, reason: 'rc $rc');
      expect(loadStatusFromRc(rc).loaded, isFalse, reason: 'rc $rc');
    }
  });

  test('loaded is true only for ok and okWithWarnings', () {
    for (final s in LoadStatus.values) {
      expect(
        s.loaded,
        s == LoadStatus.ok || s == LoadStatus.okWithWarnings,
        reason: '$s',
      );
    }
  });
}
