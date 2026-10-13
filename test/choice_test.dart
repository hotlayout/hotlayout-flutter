import 'package:flutter_test/flutter_test.dart';
import 'support/demo_data.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/bindable.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';

import 'support/fixtures.dart';
import 'support/icons.dart';

/// `ChoiceGroup` is the first contract node with state, and that is why this
/// checks not "how it is drawn" but "who owns the choice".
///
/// We ask about state in contract terms -- via [ChoiceOptionMark], not via the
/// icon: which glyph the renderer draws for the mark today is irrelevant to the contract,
/// while "which option is selected" is relevant.
Set<String> selectedOptions(WidgetTester tester) => tester
    .widgetList<ChoiceOptionMark>(find.byType(ChoiceOptionMark))
    .where((mark) => mark.selected)
    .map((mark) => mark.optionValue)
    .toSet();

Iterable<ChoiceOptionMark> optionMarks(WidgetTester tester) =>
    tester.widgetList<ChoiceOptionMark>(find.byType(ChoiceOptionMark));

Map<String, Object?> rewardGroup({
  Object value = const {'kind': 'literal', 'value': 'headphones'},
  String id = 'reward-choice',
}) => choiceGroupNode(
  [
    optionNode('Навушники', optionValue: 'headphones'),
    {
      'id': 'sep',
      'type': 'Divider',
      'props': {'color': 'muted', 'spacing': 'sm', 'orientation': 'horizontal'},
    },
    optionNode('Колонка', optionValue: 'speaker'),
    optionNode('Сертифікат', optionValue: 'certificate'),
  ],
  id: id,
  value: value,
);

