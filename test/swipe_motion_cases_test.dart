/// "Swipe to confirm": the motion (schema 9.34.0, `Button.confirmTransition`, `x-swipeConfirmMotion`): the shared
/// table `fixtures/swipe-motion/swipe-motion-cases.json`.
///
/// The groups run through the pure rules (`swipe_motion.dart`); the mechanism runs on a REAL button of the frame
/// `swipe-motion-screens` with real frames: the fill behind the thumb, the circle, the fill over the screen and the
/// action that goes after it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/swipe_confirm.dart';
import 'package:hotlayout_flutter/src/model/swipe_motion.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/render/swipe_confirm_button.dart';
import 'package:hotlayout_flutter/src/render/swipe_confirm_paint.dart';
import 'package:hotlayout_flutter/src/render/swipe_ripple_layer.dart';

import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

final _Row _table =
    (jsonDecode(File('assets/contract/fixtures/swipe-motion/swipe-motion-cases.json').readAsStringSync()) as Map)
        .cast<String, Object?>();
final _Row _schema = (jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as Map)
    .cast<String, Object?>();

List<_Row> _rows(String key) => (_table[key]! as List<Object?>).cast<_Row>();

SwipeTrack _trackOf(Object? raw) {
  final row = (raw! as Map).cast<String, Object?>();
  return (
    height: (row['height']! as num).toDouble(),
    width: (row['width']! as num).toDouble(),
    border: (row['border']! as num).toDouble(),
    inset: (row['inset']! as num).toDouble(),
  );
}

SwipeRunner _runnerOf(Object? word) => SwipeRunner.values.byName(word! as String);

SwipeStep _stepOf(Object? word) => word == 'return' ? SwipeStep.giveBack : SwipeStep.values.byName(word! as String);

const _tolerance = 1e-4;

Finder _tracks() => find.byType(SwipeConfirmTrack);

Finder _thumb() => find.byKey(kSwipeThumbKey);

Finder _circle() => find.byKey(kSwipeCircleKey);

Finder _fill() => find.byKey(kSwipeRippleLayerKey);

void _view(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(393, 852);
  addTearDown(tester.view.reset);
}

