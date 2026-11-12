/// Default transitions between screens (schema 9.38.0, `x-screenTransition`): the shared table
/// `fixtures/screen-transition/screen-transition-cases.json`.
///
/// `curveCases`, `planCases`, `frameCases` and `fieldCases` run through the pure rules
/// (`screen_transition.dart`); `documentCases` through screen parsing (the schema half of those rows belongs to the
/// builder's validator). The widgets that play the plan are tested in `screen_transition_flow_test.dart`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/screen_transition.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/model/visibility_fade.dart' show cubicBezierAt;

typedef _Row = Map<String, Object?>;

void main() {
  final table = (jsonDecode(File('assets/contract/fixtures/screen-transition/screen-transition-cases.json').readAsStringSync()) as Map)
      .cast<String, Object?>();
  final schema = (jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as Map)
      .cast<String, Object?>();
  List<_Row> rowsOf(String name) => (table[name]! as List<Object?>).cast<_Row>();

  TransitionScreen screenOf(Object? raw) {
    final fields = (raw as _Row?) ?? const {};
    return TransitionScreen(
      modal: fields['presentation'] == 'modal',
      placement: fields['modalPlacement'],
      transition: ScreenTransitionWord.of(fields['transition']),
    );
  }

  ScreenTransitionPlan planOf(_Row row) => screenTransitionPlan(
    step: StackStep.tryParse(row['kind'])!,
    from: row['from'] == null ? null : screenOf(row['from']),
    to: screenOf(row['to']),
    areaWidth: (row['areaWidth']! as num).toDouble(),
    reducedMotion: row['reducedMotion'] == true,
    covered: row['covered'] == true,
    dragged: row['dragged'] == true,
  );

  test('the table is read in full', () {
    expect(rowsOf('curveCases'), hasLength(12));
    expect(rowsOf('planCases'), hasLength(29));
    expect(rowsOf('frameCases'), hasLength(8));
    expect(rowsOf('fieldCases'), hasLength(5));
    expect(rowsOf('documentCases'), hasLength(5));
  });

  group('the data of the artifact', () {
    test('`x-screenTransition` is mirrored whole', () {
      expect(jsonDecode(jsonEncode(kScreenTransitionRules)), schema['x-screenTransition']);
    });

    test('the capability is in the catalog from 9.38.0', () {
      expect(kFeatureCatalog['screenTransition'], '9.38.0');
      expect(supportsFeature('screenTransition'), isTrue);
      expect(supportsFeature('screenTransition', readerVersion: '9.37.0'), isFalse);
    });
  });

  group('curveCases', () {
    const curves = {'page': kDecelerateCurve, 'sheetClose': kAccelerateCurve, 'fade': kStandardFadeCurve};
    for (final row in rowsOf('curveCases')) {
      test(row['name']! as String, () {
        expect(cubicBezierAt(curves[row['curve']]!, (row['x']! as num).toDouble()), closeTo((row['y']! as num).toDouble(), 0.001));
      });
    }
  });

  group('planCases', () {
    for (final row in rowsOf('planCases')) {
      test(row['name']! as String, () {
        final plan = planOf(row);
        final expected = row['expect']! as _Row;
        expect(plan.motion.wire, expected['motion']);
        if (expected['motion'] == 'none') {
          expect(plan.reason!.wire, expected['reason']);
          return;
        }
        expect(plan.durationMs, expected['durationMs']);
        expect(plan.curve, [for (final point in expected['curve']! as List<Object?>) (point! as num).toDouble()]);
        expect(plan.parallax, (expected['parallax'] as num?)?.toDouble());
        expect(plan.scaleFrom, (expected['scaleFrom'] as num?)?.toDouble());
        expect(plan.scrim?.name, expected['scrim']);
      });
    }
  });

  group('frameCases', () {
    for (final row in rowsOf('frameCases')) {
      test(row['name']! as String, () {
        final plan = planOf(row['plan']! as _Row);
        expect(plan.moves, isTrue);
        for (final probe in (row['probes']! as List<Object?>).cast<_Row>()) {
          final frame = screenTransitionFrame(plan, (probe['at']! as num).toDouble());
          final at = '${row['name']} at ${probe['at']} ms';
          void check(String side, TransitionLayerFrame layer) {
            final expected = probe[side] as _Row?;
            if (expected == null) return;
            final got = {'x': layer.x, 'y': layer.y, 'opacity': layer.opacity, 'scale': layer.scale};
            for (final key in expected.keys) {
              expect(got[key], closeTo((expected[key]! as num).toDouble(), 0.001), reason: '$at, $side.$key');
            }
          }

          check('incoming', frame.incoming);
          check('outgoing', frame.outgoing);
          if (probe['scrim'] != null) {
            expect(frame.scrim, closeTo((probe['scrim']! as num).toDouble(), 0.001), reason: '$at, scrim');
          }
        }
      });
    }
  });

  group('fieldCases', () {
    for (final row in rowsOf('fieldCases')) {
      test(row['name']! as String, () {
        expect(ScreenTransitionWord.of(row['value'])?.name, row['reads']);
      });
    }
  });

  group('documentCases: the field on a screen record', () {
    for (final row in rowsOf('documentCases')) {
      test(row['name']! as String, () {
        final screen = row['screen']! as _Row;
        final doc = UiDocument.fromJson({
          'schemaVersion': UiDocument.supportedSchemaVersion,
          'documentId': 'transition-document',
          'name': 'Transition',
          'initialScreenId': 's',
          'screens': [
            {
              'screenId': 's',
              'name': 'S',
              'root': {
                'id': 'root',
                'type': 'Screen',
                'props': const <String, Object?>{},
                'children': const <Object?>[],
              },
              ...screen,
            },
          ],
        });
        // What the schema refuses is read as no field by this reader (it validates nothing).
        expect(doc.screens.single.transition, row['schema'] == true ? ScreenTransitionWord.of(screen['transition']) : isNull);
      });
    }
  });

  group('beyond the table', () {
    test('the frame past the duration is the final state', () {
      final plan = planOf({
        'kind': 'push',
        'to': <String, Object?>{},
        'from': <String, Object?>{},
        'areaWidth': 393,
      });
      final end = screenTransitionFrame(plan, 5000);
      expect(end.incoming.x, 0);
      expect(end.outgoing.x, closeTo(-0.3, 1e-9));
    });
  });
}