void main() {
  group('choice in ChoiceGroup', () {
    testWidgets('a tap on the second row moves the mark -- and the document does not change', (
      tester,
    ) async {
      final doc = docWith([rewardGroup()]);
      await pumpDocument(tester, doc);

      expect(selectedOptions(tester), {'headphones'});

      await tester.tap(find.text('Колонка'));
      await tester.pump();

      // The mark moved, and the first row became unselected -- this is what must
      // work in the demonstration.
      expect(selectedOptions(tester), {'speaker'});

      // And the document is the same: `value` is the initial value, not a
      // mirror of the state. The state lives in the renderer, and the contract has
      // no write back.
      final group = flattenDocument(doc).whereType<ChoiceGroupNode>().single;
      expect(group.value.resolve(ScreenData.empty), 'headphones');
    });

    testWidgets('exactly one option stays selected, however much you tap', (tester) async {
      await pumpDocument(tester, docWith([rewardGroup()]));

      for (final title in ['Сертифікат', 'Навушники', 'Колонка', 'Сертифікат']) {
        await tester.tap(find.text(title));
        await tester.pump();
        expect(
          optionMarks(tester).where((mark) => mark.selected),
          hasLength(1),
          reason: 'after a tap on "$title" exactly one option should be selected',
        );
      }
      expect(selectedOptions(tester), {'certificate'});
    });

    testWidgets('the initial choice comes from the data', (tester) async {
      // The main reason `value` is bindable: the user may have chosen a record
      // last time, and the screen must open with their choice.
      await pumpDocument(
        tester,
        docWith([
          rewardGroup(value: {'kind': 'binding', 'path': 'item.selectedId', 'fallback': ''}),
        ]),
        data: const {'item.selectedId': 'certificate'},
      );

      expect(selectedOptions(tester), {'certificate'});
    });

    testWidgets('an empty value is a legal "nothing selected" state', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          rewardGroup(value: {'kind': 'binding', 'path': 'item.selectedId', 'fallback': ''}),
        ]),
      );

      expect(selectedOptions(tester), isEmpty);
      expect(optionMarks(tester), hasLength(3));

      // And this is not a "broken group": a tap works as usual.
      await tester.tap(find.text('Навушники'));
      await tester.pump();
      expect(selectedOptions(tester), {'headphones'});
    });

    testWidgets('value points to an option that does not exist -- we mark none', (tester) async {
      // The builder catches this (`unknown_option_value`), but the document may
      // arrive from the network. An invented choice (for example, "take the first") would be
      // worse than none: it is indistinguishable from a real one.
      await pumpDocument(
        tester,
        docWith([
          rewardGroup(value: {'kind': 'literal', 'value': 'ніякого-такого'}),
        ]),
      );

      expect(selectedOptions(tester), isEmpty);

      await tester.tap(find.text('Сертифікат'));
      await tester.pump();
      expect(selectedOptions(tester), {'certificate'});
    });

    testWidgets('two groups on a screen are independent', (tester) async {
      // Checks that the choice owner is the group node, not the screen: if the state
      // lived higher and was addressed by `id`, the neighbouring group would move along with this one.
      await pumpDocument(
        tester,
        docWith([
          choiceGroupNode(
            [
              optionNode('Синій', optionValue: 'blue', id: 'a-blue'),
              optionNode('Червоний', optionValue: 'red', id: 'a-red'),
            ],
            id: 'colors',
            value: const {'kind': 'literal', 'value': 'blue'},
          ),
          choiceGroupNode(
            [
              optionNode('Малий', optionValue: 'small', id: 'b-small'),
              optionNode('Великий', optionValue: 'large', id: 'b-large'),
            ],
            id: 'sizes',
            value: const {'kind': 'literal', 'value': 'small'},
          ),
        ]),
      );

      expect(selectedOptions(tester), {'blue', 'small'});

      await tester.tap(find.text('Великий'));
      await tester.pump();

      expect(selectedOptions(tester), {'blue', 'large'});
    });

    testWidgets('a row deep in a group still belongs to the group', (tester) async {
      // The schema allows any node in a group's `children`, not only `ListTile`
      // and `Divider` (the restriction lives in the builder, not in JSON Schema), so
      // an option may well arrive inside a container.
      await pumpDocument(
        tester,
        docWith([
          choiceGroupNode(
            [
              {
                'id': 'card',
                'type': 'Container',
                'props': {
                  'gap': 'none',
                },
                'style': {
                  'padding': 'sm',
                  'radius': 'md',
                  'background': {'kind': 'color', 'color': 'surface'},
                },
                'children': [
                  optionNode('У контейнері', optionValue: 'nested'),
                ],
              },
              optionNode('Поруч', optionValue: 'plain'),
            ],
            value: const {'kind': 'literal', 'value': 'plain'},
          ),
        ]),
      );

      expect(selectedOptions(tester), {'plain'});

      await tester.tap(find.text('У контейнері'));
      await tester.pump();

      expect(selectedOptions(tester), {'nested'});
    });
  });

  group('option outside a group', () {
    testWidgets('is drawn, but does not switch', (tester) async {
      // A document the builder flags as `choice_option_outside_group`.
      // The renderer does not throw it away (the content stays on screen), but
      // does not pretend to work either: there is nothing to choose -- nobody to hold the choice.
      await pumpDocument(
        tester,
        docWith([optionNode('Сам по собі', optionValue: 'lonely')]),
      );

      final mark = optionMarks(tester).single;
      expect(mark.enabled, isFalse);
      expect(mark.selected, isFalse);

      await tester.tap(find.text('Сам по собі'));
      await tester.pump();

      expect(optionMarks(tester).single.selected, isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('option versus action (6.1.0)', () {
    testWidgets('for a group row the choice wins, not `action`', (tester) async {
      // A renderer decision, and an unambiguous one: an option row belongs to the choice.
      // If the action won, it would lead to another screen -- and the option could
      // never be chosen; an action can always be moved to a button.
      final fired = <String>[];
      await pumpDocument(
        tester,
        docWith([
          choiceGroupNode(
            [
              optionNode('Навушники', optionValue: 'headphones'),
              optionNode(
                'Колонка',
                optionValue: 'speaker',
                action: const {
                  'type': 'navigate',
                  'params': {'screenId': 'details'},
                },
              ),
            ],
            value: const {'kind': 'literal', 'value': 'headphones'},
          ),
        ]),
        onAction: (action, nodeId) => fired.add('${action.type}@$nodeId'),
      );

      await tester.tap(find.text('Колонка'));
      await tester.pump();

      expect(selectedOptions(tester), {'speaker'});
      expect(fired, isEmpty, reason: 'the option action is not run -- the touch belongs to the choice');
    });

    testWidgets('an option outside a group with an action stays dead -- both times', (tester) async {
      // Otherwise the builder's error text ("tapping affects nothing")
      // would become untrue: the user would tap the circle and go somewhere.
      final fired = <String>[];
      await pumpDocument(
        tester,
        docWith([
          optionNode(
            'Сам по собі',
            optionValue: 'lonely',
            action: const {'type': 'openDetails'},
          ),
        ]),
        onAction: (action, nodeId) => fired.add(action.type),
      );

      await tester.tap(find.text('Сам по собі'));
      await tester.pump();

      expect(fired, isEmpty);
      expect(optionMarks(tester).single.selected, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an ordinary row inside a group works as usual', (tester) async {
      // The group does not swallow taps entirely: without `radio` a row is not an option, and its
      // action works the usual way.
      final fired = <String>[];
      await pumpDocument(
        tester,
        docWith([
          choiceGroupNode(
            [
              optionNode('Навушники', optionValue: 'headphones'),
              listTileNode(
                'Умови акції',
                id: 'terms',
                trailing: const {'kind': 'chevron'},
                action: const {'type': 'openTerms'},
              ),
            ],
            value: const {'kind': 'literal', 'value': 'headphones'},
          ),
        ]),
        onAction: (action, nodeId) => fired.add('${action.type}@$nodeId'),
      );

      await tester.tap(find.text('Умови акції'));
      await tester.pump();

      expect(fired, ['openTerms@terms']);
      expect(selectedOptions(tester), {'headphones'}, reason: 'the choice did not move meanwhile');
    });

    test('isOption speaks about the node shape, not its surroundings', () {
      final doc = docWith([
        optionNode('Опція', optionValue: 'x', action: const {'type': 'go'}),
        listTileNode('Не опція', id: 'plain', action: const {'type': 'go'}),
      ]);
      final tiles = flattenDocument(doc).whereType<ListTileNode>().toList();

      expect(tiles.map((tile) => tile.isOption), [true, false]);
      // An action on an option from the document does not vanish -- the renderer just does not
      // run it. Parsing stays a mirror of the document, not of renderer decisions.
      expect(tiles.first.action?.type, 'go');
    });
  });

  group('state boundary', () {
    testWidgets('going to another screen and back restores the initial choice of the document', (tester) async {
      // A decision, not a side effect: there is nowhere to write the choice -- the contract
      // has neither an action to change it nor a data path for it. Renderer memory
      // between screens would be state nobody else knows about.
      final doc = docWithScreens([
        screenEntry('choice', [
          rewardGroup(),
          buttonNode(
            'Далі',
            id: 'next',
            action: {
              'type': 'navigate',
              'params': {'screenId': 'other'},
            },
          ),
        ]),
        screenEntry('other', [
          textNode('Інший екран'),
          buttonNode('Назад', id: 'back', action: {'type': 'navigate.back'}),
        ]),
      ], initialScreenId: 'choice');

      await pumpDocument(tester, doc);
      await tester.tap(find.text('Сертифікат'));
      await tester.pump();
      expect(selectedOptions(tester), {'certificate'});

      await tester.tap(find.text('Далі'));
      await tester.pumpAndSettle();
      expect(find.text('Інший екран'), findsOneWidget);

      await tester.tap(find.text('Назад'));
      await tester.pumpAndSettle();

      expect(selectedOptions(tester), {'headphones'});
    });

    testWidgets('new data under an UNTOUCHED binding override the choice', (tester) async {
      // The document outranks the state until a finger touched it: if `value`
      // was computed differently, the previous choice is no longer about that.
      final doc = docWith([
        rewardGroup(value: {'kind': 'binding', 'path': 'item.selectedId', 'fallback': ''}),
      ]);

      await pumpDocument(tester, doc, data: const {'item.selectedId': 'headphones'});
      expect(selectedOptions(tester), {'headphones'});

      await pumpDocument(tester, doc, data: const {'item.selectedId': 'certificate'});
      expect(selectedOptions(tester), {'certificate'});
    });

    testWidgets('after a write, a bound field owns its path', (tester) async {
      // **The assertion was flipped in 8.1.0, not weakened.** Until then a bound
      // `value` was ONLY a read, so new data under it legitimately wiped
      // a finger choice. Now a field whose value is bound to a path writes to
      // that path -- and while the screen stack lives, the user's explicit choice is
      // stronger than data that arrived under it. The opposite behaviour
      // would mean a data refresh silently cancels the choice just made.
      final doc = docWith([
        rewardGroup(value: {'kind': 'binding', 'path': 'item.selectedId', 'fallback': ''}),
      ]);

      await pumpDocument(tester, doc, data: const {'item.selectedId': 'headphones'});
      await tester.tap(find.text('Колонка'));
      await tester.pump();
      expect(selectedOptions(tester), {'speaker'});

      await pumpDocument(tester, doc, data: const {'item.selectedId': 'certificate'});
      expect(selectedOptions(tester), {'speaker'});
    });

    testWidgets('a bound choice survives a transition and a return', (tester) async {
      // What the write was made for: chose with the circle -> went to details ->
      // came back -> see YOUR choice, not the document's initial value.
      // A literal `value` cannot do this (the neighbouring test above) -- and must not:
      // without a binding there is no address to write to.
      final doc = docWithScreens([
        screenEntry('choice', [
          rewardGroup(value: {'kind': 'binding', 'path': 'item.selectedId', 'fallback': 'headphones'}),
          buttonNode(
            'Далі',
            id: 'next',
            action: {'type': 'navigate', 'params': {'screenId': 'other'}},
          ),
        ]),
        screenEntry('other', [
          textNode('Інший екран'),
          buttonNode('Назад', id: 'back', action: {'type': 'navigate.back'}),
        ]),
      ], initialScreenId: 'choice');

      await pumpDocument(tester, doc);
      await tester.tap(find.text('Сертифікат'));
      await tester.pump();
      expect(selectedOptions(tester), {'certificate'});

      await tester.tap(find.text('Далі'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Назад'));
      await tester.pumpAndSettle();

      expect(selectedOptions(tester), {'certificate'});
    });
  });

  group('group model', () {
    test('optionValues collects options from the depth, but not from a nested group', () {
      final doc = docWith([
        choiceGroupNode(
          [
            optionNode('Своя', optionValue: 'own'),
            {
              'id': 'box',
              'type': 'Container',
              'props': {
                'gap': 'none',
              },
              'children': [optionNode('Глибока', optionValue: 'deep')],
            },
            choiceGroupNode(
              [optionNode('Чужа', optionValue: 'foreign')],
              id: 'inner',
            ),
          ],
          id: 'outer',
        ),
      ]);

      final outer = flattenDocument(
        doc,
      ).whereType<ChoiceGroupNode>().firstWhere((node) => node.id == 'outer');

      expect(outer.optionValues, {'own', 'deep'});
    });

    test('choice is not expressed on a row: ListTile has no "selected" field', () {
      // A structural guarantee of the contract: a row names ITSELF, and the choice belongs to the
      // group, so a document with two selected is not writable at all.
      final doc = docWith([rewardGroup()]);
      final tiles = flattenDocument(doc).whereType<ListTileNode>().toList();

      expect(tiles, hasLength(3));
      for (final tile in tiles) {
        expect(tile.trailing, isA<TrailingRadio>());
      }
      expect(
        tiles.map((tile) => (tile.trailing as TrailingRadio).optionValue),
        ['headphones', 'speaker', 'certificate'],
      );
    });
  });

  group('rewards catalog fixture -- what is shown', () {
    testWidgets('the initial choice comes from the data, not from the document', (tester) async {
      await pumpDocument(
        tester,
        loadFixture('reward-catalog-screens'),
        data: sampleScreenData,
      );

      // The fixture's start screen is exactly the reward choice: three options.
      expect(find.byType(ChoiceOptionMark), findsNWidgets(3));
      expect(selectedOptions(tester), {'headphones'});
    });

    testWidgets('the reward is switched by finger, the document stays unchanged', (tester) async {
      final doc = loadFixture('reward-catalog-screens');
      await pumpDocument(tester, doc, data: sampleScreenData);

      await tester.ensureVisible(find.text('Travel backpack'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Travel backpack'));
      await tester.pump();
      expect(selectedOptions(tester), {'backpack'});

      await tester.ensureVisible(find.text('Coffee set'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Coffee set'));
      await tester.pump();
      expect(selectedOptions(tester), {'coffee-set'});

      // The group's `value` stayed a binding to data as it was: the renderer
      // wrote to its own state, not to the document.
      final group = flattenDocument(doc).whereType<ChoiceGroupNode>().single;
      expect(group.value, isA<BoundString>());
      expect(group.value.resolve(const ScreenData(sampleScreenData)), 'headphones');
    });

    testWidgets('the button leads to details, the details button leads back to the catalog', (tester) async {
      await pumpDocument(
        tester,
        loadFixture('reward-catalog-screens'),
        data: sampleScreenData,
      );

      expect(find.text('Your points'), findsNothing);
      await tester.ensureVisible(find.text('Confirm choice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm choice'));
      await tester.pumpAndSettle();
      expect(find.text('Your points'), findsOneWidget);

      // The details button leads back, not the app bar arrow: both paths must be
      // visible, since in the contract they are different mechanisms -- `navigate` versus the stack.
      await tester.ensureVisible(find.text('Back to catalog'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back to catalog'));
      await tester.pumpAndSettle();
      expect(find.text('Choose your reward'), findsOneWidget);

      // And the app bar arrow is a step on the stack, i.e. to the details again.
      await tester.tap(findAppBarBack);
      await tester.pumpAndSettle();
      expect(find.text('Your points'), findsOneWidget);
    });
  });

  group('catalog fixture', () {
    testWidgets('the reward choice moves on tap', (tester) async {
      await pumpDocument(
        tester,
        loadFixture('full-catalog-screen'),
        data: sampleScreenData,
      );

      expect(selectedOptions(tester), {'iphone'});

      await tester.ensureVisible(find.text('Сертифікат 5000 ₴'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сертифікат 5000 ₴'));
      await tester.pump();

      expect(selectedOptions(tester), {'certificate'});
      expect(tester.takeException(), isNull);
    });
  });
}
