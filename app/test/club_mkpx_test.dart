import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/api/mkpx_api.dart';
import 'package:makapix_club/club/models/post.dart';
import 'package:makapix_club/club/models/server_config.dart';

/// mkpx-upload (layers-file attachments) — client-side contract pieces:
/// config capability parsing, Post payload additions, and the magic-byte
/// pre-check that mirrors the server's `mkpx_invalid` rule.
void main() {
  group('MkpxRules (GET /config → upload.mkpx)', () {
    test('absent key → disabled with the default cap', () {
      final cfg = ClubServerConfig.fromJson({
        'upload': {'formats': ['png'], 'max_file_bytes': 5242880},
      });
      expect(cfg.upload.mkpx.enabled, isFalse);
      expect(cfg.upload.mkpx.maxFileBytes, 52428800);
    });

    test('enabled:false → disabled even when present', () {
      final cfg = ClubServerConfig.fromJson({
        'upload': {
          'mkpx': {'enabled': false, 'max_file_bytes': 1000},
        },
      });
      expect(cfg.upload.mkpx.enabled, isFalse);
      expect(cfg.upload.mkpx.maxFileBytes, 1000);
    });

    test('enabled:true parses the advertised cap', () {
      final cfg = ClubServerConfig.fromJson({
        'upload': {
          'mkpx': {'enabled': true, 'max_file_bytes': 16777216},
        },
      });
      expect(cfg.upload.mkpx.enabled, isTrue);
      expect(cfg.upload.mkpx.maxFileBytes, 16777216);
    });

    test('baked-in fallback config has mkpx disabled', () {
      expect(ClubServerConfig.fallback.upload.mkpx.enabled, isFalse);
    });
  });

  group('Post payload additions (contract §5)', () {
    final base = <String, dynamic>{
      'id': 7,
      'public_sqid': 'aB3',
      'kind': 'artwork',
      'title': 't',
      'owner': {'user_key': 'k', 'public_sqid': 'u', 'handle': 'h'},
    };

    test('attached: has_mkpx + bytes + stamp', () {
      final post = Post.fromJson({
        ...base,
        'has_mkpx': true,
        'mkpx_file_bytes': 183422,
        'mkpx_attached_at': '2026-07-02T14:11:05Z',
      });
      expect(post.hasMkpx, isTrue);
      expect(post.mkpxFileBytes, 183422);
      expect(post.mkpxAttachedAt, DateTime.utc(2026, 7, 2, 14, 11, 5));
    });

    test('no layers file: null/false variants all parse to defaults', () {
      for (final extra in [
        <String, dynamic>{},
        {'has_mkpx': false, 'mkpx_file_bytes': null, 'mkpx_attached_at': null},
        {'has_mkpx': null},
      ]) {
        final post = Post.fromJson({...base, ...extra});
        expect(post.hasMkpx, isFalse);
        expect(post.mkpxFileBytes, isNull);
        expect(post.mkpxAttachedAt, isNull);
      }
    });
  });

  group('MkpxApi.looksLikeMkpx (magic-byte pre-check)', () {
    const plain = [0x89, 0x4D, 0x4B, 0x50, 0x58, 0x0D, 0x0A, 0x1A];
    const compact = [0x89, 0x4D, 0x4B, 0x50, 0x5A, 0x0D, 0x0A, 0x1A];

    test('accepts both profile signatures (with trailing payload)', () {
      expect(MkpxApi.looksLikeMkpx(plain), isTrue);
      expect(MkpxApi.looksLikeMkpx(compact), isTrue);
      expect(MkpxApi.looksLikeMkpx([...compact, 1, 2, 3]), isTrue);
    });

    test('rejects short, empty, and non-mkpx inputs', () {
      expect(MkpxApi.looksLikeMkpx(const []), isFalse);
      expect(MkpxApi.looksLikeMkpx(plain.sublist(0, 7)), isFalse);
      // PNG signature — same PNG-style hardening, different letters.
      expect(
          MkpxApi.looksLikeMkpx(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), isFalse);
    });

    test('rejects a corrupted profile byte or tail', () {
      expect(MkpxApi.looksLikeMkpx([...plain]..[4] = 0x59), isFalse); // 'Y'
      expect(MkpxApi.looksLikeMkpx([...plain]..[7] = 0x00), isFalse);
      expect(MkpxApi.looksLikeMkpx([...plain]..[0] = 0x88), isFalse);
    });
  });
}
