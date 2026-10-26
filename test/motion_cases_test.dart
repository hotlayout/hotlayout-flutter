/// MOTION OF A NODE, BLUR UNDER A LAYER AND GLASS (schema 9.20.0).
///
/// The case table is shared by every reader of the contract
/// (`assets/contract/fixtures/motion/motion-cases.json`) and every row of its groups runs here:
///
///  1. `poseCases` (29) -- where a moving node is painted at a moment t: the formula, then a REAL document whose
///     animation clock is advanced to t (the position is read from what the widget paints, not from the formula);
///  2. `documentCases` (28) -- the value of `motion` on a node: what the reader accepts and draws and what it
///     leaves standing, the root screen included;
///  3. `blurCases` (11) -- `backdropBlur` of a screen entry: a real flow that opens the screen as a layer;
///  4. `glassCases` (11) -- `style.backdropBlur` in a style, a state, a width layer and the root of a screen.
///
/// Around the table: the mirrors of the artifact blocks `x-motion` and `x-backdropBlur`, what motion does NOT
/// do (change the layout), taps, "reduce motion", the clock of a node that appears again, the rotated frame of a
/// stack layer, the order of blur and scrim, and the fixture `motion-blur-screens`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/render/widgets/outside_shadow.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/motion_rules.dart';
import 'package:hotlayout_flutter/src/model/node_style.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/modal_layer.dart';
import 'package:hotlayout_flutter/src/render/node_motion.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

_Json _obj(Object? value) => (value! as Map).cast<String, Object?>();
List<_Json> _rows(String key) => (_table[key]! as List).map(_obj).toList();

final _Json _table = jsonDecode(File('assets/contract/fixtures/motion/motion-cases.json').readAsStringSync()) as _Json;
final _Json _schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Json;

ImageFilter _blur(num radius) => ImageFilter.blur(sigmaX: radius.toDouble(), sigmaY: radius.toDouble());

Iterable<ImageFilter?> _filters(WidgetTester tester) =>
    tester.widgetList<BackdropFilter>(find.byType(BackdropFilter)).map((widget) => widget.filter);

/// A node that moves: a 40 × 40 square, then a text that must not move.
List<_Json> _scene(Object? motion, {_Json? style, _Json? extra}) => [
  {
    'id': 'moving',
    'type': 'Container',
    'props': const <String, Object?>{},
    'style': {'width': 40, 'height': 40, 'background': colorBackground('primary'), ...?style},
    'motion': ?motion,
    ...?extra,
    'children': const <Object?>[],
  },
  textNode('Still text', id: 'still'),
];

/// The pose the widget PAINTS now: the shift and scale from its transform, the opacity from its fade.
({double x, double y, double scale, double opacity}) _painted(WidgetTester tester) {
  final box = find.byType(NodeMotionBox);
  expect(box, findsOneWidget);
  final transform = tester.widget<Transform>(find.descendant(of: box, matching: find.byType(Transform)).first);
  final translation = transform.transform.getTranslation();
  final fade = find.descendant(of: box, matching: find.byType(Opacity));
  final opacity = fade.evaluate().isEmpty ? 1.0 : tester.widget<Opacity>(fade.first).opacity;
  return (x: translation.x, y: translation.y, scale: transform.transform.entry(0, 0), opacity: opacity);
}

/// The painted square itself (the box at rest), not the widget that moves it.
Finder get _square => find.descendant(of: find.byType(NodeMotionBox), matching: find.byType(DecoratedBox)).first;

bool _sameMotion(NodeMotion? read, _Json wire) {
  if (read == null) return false;
  final delay = (wire['delay'] as num?)?.toInt() ?? 0;
  if (read.duration != wire['duration'] || read.delay != delay) return false;
  return switch (read) {
    FloatMotion() => wire['kind'] == 'float' && read.axis.name == wire['axis'] && read.amplitude == wire['amplitude'],
    PulseMotion() =>
      wire['kind'] == 'pulse' &&
          read.scale == (wire['scale']! as num).toDouble() &&
          read.opacity == (wire['opacity'] as num?)?.toDouble(),
  };
}

