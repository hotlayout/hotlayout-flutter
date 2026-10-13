/// The bundled icon set = the contract artifact (schema 9.3.0).
///
/// The set is bundled as a GENERATED copy (`tool/generate_icon_set.dart`), like the built-in
/// theme. A copy that fell behind the artifact would paint something other than the builder
/// canvas, and no other test would notice: the renderer would agree
/// with itself. So the artifact ITSELF is read here.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/icon_set.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';

void main() {
  final artifact =
      jsonDecode(File('assets/contract/icons.json').readAsStringSync()) as Map<String, Object?>;
  final schema =
      jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as Map<String, Object?>;
  final icons = (artifact['icons']! as Map<String, Object?>).cast<String, String>();

  group('the set copy = contract/icons.json', () {
    test('drawings - byte for byte, in the same order', () {
      expect(kIconBodies.keys.toList(), icons.keys.toList());
      for (final entry in icons.entries) {
        expect(kIconBodies[entry.key], entry.value, reason: entry.key);
      }
      expect(kIconBodies, hasLength(332));
    });

    test('grid - byte for byte', () {
      expect(jsonEncode(kIconGrid), jsonEncode(artifact['grid']));
      // The painter handles exactly this grid: canvas 24, no fill, stroke 2 in the
      // foreground colour, rounded caps and joins.
      expect(kIconGridSize, 24);
      expect(kIconGridStrokeWidth, 2);
    });

    test('the renderer declares the set version it bundles', () {
      expect(kIconSetVersion, artifact['iconSetVersion']);
      expect(kIconSetVersion, '1.0.0');
      // The set version is independent of the schema version: these are different numbers and
      // different constants, and a document carries no set version.
      expect(kIconSetVersion, isNot(kSupportedSchemaVersion));
    });

    test('the generated file says how to regenerate it and where the drawings licence is', () {
      final source = File('lib/src/model/icon_set.dart').readAsStringSync();
      expect(source, contains('dart run tool/generate_icon_set.dart'));
      expect(source, contains('THIRD-PARTY-NOTICES.md'));
    });
  });

  group('schema 9.3.0', () {
    test('the reader schema version is not older than 9.3.0, the capability is named', () {
      // A statement about a NUMBER ("the reader is 9.3.0") died together with the constant at
      // minor 9.4.0 - the same version trap as in the other version tests. This test asks
      // about the capability, and that still holds: the reader and the artifact are not older than
      // the minor that introduced the icon library, and they move together.
      expect(schema['x-schemaVersion'], kSupportedSchemaVersion);
      expect(
        SchemaVersion.tryParse(kSupportedSchemaVersion)!.compareTo(const SchemaVersion(9, 3, 0)),
        greaterThanOrEqualTo(0),
      );
      final features = ((schema['x-compatibility']! as Map<String, Object?>)['features']! as Map<String, Object?>);
      expect(features['iconLibrary'], '9.3.0');
      expect(kFeatureCatalog['iconLibrary'], '9.3.0');
      expect(supportsFeature('iconLibrary'), isTrue);
      expect(supportsFeature('iconLibrary', readerVersion: '9.2.0'), isFalse);
    });

    test('set names - exactly the schema IconToken.enum', () {
      final defs = schema[r'$defs']! as Map<String, Object?>;
      final names = ((defs['IconToken']! as Map<String, Object?>)['enum']! as List<Object?>).cast<String>();
      expect(IconToken.values.map((icon) => icon.wire).toList(), names);
      expect(schema['x-icons'], {'drawings': 'contract/icons.json', 'names': 'IconToken'});
    });

    test('mirrored - exactly the schema x-mirroredIcons', () {
      expect(kMirroredIcons.toList(), schema['x-mirroredIcons']);
    });

    test('the two icon policy rows are named in the artifact with these words', () {
      final policy = (schema['x-compatibility']! as Map<String, Object?>)['policy']! as Map<String, Object?>;
      expect(policy['unknownIcon'], 'empty-box-same-size');
      expect(policy['unreadableIconValue'], 'as-unknown-icon');
      expect(kIconPolicy, {'unknownIcon': 'empty-box-same-size', 'unreadableIconValue': 'as-unknown-icon'});
    });
  });

  group('drawings licence ships with the package', () {
    test('THIRD-PARTY-NOTICES.md at the package root carries the Lucide ISC and Feather MIT', () {
      final notices = File('THIRD-PARTY-NOTICES.md').readAsStringSync();
      final sources = (artifact['sources']! as List<Object?>).cast<Map<String, Object?>>();
      final lucide = sources.firstWhere((source) => source['name'] == 'Lucide');
      expect(notices, contains(lucide['copyright']! as String));
      expect(notices, contains('ISC License'));
      expect(notices, contains(((lucide['derivedFrom']! as Map<String, Object?>)['copyright']!) as String));
      expect(notices, contains(lucide['version']! as String));
    });

    test('the file is not dropped from the package archive', () {
      final ignored = File('.pubignore').readAsLinesSync().map((line) => line.trim());
      expect(ignored.where((line) => line.contains('THIRD-PARTY')), isEmpty);
    });
  });
}
