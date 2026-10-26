/// The long press of a card and of a list row (schema 9.26.0, `longPress`, `longPressLabel`, `x-longPress`): the shared
/// table `fixtures/long-press/long-press-cases.json` run row by row through the rule, through the parsed document and
/// through a real finger, and then what the table cannot say: the order of the requests, the pose that stays down, the
/// keys, and the name a screen reader hears.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/long_press.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/press_feedback.dart';
import 'package:hotlayout_flutter/src/render/long_press_row.dart';
import 'package:hotlayout_flutter/src/render/press_feedback.dart';

import 'support/fixtures.dart';
import 'support/node_press.dart';

typedef _Row = Map<String, Object?>;

void main() {
  final table = jsonDecode(File('assets/contract/fixtures/long-press/long-press-cases.json').readAsStringSync()) as _Row;
  final schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Row;
  final block = schema['x-longPress']! as _Row;
  List<_Row> rowsOf(String name) => (table[name]! as List<Object?>).cast<_Row>();
  final gestureCases = rowsOf('gestureCases');
  final keyCases = rowsOf('keyCases');
  final nodeCases = rowsOf('nodeCases');
  final receiverCases = rowsOf('receiverCases');
  final documentCases = rowsOf('documentCases');
  final ruleCases = rowsOf('ruleCases');

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  test('the table is read in full', () {
    expect(gestureCases, hasLength(11));
    expect(keyCases, hasLength(6));
    expect(nodeCases, hasLength(9));
    expect(receiverCases, hasLength(5));
    expect(documentCases, hasLength(7));
    expect(ruleCases, hasLength(5));
  });

  group('gestureCases: what a hold comes to', () {
    for (final row in gestureCases) {
      test(row['name']! as String, () {
        final outcome = longPressOutcome(
          heldMs: (row['heldMs']! as num).toDouble(),
          moved: (row['moved']! as num).toDouble(),
          cancelled: row['cancelled']! as bool,
          hasLongPress: row['hasLongPress']! as bool,
          hasAction: row['hasAction']! as bool,
        );
        expect(outcome.name, row['expect']);
      });

      testWidgets('finger: ${row['name']}', (tester) async {
        phone(tester);
        final calls = <String>[];
        await pumpDocument(
          tester,
          UiDocumentBuilder.bare([
            _card('card', action: row['hasAction']! as bool, longPress: row['hasLongPress']! as bool),
          ]),
          onAction: (action, nodeId) => calls.add(action.params['screenId'] ?? action.type),
        );
        final gesture = await tester.startGesture(tester.getCenter(find.text('Coffee week')));
        final moved = (row['moved']! as num).toDouble();
        if (moved > 0) {
          // The move comes BEFORE the threshold (the table counts the distance before it fires).
          await tester.pump(const Duration(milliseconds: 20));
          await gesture.moveBy(Offset(0, moved));
        }
        final held = (row['heldMs']! as num).toInt();
        await tester.pump(Duration(milliseconds: held - (moved > 0 ? 20 : 0)));
        if (row['cancelled']! as bool) {
          await gesture.cancel();
        } else {
          await gesture.up();
        }
        await tester.pumpAndSettle();
        expect(calls, switch (row['expect']) {
          'longPress' => ['peek'],
          'press' => ['mission'],
          _ => <String>[],
        });
      });
    }
  });

  group('keyCases: the keys that perform it at once', () {
    final keys = {
      'ContextMenu': LogicalKeyboardKey.contextMenu,
      'F10': LogicalKeyboardKey.f10,
      'Enter': LogicalKeyboardKey.enter,
      ' ': LogicalKeyboardKey.space,
    };
    for (final row in keyCases) {
      test('rule: ${row['name']}', () {
        expect(isLongPressKey(key: row['key']! as String, shift: row['shiftKey']! as bool), row['expect']);
      });

      testWidgets('focused card: ${row['name']}', (tester) async {
        phone(tester);
        final calls = <String>[];
        await pumpDocument(
          tester,
          UiDocumentBuilder.bare([_card('card', action: true, longPress: true)]),
          onAction: (action, nodeId) => calls.add(action.params['screenId'] ?? action.type),
        );
        expect(await focusWithTab(tester, find.byKey(const ValueKey('sdui-press-card@')).first), isTrue);
        final key = keys[row['key']]!;
        final shift = row['shiftKey']! as bool;
        if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(key);
        if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        // Enter and Space are the press of `action`; the others perform the long press, with no threshold.
        final press = row['key'] == 'Enter' || row['key'] == ' ';
        expect(calls, row['expect']! as bool ? ['peek'] : (press ? ['mission'] : <String>[]));
      });
    }
  });

  group('nodeCases: who carries the field, and whether it makes a control', () {
    for (final row in nodeCases) {
      final expected = row['expect']! as _Row;
      final node = row['node'] as _Row?;
      if (node == null) {
        testWidgets('never on a ${row['type']}: ${row['name']}', (tester) async {
          phone(tester);
          expect(expected['accepts'], isFalse);
          final calls = <String>[];
          await pumpDocument(
            tester,
            UiDocumentBuilder.bare([_withLongPress(_leaf(row['type']! as String))]),
            onAction: (action, nodeId) => calls.add(action.type),
          );
          expect(tester.takeException(), isNull);
          final semantics = tester.ensureSemantics();
          final gesture = await tester.startGesture(tester.getCenter(row['type'] == 'NavItem' ? find.byKey(const ValueKey('sdui-nav-item-leaf')) : finderOfNodeJson(_leafOf(row['type']! as String))));
          await tester.pump(const Duration(milliseconds: 600));
          expect(calls, isEmpty, reason: 'the field is not read there: nothing fires under the finger');
          await gesture.up();
          await tester.pumpAndSettle();
          semantics.dispose();
        });
        continue;
      }
      test('parsed: ${row['name']}', () {
        final child = UiDocumentBuilder.bare([node]).screens.first.root.children.single;
        final long = child is ListTileNode ? child.longPress : child.press?.longPress;
        expect(long != null, expected['longPress'], reason: 'the long press does something');
        final control = child is ListTileNode ? (child.longPress != null || child.action != null) : child.press != null;
        expect(control, expected['acts'], reason: 'the node is a control that performs a press');
      });
    }
  });

  group('receiverCases: who gets the hold', () {
    for (final row in receiverCases) {
      testWidgets(row['name']! as String, (tester) async {
        phone(tester);
        final chain = (row['chain']! as List<Object?>).cast<_Row>();
        // The chain from the root to the innermost: each node is the only child of the one before it.
        // A card with nothing in it has no size to hold: it gets one.
        _Row nest(int at) => {
          ...chain[at],
          if (at + 1 == chain.length && chain[at]['type'] == 'Container') 'style': {'width': 200, 'height': 60},
          if (at + 1 < chain.length) 'children': [nest(at + 1)],
        };
        final calls = <({String type, String nodeId})>[];
        await pumpDocument(
          tester,
          UiDocumentBuilder.bare([nest(0)]),
          onAction: (action, nodeId) => calls.add((type: action.type, nodeId: nodeId)),
        );
        final semantics = tester.ensureSemantics();
        final gesture = await tester.startGesture(tester.getCenter(finderOfNodeJson(chain.last)));
        // Held past the threshold, the finger still down: only a long press can have happened.
        await tester.pump(const Duration(milliseconds: 600));
        final expected = row['expect'] as String?;
        expect(calls.map((call) => call.nodeId), expected == null ? isEmpty : [expected]);
        await gesture.up();
        await tester.pumpAndSettle();
        semantics.dispose();
      });
    }
  });

  group('documentCases: the documents the table names are drawn', () {
    for (final row in documentCases) {
      testWidgets(row['name']! as String, (tester) async {
        phone(tester);
        await pumpDocument(tester, UiDocumentBuilder.bare([row['node']! as _Row]), onAction: (_, _) {});
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('ruleCases and the mirror of the artifact', () {
    for (final row in ruleCases) {
      test('rule: ${row['name']}', () {
        final expected = row['expect'];
        switch (row['rule']) {
          case 'thresholdMs':
            expect(kLongPressMs, expected);
            expect(block['thresholdMs'], expected);
          case 'touchSlop':
            expect(kLongPressSlop, expected);
            expect(block['touchSlop'], expected);
          case 'props':
            expect({'action': kLongPressKey, 'label': kLongPressLabelKey}, expected);
          case 'order':
            expect(block['order'], expected);
          case 'accessibility.keys':
            expect((block['accessibility']! as _Row)['keys'], expected);
          default:
            fail('unknown rule ${row['rule']}');
        }
      });
    }

    test('the scalar rows of the block are the ones in code', () {
      for (final entry in kLongPressRules.entries) {
        expect(block[entry.key], entry.value, reason: entry.key);
      }
    });
  });

  group('the finger', () {
    testWidgets('it fires at the threshold while the finger is down, and the lifted finger presses nothing', (tester) async {
      phone(tester);
      final calls = <String>[];
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([_card('card', action: true, longPress: true)]),
        onAction: (action, nodeId) => calls.add(action.params['screenId'] ?? action.type),
      );
      final gesture = await tester.startGesture(tester.getCenter(find.text('Coffee week')));
      await tester.pump(const Duration(milliseconds: 449));
      expect(calls, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, ['peek'], reason: 'at 450 ms, not at the release');
      await tester.pump(const Duration(seconds: 2));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls, ['peek'], reason: '`action` is not run after a long press');
    });

    testWidgets('a hold released before the threshold is the press, and a second tap after a long press is a press again',
        (tester) async {
      phone(tester);
      final calls = <String>[];
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([_card('card', action: true, longPress: true)]),
        onAction: (action, nodeId) => calls.add(action.params['screenId'] ?? action.type),
      );
      final target = tester.getCenter(find.text('Coffee week'));
      var gesture = await tester.startGesture(target);
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls, ['mission']);

      gesture = await tester.startGesture(target);
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls, ['mission', 'peek']);

      await tester.tap(find.text('Coffee week'));
      await tester.pumpAndSettle();
      expect(calls, ['mission', 'peek', 'mission'], reason: 'the swallowed tap does not leak into the next one');
    });

    testWidgets('the request goes in the order haptic, track, action, all at the threshold', (tester) async {
      phone(tester);
      final log = <String>[];
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          _card(
            'card',
            action: true,
            longPress: true,
            longPressExtra: {'haptic': 'medium', 'track': {'event': 'peeked'}},
          ),
        ]),
        onHaptic: (word, nodeId, record) => log.add('haptic:${word.wire}'),
        onTrack: (event, nodeId, record) => log.add('track:${event.event}'),
        onAction: (action, nodeId) => log.add('action:${action.type}'),
      );
      final gesture = await tester.startGesture(tester.getCenter(find.text('Coffee week')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(log, isEmpty, reason: 'nothing is requested before the threshold');
      await tester.pump(const Duration(milliseconds: 400));
      expect(log, ['haptic:medium', 'track:peeked', 'action:navigate']);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(log, hasLength(3));
    });

    testWidgets('a long press that only carries an analytics event is a long press; «none» without one is no field',
        (tester) async {
      phone(tester);
      final tracks = <String>[];
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          _card('a', action: false, longPress: true, longPressOverride: {'type': 'none', 'track': {'event': 'held'}}),
          _card('b', action: false, longPress: true, longPressOverride: {'type': 'none'}),
        ]),
        onTrack: (event, nodeId, record) => tracks.add('${event.event}@$nodeId'),
        onAction: (_, _) {},
      );
      expect(find.byKey(const ValueKey('sdui-press-a@')), findsOneWidget);
      expect(find.byKey(const ValueKey('sdui-press-b@')), findsNothing, reason: 'no long press that does something, no action: not a control');
      final gesture = await tester.startGesture(tester.getCenter(find.text('Coffee week').first));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tracks, ['held@a']);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('the pressed pose stays while the finger is down, also after the long press fired', (tester) async {
      phone(tester);
      await pumpDocument(tester, UiDocumentBuilder.bare([_card('card', action: true, longPress: true)]), onAction: (_, _) {});
      final target = find.text('Coffee week');
      double scale() => tester
          .widget<Transform>(find.descendant(of: find.ancestor(of: target, matching: find.byType(PressFeedback)).first, matching: find.byType(Transform)).first)
          .transform
          .storage[0];
      final gesture = await tester.startGesture(tester.getCenter(target));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(scale(), closeTo(0.97, 1e-6));
      await tester.pump(const Duration(milliseconds: 600));
      expect(scale(), closeTo(0.97, 1e-6), reason: 'after the long press fired');
      await gesture.up();
      await tester.pumpAndSettle();
      expect(scale(), 1);
    });

    testWidgets('a button in a card keeps its press, and the card gets no long press from it', (tester) async {
      phone(tester);
      final calls = <String>[];
      final button = {
        'id': 'more',
        'type': 'Button',
        'props': {'label': {'kind': 'literal', 'value': 'More'}, 'variant': 'primary', 'action': {'type': 'open', 'params': {}}},
      };
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([_card('card', action: false, longPress: true, children: [button])]),
        onAction: (action, nodeId) => calls.add('${action.type}@$nodeId'),
      );
      final gesture = await tester.startGesture(tester.getCenter(find.text('More')));
      await tester.pump(const Duration(milliseconds: 800));
      expect(calls, isEmpty, reason: 'a hold on a button is not the card\'s long press');
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls, ['open@more'], reason: 'the button presses as it always did');

      // The card around still has its long press where no control is.
      final text = await tester.startGesture(tester.getTopLeft(find.byKey(const ValueKey('sdui-press-card@'))) + const Offset(6, 6));
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls.last, 'navigate@card');
      await text.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a hold on a disabled button inside the card is the button\'s, the card does not get it', (tester) async {
      phone(tester);
      final calls = <String>[];
      final button = {
        'id': 'locked',
        'type': 'Button',
        'props': {
          'label': {'kind': 'literal', 'value': 'Locked'},
          'variant': 'primary',
          'action': {'type': 'open'},
          'disabledIf': {'path': 'task.locked', 'op': 'isTrue'},
        },
      };
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([_card('card', action: true, longPress: true, children: [button])]),
        data: const {'task.locked': true},
        onAction: (action, nodeId) => calls.add('${action.type}@$nodeId'),
      );
      final gesture = await tester.startGesture(tester.getCenter(find.text('Locked')));
      await tester.pump(const Duration(milliseconds: 800));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
    });
  });

  group('a list row', () {
    _Row row({bool action = false, bool option = false}) => {
      'id': 'row',
      'type': 'ListTile',
      'props': {
        'leading': {'kind': 'none'},
        'trailing': option ? {'kind': 'radio', 'optionValue': 'a'} : {'kind': 'none'},
        'title': {'kind': 'literal', 'value': 'Coffee row'},
        if (action) 'action': {'type': 'navigate', 'params': {'screenId': 'mission'}},
        'longPress': {'type': 'share'},
        'longPressLabel': {'kind': 'literal', 'value': 'Share'},
      },
    };

    testWidgets('a row with only a long press is a control: the hold fires, the tap does nothing', (tester) async {
      phone(tester);
      final calls = <String>[];
      await pumpDocument(tester, UiDocumentBuilder.bare([row()]), onAction: (action, nodeId) => calls.add('${action.type}@$nodeId'));
      await tester.tap(find.text('Coffee row'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      final gesture = await tester.startGesture(tester.getCenter(find.text('Coffee row')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls, ['share@row']);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls, hasLength(1));
    });

    testWidgets('a row with an action and a long press: the tap presses, the hold does not', (tester) async {
      phone(tester);
      final calls = <String>[];
      await pumpDocument(tester, UiDocumentBuilder.bare([row(action: true)]), onAction: (action, nodeId) => calls.add(action.type));
      await tester.tap(find.text('Coffee row'));
      await tester.pumpAndSettle();
      expect(calls, ['navigate']);
      final gesture = await tester.startGesture(tester.getCenter(find.text('Coffee row')));
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls, ['navigate', 'share']);
    });

    testWidgets('the context menu key performs it on the focused row', (tester) async {
      phone(tester);
      final calls = <String>[];
      await pumpDocument(tester, UiDocumentBuilder.bare([row()]), onAction: (action, nodeId) => calls.add(action.type));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pump();
      expect(calls, ['share']);
    });

    testWidgets('a row without a long press is not a focus stop, as before', (tester) async {
      phone(tester);
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          {
            'id': 'plain',
            'type': 'ListTile',
            'props': {'leading': {'kind': 'none'}, 'trailing': {'kind': 'none'}, 'title': {'kind': 'literal', 'value': 'Plain'}, 'action': {'type': 'open'}},
          },
        ]),
        onAction: (_, _) {},
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(find.byType(LongPressRow), findsNothing);
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<PressFeedback>(), isNull);
    });

    testWidgets('an option of a choice keeps the touch: the long press is not run', (tester) async {
      phone(tester);
      final calls = <String>[];
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          {
            'id': 'group',
            'type': 'ChoiceGroup',
            'props': {'value': {'kind': 'literal', 'value': 'a'}},
            'children': [row(option: true)],
          },
        ]),
        onAction: (action, nodeId) => calls.add(action.type),
      );
      final gesture = await tester.startGesture(tester.getCenter(find.text('Coffee row')));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
    });
  });

  group('what a screen reader hears', () {
    testWidgets('a custom action named by longPressLabel, which performs the long press', (tester) async {
      phone(tester);
      final handle = tester.ensureSemantics();
      final calls = <String>[];
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([_card('card', action: true, longPress: true)]),
        onAction: (action, nodeId) => calls.add(action.params['screenId'] ?? action.type),
      );
      final node = tester.getSemantics(find.byKey(const ValueKey('sdui-press-card@')).first);
      final ids = node.getSemanticsData().customSemanticsActionIds!;
      expect(ids.map((id) => CustomSemanticsAction.getAction(id)!.label), ['Mission options']);
      tester.semantics.performAction(find.semantics.byPredicate((candidate) => candidate.id == node.id), SemanticsAction.customAction, args: ids.single);
      await tester.pump();
      expect(calls, ['peek']);
      handle.dispose();
    });

    testWidgets('a name nobody can hear gives the platform\'s own long press action instead', (tester) async {
      phone(tester);
      final handle = tester.ensureSemantics();
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([_card('card', action: true, longPress: true, label: '​')]),
        onAction: (_, _) {},
      );
      final data = tester.getSemantics(find.byKey(const ValueKey('sdui-press-card@')).first).getSemanticsData();
      expect(data.hasAction(SemanticsAction.longPress), isTrue);
      expect(data.customSemanticsActionIds, anyOf(isNull, isEmpty));
      handle.dispose();
    });

    testWidgets('a card with only a long press is a named button with no tap action', (tester) async {
      phone(tester);
      final handle = tester.ensureSemantics();
      await pumpDocument(tester, UiDocumentBuilder.bare([_card('card', action: false, longPress: true)]), onAction: (_, _) {});
      final data = tester.getSemantics(find.byKey(const ValueKey('sdui-press-card@')).first).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      handle.dispose();
    });
  });

  test('the press feedback kind of a card is unchanged by a long press', () {
    final card = UiDocumentBuilder.bare([_card('card', action: true, longPress: true)]).screens.first.root.children.single;
    expect(pressFeedbackKindOf(card), PressFeedbackKind.card);
  });
}

