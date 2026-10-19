/// A TEXT THAT PAINTS NOTHING IS NOT IN THE NAME OF A CARD (`x-silentText`): the shared table
/// `assets/contract/fixtures/accessible-name/silent-text-cases.json`.
///
///  1. `paintCases` -- the rule as a function of the resolved paint;
///  2. `silentCases` -- a real card on a real screen: the merged name of the card holds the heard texts and none of
///     the silent ones.
///
/// Then what the table does not say: the card and a control inside it are not judged, and 0.01 is seen.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/silent_text.dart';

import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

final _Row _table = jsonDecode(File('assets/contract/fixtures/accessible-name/silent-text-cases.json').readAsStringSync()) as _Row;

List<_Row> _rows(String key) => (_table[key]! as List<Object?>).cast<_Row>();

Map<String, Object?> _card(List<Object?> children, {Map<String, Object?>? style, Map<String, Object?> props = const {}}) => {
  'id': 'card',
  'type': 'Container',
  'props': {
    'direction': 'column',
    'action': const {'type': 'navigate', 'screenId': 'details'},
    ...props,
  },
  'style': ?style,
  'children': children,
};

Future<String> _pumpCard(WidgetTester tester, Map<String, Object?> card, {Map<String, Object?> data = const {}}) async {
  await pumpDocument(
    tester,
    docWithScreens([
      screenEntry('home', [card]),
      screenEntry('details', [textNode('Details')]),
    ], initialScreenId: 'home'),
    data: data,
  );
  return tester.getSemantics(find.byKey(const ValueKey<String>('sdui-press-card@'))).label;
}

void main() {
  test('the table has the promised rows', () {
    expect(_rows('silentCases'), hasLength(12));
    expect(_rows('paintCases'), hasLength(6));
  });

  group('paintCases -- the rule over the resolved paint', () {
    for (final row in _rows('paintCases')) {
      test(row['name']! as String, () {
        final opacities = [for (final value in row['opacities']! as List<Object?>) (value as num?)?.toDouble()];
        expect(
          textPaintsNothing(opacities: opacities, colorOpacity: (row['colorOpacity'] as num?)?.toDouble()),
          row['paintsNothing'],
        );
      });
    }
  });

  group('silentCases -- the name of a real card', () {
    for (final row in _rows('silentCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final handle = tester.ensureSemantics();
        final data = (row['data'] as Map<String, Object?>?) ?? const {};
        final name = await _pumpCard(tester, _card(row['children']! as List<Object?>), data: data);
        for (final heard in (row['heard']! as List<Object?>).cast<String>()) {
          expect(name, contains(heard), reason: 'heard');
        }
        for (final silent in (row['silent']! as List<Object?>).cast<String>()) {
          expect(name, isNot(contains(silent)), reason: 'silent');
        }
        handle.dispose();
      });
    }
  });

  group('what the table does not say', () {
    testWidgets('the card itself is not judged: at opacity 0 it keeps its name', (tester) async {
      final handle = tester.ensureSemantics();
      final name = await _pumpCard(
        tester,
        _card([textNode('Show offer', id: 'a')], style: const {'opacity': 0}, props: const {'label': {'kind': 'literal', 'value': 'Offer card'}}),
      );
      expect(name, contains('Offer card'));
      expect(name, contains('Show offer'));
      handle.dispose();
    });

    testWidgets('a control that paints nothing keeps its own name and its place', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpDocument(
        tester,
        docWith([
          {...buttonNode('Pay now', action: const {'type': 'submit'}, id: 'pay'), 'style': const {'opacity': 0}},
        ]),
      );
      expect(find.bySemanticsLabel('Pay now'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a card of opacity 0 inside the card is a control too: it keeps its name', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpDocument(
        tester,
        docWith([
          _card([
            {
              ..._card([textNode('Inner offer', id: 'inner')]),
              'id': 'inner-card',
              'style': const {'opacity': 0},
            },
          ]),
        ]),
      );
      expect(find.bySemanticsLabel(RegExp('Inner offer')), findsWidgets);
      handle.dispose();
    });

    testWidgets('a text with opacity 0.01 and a half-transparent colour is heard', (tester) async {
      final handle = tester.ensureSemantics();
      final name = await _pumpCard(tester, _card([
        textNode('Faint', id: 'a', style: const {'opacity': 0.01}),
        textNode('Half', id: 'b', style: const {'color': {'token': 'primary', 'opacity': 0.5}}),
      ]));
      expect(name, contains('Faint'));
      expect(name, contains('Half'));
      handle.dispose();
    });

    testWidgets('a transparent text outside a card is not read either', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpDocument(tester, docWith([textNode('Invisible', style: const {'opacity': 0}), textNode('Seen', id: 'b')]));
      expect(find.bySemanticsLabel('Invisible'), findsNothing);
      expect(find.bySemanticsLabel('Seen'), findsOneWidget);
      handle.dispose();
    });
  });
}
