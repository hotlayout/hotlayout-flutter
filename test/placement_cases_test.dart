import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/placements/placement_map.dart';

/// The shared placement table (`assets/contract/fixtures/placements/placement-cases.json`): EVERY row
/// of `readCases`, `sourceCases` and `showingCases` runs here, as in every other reader.
///
/// The table is read with a plain JSON decode, so `__proto__` stays an own key of its rows.
void main() {
  final table = jsonDecode(File('assets/contract/fixtures/placements/placement-cases.json').readAsStringSync())
      as Map<String, Object?>;
  final readCases = (table['readCases']! as List).cast<Map<String, Object?>>();
  final sourceCases = (table['sourceCases']! as List).cast<Map<String, Object?>>();
  final showingCases = (table['showingCases']! as List).cast<Map<String, Object?>>();

  Map<String, Object?> row(Object? value) => (value! as Map).cast<String, Object?>();

  void expectResolution(PlacementMapRead map, List<Object?> expected) {
    for (final item in expected) {
      final e = row(item);
      final got = resolvePlacement(map, e['name']! as String);
      expect(
        (got.status.name, got.documentId, got.entry),
        (e['status'], e['documentId'], e['entry']),
        reason: 'name ${jsonEncode(e['name'])}',
      );
    }
  }

  String kindOf(PlacementMapRead read) => switch (read) {
    PlacementMapOk() => 'map',
    PlacementMapCorrupt() => 'corrupt',
    PlacementMapUnsupported() => 'unsupported',
  };

  test('the table has the rows the contract promises', () {
    expect(table['placementsVersion'], kPlacementsContractVersion);
    expect(readCases.length, 36);
    expect(sourceCases.length, 21);
    expect(showingCases.length, 10);
    expect(readCases.fold<int>(0, (n, r) => n + (r['resolve']! as List).length), 80);
    expect(sourceCases.fold<int>(0, (n, r) => n + (r['resolve']! as List).length), 22);
  });

  group('readCases', () {
    for (final c in readCases) {
      test(c['name']! as String, () {
        final read = c.containsKey('text') ? readPlacementMapText(c['text']! as String) : readPlacementMap(c['json']);
        expect(kindOf(read), c['read']);
        expectResolution(read, (c['resolve']! as List).cast<Object?>());
        // The tolerant reader reads the same map from its serialised text.
        if (c.containsKey('json')) {
          expect(kindOf(readPlacementMapText(jsonEncode(c['json']))), c['read']);
        }
      });
    }
  });

  group('sourceCases', () {
    PlacementNetworkOutcome outcomeOf(Map<String, Object?> network) => switch (network['kind']) {
      'map' => PlacementNetworkMap(network['text']! as String),
      'notModified' => const PlacementNetworkNotModified(),
      'notFound' => const PlacementNetworkNotFound(),
      'offline' => const PlacementNetworkOffline(),
      final other => fail('unknown network kind $other'),
    };

    for (final c in sourceCases) {
      test(c['name']! as String, () {
        final decision = pickPlacementMap(
          network: outcomeOf(row(c['network'])),
          lastKnown: c['lastKnown'] as String?,
          bundled: c['bundled'] as String?,
        );
        final expected = row(c['expected']);
        expect(decision.source.name, expected['source']);
        expect(decision.status.name, expected['status']);
        expect(decision.remember, expected['remember']);
        expectResolution(decision.map, (c['resolve']! as List).cast<Object?>());
      });
    }
  });

  group('showingCases', () {
    for (final c in showingCases) {
      test(c['name']! as String, () {
        final r = row(c['resolution']);
        final resolution = PlacementResolution(
          PlacementStatus.values.byName(r['status']! as String),
          documentId: r['documentId'] as String?,
          entry: r['entry'] as String?,
        );
        final document = c['document'] == null ? null : row(c['document']);
        final outcome = switch (document?['kind']) {
          null => null,
          'ok' => PlacementDocumentOk((document!['entryPoints']! as List).cast<String>()),
          'missing' => const PlacementDocumentMissing(),
          'unreadable' => const PlacementDocumentUnreadable(),
          final other => fail('unknown document kind $other'),
        };
        final got = placementShowing(resolution, outcome);
        final expected = row(c['expected']);
        expect((got.show.name, got.entry, got.report?.name), (expected['show'], expected['entry'], expected['report']));
      });
    }
  });

  group('hostile input', () {
    test('names that cannot be placements are unknown, whatever the map holds', () {
      final map = readPlacementMapText(jsonEncode({
        'placementsVersion': '1.0.0',
        'placements': {'home.banner': {'documentId': 'd1'}},
      }));
      for (final name in ['__proto__', 'constructor', 'toString', '', 'a' * 65, 'Home.banner', 'home..banner', 'home.banner\n', '../x']) {
        expect(resolvePlacement(map, name).status, PlacementStatus.unknown, reason: jsonEncode(name));
      }
      expect(isPlacementName('a' * 64), isTrue);
      expect(isPlacementName('a' * 65), isFalse);
    });

    test('a document id that could walk out of the folder is unreadable', () {
      for (final id in ['..', '.', 'a/b', r'a\b', '', 'a' * 65, 'a b', '%2e%2e', 'd1\n']) {
        final map = readPlacementMapText(jsonEncode({
          'placementsVersion': '1.0.0',
          'placements': {'home.banner': {'documentId': id}},
        }));
        expect(resolvePlacement(map, 'home.banner').status, PlacementStatus.unreadable, reason: jsonEncode(id));
      }
    });

    test('a map is read whatever its size: the limits are the publisher\'s', () {
      final places = {for (var i = 0; i < 300; i++) 'p$i': {'documentId': 'd$i'}};
      final map = readPlacementMapText(jsonEncode({'placementsVersion': '1.0.0', 'placements': places}));
      expect(map, isA<PlacementMapOk>());
      expect(resolvePlacement(map, 'p299').documentId, 'd299');
      expect(kMaxPlacements, 200);
      expect(kPlacementsMaxBytes, 65536);
    });

    test('a version that is not a plain semver is not a map', () {
      for (final version in ['1.0', '1.0.0-beta', 'v1.0.0', '01.0.0', 1, null]) {
        expect(
          readPlacementMap({'placementsVersion': version, 'placements': <String, Object?>{}}),
          isA<PlacementMapCorrupt>(),
          reason: '$version',
        );
      }
    });
  });
}
