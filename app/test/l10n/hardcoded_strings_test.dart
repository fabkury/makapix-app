// T2 (docs/i18n/TESTING.md): no user-facing string is hardcoded in lib/.
//
// tool/l10n/scan.dart finds string literals that look like display text. While the extraction
// is in progress each file is pinned to the number it still has (hardcoded_baseline.txt): a
// file may not gain one, and when it loses some the pin must be lowered. Once the baseline is
// empty this is a plain "zero findings" gate, and new UI text has to go through the ARB files
// (or carry a `// l10n-ignore: <why>` comment).
import 'package:flutter_test/flutter_test.dart';

import '../../tool/l10n/scan.dart';

void main() {
  test('no file has more hardcoded strings than its baseline (and no fewer, unpinned)', () {
    final actual = countsByFile(scan('lib'));
    final baseline = readBaseline();
    final grew = <String>[];
    final shrank = <String>[];
    for (final file in {...actual.keys, ...baseline.keys}) {
      final now = actual[file] ?? 0;
      final pinned = baseline[file] ?? 0;
      if (now > pinned) grew.add('$file: $pinned → $now');
      if (now < pinned) shrank.add('$file: $pinned → $now');
    }
    expect(grew, isEmpty,
        reason: 'new hardcoded UI strings — move them to lib/l10n/app_en.arb, or mark a '
            'non-UI literal with `// l10n-ignore: <why>`.\n'
            'List them with: dart run tool/l10n/scan.dart --list <file>');
    expect(shrank, isEmpty,
        reason: 'strings were extracted — re-pin with: dart run tool/l10n/scan.dart --write-baseline');
  });
}
