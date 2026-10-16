/// The haptic request of a press (schema 9.25.0, `haptic` next to `type` and `track`; `x-haptic`): the groups
/// `hapticCases` and `hapticSchemaCases` of the shared table `fixtures/actions/action-cases.json`, every row run
/// through the rule and through a real press -- the order (`haptic`, `track`, the action), the cases where nothing is
/// asked, and the fact that the reader never vibrates by itself.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart';
import 'package:hotlayout_flutter/src/render/swipe_confirm_button.dart';

import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

void main() {
  final table = jsonDecode(File('assets/contract/fixtures/actions/action-cases.json').readAsStringSync()) as _Row;
  final schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Row;
  final block = schema['x-haptic']! as _Row;
  final cases = (table['hapticCases']! as List<Object?>).cast<_Row>();
  final schemaCases = (table['hapticSchemaCases']! as List<Object?>).cast<_Row>();

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// A button (it is a control whatever its action, `none` too) that is disabled when [disabled].
  _Row button(Object? action, {bool disabled = false}) => {
    'id': 'go',
    'type': 'Button',
    'props': {
      'label': {'kind': 'literal', 'value': 'Go'},
      'variant': 'primary',
      'action': action,
      if (disabled) 'disabledIf': {'path': 'task.locked', 'op': 'isTrue'},
    },
  };

  _Row card(Object? action) => {
    'id': 'card',
    'type': 'Container',
    'props': {'direction': 'column', 'gap': 'sm', 'action': action},
    'style': {'padding': 'md', 'width': 200, 'height': 80},
    'children': [
      {'id': 't', 'type': 'Text', 'props': {'content': {'kind': 'literal', 'value': 'Tap me'}}},
    ],
  };

  test('the groups are read in full', () {
    expect(cases, hasLength(7));
    expect(schemaCases, hasLength(4));
  });

  group('hapticCases', () {
    for (final row in cases) {
      final name = row['name']! as String;
      final expected = row['expect'] as String?;
      final disabled = row['disabled']! as bool;

      test('rule: $name', () {
        // A disabled control has no press, and a press that does not happen asks for nothing.
        expect(disabled ? null : ButtonAction.parse(row['action']).haptic?.wire, expected);
      });

      testWidgets('screen: $name', (tester) async {
        phone(tester);
        final log = <String>[];
        await pumpDocument(
          tester,
          UiDocumentBuilder.bare([button(row['action'], disabled: disabled)]),
          data: {'task.locked': disabled},
          onHaptic: (word, nodeId, record) => log.add('haptic:${word.wire}:$nodeId'),
          onTrack: (event, nodeId, record) => log.add('track:${event.event}'),
          onAction: (action, nodeId) => log.add('action:${action.type}'),
        );
        await tester.tap(find.text('Go'), warnIfMissed: false);
        await tester.pumpAndSettle();
        final asked = log.where((entry) => entry.startsWith('haptic:')).toList();
        expect(asked, expected == null ? isEmpty : ['haptic:$expected:go']);
        // The order of one press: the haptic request, the analytics event, the action.
        final order = log.map((entry) => entry.split(':').first).toList();
        expect(order, [...order]..sort((a, b) => const ['haptic', 'track', 'action'].indexOf(a) - const ['haptic', 'track', 'action'].indexOf(b)));
        expect(log.where((entry) => entry.startsWith('haptic:')).length, lessThanOrEqualTo(1), reason: 'once per press');
      });
    }
  });

  group('hapticSchemaCases: what the reader takes of what the schema accepts or refuses', () {
    for (final row in schemaCases) {
      test(row['name']! as String, () {
        final word = ButtonAction.parse(row['action']).haptic;
        if (row['valid']! as bool) {
          expect(word, isNotNull);
        } else {
          expect(word, isNull, reason: 'a value the schema refuses is no request');
        }
      });
    }
  });

  group('the rules around the table', () {
    test('the mirror of the artifact block', () {
      expect(HapticWord.values.map((word) => word.wire).toList(), block['words']);
      expect(block['order'], ['haptic', 'track', 'action']);
      expect(block['prop'], 'haptic');
    });

    test('the action handed to the host does not carry the field', () {
      final action = ButtonAction.parse({'type': 'redeem', 'haptic': 'success'});
      expect(action.haptic, HapticWord.success);
      expect(action.handOver((path) => null).haptic, isNull);
    });

    test('a node with `none` and a haptic word only is not a control: nothing to press', () {
      final child = UiDocumentBuilder.bare([card({'type': 'none', 'haptic': 'light'})]).screens.first.root.children.single;
      expect(child.press, isNull);
    });

    testWidgets('a pressable card asks once per press, a drag that stays a drag asks for nothing', (tester) async {
      phone(tester);
      final log = <String>[];
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([card({'type': 'navigate', 'params': {'screenId': 'nowhere'}, 'haptic': 'light', 'track': {'event': 'open'}})]),
        onHaptic: (word, nodeId, record) => log.add('haptic:${word.wire}'),
        onTrack: (event, nodeId, record) => log.add('track:${event.event}'),
        onAction: (action, nodeId) => log.add('action:${action.type}'),
      );
      final gesture = await tester.startGesture(tester.getCenter(find.text('Tap me')));
      await gesture.moveBy(const Offset(0, 120));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(log, isEmpty);
      await tester.tap(find.text('Tap me'));
      await tester.pumpAndSettle();
      expect(log, ['haptic:light', 'track:open', 'action:navigate'], reason: 'the order of one press, also when the host takes the action');
    });

    testWidgets('«swipe to confirm»: nothing while the thumb is dragged, one request when the drag completes', (tester) async {
      phone(tester);
      final log = <String>[];
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          {
            'id': 'pay',
            'type': 'Button',
            'props': {
              'label': {'kind': 'literal', 'value': 'Pay'},
              'variant': 'primary',
              'confirm': 'swipe',
              'fullWidth': true,
              'action': {'type': 'redeem', 'haptic': 'success', 'track': {'event': 'paid'}},
            },
          },
        ]),
        onHaptic: (word, nodeId, record) => log.add('haptic:${word.wire}'),
        onTrack: (event, nodeId, record) => log.add('track:${event.event}'),
        onAction: (action, nodeId) => log.add('action:${action.type}'),
      );
      final track = tester.getRect(find.byType(SwipeConfirmTrack));
      final thumb = tester.getRect(
        find.descendant(
          of: find.byType(SwipeConfirmTrack),
          matching: find.byWidgetPredicate((w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).shape == BoxShape.circle),
        ),
      );
      final gesture = await tester.startGesture(Offset(thumb.center.dx, track.center.dy));
      for (var i = 0; i < 4; i += 1) {
        await gesture.moveBy(Offset((track.width - thumb.width) / 10, 0));
        await tester.pump();
      }
      expect(log, isEmpty, reason: 'the drag has not completed');
      for (var i = 0; i < 6; i += 1) {
        await gesture.moveBy(Offset((track.width - thumb.width) / 10 * 1.05, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump(const Duration(seconds: 9));
      expect(log, ['haptic:success', 'track:paid', 'action:redeem']);
    });

    testWidgets('a section switch with no word asks for nothing, with a word asks once', (tester) async {
      phone(tester);
      final log = <String>[];
      final doc = UiDocument.fromJson({
        'schemaVersion': UiDocument.supportedSchemaVersion,
        'documentId': 'sections',
        'name': 'Sections',
        'initialScreenId': 'a',
        'screens': [
          screenEntry('a', [
            {
              'id': 'bar',
              'type': 'NavBar',
              'props': <String, Object?>{},
              'children': [
                {'id': 'ia', 'type': 'NavItem', 'props': {'icon': 'house', 'label': {'kind': 'literal', 'value': 'A'}, 'action': {'type': 'navigate.section', 'params': {'screenId': 'a'}}}},
                {'id': 'ib', 'type': 'NavItem', 'props': {'icon': 'star', 'label': {'kind': 'literal', 'value': 'B'}, 'action': {'type': 'navigate.section', 'params': {'screenId': 'b'}, 'haptic': 'selection'}}},
              ],
            },
          ]),
          screenEntry('b', [
            {
              'id': 'bar',
              'type': 'NavBar',
              'props': <String, Object?>{},
              'children': [
                {'id': 'ia', 'type': 'NavItem', 'props': {'icon': 'house', 'label': {'kind': 'literal', 'value': 'A'}, 'action': {'type': 'navigate.section', 'params': {'screenId': 'a'}}}},
                {'id': 'ib', 'type': 'NavItem', 'props': {'icon': 'star', 'label': {'kind': 'literal', 'value': 'B'}, 'action': {'type': 'navigate.section', 'params': {'screenId': 'b'}, 'haptic': 'selection'}}},
              ],
            },
          ]),
        ],
      });
      await pumpDocument(tester, doc, onHaptic: (word, nodeId, record) => log.add('${word.wire}:$nodeId'), transitions: HotlayoutTransitions.none);
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      expect(log, isEmpty, reason: 'no word, no request');
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      expect(log, ['selection:ib']);
    });
  });
}
