/// Motion 2 (schema 9.40.0): `spin` and `sway` of a node and its one-time appearance (`appear`), the shared table
/// `fixtures/motion/motion-turn-cases.json`.
///
/// `turnCases` and `appearCases` run twice: through the pure formula (`motion_rules.dart`, `node_appear.dart`) and
/// through a REAL document whose clock is advanced to the moment (the pose is read from what the widget paints).
/// `momentCases` run through real flows: a first show, a step forward, back and a section switch play the appearance;
/// closing a layer, a condition that starts to hold, a width class and a new record of a list do not. `documentCases`
/// check what the reader reads and draws. `zoneCases` are the builder's validator (the reader validates nothing).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/motion_rules.dart';
import 'package:hotlayout_flutter/src/model/node_appear.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/node_appear.dart';
import 'package:hotlayout_flutter/src/render/node_motion.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

_Json _obj(Object? value) => (value! as Map).cast<String, Object?>();

final _Json _table = _obj(jsonDecode(File('assets/contract/fixtures/motion/motion-turn-cases.json').readAsStringSync()));
final _Json _schema = _obj(jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()));
List<_Json> _rows(String key) => (_table[key]! as List).map(_obj).toList();

/// A node that moves or appears: a 40 x 40 square, then a text that must not move.
List<_Json> _scene({Object? motion, Object? appear, _Json? extra}) => [
  {
    'id': 'moving',
    'type': 'Container',
    'props': const <String, Object?>{},
    'style': {'width': 40, 'height': 40, 'background': colorBackground('primary')},
    'motion': ?motion,
    'appear': ?appear,
    ...?extra,
    'children': const <Object?>[],
  },
  textNode('Still text', id: 'still'),
];

/// The turn the widget PAINTS now, in degrees clockwise: from the rotation matrix of the transform under the motion box.
({double degrees, Alignment about}) _turned(WidgetTester tester) {
  final box = find.byType(NodeMotionBox);
  expect(box, findsOneWidget);
  final transform = tester.widget<Transform>(find.descendant(of: box, matching: find.byType(Transform)).first);
  final m = transform.transform;
  return (degrees: math.atan2(m.entry(1, 0), m.entry(0, 0)) * 180 / math.pi, about: transform.alignment! as Alignment);
}

/// Whether two angles in degrees are the same turn (270 and -90 are).
Matcher _sameTurn(double expected) => predicate<double>((got) {
  final a = got * math.pi / 180;
  final b = expected * math.pi / 180;
  return (math.sin(a) - math.sin(b)).abs() < 1e-6 && (math.cos(a) - math.cos(b)).abs() < 1e-6;
}, 'the turn of $expected degrees');

/// The pose the appearance paints now; `null` when the node was not wrapped at all (it stands at once).
({double y, double opacity})? _appeared(WidgetTester tester) {
  final box = find.byType(NodeAppearBox);
  expect(box, findsOneWidget);
  final fade = find.descendant(of: box, matching: find.byType(Opacity));
  if (fade.evaluate().isEmpty) return null;
  final shift = tester.widget<Transform>(find.descendant(of: fade.first, matching: find.byType(Transform)).first);
  return (y: shift.transform.getTranslation().y, opacity: tester.widget<Opacity>(fade.first).opacity);
}

