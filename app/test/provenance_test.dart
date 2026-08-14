// Provenance + lineage declarations (docs/artwork-provenance messages 0001+0002):
// the DocProvenance model, its META round trip, the packed META wire format, and
// the upload form-field assembly. Pure Dart — no engine binary, no network.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/publish/doc_provenance.dart';
import 'package:makapix_club/club/publish/provenance_fields.dart';
import 'package:makapix_club/engine_ffi.dart' show packMkpxMeta, unpackMkpxMeta;

void main() {
  group('packMkpxMeta / unpackMkpxMeta', () {
    test('round-trips entries in order', () {
      final entries = {'club.parents': 'aB3xY,qW9zK', 'club.everImported': '1'};
      expect(unpackMkpxMeta(packMkpxMeta(entries)), entries);
    });

    test('empty map packs to empty string and back', () {
      expect(packMkpxMeta(const {}), '');
      expect(unpackMkpxMeta(''), const <String, String>{});
    });

    test('entries containing separators are dropped, not corrupted', () {
      final packed = packMkpxMeta({'bad\u001Fkey': 'v', 'good': 'v2'});
      expect(unpackMkpxMeta(packed), {'good': 'v2'});
    });
  });

  group('DocProvenance', () {
    test('fresh documents are provably hand-drawn', () {
      final p = DocProvenance.fresh();
      expect(p.creationMethod, 'editor_hand_drawn');
      expect(p.toMeta(), {DocProvenance.keyEverImported: '0'});
    });

    test('unknown documents declare nothing', () {
      final p = DocProvenance.unknown();
      expect(p.creationMethod, isNull);
      expect(p.toMeta(), isEmpty);
    });

    test('import sets the sticky bit and records the format once', () {
      final p = DocProvenance.fresh()
        ..markImported('PNG')
        ..markImported('png')
        ..markImported('gif');
      expect(p.creationMethod, 'editor_import');
      expect(p.importedFormat, 'png,gif');
      expect(p.toMeta()[DocProvenance.keyImportedFormats], 'png,gif');
    });

    test('import on an unknown document still claims the import truthfully', () {
      final p = DocProvenance.unknown()..markImported('png');
      expect(p.creationMethod, 'editor_import');
    });

    test('remix seeding counts as import; parents dedup and cap at 8', () {
      final p = DocProvenance.fresh()..addParent('base1');
      expect(p.creationMethod, 'editor_import');
      p.addParent('base1'); // dup ignored
      for (var i = 2; i <= 12; i++) {
        p.addParent('p$i');
      }
      expect(p.parents.length, DocProvenance.maxParents);
      expect(p.parents.first, 'base1'); // declaration order: base first
    });

    test('META round trip preserves bit, formats, and parent order', () {
      final p = DocProvenance.fresh()
        ..addParent('aB3xY')
        ..addParent('qW9zK')
        ..markImported('png');
      final back = DocProvenance.fromMeta(p.toMeta());
      expect(back.everImported, isTrue);
      expect(back.parents, ['aB3xY', 'qW9zK']);
      expect(back.importedFormat, 'png');
    });

    test('fromMeta of a hand-drawn doc stays hand-drawn', () {
      final back = DocProvenance.fromMeta(DocProvenance.fresh().toMeta());
      expect(back.everImported, isFalse);
      expect(back.creationMethod, 'editor_hand_drawn');
    });

    test('fromMeta with no keys is unknown', () {
      expect(DocProvenance.fromMeta(const {}).creationMethod, isNull);
    });

    test('parentsForPublish excludes the replaced post itself', () {
      final p = DocProvenance.fresh()
        ..addParent('self1')
        ..addParent('other');
      expect(p.parentsForPublish(replacedSqid: 'self1'), ['other']);
      expect(p.parentsForPublish(), ['self1', 'other']);
    });
  });

  group('provenanceFormFields', () {
    test('full declaration for a remix upload', () {
      final p = DocProvenance.fresh()
        ..addParent('aB3xY')
        ..markImported('png');
      final f = provenanceFormFields(
        appVersion: '1.2.3',
        platform: 'android',
        deviceType: 'mobile',
        provenance: p,
        remixable: true,
      );
      expect(f['client'], 'app/1.2.3');
      expect(f['creation_method'], 'editor_import');
      expect(f['remixed_from'], 'aB3xY');
      expect(f['remixable'], 'true');
      final details = jsonDecode(f['source_details']!) as Map<String, dynamic>;
      expect(details['editor_version'], '1.2.3');
      expect(details['editor_platform'], 'android');
      expect(details['device_type'], 'mobile');
      expect(details['imported_format'], 'png');
    });

    test('hand-drawn upload declares the strong claim and no lineage', () {
      final f = provenanceFormFields(
        appVersion: '1.2.3',
        platform: 'ios',
        deviceType: 'tablet',
        provenance: DocProvenance.fresh(),
      );
      expect(f['creation_method'], 'editor_hand_drawn');
      expect(f.containsKey('remixed_from'), isFalse);
      expect(f.containsKey('remixable'), isFalse);
      final details = jsonDecode(f['source_details']!) as Map<String, dynamic>;
      expect(details.containsKey('imported_format'), isFalse);
    });

    test('unknown provenance omits creation_method rather than guessing', () {
      final f = provenanceFormFields(
        appVersion: '1.2.3',
        platform: 'android',
        deviceType: 'mobile',
        provenance: DocProvenance.unknown(),
      );
      expect(f.containsKey('creation_method'), isFalse);
      expect(f['client'], 'app/1.2.3'); // client is still declared
    });

    test('non-mobile platform omits editor_platform (whitelisted values only)', () {
      final f = provenanceFormFields(
        appVersion: '1.2.3',
        platform: 'windows',
        deviceType: 'desktop',
        provenance: DocProvenance.fresh(),
      );
      final details = jsonDecode(f['source_details']!) as Map<String, dynamic>;
      expect(details.containsKey('editor_platform'), isFalse);
      expect(details['device_type'], 'desktop');
    });

    test('replace excludes the replaced post from remixed_from', () {
      final p = DocProvenance.fresh()
        ..addParent('replaced')
        ..addParent('imported');
      final f = provenanceFormFields(
        appVersion: '1.2.3',
        platform: 'android',
        deviceType: 'mobile',
        provenance: p,
        replacedSqid: 'replaced',
      );
      expect(f['remixed_from'], 'imported');
    });

    test('declareParents=false drops only the remix claim', () {
      final p = DocProvenance.fresh()..addParent('aB3xY');
      final f = provenanceFormFields(
        appVersion: '1.2.3',
        platform: 'android',
        deviceType: 'mobile',
        provenance: p,
        declareParents: false,
      );
      expect(f.containsKey('remixed_from'), isFalse);
      expect(f['creation_method'], 'editor_import'); // the rest stays honest
    });

    test('empty version omits client and editor_version', () {
      final f = provenanceFormFields(
        appVersion: '',
        platform: 'android',
        deviceType: 'mobile',
        provenance: DocProvenance.fresh(),
      );
      expect(f.containsKey('client'), isFalse);
      final details = jsonDecode(f['source_details']!) as Map<String, dynamic>;
      expect(details.containsKey('editor_version'), isFalse);
    });
  });
}
