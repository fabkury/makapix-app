// Blend-mode metadata invariants — pure Dart, no engine binary.
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/blend_modes.dart';

void main() {
  test('the groups cover every token exactly once, in a known universe', () {
    final grouped = [for (final (_, modes) in kBlendGroups) ...modes];
    expect(grouped.toSet(), kBlendModes.toSet());
    expect(grouped.length, kBlendModes.length, reason: 'no token appears twice');
    expect(kBlendModes.length, 11);
    expect(kBlendModes.first, 'Normal');
  });

  test('display names match engine tokens except Hard Light', () {
    expect(blendDisplayName('HardLight'), 'Hard Light');
    for (final t in kBlendModes.where((t) => t != 'HardLight')) {
      expect(blendDisplayName(t), t);
    }
  });

  test('badges: none for Normal, unique two-letter codes for the ten modes', () {
    expect(blendBadge('Normal'), '');
    expect(blendBadge('SomethingUnknown'), '');
    final badges = [for (final t in kBlendModes.where((t) => t != 'Normal')) blendBadge(t)];
    expect(badges.length, 10);
    for (final b in badges) {
      expect(b.length, 2, reason: b);
    }
    expect(badges.toSet().length, badges.length, reason: 'badges collide: $badges');
  });
}
