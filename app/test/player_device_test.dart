import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/models/player_device.dart';

void main() {
  group('PlayerDevice.fromJson', () {
    test('parses a fully-populated online player with capabilities', () {
      final p = PlayerDevice.fromJson({
        'id': 'p1',
        'player_key': 'key-uuid',
        'name': 'Living room',
        'device_model': 'p3a',
        'firmware_version': '1.2.3',
        'connection_status': 'online',
        'current_post_id': 42,
        'is_paused': true,
        'brightness': 80,
        'rotation': 90,
        'mirror': 'h',
        'capabilities': {
          'pause': <String, dynamic>{},
          'brightness': {'min': 0, 'max': 100, 'step': 5},
          'rotation': {
            'values': [0, 90, 180, 270]
          },
          'mirror': {
            'values': ['none', 'h', 'v', 'both']
          },
        },
      });

      expect(p.id, 'p1');
      expect(p.isOnline, isTrue);
      expect(p.displayName, 'Living room');
      expect(p.currentPostId, 42);
      expect(p.isPaused, isTrue);
      expect(p.brightness, 80);
      expect(p.rotation, 90);
      expect(p.mirror, 'h');
      expect(p.capabilities.pause, isTrue);
      expect(p.capabilities.brightness!.max, 100);
      expect(p.capabilities.brightness!.step, 5);
      expect(p.capabilities.rotation, [0, 90, 180, 270]);
      expect(p.capabilities.mirror, ['none', 'h', 'v', 'both']);
      expect(p.capabilities.hasAdjustments, isTrue);
    });

    test('parses registration status and timestamps', () {
      final p = PlayerDevice.fromJson({
        'id': 'p1',
        'player_key': 'k',
        'registration_status': 'registered',
        'last_seen_at': '2026-07-17T12:00:00Z',
        'registered_at': '2026-07-10T09:30:00Z',
      });
      expect(p.registrationStatus, 'registered');
      expect(p.lastSeenAt, DateTime.utc(2026, 7, 17, 12));
      expect(p.registeredAt, DateTime.utc(2026, 7, 10, 9, 30));
    });

    test('registration status defaults to pending; bad/absent timestamps are null', () {
      final p = PlayerDevice.fromJson({
        'id': 'p2',
        'player_key': 'k2',
        'last_seen_at': 'not-a-date',
      });
      expect(p.registrationStatus, 'pending');
      expect(p.lastSeenAt, isNull);
      expect(p.registeredAt, isNull);
    });

    test('defaults to offline with no capabilities when fields are missing', () {
      final p = PlayerDevice.fromJson({'id': 'p2', 'player_key': 'k2'});
      expect(p.isOnline, isFalse);
      expect(p.connectionStatus, 'offline');
      expect(p.isPaused, isNull);
      expect(p.brightness, isNull);
      expect(p.capabilities.pause, isFalse);
      expect(p.capabilities.brightness, isNull);
      expect(p.capabilities.rotation, isEmpty);
      expect(p.capabilities.mirror, isEmpty);
      expect(p.capabilities.hasAdjustments, isFalse);
    });

    test('displayName falls back to device model, then a generic label', () {
      expect(PlayerDevice.fromJson({'device_model': 'Pixelix'}).displayName, 'Pixelix');
      expect(PlayerDevice.fromJson({'name': '   '}).displayName, 'Player');
      expect(PlayerDevice.fromJson(const {}).displayName, 'Player');
    });
  });
}
