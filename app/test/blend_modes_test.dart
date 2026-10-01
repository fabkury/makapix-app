// Blend-mode metadata invariants — pure Dart, no engine binary.
import 'package:flutter_test/flutter_test.dart';
import 'dart:ui' show Locale;

import 'package:makapix_club/editor/blend_l10n.dart';
import 'package:makapix_club/editor/blend_modes.dart';

import 'l10n/l10n_test_support.dart';

void main() {
  test('the groups cover every token exactly once, in a known universe', () {
    final grouped = [for (final (_, modes) in kBlendGroups) ...modes];
    expect(grouped.toSet(), kBlendModes.toSet());
    expect(grouped.length, kBlendModes.length, reason: 'no token appears twice');
    expect(kBlendModes.length, 11);
    expect(kBlendModes.first, 'Normal');
  });

  test('English display names match engine tokens except Hard Light', () {
    final en = l10nFor(const Locale('en'));
    expect(blendName(en, 'HardLight'), 'Hard Light');
    for (final t in kBlendModes.where((t) => t != 'HardLight')) {
      expect(blendName(en, t), t);
    }
  });

  test('every language names every mode and every group, all different', () {
    for (final locale in allLocales) {
      final l = l10nFor(locale);
      final names = [for (final t in kBlendModes) blendName(l, t)];
      expect(names.toSet().length, names.length, reason: '$locale: two modes share a name: $names');
      final groups = [for (final (g, _) in kBlendGroups) blendGroupName(l, g)];
      expect(groups.toSet().length, groups.length, reason: '$locale: two groups share a heading: $groups');
    }
  });

  test('badges: none for Normal, unique short codes for the ten modes, in every language', () {
    for (final locale in allLocales) {
      final l = l10nFor(locale);
      expect(blendBadgeText(l, 'Normal'), '');
      expect(blendBadgeText(l, 'SomethingUnknown'), '');
      expect(l.blendBadges.split(',').length, 10, reason: '$locale');
      final badges = [for (final t in kBlendModes.where((t) => t != 'Normal')) blendBadgeText(l, t)];
      // Two letters; one character where a character is as wide as two letters.
      final want = locale.languageCode == 'ja' || locale.languageCode == 'zh' ? 1 : 2;
      for (final b in badges) {
        expect(b.runes.length, want, reason: '$locale: $b');
      }
      expect(badges.toSet().length, badges.length, reason: '$locale: badges collide: $badges');
    }
  });
}
