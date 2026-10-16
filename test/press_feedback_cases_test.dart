/// The feedback of a pressed node (schema 9.25.0, `pressFeedback`, `x-pressFeedback`): the shared table
/// `fixtures/press-feedback/press-feedback-cases.json` run through the rule and through a real node, and then the
/// motion itself with a real finger: who sinks, how far, how fast, and what stays still.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/press_feedback.dart';
import 'package:hotlayout_flutter/src/render/press_feedback.dart';
import 'package:hotlayout_flutter/src/render/swipe_confirm_button.dart';

import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

void main() {
  final table = jsonDecode(File('assets/contract/fixtures/press-feedback/press-feedback-cases.json').readAsStringSync()) as _Row;
  final schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Row;
  final block = schema['x-pressFeedback']! as _Row;
  List<_Row> rowsOf(String name) => (table[name]! as List<Object?>).cast<_Row>();
  final kindCases = rowsOf('kindCases');
  final poseCases = rowsOf('poseCases');
  final ruleCases = rowsOf('ruleCases');

  PressFeedbackKind? kindNamed(Object? name) => name == null ? null : PressFeedbackKind.values.byName(name as String);

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  test('the table is read in full', () {
    expect(kindCases, hasLength(10));
    expect(poseCases, hasLength(3));
    expect(ruleCases, hasLength(5));
  });

  group('kindCases: who sinks and how', () {
    for (final row in kindCases) {
      final name = row['name']! as String;
      final node = row['node']! as _Row;
      final disabled = row['disabled']! as bool;
      final expected = kindNamed(row['expect']);

      /// The node, in a document that can hold it, and the data that makes a disabled row disabled.
      List<_Row> children() => [
        if (node['type'] == 'NavItem')
          {'id': 'bar', 'type': 'NavBar', 'props': <String, Object?>{}, 'children': [node]}
        else
          {...node, if (disabled) 'props': {...(node['props']! as _Row), 'disabledIf': {'path': 'task.locked', 'op': 'isTrue'}}},
      ];

      test('rule: $name', () {
        final child = UiDocumentBuilder.bare(children()).screens.first.root.children.single;
        final target = child is NavBarNode ? child.children.single : child;
        expect(pressFeedbackKindOf(target, disabled: disabled), expected);
      });

      testWidgets('screen: $name', (tester) async {
        phone(tester);
        await pumpDocument(tester, UiDocumentBuilder.bare(children()), data: {'task.locked': disabled}, onAction: (_, _) {});
        expect(tester.takeException(), isNull);
        final tapped = switch (node['type']) {
          'NavItem' => find.byKey(ValueKey('sdui-nav-item-${node['id']}')),
          'Container' => find.descendant(of: find.byKey(ValueKey('sdui-press-${node['id']}@')), matching: find.byType(GestureDetector)).first,
          'ListTile' => find.text(((node['props']! as _Row)['title']! as _Row)['value']! as String),
          'IconButton' => find.bySubtype<ButtonStyleButton>().first,
          'Button' when (node['props']! as _Row)['confirm'] == 'swipe' => find.byType(SwipeConfirmTrack).first,
          _ => find.bySubtype<ButtonStyleButton>().first,
        };
        final feedback = find.ancestor(of: tapped, matching: find.byType(PressFeedback));
        expect(feedback.evaluate(), isNotEmpty);
        // The innermost control of the node answers (the nearest ancestor of what is tapped).
        expect(tester.widget<PressFeedback>(feedback.first).kind, expected);
      });
    }
  });

  group('poseCases and ruleCases', () {
    for (final row in poseCases) {
      test('pose: ${row['name']}', () {
        final pose = pressPoseOf(PressFeedbackKind.values.byName(row['kind']! as String));
        final expected = row['expect']! as _Row;
        expect(pose.scale, expected['scale']);
        expect(pose.opacity, expected['opacity']);
      });
      test('pose under «reduce motion»: ${row['name']}', () {
        final pose = pressPoseOf(PressFeedbackKind.values.byName(row['kind']! as String), reduceMotion: true);
        expect(pose.scale, 1);
        expect(pose.opacity, 0.7);
      });
    }

    for (final row in ruleCases) {
      test('rule: ${row['name']}', () {
        final rule = row['rule']! as String;
        final expected = row['expect'];
        switch (rule) {
          case 'down.durationMs':
            expect(kPressDownMs, expected);
          case 'up.durationMs':
            expect(kPressUpMs, expected);
          case 'down.curve':
            expect(kPressDownCurve, expected);
          case 'up.curve':
            expect(kPressUpCurve, expected);
          case 'words':
            expect(kPressFeedbackNone, (expected! as List<Object?>).single);
          default:
            fail('unknown rule $rule');
        }
      });
    }

    test('the mirror of the artifact block', () {
      for (final entry in kPressFeedbackRules.entries) {
        expect(block[entry.key], entry.value, reason: entry.key);
      }
      expect(((block['down']! as _Row)['curve']), kPressDownCurve);
      expect(((block['up']! as _Row)['curve']), kPressUpCurve);
      expect((block['kinds']! as _Row).keys, PressFeedbackKind.values.map((kind) => kind.name));
    });

    test('any word but «none» is no field', () {
      for (final raw in ['', 'None', 'off', 1, true, null]) {
        final child = UiDocumentBuilder.bare([
          {'id': 'card', 'type': 'Container', 'pressFeedback': raw, 'props': {'direction': 'column', 'action': {'type': 'navigate', 'params': {'screenId': 'x'}}}},
        ]).screens.first.root.children.single;
        expect(child.pressFeedbackOff, isFalse, reason: '$raw');
      }
    });
  });

  group('the finger', () {
    _Row card(String id, {List<_Row> children = const [], Object? feedback, _Row? props}) => {
      'id': id,
      'type': 'Container',
      'pressFeedback': ?feedback,
      'props': {
        'direction': 'column',
        'gap': 'sm',
        'action': {'type': 'none', 'track': {'event': 'tap_$id'}},
        ...?props,
      },
      'style': {'padding': 'md', 'background': {'kind': 'color', 'color': 'surface'}, 'width': 200, 'height': 80},
      'children': children.isEmpty
          ? [
              {'id': '$id-t', 'type': 'Text', 'props': {'content': {'kind': 'literal', 'value': 'Card $id'}}},
            ]
          : children,
    };

    /// Pointer down, then the way down: the first frame of an animation has no time on it, so one empty frame first.
    Future<TestGesture> press(WidgetTester tester, Finder target, {int ms = 100}) async {
      final gesture = await tester.startGesture(tester.getCenter(target));
      await tester.pump();
      await tester.pump(Duration(milliseconds: ms));
      return gesture;
    }

    double scaleOf(WidgetTester tester, Finder within) {
      final transform = tester.widget<Transform>(
        find.descendant(of: find.ancestor(of: within, matching: find.byType(PressFeedback)).first, matching: find.byType(Transform)).first,
      );
      return transform.transform.storage[0];
    }

    double opacityOf(WidgetTester tester, Finder within) => tester
        .widget<FadeTransition>(
          find.descendant(of: find.ancestor(of: within, matching: find.byType(PressFeedback)).first, matching: find.byType(FadeTransition)).first,
        )
        .opacity
        .value;

    testWidgets('a card goes down to 0.97 in 80 ms and comes back in 160 ms with a small overshoot', (tester) async {
      phone(tester);
      await pumpDocument(tester, UiDocumentBuilder.bare([card('a')]));
      final target = find.text('Card a');
      expect(scaleOf(tester, target), 1);

      final gesture = await press(tester, target, ms: 40);
      final half = scaleOf(tester, target);
      expect(half, lessThan(1));
      expect(half, greaterThan(0.97));
      await tester.pump(const Duration(milliseconds: 40));
      expect(scaleOf(tester, target), closeTo(0.97, 1e-6));
      // Painting only: the box the neighbours see does not change.
      expect(tester.renderObject<RenderBox>(find.byType(PressFeedback).first).size, const Size(200, 80));
      await tester.pump(const Duration(seconds: 1));
      expect(scaleOf(tester, target), closeTo(0.97, 1e-6), reason: 'it stays down while the finger is down');

      await gesture.up();
      var biggest = 0.0;
      for (var i = 0; i < 20; i += 1) {
        await tester.pump(const Duration(milliseconds: 10));
        if (scaleOf(tester, target) > biggest) biggest = scaleOf(tester, target);
      }
      expect(biggest, greaterThan(1), reason: 'the curve passes 1 once: the card grows a little over its size');
      expect(biggest, lessThan(1.01));
      expect(scaleOf(tester, target), 1);
    });

    testWidgets('a press shorter than the way down still reaches the pressed pose, then returns', (tester) async {
      phone(tester);
      await pumpDocument(tester, UiDocumentBuilder.bare([card('a')]));
      final target = find.text('Card a');
      final gesture = await press(tester, target, ms: 20);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 20));
      expect(scaleOf(tester, target), lessThan(1), reason: 'the finger is up, the node is still on its way down');
      await tester.pump(const Duration(milliseconds: 40));
      expect(scaleOf(tester, target), closeTo(0.97, 0.01), reason: 'it got to the pressed pose');
      await tester.pumpAndSettle();
      expect(scaleOf(tester, target), 1);
    });

    testWidgets('a cancelled press, a finger that leaves the node and one that drags away all return it', (tester) async {
      phone(tester);
      await pumpDocument(tester, UiDocumentBuilder.bare([card('a')]));
      final target = find.text('Card a');
      for (final move in [Offset.zero, const Offset(0, 300), const Offset(300, 0)]) {
        final gesture = await press(tester, target);
        expect(scaleOf(tester, target), closeTo(0.97, 1e-6));
        if (move == Offset.zero) {
          await gesture.cancel();
        } else {
          await gesture.moveBy(move);
        }
        await tester.pumpAndSettle();
        expect(scaleOf(tester, target), 1, reason: 'after $move');
        if (move != Offset.zero) await gesture.up();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('the innermost control answers: a button in a card sinks to 0.96, the card stays still', (tester) async {
      phone(tester);
      final button = {
        'id': 'go',
        'type': 'Button',
        'props': {'label': {'kind': 'literal', 'value': 'Go'}, 'variant': 'primary', 'action': {'type': 'none'}},
      };
      await pumpDocument(tester, UiDocumentBuilder.bare([card('a', children: [button])]));
      final go = find.text('Go');
      final gesture = await press(tester, go);
      expect(scaleOf(tester, go), closeTo(0.96, 1e-6));
      final cardFeedback = find.byType(PressFeedback).evaluate().map((e) => e.widget as PressFeedback).where((w) => w.kind == PressFeedbackKind.card);
      expect(cardFeedback, hasLength(1));
      final cardTransform = find.descendant(of: find.byType(PressFeedback).first, matching: find.byType(Transform)).first;
      expect(tester.widget<Transform>(cardTransform).transform.storage[0], 1, reason: 'the card around the button does not sink');
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a text field in a card is its own control: the card does not sink', (tester) async {
      phone(tester);
      final field = {
        'id': 'f',
        'type': 'TextField',
        'props': {'label': {'kind': 'literal', 'value': 'Name'}, 'value': {'kind': 'binding', 'path': 'user.name', 'fallback': ''}},
      };
      await pumpDocument(tester, UiDocumentBuilder.bare([card('a', children: [field])]), data: const {'user.name': ''});
      final gesture = await press(tester, find.byType(TextField).first, ms: 120);
      final cardTransform = find.descendant(of: find.byType(PressFeedback).first, matching: find.byType(Transform)).first;
      expect(tester.widget<Transform>(cardTransform).transform.storage[0], 1);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('`pressFeedback: none` turns it off, and the card is still pressable', (tester) async {
      phone(tester);
      final taps = <String>[];
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([card('a', feedback: 'none')]),
        onTrack: (event, nodeId, record) => taps.add(event.event),
      );
      final target = find.text('Card a');
      final gesture = await press(tester, target);
      expect(scaleOf(tester, target), 1);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, ['tap_a']);
    });

    testWidgets('a disabled button does not sink', (tester) async {
      phone(tester);
      final button = {
        'id': 'go',
        'type': 'Button',
        'props': {'label': {'kind': 'literal', 'value': 'Go'}, 'variant': 'primary', 'action': {'type': 'none'}, 'disabledIf': {'path': 'x', 'op': 'isEmpty'}},
      };
      await pumpDocument(tester, UiDocumentBuilder.bare([button]));
      final go = find.text('Go');
      final gesture = await press(tester, go);
      expect(scaleOf(tester, go), 1);
      expect(opacityOf(tester, go), 1);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a ghost button fades to 0.7 and does not scale', (tester) async {
      phone(tester);
      final button = {
        'id': 'later',
        'type': 'Button',
        'props': {'label': {'kind': 'literal', 'value': 'Later'}, 'variant': 'ghost', 'action': {'type': 'none'}},
      };
      await pumpDocument(tester, UiDocumentBuilder.bare([button]));
      final later = find.text('Later');
      final gesture = await press(tester, later);
      expect(scaleOf(tester, later), 1);
      expect(opacityOf(tester, later), closeTo(0.7, 1e-6));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(opacityOf(tester, later), 1);
    });

    testWidgets('«reduce motion»: a card only fades to 0.7, it does not scale', (tester) async {
      phone(tester);
      await pumpDocument(tester, UiDocumentBuilder.bare([card('a')]), disableAnimations: true);
      final target = find.text('Card a');
      final gesture = await press(tester, target);
      expect(scaleOf(tester, target), 1);
      expect(opacityOf(tester, target), closeTo(0.7, 1e-6));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('the keyboard gives no feedback and the press still acts', (tester) async {
      phone(tester);
      final taps = <String>[];
      await pumpDocument(tester, UiDocumentBuilder.bare([card('a')]), onTrack: (event, nodeId, record) => taps.add(event.event));
      final target = find.text('Card a');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 100));
      expect(scaleOf(tester, target), 1);
      expect(taps, ['tap_a']);
    });
  });
}
