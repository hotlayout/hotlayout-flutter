/// The write action on a long press (schema 9.30.0, `x-longPressWrite`): the shared table
/// `fixtures/long-press/long-press-write-cases.json` run through real fingers and keys on a finished screen, and the
/// node `name` field (9.29.0), which the reader does not read.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';
import 'support/node_press.dart';

typedef _Row = Map<String, Object?>;

void main() {
  final table = jsonDecode(File('assets/contract/fixtures/long-press/long-press-write-cases.json').readAsStringSync()) as _Row;
  final runCases = (table['runCases']! as List<Object?>).cast<_Row>();

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  test('the table is read in full', () {
    expect(runCases, hasLength(6));
  });

  group('runCases: what the host gets and what the screen shows', () {
    for (final row in runCases) {
      testWidgets(row['name']! as String, (tester) async {
        phone(tester);
        final nodes = (row['nodes']! as List<Object?>).cast<_Row>();
        final log = <List<Object?>>[];
        final handed = <String>[];
        final doc = UiDocumentBuilder.bare(nodes);
        final semantics = tester.ensureSemantics();
        await pumpDocument(
          tester,
          doc,
          onAction: (action, nodeId) => handed.add(action.type),
          onTrack: (event, nodeId, record) => log.add(['track', event.event]),
          onWrite: (path, value) => log.add(['write', path, value]),
        );
        final target = findNodeJson(nodes, row['node']! as String)!;
        // The card has no press of its own in some rows, so it is found by the text inside it.
        final finder = target['type'] == 'Container' ? find.text('Step 1: order a coffee') : finderOfNodeJson(target);
        for (final gesture in (row['gestures']! as List<Object?>).cast<String>()) {
          switch (gesture) {
            case 'hold':
              final finger = await tester.startGesture(tester.getCenter(finder));
              await tester.pump(const Duration(milliseconds: 600));
              await finger.up();
              await tester.pumpAndSettle();
            case 'tap':
              await tester.tap(finder);
              await tester.pumpAndSettle();
            case 'key':
              expect(await focusWithTab(tester, finder), isTrue);
              await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
              await tester.sendKeyEvent(LogicalKeyboardKey.f10);
              await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
              await tester.pumpAndSettle();
            default:
              fail('unknown gesture $gesture');
          }
        }
        expect(log, row['log']);
        expect(handed, row['handed']);
        final shown = (row['shown']! as List<Object?>).cast<String>();
        for (final id in (row['watch']! as List<Object?>).cast<String>()) {
          final content = (((findNodeJson(nodes, id)!['props']! as _Row)['content']!) as _Row)['value']! as String;
          expect(find.text(content), shown.contains(id) ? findsOneWidget : findsNothing, reason: id);
        }
        // The role comes from `action` alone: a write on the hold makes no option and no switch.
        final control = row['control']! as _Row;
        expect(control['role'], 'button');
        final data = tester.getSemantics(find.byType(Semantics).evaluate().isEmpty ? finder : finder).getSemanticsData();
        expect(data.flagsCollection.isChecked, CheckedState.none);
        expect(data.flagsCollection.isToggled, Tristate.none);
        expect(data.flagsCollection.isSelected, Tristate.none);
        semantics.dispose();
      });
    }
  });

  group('node name (9.29.0)', () {
    testWidgets('a named node is drawn and heard as the same node without a name', (tester) async {
      phone(tester);
      _Row card({String? name}) => {
        'id': 'card',
        'name': ?name,
        'type': 'Container',
        'props': {
          'direction': 'column',
          'gap': 'none',
          'action': {'type': 'share'},
        },
        'children': [
          {
            'id': 'title',
            'type': 'Text',
            'props': {'content': {'kind': 'literal', 'value': 'Step 1: order a coffee'}},
          },
        ],
      };

      Future<(Size, List<String>, List<String>)> run(_Row node) async {
        final handed = <String>[];
        final labels = <String>[];
        final semantics = tester.ensureSemantics();
        await pumpDocument(tester, UiDocumentBuilder.bare([node]), onAction: (action, nodeId) => handed.add('${action.type}:$nodeId'));
        expect(tester.takeException(), isNull);
        final size = tester.getSize(find.byKey(const ValueKey('sdui-press-card@')).first);
        void collect(SemanticsNode n) {
          labels.add(n.label);
          n.visitChildren((c) {
            collect(c);
            return true;
          });
        }

        collect(tester.getSemantics(find.byKey(const ValueKey('sdui-press-card@')).first));
        await tester.tap(find.text('Step 1: order a coffee'));
        await tester.pumpAndSettle();
        semantics.dispose();
        return (size, labels, handed);
      }

      final plain = await run(card());
      final named = await run(card(name: 'Mission card'));
      expect(named.$1, plain.$1);
      expect(named.$2, plain.$2);
      expect(named.$2.join(' '), isNot(contains('Mission card')));
      expect(named.$3, plain.$3);
    });
  });
}
