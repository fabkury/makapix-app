import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/ui/widgets/common.dart';

void main() {
  group('compactCount', () {
    test('small numbers pass through', () {
      expect(compactCount(0), '0');
      expect(compactCount(7), '7');
      expect(compactCount(999), '999');
    });

    test('thousands: one decimal under 100k, whole k above', () {
      expect(compactCount(1000), '1k');
      expect(compactCount(1234), '1.2k');
      expect(compactCount(9949), '9.9k');
      expect(compactCount(12345), '12.3k');
      expect(compactCount(99940), '99.9k');
      expect(compactCount(100000), '100k');
      expect(compactCount(123456), '123k');
      expect(compactCount(999499), '999k');
    });

    test('millions: hand-off avoids the "1000k" rounding artifact', () {
      expect(compactCount(999500), '1M');
      expect(compactCount(1200000), '1.2M');
      expect(compactCount(34500000), '34.5M');
      expect(compactCount(123000000), '123M');
    });
  });

  group('formatFileSize', () {
    test('bytes below 1 KiB', () {
      expect(formatFileSize(0), '0 bytes');
      expect(formatFileSize(512), '512 bytes');
      expect(formatFileSize(1023), '1023 bytes');
    });

    test('KiB with one decimal, trailing .0 stripped', () {
      expect(formatFileSize(1024), '1 KiB');
      expect(formatFileSize(1536), '1.5 KiB');
      expect(formatFileSize(38214), '37.3 KiB');
    });

    test('MiB from 1024 KiB up', () {
      expect(formatFileSize(1048576), '1 MiB');
      expect(formatFileSize(5452595), '5.2 MiB');
    });
  });
}