void main() {
  test('the table is read in full', () {
    expect(_rows('turnCases'), hasLength(24));
    expect(_rows('appearCases'), hasLength(13));
    expect(_rows('momentCases'), hasLength(8));
    expect(_rows('documentCases'), hasLength(34));
    expect(_rows('zoneCases'), hasLength(7));
  });

  group('the data of the artifact', () {
    test('`x-motionTurn` is mirrored whole', () {
      expect(jsonDecode(jsonEncode(kMotionTurnRules)), _schema['x-motionTurn']);
    });

    test('`x-appear` is mirrored whole', () {
      expect(jsonDecode(jsonEncode(kAppearRules)), _schema['x-appear']);
    });

    test('`x-motion` does not name the new kinds', () {
      expect(_obj(_schema['x-motion'])['kinds'], ['float', 'pulse']);
    });

    test('the capabilities are in the catalog from 9.40.0', () {
      for (final feature in ['motionTurn', 'nodeAppear']) {
        expect(kFeatureCatalog[feature], '9.40.0');
        expect(supportsFeature(feature), isTrue);
        expect(supportsFeature(feature, readerVersion: '9.39.0'), isFalse);
      }
    });
  });

  group('turnCases: the turn of a node at the moment t', () {
    for (final row in _rows('turnCases')) {
      final name = row['name']! as String;
      final motion = _obj(row['motion']);
      final t = (row['t']! as num).toDouble();
      final expected = _obj(row['expected']);
      final rtl = row['direction'] == 'rtl';
      final reduced = row['reducedMotion'] == true;
      final degrees = (expected['rotate']! as num).toDouble();
      final pivot = switch (expected['pivot']) {
        'top' => Alignment.topCenter,
        'bottom' => Alignment.bottomCenter,
        _ => Alignment.center,
      };

      test('formula: $name', () {
        final pose = motionPoseAt(NodeMotion.tryParse(motion)!, t, reducedMotion: reduced, rtl: rtl);
        expect(pose.rotate, closeTo(degrees, 1e-6));
        expect(pose.pivot.name, expected['pivot']);
        expect(pose.x, 0);
        expect(pose.y, 0);
        expect(pose.scale, 1);
        expect(pose.opacity, 1);
      });

      testWidgets('widget: $name', (tester) async {
        await pumpDocument(
          tester,
          UiDocumentBuilder.bare(_scene(motion: motion)),
          locale: rtl ? 'ar' : 'en',
          disableAnimations: reduced,
        );
        await tester.pump();
        if (t > 0) await tester.pump(Duration(microseconds: (t * 1000).round()));
        final turned = _turned(tester);
        expect(turned.degrees, _sameTurn(degrees), reason: 'the angle painted');
        // At rest the pivot does not matter (nothing is turned); a turn is about the named point.
        if (degrees != 0) expect(turned.about, pivot);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('appearCases: the pose of an appearing node at the moment t', () {
    for (final row in _rows('appearCases')) {
      final name = row['name']! as String;
      final appear = _obj(row['appear']);
      final t = (row['t']! as num).toDouble();
      final expected = _obj(row['expected']);
      final reduced = row['reducedMotion'] == true;

      test('formula: $name', () {
        final pose = appearPoseAt(NodeAppear.tryParse(appear)!, t, reducedMotion: reduced);
        expect(pose.y, closeTo((expected['y']! as num).toDouble(), 1e-6));
        expect(pose.opacity, closeTo((expected['opacity']! as num).toDouble(), 1e-6));
      });

      testWidgets('widget: $name', (tester) async {
        await pumpDocument(tester, UiDocumentBuilder.bare(_scene(appear: appear)), disableAnimations: reduced);
        await tester.pump();
        await tester.pump(Duration(microseconds: (t * 1000).round()));
        final pose = _appeared(tester);
        expect(pose, isNotNull, reason: 'the node is wrapped at the show');
        expect(pose!.y, closeTo((expected['y']! as num).toDouble(), 1e-6), reason: 'y');
        expect(pose.opacity, closeTo((expected['opacity']! as num).toDouble(), 1e-6), reason: 'opacity');
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('documentCases: the value of `motion` and `appear` on a node', () {
    for (final row in _rows('documentCases')) {
      final name = row['name']! as String;
      final valid = row['valid']! as bool;
      final onRoot = row['onRoot'] == true;
      final isAppear = row['field'] == 'appear';

      testWidgets(name, (tester) async {
        final UiDocument doc;
        if (onRoot) {
          doc = UiDocument.fromJson({
            'schemaVersion': UiDocument.supportedSchemaVersion,
            'documentId': 'root-field',
            'name': 'root',
            'initialScreenId': 'main',
            'screens': [
              {
                'screenId': 'main',
                'name': 'main',
                'root': {
                  'id': 'root',
                  'type': 'Screen',
                  'props': const {},
                  row['field']! as String: row['value'],
                  'children': [textNode('Still text')],
                },
              },
            ],
          });
        } else {
          doc = UiDocumentBuilder.bare(
            _scene(motion: isAppear ? null : row['value'], appear: isAppear ? row['value'] : null),
          );
          final node = doc.screens.first.root.children.first;
          if (isAppear) {
            expect(node.appear != null, valid, reason: 'the appearance is read when the schema accepts it');
          } else {
            expect(node.motion != null, valid, reason: 'the motion is read when the schema accepts it');
          }
        }
        await pumpDocument(tester, doc);
        expect(tester.takeException(), isNull);
        expect(find.text('Still text'), findsOneWidget);
        final drawn = valid && !onRoot;
        expect(find.byType(isAppear ? NodeAppearBox : NodeMotionBox), drawn ? findsOneWidget : findsNothing);
      });
    }
  });

  group('momentCases: when the appearance plays', () {
    test('the rule', () {
      const moments = {
        'firstShow': AppearShowMoment.firstShow,
        'forward': AppearShowMoment.forward,
        'back': AppearShowMoment.back,
        'switch': AppearShowMoment.switchSection,
        'modalClosed': AppearShowMoment.modalClosed,
        'conditionMet': AppearShowMoment.conditionMet,
        'widthClassChanged': AppearShowMoment.widthClassChanged,
        'newRecord': AppearShowMoment.newRecord,
      };
      for (final row in _rows('momentCases')) {
        expect(appearPlaysOn(moments[row['moment']]!), row['plays'], reason: row['name']! as String);
      }
    });

    final appearing = {
      'id': 'card',
      'type': 'Container',
      'props': const <String, Object?>{},
      'style': {'width': 40, 'height': 40, 'background': colorBackground('primary')},
      'appear': {'kind': 'fade', 'duration': 400},
      'children': const <Object?>[],
    };
    Map<String, Object?> go(String id, {String type = 'navigate'}) => {
      'type': type,
      'params': {'screenId': id},
    };

    /// The screens of the flow: `home` opens `second` and `sheet`; the appearing card is on `second` or on `home`.
    UiDocument flow({required bool cardOnHome}) => docWithScreens([
      screenEntry('home', [
        buttonNode('Open', id: 'open', action: go('second')),
        buttonNode('Sheet', id: 'sheet', action: go('layer')),
        buttonNode('Section', id: 'section', action: go('second', type: 'navigate.section')),
        if (cardOnHome) appearing,
      ]),
      screenEntry('second', [
        buttonNode('Back', id: 'back', action: const {'type': 'navigate.back'}),
        if (!cardOnHome) appearing,
      ]),
      screenEntry('layer', [
        buttonNode('Close', id: 'close', action: const {'type': 'navigate.back'}),
      ], presentation: 'modal'),
    ], initialScreenId: 'home');

    testWidgets('the first show plays', (tester) async {
      await pumpDocument(tester, flow(cardOnHome: true));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_appeared(tester)!.opacity, lessThan(1));
      await tester.pumpAndSettle();
      expect(_appeared(tester)!.opacity, 1);
    });

    testWidgets('a screen pushed on top plays', (tester) async {
      await pumpDocument(tester, flow(cardOnHome: false));
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_appeared(tester)!.opacity, lessThan(1));
      await tester.pumpAndSettle();
      expect(_appeared(tester)!.opacity, 1);
    });

    testWidgets('a screen shown again by back plays', (tester) async {
      await pumpDocument(tester, flow(cardOnHome: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_appeared(tester)!.opacity, lessThan(1));
    });

    testWidgets('a screen shown by a section switch plays', (tester) async {
      await pumpDocument(tester, flow(cardOnHome: false));
      await tester.tap(find.text('Section'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_appeared(tester)!.opacity, lessThan(1));
    });

    testWidgets('closing a layer above is not a show', (tester) async {
      await pumpDocument(tester, flow(cardOnHome: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sheet'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(_appeared(tester)!.opacity, 1, reason: 'the card does not play again');
      await tester.pumpAndSettle();
    });

    testWidgets('a condition that starts to hold on a shown screen does not play', (tester) async {
      final doc = UiDocumentBuilder.bare([
        textNode('Still text', id: 'still'),
        {
          ...appearing,
          'visibleIf': {'path': 'user.on', 'op': 'eq', 'value': true},
        },
      ]);
      await pumpDocument(tester, doc, data: const {'user.on': false});
      await tester.pumpAndSettle();
      expect(find.byType(NodeAppearBox), findsNothing);
      await pumpDocument(tester, doc, data: const {'user.on': true});
      await tester.pump(const Duration(milliseconds: 20));
      expect(_appeared(tester), isNull, reason: 'it stands at once');
    });

    testWidgets('a width class that starts to show the node does not play', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.reset);
      final doc = UiDocumentBuilder.bare([
        textNode('Still text', id: 'still'),
        {
          ...appearing,
          'showOn': ['expanded'],
        },
      ]);
      await pumpDocument(tester, doc);
      await tester.pumpAndSettle();
      expect(find.byType(NodeAppearBox), findsNothing);
      tester.view.physicalSize = const Size(1400, 800);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(_appeared(tester), isNull, reason: 'it stands at once');
    });

    testWidgets('a new record of a list on a shown screen does not play', (tester) async {
      final list = {
        'id': 'list',
        'type': 'Repeater',
        'props': {'source': 'items', 'item': 'item'},
        'children': [
          {
            ...appearing,
            'id': 'record',
          },
        ],
      };
      final doc = UiDocumentBuilder.bare([list]);
      await pumpDocument(tester, doc, data: const {'items': <Object?>[]});
      await tester.pumpAndSettle();
      expect(find.byType(NodeAppearBox), findsNothing);
      await pumpDocument(
        tester,
        doc,
        data: const {
          'items': [
            {'name': 'First'},
          ],
        },
      );
      await tester.pump(const Duration(milliseconds: 20));
      expect(_appeared(tester), isNull, reason: 'the record stands at once');
    });
  });

  group('beyond the table', () {
    testWidgets('the appearance is laid over the pose of a motion: the shift adds, the opacity multiplies', (tester) async {
      final doc = UiDocumentBuilder.bare(
        _scene(
          motion: {'kind': 'pulse', 'scale': 1, 'opacity': 0.5, 'duration': 4000},
          appear: {'kind': 'rise', 'distance': 16, 'duration': 400},
        ),
      );
      await pumpDocument(tester, doc);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final appeared = _appeared(tester)!;
      expect(appeared.y, closeTo(16 * (1 - 0.839245058), 1e-6));
      expect(appeared.opacity, closeTo(0.839245058, 1e-6));
      // The motion runs under the appearance from the same show: the breath has already dimmed the square.
      final breath = find.descendant(of: find.byType(NodeMotionBox), matching: find.byType(Opacity));
      expect(tester.widget<Opacity>(breath.first).opacity, lessThan(1));
    });

    testWidgets('a turning node does not move what is next to it', (tester) async {
      final doc = UiDocumentBuilder.bare([
        {
          'id': 'tile',
          'type': 'Container',
          'props': const <String, Object?>{},
          'style': {'width': 40, 'height': 40, 'background': colorBackground('primary')},
          'motion': {'kind': 'sway', 'angle': 45, 'pivot': 'top', 'duration': 4000},
          'children': const <Object?>[],
        },
        textNode('Below', id: 'below'),
      ]);
      await pumpDocument(tester, doc);
      final before = tester.getRect(find.text('Below'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));
      expect(_turned(tester).degrees, closeTo(45, 1e-6));
      expect(tester.getRect(find.text('Below')), before);
    });
  });
}
