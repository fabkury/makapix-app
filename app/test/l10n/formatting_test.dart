// Relative times, file sizes, and compact counts in every language: the helpers in
// club/ui/widgets/common.dart read the current language through `appL10n`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/ui/widgets/common.dart';

import 'l10n_test_support.dart';

DateTime _ago(Duration d) => DateTime.now().toUtc().subtract(d);

void main() {
  /// Runs [body] with the app showing [locale].
  Future<void> inLocale(WidgetTester tester, String locale, void Function() body) async {
    await pumpLocalized(tester, Locale(locale), const SizedBox());
    body();
  }

  testWidgets('English keeps its compact forms', (tester) async {
    await inLocale(tester, 'en', () {
      expect(timeAgo(_ago(const Duration(seconds: 5))), 'now');
      expect(timeAgo(_ago(const Duration(minutes: 5))), '5m');
      expect(timeAgo(_ago(const Duration(hours: 3))), '3h');
      expect(timeAgo(_ago(const Duration(days: 2))), '2d');
      expect(timeAgo(_ago(const Duration(days: 15))), '2w');
      expect(timeAgo(_ago(const Duration(days: 70))), '2mo');
      expect(timeAgo(_ago(const Duration(days: 800))), '2y');
      expect(formatFileSize(1), '1 byte');
      expect(formatFileSize(512), '512 bytes');
      expect(formatFileSize(38214), '37.3 KiB');
      expect(compactCount(12345), '12.3k');
    });
  });

  testWidgets('Russian: plural years, comma decimals', (tester) async {
    await inLocale(tester, 'ru', () {
      expect(timeAgo(_ago(const Duration(seconds: 5))), 'сейчас');
      expect(timeAgo(_ago(const Duration(hours: 3))), '3 ч');
      expect(timeAgo(_ago(const Duration(days: 366))), '1 г.');
      expect(timeAgo(_ago(const Duration(days: 365 * 3 + 5))), '3 г.');
      expect(timeAgo(_ago(const Duration(days: 365 * 7 + 5))), '7 л.');
      expect(formatFileSize(1), '1 байт');
      expect(formatFileSize(3), '3 байта');
      expect(formatFileSize(7), '7 байт');
      expect(formatFileSize(38214), '37,3 KiB');
    });
  });

  testWidgets('Japanese and Chinese say "ago" and use their own compact counts', (tester) async {
    await inLocale(tester, 'ja', () {
      expect(timeAgo(_ago(const Duration(hours: 3))), '3時間前');
      expect(timeAgo(_ago(const Duration(days: 70))), '2か月前');
      expect(formatFileSize(512), '512バイト');
      expect(compactCount(12345), '1.23万');
    });
    await tester.pumpWidget(const SizedBox());
    await inLocale(tester, 'zh', () {
      expect(timeAgo(_ago(const Duration(minutes: 5))), '5分钟前');
      expect(timeAgo(_ago(const Duration(days: 2))), '2天前');
      expect(formatFileSize(512), '512 字节');
    });
  });

  testWidgets('Spanish, Portuguese, French, German', (tester) async {
    await inLocale(tester, 'es', () {
      expect(timeAgo(_ago(const Duration(days: 35))), '1 mes');
      expect(timeAgo(_ago(const Duration(days: 70))), '2 meses');
      expect(timeAgo(_ago(const Duration(days: 800))), '2 años');
      expect(formatFileSize(38214), '37,3 KiB');
    });
    await tester.pumpWidget(const SizedBox());
    await inLocale(tester, 'pt', () {
      expect(timeAgo(_ago(const Duration(days: 35))), '1 mês');
      expect(timeAgo(_ago(const Duration(days: 400))), '1 ano');
    });
    await tester.pumpWidget(const SizedBox());
    await inLocale(tester, 'fr', () {
      expect(timeAgo(_ago(const Duration(days: 2))), '2 j');
      expect(timeAgo(_ago(const Duration(days: 400))), '1 an');
      expect(timeAgo(_ago(const Duration(days: 800))), '2 ans');
      expect(formatFileSize(1), '1 octet');
    });
    await tester.pumpWidget(const SizedBox());
    await inLocale(tester, 'de', () {
      expect(timeAgo(_ago(const Duration(hours: 3))), '3 Std.');
      expect(formatFileSize(2), '2 Bytes');
      expect(formatFileSize(38214), '37,3 KiB');
    });
  });
}