/// A card with a title; with the tap [action] (`navigate` to `mission`) and the [longPress] (`navigate` to `peek`).
_Row _card(
  String id, {
  required bool action,
  bool longPress = false,
  Map<String, Object?>? longPressExtra,
  Map<String, Object?>? longPressOverride,
  List<_Row>? children,
  String label = 'Mission options',
}) => {
  'id': id,
  'type': 'Container',
  'props': {
    'direction': 'column',
    'gap': 'sm',
    if (action) 'action': {'type': 'navigate', 'params': {'screenId': 'mission'}},
    if (longPress)
      'longPress': longPressOverride ?? {'type': 'navigate', 'params': {'screenId': 'peek'}, ...?longPressExtra},
    if (longPress) 'longPressLabel': {'kind': 'literal', 'value': label},
  },
  'style': {'padding': 'md', 'background': {'kind': 'color', 'color': 'surface'}, 'width': 300, 'height': 80},
  'children': children ?? [{'id': '$id-t', 'type': 'Text', 'props': {'content': {'kind': 'literal', 'value': 'Coffee week'}}}],
};

/// A leaf of a type that takes no long press, with enough props to be drawn.
_Row _leaf(String type) => switch (type) {
  'Button' => {'id': 'leaf', 'type': 'Button', 'props': {'label': {'kind': 'literal', 'value': 'Go'}, 'variant': 'primary', 'action': {'type': 'open'}}},
  'IconButton' => {'id': 'leaf', 'type': 'IconButton', 'props': {'icon': 'star', 'label': {'kind': 'literal', 'value': 'Star'}, 'action': {'type': 'open'}}},
  'NavItem' => {
    'id': 'bar',
    'type': 'NavBar',
    'props': <String, Object?>{},
    'children': [
      {'id': 'leaf', 'type': 'NavItem', 'props': {'label': {'kind': 'literal', 'value': 'Home'}, 'icon': 'house', 'action': {'type': 'open'}}},
    ],
  },
  _ => {'id': 'leaf', 'type': 'Text', 'props': {'content': {'kind': 'literal', 'value': 'Words'}}},
};

/// The node of [_leaf] that has the interesting widget (the item, for a bar).
_Row _leafOf(String type) {
  final leaf = _leaf(type);
  return type == 'NavItem' ? (leaf['children']! as List<Object?>).single! as _Row : leaf;
}

/// [node] with the long press fields on it (or on its first child, for a bar).
_Row _withLongPress(_Row node) {
  final extra = {
    'longPress': {'type': 'share'},
    'longPressLabel': {'kind': 'literal', 'value': 'Share'},
  };
  if (node['type'] == 'NavBar') {
    final item = (node['children']! as List<Object?>).single! as _Row;
    return {...node, 'children': [{...item, 'props': {...(item['props']! as _Row), ...extra}}]};
  }
  return {...node, 'props': {...(node['props']! as _Row), ...extra}};
}