void main() {
  group('the mirrors of the artifact blocks', () {
    test('x-motion: kinds, axes and the bounds of every number', () {
      final block = _obj(_schema['x-motion']);
      expect(block['kinds'], ['float', 'pulse']);
      expect(_obj(block['float'])['axes'], FloatAxis.values.map((axis) => axis.name).toList());
      final ranges = _obj(block['ranges']);
      expect(_obj(ranges['duration']), {'min': kMotionDurationMin, 'max': kMotionDurationMax});
      expect(_obj(ranges['delay']), {'min': kMotionDelayMin, 'max': kMotionDelayMax});
      expect(_obj(ranges['amplitude']), {'min': kFloatAmplitudeMin, 'max': kFloatAmplitudeMax});
      expect(_obj(ranges['scale']), {'min': kPulseScaleMin, 'max': kPulseScaleMax});
      expect(_obj(ranges['opacity']), {'min': kPulseOpacityMin, 'max': kPulseOpacityMax});
      expect(block['reducedMotion'], contains('rest'));
      expect(block['olderReader'], contains('skips the field'));
    });

    test('x-backdropBlur: the radius bounds, the order, the web and Flutter words', () {
      final block = _obj(_schema['x-backdropBlur']);
      final radius = _obj(block['radius']);
      expect(radius['min'], kBackdropBlurMin);
      expect(radius['max'], kBackdropBlurMax);
      expect(block['flutter'], 'ImageFilter.blur(sigmaX: radius, sigmaY: radius)');
      expect(block['order'], 'the blur first, the scrim over it');
      expect(block['inherited'] ?? _obj(block['style'])['inherited'], isFalse);
    });

    test('the catalog of capabilities names both minors', () {
      final features = _obj(_obj(_schema['x-compatibility'])['features']);
      expect(features['nodeMotion'], '9.20.0');
      expect(features['backdropBlur'], '9.20.0');
      expect(supportsFeature('nodeMotion'), isTrue);
      expect(supportsFeature('backdropBlur'), isTrue);
      expect(supportsFeature('nodeMotion', readerVersion: '9.19.0'), isFalse);
    });

    test('the schema defines the same fields the reader reads', () {
      final defs = _obj(_schema[r'$defs']);
      final variants = (_obj(defs['NodeMotion'])['oneOf']! as List).map(_obj).toList();
      Set<String> keys(int index) => _obj(variants[index]['properties']).keys.toSet();
      expect(keys(0), {'kind', 'axis', 'amplitude', 'duration', 'delay'});
      expect(keys(1), {'kind', 'scale', 'opacity', 'duration', 'delay'});
      expect(_obj(_obj(defs['ScreenEntry'])['properties']).containsKey('backdropBlur'), isTrue);
      expect(_obj(_obj(defs['NodeStyle'])['properties']).containsKey('backdropBlur'), isTrue);
    });
  });

  group('poseCases: where a moving node is painted at the moment t', () {
    for (final row in _rows('poseCases')) {
      final name = row['name']! as String;
      final motion = _obj(row['motion']);
      final t = (row['t']! as num).toDouble();
      final expected = _obj(row['expected']);
      final rtl = row['direction'] == 'rtl';
      final reduced = row['reducedMotion'] == true;

      test('formula: $name', () {
        final pose = motionPoseAt(NodeMotion.tryParse(motion)!, t, reducedMotion: reduced, rtl: rtl);
        expect(pose.x, closeTo((expected['x']! as num).toDouble(), 1e-6));
        expect(pose.y, closeTo((expected['y']! as num).toDouble(), 1e-6));
        expect(pose.scale, closeTo((expected['scale']! as num).toDouble(), 1e-6));
        expect(pose.opacity, closeTo((expected['opacity']! as num).toDouble(), 1e-6));
      });

      testWidgets('widget: $name', (tester) async {
        await pumpDocument(
          tester,
          UiDocumentBuilder.bare(_scene(motion)),
          locale: rtl ? 'ar' : 'en',
          disableAnimations: reduced,
        );
        await tester.pump();
        // A negative moment is "before the node appeared": the widget at its first frame is where it is at rest.
        if (t > 0) await tester.pump(Duration(milliseconds: t.toInt()));
        final pose = _painted(tester);
        expect(pose.x, closeTo((expected['x']! as num).toDouble(), 1e-6), reason: 'x');
        expect(pose.y, closeTo((expected['y']! as num).toDouble(), 1e-6), reason: 'y');
        expect(pose.scale, closeTo((expected['scale']! as num).toDouble(), 1e-6), reason: 'scale');
        expect(pose.opacity, closeTo((expected['opacity']! as num).toDouble(), 1e-6), reason: 'opacity');
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('documentCases: the value of `motion` on a node', () {
    for (final row in _rows('documentCases')) {
      final name = row['name']! as String;
      final valid = row['valid']! as bool;
      final onRoot = row['onRoot'] == true;

      testWidgets(name, (tester) async {
        final UiDocument doc;
        if (onRoot) {
          doc = UiDocument.fromJson({
            'schemaVersion': UiDocument.supportedSchemaVersion,
            'documentId': 'root-motion',
            'name': 'root',
            'initialScreenId': 'main',
            'screens': [
              {
                'screenId': 'main',
                'name': 'main',
                'root': {'id': 'root', 'type': 'Screen', 'props': const {}, 'motion': row['motion'], 'children': [textNode('Still text')]},
              },
            ],
          });
        } else {
          doc = UiDocumentBuilder.bare(_scene(row.containsKey('motion') ? row['motion'] : null, extra: {'motion': row['motion']}));
        }
        final first = doc.screens.first.root.children.first;
        if (valid && !onRoot) {
          expect(_sameMotion(first.motion, _obj(row['motion'])), isTrue, reason: 'read as written');
        } else if (!onRoot) {
          expect(first.motion, isNull, reason: 'a form the reader cannot draw is no motion');
        }

        await pumpDocument(tester, doc);
        expect(tester.takeException(), isNull);
        expect(find.text('Still text'), findsOneWidget);
        expect(find.byType(NodeMotionBox), valid && !onRoot ? findsOneWidget : findsNothing);
      });
    }
  });

  group('blurCases: `backdropBlur` of a screen entry', () {
    UiDocument flow(_Json row) => docWithScreens([
      screenEntry('home', [
        buttonNode('Open', action: {'type': 'navigate', 'params': {'screenId': 'sheet'}}),
      ]),
      {
        ...screenEntry('sheet', [textNode('Sheet text', id: 'sheet-text')], presentation: row['presentation'] as String?, modalPlacement: row['modalPlacement']),
        if (row.containsKey('backdropBlur')) 'backdropBlur': row['backdropBlur'],
      },
    ], initialScreenId: 'home');

    for (final row in _rows('blurCases')) {
      final name = row['name']! as String;
      final schema = row['schema']! as bool;
      final modal = row['presentation'] == 'modal';

      testWidgets(name, (tester) async {
        final doc = flow(row);
        expect(doc.screens[1].backdropBlur, schema ? row['backdropBlur'] : isNull, reason: 'the value read');

        await pumpDocument(tester, doc);
        expect(_filters(tester), isEmpty, reason: 'the first screen has nothing under it');
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Sheet text'), findsOneWidget);

        if (schema && modal) {
          // The blur lies between the screen under the layer and the scrim: the scrim is ITS child.
          final blur = find.byType(BackdropFilter);
          expect(blur, findsOneWidget);
          expect(tester.widget<BackdropFilter>(blur).filter, _blur(row['backdropBlur']! as num));
          expect(find.descendant(of: blur, matching: find.byType(ColoredBox)), findsOneWidget);
          // The layer itself is never blurred: it is neither inside the filter nor under it.
          expect(find.descendant(of: blur, matching: find.byKey(kModalLayerKey)), findsNothing);
          expect(find.ancestor(of: find.byKey(kModalLayerKey), matching: find.byType(BackdropFilter)), findsNothing);
          // And the blur does not wipe out the scrim: it is the same scrim of before 9.20.0.
          expect(find.text('Open'), findsOneWidget, reason: 'the screen under the layer stays');
        } else {
          expect(find.byType(BackdropFilter), findsNothing, reason: 'a page has no layer; an invalid value is no blur');
        }
      });
    }

    testWidgets('a layer with no field has only its scrim, as before 9.20.0', (tester) async {
      final doc = flow({'presentation': 'modal'});
      await pumpDocument(tester, doc);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byKey(kModalLayerKey), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('the radius grows with the layer and ends at the named one', (tester) async {
      await pumpDocument(tester, flow({'presentation': 'modal', 'backdropBlur': 24}));
      await tester.tap(find.text('Open'));
      await tester.pump(); // the layer is built; its controller starts after this frame
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final during = tester.widget<BackdropFilter>(find.byType(BackdropFilter)).filter;
      expect(during, isNot(_blur(24)));
      await tester.pumpAndSettle();
      expect(tester.widget<BackdropFilter>(find.byType(BackdropFilter)).filter, _blur(24));
    });

    testWidgets('"reduce motion": the layer, the scrim and the blur are there at once', (tester) async {
      await pumpDocument(tester, flow({'presentation': 'modal', 'backdropBlur': 24}), disableAnimations: true);
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump();
      expect(tester.widget<BackdropFilter>(find.byType(BackdropFilter)).filter, _blur(24));
    });

    testWidgets('a layer over a layer: each blurs what is under it', (tester) async {
      final doc = docWithScreens([
        screenEntry('home', [
          buttonNode('Open', action: {'type': 'navigate', 'params': {'screenId': 'first'}}),
        ]),
        {
          ...screenEntry('first', [
            buttonNode('Open second', id: 'go', action: {'type': 'navigate', 'params': {'screenId': 'second'}}),
          ], presentation: 'modal'),
          'backdropBlur': 6,
        },
        {...screenEntry('second', [textNode('Second')], presentation: 'modal'), 'backdropBlur': 30},
      ], initialScreenId: 'home');
      await pumpDocument(tester, doc);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open second'));
      await tester.pumpAndSettle();
      expect(_filters(tester).toList(), [_blur(6), _blur(30)]);
    });
  });

  group('glassCases: `style.backdropBlur`', () {
    const radius = 'lg';
    const base = <String, Object?>{'width': 120, 'height': 60, 'radius': radius, 'background': {'kind': 'color', 'color': 'primary'}};

    UiDocument doc(_Json row) {
      final value = row['value'];
      switch (row['where']) {
        case 'style':
          return UiDocumentBuilder.bare(_scene(null, style: {...base, 'backdropBlur': value}));
        case 'styleWhen':
          return UiDocumentBuilder.bare(_scene(null, style: base, extra: {
            'styleWhen': [
              {
                'when': {'path': 'flags.off', 'op': 'isEmpty'},
                'style': {'backdropBlur': value},
              },
            ],
          }));
        case 'styleOn':
          return UiDocumentBuilder.bare(_scene(null, style: base, extra: {
            'styleOn': {
              'medium': {'backdropBlur': value},
            },
          }));
        default:
          return UiDocumentBuilder.bare([textNode('Still text')], style: {'background': colorBackground(), 'backdropBlur': value});
      }
    }

    for (final row in _rows('glassCases')) {
      final name = row['name']! as String;
      final valid = row['valid']! as bool;
      final where = row['where']! as String;

      testWidgets('$where: $name', (tester) async {
        // The width layer names its field for a wider class; the others at any width.
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(where == 'styleOn' ? 768 : 393, 800);
        addTearDown(tester.view.reset);

        await pumpDocument(tester, doc(row));
        expect(tester.takeException(), isNull);
        if (valid) {
          expect(_filters(tester).toList(), [_blur(row['value']! as num)]);
          // Within the radius: the blur is clipped by the rounded corners of the same box.
          final clip = find.ancestor(of: find.byType(BackdropFilter), matching: find.byType(ClipRRect));
          if (where != 'rootStyle') expect(clip, findsOneWidget, reason: 'the radius of the node clips the glass');
        } else {
          expect(_filters(tester), isEmpty);
        }
      });
    }

    testWidgets('the width layer names glass for a wider class only: none on a phone', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 800);
      addTearDown(tester.view.reset);
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare(_scene(null, style: base, extra: {'styleOn': {'medium': {'backdropBlur': 24}}})),
      );
      expect(_filters(tester), isEmpty);
    });

    testWidgets('a width layer can remove the glass of the base (`unset`)', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(768, 800);
      addTearDown(tester.view.reset);
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare(_scene(null, style: {...base, 'backdropBlur': 12}, extra: {
          'styleOn': {'unset': {'medium': ['backdropBlur']}},
        })),
      );
      expect(_filters(tester), isEmpty);
    });

    testWidgets('the shadow lies outside the clip of the blur; the background lies over the blur', (tester) async {
      await pumpDocument(tester, UiDocumentBuilder.bare(_scene(null, style: {...base, 'shadow': 'low', 'backdropBlur': 12})));
      final blur = find.byType(BackdropFilter);
      final shadowBox = find.ancestor(of: blur, matching: find.byWidgetPredicate((w) => w is OutsideShadow && w.shadow.isNotEmpty));
      expect(shadowBox, findsOneWidget);
      expect(find.ancestor(of: blur, matching: find.byType(ClipRRect)), findsOneWidget);
      // The node's own background is INSIDE the filter, painted after the backdrop was blurred.
      final background = find.descendant(
        of: blur,
        matching: find.byWidgetPredicate((w) => w is DecoratedBox && (w.decoration as BoxDecoration).color != null),
      );
      expect(background, findsOneWidget);
    });

    testWidgets('glass is not inherited by the children', (tester) async {
      await pumpDocument(tester, UiDocumentBuilder.bare([
        {
          'id': 'card',
          'type': 'Column',
          'props': const {'gap': 'none'},
          'style': {...base, 'backdropBlur': 12},
          'children': [textNode('Inside', id: 'inside'), badgeNode('Badge', id: 'badge')],
        },
      ]));
      expect(_filters(tester).toList(), [_blur(12)]);
    });

    testWidgets('on a button the glass lies on the role surface, once', (tester) async {
      final button = {
        ...buttonNode('Go', action: {'type': 'none'}),
        'style': {'radius': radius, 'backdropBlur': 9},
      };
      await pumpDocument(tester, UiDocumentBuilder.bare([button]));
      expect(_filters(tester).toList(), [_blur(9)]);
      final blur = find.byType(BackdropFilter);
      expect(find.descendant(of: find.byWidgetPredicate((w) => w is ButtonStyleButton), matching: blur), findsOneWidget);
      expect(find.ancestor(of: blur, matching: find.byType(ClipRRect)), findsWidgets);
    });

    testWidgets('on a badge the glass lies on the role surface, once', (tester) async {
      final badge = {
        ...badgeNode('New'),
        'style': {'backdropBlur': 5},
      };
      await pumpDocument(tester, UiDocumentBuilder.bare([badge]));
      expect(_filters(tester).toList(), [_blur(5)]);
    });
  });

  group('what motion does and does not do', () {
    testWidgets('the layout stays: the siblings and the box at rest do not move, only the painting does', (tester) async {
      await pumpDocument(tester, UiDocumentBuilder.bare(_scene({'kind': 'float', 'axis': 'both', 'amplitude': 12, 'duration': 4000})));
      await tester.pump();
      final still = find.text('Still text');
      final rest = tester.getTopLeft(_square);
      final stillRest = tester.getRect(still);
      final stack = tester.getSize(_square);

      await tester.pump(const Duration(milliseconds: 500)); // an eighth: (7.07, -12)
      expect(tester.getRect(still), stillRest, reason: 'a sibling does not move');
      expect(tester.getSize(_square), stack, reason: 'the box at rest keeps its size');
      final moved = tester.getTopLeft(_square);
      expect(moved.dx - rest.dx, closeTo(12 * 0.7071068, 1e-3));
      expect(moved.dy - rest.dy, closeTo(-12, 1e-3));
    });

    testWidgets('a pulse scales about the centre of the box', (tester) async {
      await pumpDocument(tester, UiDocumentBuilder.bare(_scene({'kind': 'pulse', 'scale': 1.5, 'duration': 2000})));
      await tester.pump();
      final centre = tester.getCenter(_square);
      await tester.pump(const Duration(milliseconds: 1000)); // the peak
      expect(tester.getCenter(_square), centre);
      expect(tester.getSize(_square), const Size(40, 40), reason: 'the layout size is the size at rest');
      final painted = tester.getRect(_square);
      // `getRect` follows the transform of the paint: the box is 60 wide there.
      expect(painted.width, closeTo(60, 1e-6));
    });

    testWidgets('the opacity of a pulse multiplies the own opacity of the node', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare(_scene({'kind': 'pulse', 'scale': 1, 'opacity': 0.4, 'duration': 2000}, style: {'opacity': 0.5})),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));
      final fades = tester.widgetList<Opacity>(find.descendant(of: find.byType(NodeMotionBox), matching: find.byType(Opacity))).map((o) => o.opacity).toList();
      expect(fades, hasLength(2));
      expect(fades.reduce((a, b) => a * b), closeTo(0.2, 1e-9));
    });

    testWidgets('a node that fades out completely is still there for a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      final button = {
        ...buttonNode('Go', action: {'type': 'none'}),
        'motion': {'kind': 'pulse', 'scale': 1, 'opacity': 0, 'duration': 1000},
      };
      await pumpDocument(tester, UiDocumentBuilder.bare([button]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(_painted(tester).opacity, 0);
      expect(find.bySemanticsLabel('Go'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a tap inside the box at rest reaches the button at every moment of the cycle', (tester) async {
      final taps = <String>[];
      final button = {
        ...buttonNode('Go', action: {'type': 'custom'}, id: 'go'),
        'motion': {'kind': 'pulse', 'scale': 1.5, 'duration': 2000},
      };
      await pumpDocument(tester, UiDocumentBuilder.bare([button]), onAction: (action, nodeId) => taps.add(nodeId));
      await tester.pump();
      for (var i = 0; i < 4; i += 1) {
        await tester.tap(find.text('Go'));
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(taps, ['go', 'go', 'go', 'go']);
    });

    testWidgets('"reduce motion": the node stands at rest and nothing keeps ticking', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare(_scene({'kind': 'float', 'axis': 'both', 'amplitude': 12, 'duration': 4000})),
        disableAnimations: true,
      );
      await tester.pump(const Duration(milliseconds: 1000));
      expect(_painted(tester), (x: 0.0, y: 0.0, scale: 1.0, opacity: 1.0));
      expect(tester.binding.transientCallbackCount, 0, reason: 'no ticker runs');
    });

    testWidgets('a node that appears again counts from zero', (tester) async {
      final doc = docWithScreens([
        screenEntry('a', [
          ..._scene({'kind': 'float', 'axis': 'horizontal', 'amplitude': 10, 'duration': 4000}),
          buttonNode('Next', action: {'type': 'navigate', 'params': {'screenId': 'b'}}),
        ]),
        screenEntry('b', [
          buttonNode('Back', action: {'type': 'navigate.back'}),
        ]),
      ], initialScreenId: 'a');
      await pumpDocument(tester, doc);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));
      expect(_painted(tester).x, closeTo(10, 1e-6));
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.tap(find.text('Back'));
      await tester.pump();
      await tester.pump();
      expect(_painted(tester).x, closeTo(0, 1e-6), reason: 'the clock starts again');
      await tester.pump(const Duration(milliseconds: 1000));
      expect(_painted(tester).x, closeTo(10, 1e-6));
    });

    for (final rtl in [false, true]) {
      testWidgets('a layer turned by 90 degrees: the shift still goes along the axes of the screen (${rtl ? 'rtl' : 'ltr'})', (tester) async {
        final doc = UiDocumentBuilder.bare([
          {
            'id': 'stack',
            'type': 'Stack',
            'props': const {'alignHorizontal': 'start', 'alignVertical': 'start'},
            'style': {'width': 200, 'height': 200},
            'children': [
              {'id': 'sizer', 'type': 'Container', 'props': const <String, Object?>{}},
              {
                'id': 'turned',
                'type': 'Container',
                'props': const <String, Object?>{},
                'style': {'width': 40, 'height': 20, 'background': colorBackground('primary')},
                'layer': {'alignHorizontal': 'center', 'alignVertical': 'center', 'rotate': 90},
                'motion': {'kind': 'float', 'axis': 'horizontal', 'amplitude': 10, 'duration': 4000},
              },
            ],
          },
        ]);
        await pumpDocument(tester, doc, locale: rtl ? 'ar' : 'en');
        await tester.pump();
        final rest = tester.getCenter(_square);
        await tester.pump(const Duration(milliseconds: 1000)); // a quarter: toward the END of the line
        final moved = tester.getCenter(_square);
        expect(moved.dx - rest.dx, closeTo(rtl ? -10 : 10, 1e-6));
        expect(moved.dy - rest.dy, closeTo(0, 1e-6));
      });
    }

    testWidgets('documents without the fields are drawn with no motion and no blur', (tester) async {
      for (final id in ['reward-catalog-screens', 'rewards-showcase-screens', 'composition-screens']) {
        await pumpDocument(tester, loadFixture(id));
        expect(find.byType(NodeMotionBox), findsNothing, reason: id);
        expect(find.byType(BackdropFilter), findsNothing, reason: id);
      }
    });
  });

  group('the fixture motion-blur-screens', () {
    final doc = loadFixture('motion-blur-screens');

    test('the screens and the fields the reader reads', () {
      expect(doc.schemaVersion, '9.30.0');
      expect(doc.screens.map((s) => s.screenId), ['home', 'sheet']);
      expect(doc.screens[1].presentation, ScreenPresentationToken.modal);
      expect(doc.screens[1].backdropBlur, 16);
    });

    testWidgets('six dots and a button move, not in unison; the glass card blurs the dots', (tester) async {
      await pumpDocument(tester, doc);
      await tester.pump();
      expect(find.byType(NodeMotionBox), findsNWidgets(7));
      expect(_filters(tester).toList(), [_blur(14)]);

      await tester.pump(const Duration(milliseconds: 3500));
      final poses = <String>{};
      for (final box in tester.widgetList<Transform>(find.descendant(of: find.byType(NodeMotionBox), matching: find.byType(Transform)))) {
        poses.add(box.transform.storage.take(16).map((v) => v.toStringAsFixed(3)).join(','));
      }
      expect(poses.length, greaterThan(4), reason: 'every node has its own numbers');
      expect(tester.takeException(), isNull);
    });

    testWidgets('"Open the sheet": a sheet over the blurred home screen', (tester) async {
      await pumpDocument(tester, doc);
      await tester.pump();
      await tester.tap(find.text('Open the sheet'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(kModalLayerKey), findsOneWidget);
      expect(_filters(tester).toList(), contains(_blur(16)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('with "reduce motion" every node of the fixture stands at rest', (tester) async {
      await pumpDocument(tester, doc, disableAnimations: true);
      await tester.pump(const Duration(milliseconds: 2000));
      for (final box in tester.widgetList<Transform>(find.descendant(of: find.byType(NodeMotionBox), matching: find.byType(Transform)))) {
        expect(box.transform.getTranslation().length, 0);
        expect(box.transform.entry(0, 0), 1);
      }
      expect(tester.binding.transientCallbackCount, 0);
    });

    test('the model: a style carries the glass', () {
      expect(NodeStyle.parse({'backdropBlur': 14})?.backdropBlur, 14);
      expect(NodeStyle.parse({'backdropBlur': 14, 'opacity': 1})?.over(null).backdropBlur, 14);
    });
  });
}
