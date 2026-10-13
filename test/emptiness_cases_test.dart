/// "EMPTY" IS A QUESTION ABOUT THE VALUE, NOT THE TYPE OF THE PATH (schema 9.19.0, `x-conditions`).
///
/// The shared table (`assets/contract/fixtures/inputs/input-cases.json`) runs row by row:
///
///  1. `emptinessCases` (14) -- the value under the path and the verdict of `isEmpty` / `isNotEmpty`, by the
///     function and by a real condition over the data layers;
///  2. `emptinessDocumentCases` (10) -- the builder's verdict on a condition is not the reader's business:
///     every condition is read and judged without a crash, with data and without.
///
/// What this reader changed: a number and a flag used to be neither empty nor not empty, and a string of spaces
/// used to be trimmed to empty.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/visibility.dart';

typedef _Json = Map<String, Object?>;

final _Json _table = jsonDecode(File('assets/contract/fixtures/inputs/input-cases.json').readAsStringSync()) as _Json;
final _Json _schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Json;

List<_Json> _rows(String key) => (_table[key]! as List<Object?>).cast<_Json>();

bool _holds(String op, Map<String, Object?> data) =>
    VisibilityCondition.parse({'path': 'survey.value', 'op': op})!.evaluate(ScreenData(data));

void main() {
  test('the table has the promised rows', () {
    expect(_rows('emptinessCases'), hasLength(14));
    expect(_rows('emptinessDocumentCases'), hasLength(10));
  });

  group('emptinessCases: the value under the path', () {
    for (final row in _rows('emptinessCases')) {
      test(row['name']! as String, () {
        final present = row.containsKey('value');
        final value = row['value'];
        expect(isEmptyConditionValue(value), row['isEmpty'], reason: 'the function');
        final data = <String, Object?>{if (present) 'survey.value': value};
        expect(_holds('isEmpty', data), row['isEmpty'], reason: 'isEmpty over the data layers');
        expect(_holds('isNotEmpty', data), row['isNotEmpty'], reason: 'isNotEmpty over the data layers');
      });
    }
  });

  group('emptinessDocumentCases: every condition is read and judged without a crash', () {
    for (final row in _rows('emptinessDocumentCases')) {
      test(row['name']! as String, () {
        final condition = VisibilityCondition.parse(row['condition']);
        expect(condition, isNotNull);
        for (final data in <Map<String, Object?>>[
          const {},
          const {'survey.score': 3, 'survey.agreed': false, 'survey.goal': 'gold', 'offer.endsAt': '2026-10-31T12:00:00.000Z', 'items': <Object?>[]},
        ]) {
          expect(() => condition!.evaluate(ScreenData(data)), returnsNormally);
        }
      });
    }
  });

  test('x-conditions: the emptiness block of the artifact', () {
    final block = _schema['x-conditions']! as _Json;
    final emptiness = block['emptiness']! as _Json;
    expect(emptiness['ops'], ['isEmpty', 'isNotEmpty']);
    expect(emptiness['pathTypes'], 'any');
    expect(emptiness['empty'], ['absent', 'null', 'the-empty-string', 'a-list-without-records']);
    expect(block['collectionOps'], ['isEmpty', 'isNotEmpty']);
  });
}
