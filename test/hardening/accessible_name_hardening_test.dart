/// Limit: the accessible name of a pressable card is made of what the person can SEE.
///
/// A child hidden by `visibleIf` or by `showOn` is not on the screen, so a screen reader must not
/// read it either: otherwise a document could hide text from sighted users (a fee, a condition)
/// and still have it read, or put words into the name of a button the user cannot check.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

Map<String, Object?> _card(List<Map<String, Object?>> inside, {Object? label}) => {
  'id': 'card',
  'type': 'Container',
  'props': {'action': const {'type': 'submit'}, 'label': ?label},
  'children': inside,
};

/// The merged label of the button node of the card.
String _cardName(WidgetTester tester) {
  final node = tester.getSemantics(find.byKey(const ValueKey<String>('sdui-press-card@')));
  return node.label;
}

void main() {
  testWidgets('a child hidden by visibleIf is not part of the name', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpDocument(
      tester,
      docWith([
        _card([
          textNode('Visible title', id: 'a'),
          textNode('HIDDEN-BY-CONDITION', id: 'b', visibleIf: const {'path': 'user.none', 'op': 'isNotEmpty'}),
        ]),
      ]),
    );
    final name = _cardName(tester);
    expect(name, contains('Visible title'));
    expect(name, isNot(contains('HIDDEN-BY-CONDITION')));
    handle.dispose();
  });

  testWidgets('a child hidden by showOn for this width class is not part of the name', (tester) async {
    final handle = tester.ensureSemantics();
    // The test surface is 800 wide: `medium`. The node shows on `compact` only.
    await pumpDocument(
      tester,
      docWith([
        _card([
          textNode('Visible title', id: 'a'),
          textNode('HIDDEN-BY-WIDTH', id: 'b', extra: const {}),
        ]).map((key, value) => MapEntry(key, key == 'children'
            ? [
                (value as List)[0],
                {...(value[1] as Map<String, Object?>), 'showOn': ['compact']},
              ]
            : value)),
      ]),
    );
    final name = _cardName(tester);
    expect(name, contains('Visible title'));
    expect(name, isNot(contains('HIDDEN-BY-WIDTH')));
    handle.dispose();
  });

  testWidgets('a hidden picture description is not part of the name either', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpDocument(
      tester,
      docWith([
        _card([
          textNode('Visible title', id: 'a'),
          {
            'id': 'pic',
            'type': 'Image',
            'props': {
              'source': const {'kind': 'asset', 'asset': 'placeholder'},
              'aspectRatio': '1:1',
              'fit': 'cover',
              'alt': 'HIDDEN-PICTURE-ALT',
            },
            'visibleIf': const {'path': 'user.none', 'op': 'isNotEmpty'},
          },
        ]),
      ]),
    );
    expect(_cardName(tester), isNot(contains('HIDDEN-PICTURE-ALT')));
    handle.dispose();
  });
}