/// Plays [ms] milliseconds in frames of 50: each controller of the button starts when the previous one ends, and a
/// ticker starts on its first frame, so one long pump would not run them in turn.
Future<void> _play(WidgetTester tester, int ms) async {
  for (var spent = 0; spent < ms; spent += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Drags the thumb of the track number [index] by [share] of its travel; `null` releases it all the way.
Future<TestGesture> _drag(WidgetTester tester, int index, {double? share, bool release = true}) async {
  final track = tester.getRect(_tracks().at(index));
  final thumb = tester.getRect(find.descendant(of: _tracks().at(index), matching: _thumb()));
  final travel = track.width - thumb.width - 2 * (thumb.left - track.left);
  final gesture = await tester.startGesture(Offset(thumb.center.dx, track.center.dy));
  final total = share == null ? travel * 1.05 : travel * share;
  for (var i = 0; i < 10; i += 1) {
    await gesture.moveBy(Offset(total / 10, 0));
    await tester.pump();
  }
  if (release) await gesture.up();
  return gesture;
}

Future<void> _pumpFrame(
  WidgetTester tester, {
  bool reduced = false,
  List<String>? log,
  FutureOr<void> Function(ButtonAction action)? answer,
}) => pumpDocument(
  tester,
  loadFixture('swipe-motion-screens'),
  disableAnimations: reduced,
  onTrack: log == null ? null : (event, nodeId, record) => log.add('track:$nodeId'),
  onAction: (action, nodeId) {
    log?.add('action:${action.type}');
    answer?.call(action);
  },
);

void main() {
  test('the table is read in full', () {
    expect(_rows('labelCases'), hasLength(6));
    expect(_rows('trailCases'), hasLength(4));
    expect(_rows('thumbRadiusCases'), hasLength(12));
    expect(_rows('collapseCases'), hasLength(7));
    expect(_rows('rippleScaleCases'), hasLength(4));
    expect(_rows('rippleCases'), hasLength(5));
    expect(_rows('revealCases'), hasLength(4));
    expect(_rows('sequenceCases'), hasLength(10));
    expect(_rows('busyReturnCases'), hasLength(2));
    expect(_rows('fieldCases'), hasLength(4));
    expect(_rows('documentCases'), hasLength(6));
    expect(_rows('ruleCases'), hasLength(12));
  });

  group('the data of the artifact', () {
    test('`x-swipeConfirmMotion` is mirrored whole', () {
      expect(jsonDecode(jsonEncode(kSwipeMotionRules)), _schema['x-swipeConfirmMotion']);
    });

    test('the capability is in the catalog from 9.34.0', () {
      expect(kFeatureCatalog['swipeMotion'], '9.34.0');
      expect(supportsFeature('swipeMotion'), isTrue);
      expect(supportsFeature('swipeMotion', readerVersion: '9.33.0'), isFalse);
    });

    test('the field is one word in the schema', () {
      final props = ((_schema[r'$defs']! as _Row)['ButtonProps']! as _Row)['properties']! as _Row;
      expect((props[kConfirmTransitionKey]! as _Row)['enum'], [kConfirmTransitionRipple]);
    });

    for (final row in _rows('ruleCases')) {
      test('rule: ${row['name']}', () {
        Object? at(Object? node, String path) =>
            path.split('.').fold<Object?>(node, (value, key) => (value! as Map)[key]);
        final rule = at(kSwipeMotionRules, row['rule']! as String);
        final expected = row['expect'];
        if (expected is List) {
          expect(rule, expected);
        } else {
          expect(rule, expected);
        }
        // The constants the code runs on are the same numbers.
        expect(kSwipeCollapseMs, 600);
        expect(kSwipeRippleMs, 800);
        expect(kSwipeRevealMs, 200);
        expect(kSwipeHaloOpacity, 0.4);
        expect(kSwipeCollapseCurve, [0.4, 0, 0.2, 1]);
        expect(kRippleActionTypes, ['navigate', 'navigate.back']);
      });
    }
  });

  group('the pure rules', () {
    for (final row in _rows('labelCases')) {
      test('label: ${row['name']}', () {
        expect(
          swipeLabelOpacityOf((row['progress']! as num).toDouble()),
          closeTo((row['expect']! as num).toDouble(), _tolerance),
        );
      });
    }

    for (final row in _rows('trailCases')) {
      test('trail: ${row['name']}', () {
        final strip = swipeTrailOf(_trackOf(row['track']), (row['progress']! as num).toDouble());
        final expected = (row['expect']! as Map).cast<String, Object?>();
        expect(strip.start, closeTo((expected['start']! as num).toDouble(), _tolerance));
        expect(strip.width, closeTo((expected['width']! as num).toDouble(), _tolerance));
      });
    }

    for (final row in _rows('thumbRadiusCases')) {
      test('thumb radius: ${row['name']}', () {
        final radius = (row['radius'] as num?)?.toDouble();
        expect(
          swipeThumbRadiusOf(_trackOf(row['track']), radius),
          closeTo((row['expect']! as num).toDouble(), _tolerance),
        );
      });
    }

    for (final row in _rows('collapseCases')) {
      test('collapse: ${row['name']}', () {
        final frame = swipeCollapseAt(_trackOf(row['track']), (row['elapsed']! as num).toDouble());
        final expected = (row['expect']! as Map).cast<String, Object?>();
        expect(frame.start, closeTo((expected['start']! as num).toDouble(), _tolerance));
        expect(frame.width, closeTo((expected['width']! as num).toDouble(), _tolerance));
        expect(frame.height, closeTo((expected['height']! as num).toDouble(), _tolerance));
        expect(frame.ring, closeTo((expected['ring']! as num).toDouble(), _tolerance));
        expect(frame.surfaceOpacity, closeTo((expected['surfaceOpacity']! as num).toDouble(), _tolerance));
        expect(frame.haloOpacity, closeTo((expected['haloOpacity']! as num).toDouble(), _tolerance));
      });
    }

    for (final row in _rows('rippleScaleCases')) {
      test('ripple scale: ${row['name']}', () {
        final area = (row['area']! as Map).cast<String, Object?>();
        final scale = swipeRippleScaleOf(
          centerX: (area['centerX']! as num).toDouble(),
          centerY: (area['centerY']! as num).toDouble(),
          screenWidth: (area['screenWidth']! as num).toDouble(),
          screenHeight: (area['screenHeight']! as num).toDouble(),
          core: (area['core']! as num).toDouble(),
        );
        expect(scale, closeTo((row['expect']! as num).toDouble(), _tolerance));
      });
    }

    for (final row in _rows('rippleCases')) {
      test('ripple: ${row['name']}', () {
        expect(
          swipeRippleAt((row['scale']! as num).toDouble(), (row['elapsed']! as num).toDouble()),
          closeTo((row['expect']! as num).toDouble(), _tolerance),
        );
      });
    }

    for (final row in _rows('revealCases')) {
      test('reveal: ${row['name']}', () {
        expect(
          swipeRevealAt((row['elapsed']! as num).toDouble()),
          closeTo((row['expect']! as num).toDouble(), _tolerance),
        );
      });
    }

    for (final row in _rows('sequenceCases')) {
      test('sequence: ${row['name']}', () {
        final input = (row['input']! as Map).cast<String, Object?>();
        final steps = swipeSequenceOf(
          runner: _runnerOf(input['runner']),
          actionType: input['actionType']! as String,
          ripple: input['transition'] == 'ripple',
          way: SwipeWay.values.byName(input['way']! as String),
          reducedMotion: input['reducedMotion']! as bool,
        );
        expect(steps, (row['expect']! as List<Object?>).map(_stepOf).toList());
      });
    }

    for (final row in _rows('busyReturnCases')) {
      test('busy return: ${row['name']}', () {
        expect(
          swipeBusyReturnOf(row['reducedMotion']! as bool),
          (row['expect']! as List<Object?>).map(_stepOf).toList(),
        );
      });
    }

    for (final row in _rows('fieldCases')) {
      test('field: ${row['name']}', () {
        final props = (row['props']! as Map).cast<String, Object?>();
        final reads = row['reads'];
        expect(confirmTransitionIsRipple(props[kConfirmTransitionKey]), reads == 'ripple');
        final node = UiNode.parse({
          'id': 'b',
          'type': 'Button',
          'props': {
            'label': {'kind': 'literal', 'value': 'x'},
            'action': {'type': 'none'},
            'confirm': 'swipe',
            ...props,
          },
        });
        expect((node as ButtonNode).confirmRipple, reads == 'ripple');
      });
    }

    for (final row in _rows('documentCases')) {
      test('document: ${row['name']}', () {
        final props = (row['props']! as Map).cast<String, Object?>();
        final node = UiNode.parse({
          'id': 'b',
          'type': 'Button',
          'props': {
            'label': {'kind': 'literal', 'value': 'x'},
            ...props,
          },
        });
        // The reader skips what the builder would not publish: the word is read, and the sequence decides.
        expect((node as ButtonNode).confirmRipple, props['confirmTransition'] == 'ripple');
        if (row['publishes'] == false && props['confirmTransition'] == 'ripple') {
          final type = ((props['action'] as Map?)?['type'] ?? 'none') as String;
          final plays = swipeRipplePlays(
            runner: type == 'none' ? SwipeRunner.none : (type == 'submit' ? SwipeRunner.host : SwipeRunner.reader),
            actionType: type,
            ripple: node.confirmRipple,
            way: SwipeWay.swipe,
            reducedMotion: false,
          );
          expect(plays && node.confirmBySwipe, isFalse, reason: 'a document that is not published plays no fill');
        }
      });
    }
  });

  group('on a real button', () {
    testWidgets('the fill follows the thumb with its height and radius, and the label fades with the travel', (
      tester,
    ) async {
      _view(tester);
      await _pumpFrame(tester);
      final track = tester.getRect(_tracks().at(0));
      final rest = tester.getRect(find.descendant(of: _tracks().at(0), matching: _thumb()));
      final trailRest = tester.getRect(find.descendant(of: _tracks().at(0), matching: find.byKey(kSwipeTrailKey)));
      expect(trailRest, rest, reason: 'at rest the fill is exactly the thumb');
      final gesture = await _drag(tester, 0, share: 0.5, release: false);
      final thumb = tester.getRect(find.descendant(of: _tracks().at(0), matching: _thumb()));
      final trail = tester.getRect(find.descendant(of: _tracks().at(0), matching: find.byKey(kSwipeTrailKey)));
      expect(trail.left, rest.left, reason: 'from the place of rest of the thumb');
      expect(trail.right, closeTo(thumb.right, 0.01), reason: 'to the far edge of the thumb');
      expect(trail.height, thumb.height);
      final shape =
          (tester
                      .widget<DecoratedBox>(find.descendant(of: _tracks().at(0), matching: find.byKey(kSwipeTrailKey)))
                      .decoration
                  as BoxDecoration)
              .borderRadius;
      final thumbShape =
          (tester.widget<DecoratedBox>(find.descendant(of: _tracks().at(0), matching: _thumb())).decoration
                  as BoxDecoration)
              .borderRadius;
      expect(shape, thumbShape, reason: 'the fill has the radius of the thumb on every corner');
      final progress = (thumb.left - rest.left) / (track.width - thumb.width - 2 * (rest.left - track.left));
      final label = tester.widget<Opacity>(
        find.descendant(
          of: _tracks().at(0),
          matching: find.byWidgetPredicate((w) => w is Opacity && w.child is Padding),
        ),
      );
      expect(label.opacity, closeTo(1 - progress, 0.01), reason: 'the label fades with the travel');
      await gesture.up();
      await _play(tester, 600);
    });

    testWidgets('the thumb radius is concentric with the track radius: the theme role, a style radius, a pill', (
      tester,
    ) async {
      _view(tester);
      await _pumpFrame(tester);
      final inset = RenderTheme.fallback().space(SpacingToken.xs);
      final md = RenderTheme.fallback().radius(RadiusToken.md);
      double radiusOf(int index) {
        final box =
            tester.widget<DecoratedBox>(find.descendant(of: _tracks().at(index), matching: _thumb())).decoration
                as BoxDecoration;
        return (box.borderRadius! as BorderRadius).topLeft.x;
      }

      final heights = [for (var i = 0; i < 3; i += 1) tester.getSize(_tracks().at(i)).height];
      final borders = [for (var i = 0; i < 3; i += 1) tester.widget<SwipeConfirmTrack>(_tracks().at(i)).border];
      double expected(int index, double? radius) =>
          swipeThumbRadiusOf((height: heights[index], width: 345, border: borders[index], inset: inset), radius);
      expect(radiusOf(0), expected(0, md), reason: 'no radius: the radius of the theme role');
      expect(radiusOf(1), expected(1, md), reason: 'a style radius `md`');
      expect(radiusOf(2), expected(2, 9999), reason: 'a pill track keeps the thumb a circle');
    });

    testWidgets(
      'a swipe on `navigate` with ripple: the circle, the fill, then the action under the fill, then the reveal',
      (tester) async {
        _view(tester);
        final log = <String>[];
        await _pumpFrame(tester, log: log);
        expect(find.text('Payment'), findsOneWidget);
        await _drag(tester, 0);
        expect(log, isEmpty, reason: 'the action does not run on the release: the fill goes first');

        await _play(tester, 300);
        expect(_circle(), findsOneWidget, reason: 'the button collapses into a circle');
        expect(_thumb(), findsNWidgets(2), reason: 'only the thumbs of the other two buttons are left');
        expect(_fill(), findsNothing);

        await _play(tester, 700);
        expect(_fill(), findsOneWidget, reason: 'the circle grows over the screen');
        expect(log, isEmpty);

        // The fill catches presses while it grows: a drag on another button does nothing.
        final other = tester.getCenter(_tracks().at(1));
        final press = await tester.startGesture(other);
        await press.moveBy(const Offset(300, 0));
        await tester.pump();
        await press.up();

        await _play(tester, 400);
        expect(find.text('Payment sent'), findsNothing, reason: 'the screen is still the old one under the fill');
        expect(log, isEmpty);

        await _play(tester, 400);
        expect(find.text('Payment sent'), findsOneWidget, reason: 'the next screen stands under the fill');
        expect(_fill(), findsOneWidget, reason: 'the fill fades away over it');
        final at = tester.getTopLeft(find.text('Payment sent'));
        await _play(tester, 100);
        expect(
          tester.getTopLeft(find.text('Payment sent')),
          at,
          reason: 'the change of screen has no motion of its own',
        );

        await _play(tester, 400);
        expect(_fill(), findsNothing, reason: 'the fill is gone');
        expect(find.text('Payment sent'), findsOneWidget);
      },
    );

    testWidgets('a thumb already at the end still glides for 200 ms before the circle forms', (tester) async {
      _view(tester);
      await _pumpFrame(tester);
      await _drag(tester, 0);
      await _play(tester, 100);
      expect(_circle(), findsNothing, reason: 'the glide to the end takes its 200 ms whatever the distance');
      await _play(tester, 200);
      expect(_circle(), findsOneWidget, reason: 'the circle forms once the glide is over');
      await _play(tester, 2500);
    });

    testWidgets('the fill is in the tree only for its time and covers every corner of the flow', (tester) async {
      _view(tester);
      await _pumpFrame(tester);
      await _drag(tester, 0);
      await _play(tester, 1000);
      expect(_fill(), findsOneWidget);
      // Grown past 25 times: the core reaches the farthest corner of 393 x 852 from a circle low on the screen.
      final layer = tester.getRect(_fill());
      expect(layer, const Rect.fromLTWH(0, 0, 393, 852), reason: 'a layer over the whole flow, cut by its edges');
      await _play(tester, 1500);
      expect(_fill(), findsNothing);
    });

    testWidgets('the keyboard acts at once: no circle, no fill', (tester) async {
      _view(tester);
      await _pumpFrame(tester);
      Focus.of(
        tester.element(find.descendant(of: _tracks().at(0), matching: find.byType(IntrinsicWidth))),
        scopeOk: false,
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await _play(tester, 400);
      expect(find.text('Payment sent'), findsOneWidget, reason: 'the screen changes at once');
      expect(_fill(), findsNothing);
      await _play(tester, 1200);
      expect(_fill(), findsNothing);
    });

    testWidgets('"reduce motion": no circle, no fill, the action at once', (tester) async {
      _view(tester);
      final log = <String>[];
      await _pumpFrame(tester, reduced: true, log: log);
      await _drag(tester, 0);
      await tester.pump();
      await _play(tester, 100);
      expect(find.text('Payment sent'), findsOneWidget);
      expect(_circle(), findsNothing);
      expect(_fill(), findsNothing);
    });

    testWidgets('an action of the host: the circle holds the indicator, no fill; the answer expands it back', (
      tester,
    ) async {
      _view(tester);
      final log = <String>[];
      final answer = Completer<void>();
      await pumpDocument(
        tester,
        loadFixture('swipe-motion-screens'),
        onTrack: (event, nodeId, record) => log.add('track:$nodeId'),
        onAction: (action, nodeId) => log.add('action:${action.type}'),
        onRecordAction: HostActions(
          handlers: {
            'submit': (call) {
              log.add('host:submit');
              return answer.future;
            },
          },
        ).handle,
      );
      await _drag(tester, 1);
      expect(log.where((e) => e.startsWith('host')), ['host:submit'], reason: 'the action runs at once');
      await _play(tester, 800);
      expect(_circle(), findsOneWidget);
      expect(find.descendant(of: _tracks().at(1), matching: find.byType(RotationTransition)), findsOneWidget);
      expect(_fill(), findsNothing, reason: 'an action of the host never plays the fill');
      await _play(tester, 2000);
      expect(_circle(), findsOneWidget, reason: 'the circle is held until the host answers');

      answer.complete();
      await _play(tester, 300);
      expect(_circle(), findsOneWidget, reason: 'the circle expands back first');
      await _play(tester, 1200);
      expect(_circle(), findsNothing);
      expect(
        find.descendant(of: _tracks().at(1), matching: _thumb()),
        findsOneWidget,
        reason: 'then the thumb returns',
      );
    });

    testWidgets('the event of the action goes once, with the action, after the fill and not on the release', (
      tester,
    ) async {
      _view(tester);
      final events = <String>[];
      final doc = docWithScreens([
        screenEntry('first', [
          {
            'id': 'go',
            'type': 'Button',
            'props': {
              'label': {'kind': 'literal', 'value': 'Go'},
              'variant': 'primary',
              'action': {
                'type': 'navigate',
                'params': {'screenId': 'second'},
                'track': {'event': 'paid'},
              },
              'fullWidth': true,
              'confirm': 'swipe',
              'confirmTransition': 'ripple',
            },
          },
        ]),
        screenEntry('second', [textNode('Second', id: 'second-text')]),
      ], initialScreenId: 'first');
      await pumpDocument(tester, doc, onTrack: (event, nodeId, record) => events.add('${event.event}@$nodeId'));
      await _drag(tester, 0);
      await _play(tester, 1200);
      expect(_fill(), findsOneWidget);
      expect(events, isEmpty, reason: 'the fill is still growing');
      await _play(tester, 600);
      expect(events, ['paid@go']);
      expect(find.text('Second'), findsOneWidget);
      await _play(tester, 1000);
      expect(events, ['paid@go'], reason: 'once');
    });

    testWidgets('a button that leaves before the screen is covered: the fill goes with it and the action never runs', (
      tester,
    ) async {
      _view(tester);
      final log = <String>[];
      Map<String, Object?> button() => {
        'id': 'go',
        'type': 'Button',
        'visibleIf': {'path': 'shown', 'op': 'eq', 'value': true},
        'props': {
          'label': {'kind': 'literal', 'value': 'Go'},
          'variant': 'primary',
          'action': {
            'type': 'navigate',
            'params': {'screenId': 'second'},
          },
          'fullWidth': true,
          'confirm': 'swipe',
          'confirmTransition': 'ripple',
        },
      };
      final doc = docWithScreens([
        screenEntry('first', [button(), textNode('First', id: 'first-text')]),
        screenEntry('second', [textNode('Second', id: 'second-text')]),
      ], initialScreenId: 'first');
      await pumpDocument(
        tester,
        doc,
        data: const {'shown': true},
        onTrack: (event, nodeId, record) => log.add('track:$nodeId'),
        onAction: (action, nodeId) => log.add('action:${action.type}'),
      );
      await _drag(tester, 0);
      await _play(tester, 1000);
      expect(_fill(), findsOneWidget);
      await pumpDocument(tester, doc, data: const {'shown': false});
      await tester.pump();
      expect(_fill(), findsNothing, reason: 'the fill is dropped with the button');
      await _play(tester, 1500);
      expect(find.text('Second'), findsNothing);
      expect(find.text('First'), findsOneWidget);
      expect(log, isEmpty, reason: 'no action and no event');
    });

    testWidgets('a button without the field changes the screen at once after the swipe', (tester) async {
      _view(tester);
      final doc = docWithScreens([
        screenEntry('first', [
          {
            'id': 'go',
            'type': 'Button',
            'props': {
              'label': {'kind': 'literal', 'value': 'Go'},
              'variant': 'primary',
              'action': {
                'type': 'navigate',
                'params': {'screenId': 'second'},
              },
              'fullWidth': true,
              'confirm': 'swipe',
            },
          },
        ]),
        screenEntry('second', [textNode('Second', id: 'second-text')]),
      ], initialScreenId: 'first');
      await pumpDocument(tester, doc);
      await _drag(tester, 0);
      await _play(tester, 600);
      expect(find.text('Second'), findsOneWidget);
      expect(_fill(), findsNothing);
    });
  });
}
