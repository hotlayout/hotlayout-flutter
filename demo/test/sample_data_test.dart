import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_demo/sample_data.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';

/// Sample data = the DATA DICTIONARY, and now a test holds this, not a convention.
///
/// Why: `visibleIf` and `styleWhen` are evaluated against `sampleScreenData`, so
/// a mismatch with the dictionary is not "different text on screen" but "block present /
/// block absent". That is how an accordion once silently vanished from a golden document: the dictionary
/// moved, the samples stayed, and the test had to be "fixed" by substituting a value.
/// Until this check existed, it could be noticed only by eye.
///
/// The dictionary is read from the ARTIFACT (`assets/contract/data-contract.json`) - the
/// same file the builder ships - not from a copy in code: a copy would drift
/// silently, as it already has.
void main() {
  final artifact =
      jsonDecode(File('assets/contract/data-contract.json').readAsStringSync()) as Map<String, Object?>;
  final contract = artifact['contract']! as Map<String, Object?>;
  final paths = (contract['paths']! as List<Object?>).cast<Map<String, Object?>>();
  final collections = (contract['collections']! as List<Object?>).cast<Map<String, Object?>>();

  const data = ScreenData(sampleScreenData);

  group('data dictionary mirror', () {
    test('image samples are the dictionary real data: images, not addresses that do not exist', () {
      String sample(String path) => paths.firstWhere((p) => p['path'] == path)['sampleValue']! as String;
      expect(data.lookup('item.image'), sample('item.image'));
      expect(data.lookup('task.image'), sample('task.image'));
      expect(data.lookup('offer.image'), sample('offer.image'));
      for (final key in ['tasks', 'items', 'offers']) {
        for (final record in data.listOf(key)) {
          expect(record, isA<Map<Object?, Object?>>());
          final image = (record! as Map<Object?, Object?>)['image'];
          expect(image, startsWith('data:image/'), reason: key);
        }
      }
    });

    test('every dictionary path has a value of the right type', () {
      for (final entry in paths) {
        final path = entry['path']! as String;
        final value = data.lookup(path);

        expect(value, isNotNull, reason: '$path: no sample');
        switch (entry['type']! as String) {
          case 'number':
            expect(value, isA<num>(), reason: path);
          case 'boolean':
            expect(value, isA<bool>(), reason: path);
          // A date in the contract is an ISO string, so the sample is a string too.
          case 'string' || 'date':
            expect(value, isA<String>(), reason: path);
        }
      }
    });

    test('the samples "now" is the moment from the artifact (x-sampleNow), and days from it are what the dictionary promises', () {
      // Dictionary 1.2.0: the reader demo takes this moment as its clock. The number of days
      // is checked here too, because that is what the moment is named for: a date sample
      // changed without changing the moment would silently give a different number in all frames.
      expect(kSampleNow, artifact['x-sampleNow']);
      final now = DateTime.parse(kSampleNow);
      int days(String path) => (DateTime.parse(data.lookup(path)! as String)
                  .difference(now)
                  .inMilliseconds /
              Duration.millisecondsPerDay)
          .ceil();
      expect(days('campaign.endsAt'), 52);
      expect(days('offer.endsAt'), 22);
    });

    test('no extra samples: every path in the map is in the dictionary', () {
      // Otherwise the map would start growing fields the backend never promised, and a
      // document built against them would show fallbacks on the phone.
      final known = {
        for (final entry in paths) entry['path']! as String,
        for (final entry in collections) entry['path']! as String,
      };

      for (final key in sampleScreenData.keys) {
        expect(known, contains(key), reason: '$key: the dictionary does not promise such a path');
      }
    });

    test('every dictionary collection has records, and a record carries the fields of its entity', () {
      for (final entry in collections) {
        final path = entry['path']! as String;
        final item = entry['item']! as String;
        final itemPaths = [
          for (final p in paths)
            if ((p['path']! as String).startsWith('$item.')) p['path']! as String,
        ];

        // The nested collection (`taskGroup.tasks`) lives INSIDE its parent's
        // record, so it has to be looked up there - in the record layer, not in the document.
        final records = path.contains('.')
            ? data.withItem(path.split('.').first, (data.listOf(_parentOf(path)).first)!).listOf(path)
            : data.listOf(path);

        expect(records, isNotEmpty, reason: '$path: no records');
        for (final record in records) {
          final scoped = data.withItem(item, record);
          for (final itemPath in itemPaths) {
            expect(scoped.lookup(itemPath), isNotNull, reason: '$path → $itemPath');
          }
        }
      }
    });

    test('the FIRST record of a collection does not duplicate the dictionary sample', () {
      /*
       * The builder's rule, mirrored here (`data-collections.test.ts`).
       * If the first record matched the path sample, a node inside a
       * repeater and the same node outside it would render identically, so the
       * record scope would look broken exactly where it works.
       */
      for (final entry in collections) {
        final item = entry['item']! as String;
        final titlePath = paths
            .map((p) => p['path']! as String)
            .firstWhere((p) => p.startsWith('$item.'));
        final dictionarySample = paths.firstWhere((p) => p['path'] == titlePath)['sampleValue'];

        final path = entry['path']! as String;
        final records = path.contains('.')
            ? data.withItem(path.split('.').first, (data.listOf(_parentOf(path)).first)!).listOf(path)
            : data.listOf(path);

        expect(
          data.withItem(item, records.first).lookup(titlePath),
          isNot(dictionarySample),
          reason: '$path: the first record matches the sample $titlePath',
        );
      }
    });
  });
}

/// Parent collection for a nested path: `taskGroup.tasks` -> `taskGroups`.
///
/// The rule is deliberately simple and local to the test: the dictionary does not name
/// this link itself (a nested collection is a field of a RECORD, not a reference), and nobody
/// needs to invent it in the renderer runtime.
String _parentOf(String nested) => '${nested.split('.').first}s';
