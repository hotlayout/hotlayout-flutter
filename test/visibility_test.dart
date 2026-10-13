import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/demo_data.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/visibility.dart';

import 'support/fixtures.dart';

bool _eval(Map<String, Object?> condition, Map<String, Object?> data) =>
    VisibilityCondition.parse(condition)!.evaluate(ScreenData(data));

void main() {
  group('visibleIf: unary operators', () {
    test('isTrue / isFalse read a flag', () {
      const done = {'path': 'task.completed', 'op': 'isTrue'};
      const notDone = {'path': 'task.completed', 'op': 'isFalse'};

      expect(_eval(done, const {'task.completed': true}), isTrue);
      expect(_eval(done, const {'task.completed': false}), isFalse);
      expect(_eval(notDone, const {'task.completed': false}), isTrue);
      // Backends like to send flags as strings - the same way as numbers.
      expect(_eval(done, const {'task.completed': 'true'}), isTrue);
    });

    test('isEmpty / isNotEmpty judge the value as it is: a string of spaces is a value (x-conditions.emptiness)', () {
      const empty = {'path': 'item.name', 'op': 'isEmpty'};
      const filled = {'path': 'item.name', 'op': 'isNotEmpty'};

      expect(_eval(empty, const {'item.name': ''}), isTrue);
      expect(_eval(empty, const {'item.name': '   '}), isFalse);
      expect(_eval(filled, const {'item.name': '   '}), isTrue);
      expect(_eval(filled, const {'item.name': 'Смартфон'}), isTrue);
      expect(_eval(filled, const {'item.name': ''}), isFalse);
    });
  });

  group('visibleIf: comparison', () {
    test('eq / neq for strings, numbers and flags', () {
      expect(
        _eval(const {'path': 'campaign.title', 'op': 'eq', 'value': 'Вересень'}, const {
          'campaign.title': 'Вересень',
        }),
        isTrue,
      );
      expect(
        _eval(const {'path': 'campaign.title', 'op': 'neq', 'value': 'Вересень'}, const {
          'campaign.title': 'Жовтень',
        }),
        isTrue,
      );
      expect(
        _eval(const {'path': 'user.points', 'op': 'eq', 'value': 1250}, const {
          'user.points': 1250,
        }),
        isTrue,
      );
      expect(
        _eval(const {'path': 'task.completed', 'op': 'eq', 'value': false}, const {
          'task.completed': false,
        }),
        isTrue,
      );
    });

    test('gt / gte / lt / lte also work with a numeric string from the backend', () {
      const gte = {'path': 'task.progress', 'op': 'gte', 'value': 100000};
      expect(_eval(gte, const {'task.progress': 150000}), isTrue);
      expect(_eval(gte, const {'task.progress': 100000}), isTrue);
      expect(_eval(gte, const {'task.progress': 99999}), isFalse);
      expect(_eval(gte, const {'task.progress': '150000'}), isTrue);

      expect(
        _eval(const {'path': 'task.progress', 'op': 'lt', 'value': 10}, const {
          'task.progress': 5,
        }),
        isTrue,
      );
    });
  });

  group('condition degradation (x-compatibility.policy)', () {
    test('an unknown operator does NOT hide content', () {
      // Contract policy `unknownVisibilityOp: 'visible'`. The opposite choice would
      // mean an old app shows an empty screen instead of an
      // extra block.
      final condition = VisibilityCondition.parse(const {
        'path': 'task.progress',
        'op': 'between',
        'value': 5,
      });

      expect(condition, isA<AlwaysVisibleCondition>());
      expect(condition!.evaluate(ScreenData.empty), isTrue);
    });

    test('a corrupted condition degrades the same way - to "visible"', () {
      for (final broken in <Object>[
        'не обʼєкт',
        const {'op': 'isTrue'},
        const {'path': 'task.progress'},
        const {'path': 'task.progress', 'op': 'gt'},
        const {'path': 'task.progress', 'op': 'gt', 'value': 'багато'},
        const {'path': 'campaign.title', 'op': 'eq'},
      ]) {
        expect(
          VisibilityCondition.parse(broken)!.evaluate(ScreenData.empty),
          isTrue,
          reason: '$broken',
        );
      }
    });

    test('no visibleIf field - no condition at all', () {
      expect(VisibilityCondition.parse(null), isNull);
      final node = flatten(rootOf(docWith([textNode('Без умови')])))
          .whereType<TextNode>()
          .single;
      expect(node.visibleIf, isNull);
      expect(node.isVisible(ScreenData.empty), isTrue);
    });

    /*
     * NO DATA (8.18.0). This used to be a renderer decision - one rule for all
     * operators, "the condition did not hold" - and it looked cautious.
     *
     * It was broken where it did not seem. The same rule for an operator AND ITS
     * NEGATION meant BOTH halves of a branch vanished:
     * the document said "either the list, or the text 'nothing yet'", and the screen showed
     * neither.
     */
    test('a missing value is EMPTY - "empty" holds', () {
      expect(_eval(const {'path': 'item.name', 'op': 'isEmpty'}, const {}), isTrue);
      // And its negation does not. Together they now complement each other instead of
      // vanishing together: this is exactly what the empty state lacked.
      expect(_eval(const {'path': 'item.name', 'op': 'isNotEmpty'}, const {}), isFalse);
    });

    test('the other operators stay silent, both - and legitimately', () {
      // A missing flag has neither truth nor falsehood: showing "task not
      // completed" where there is no task at all is as false as
      // showing "completed".
      expect(_eval(const {'path': 'task.completed', 'op': 'isTrue'}, const {}), isFalse);
      expect(_eval(const {'path': 'task.completed', 'op': 'isFalse'}, const {}), isFalse);
      expect(
        _eval(const {'path': 'campaign.title', 'op': 'eq', 'value': 'Вересень'}, const {}),
        isFalse,
      );
      expect(
        _eval(const {'path': 'campaign.title', 'op': 'neq', 'value': 'Вересень'}, const {}),
        isFalse,
      );
    });

    /*
     * ORDER OF TWO POLICY RULES: `unknownVisibilityOp` is stronger than
     * `missingConditionValue`. Here it falls out STRUCTURALLY, not by a check:
     * an unknown operator becomes `AlwaysVisibleCondition` already during PARSING, so
     * it never reaches evaluation with data. The test guards exactly this
     * property - in the web renderer, where both checks sit in one
     * function, the order had to be set by hand.
     */
    test('an unknown operator leaves the node visible EVEN without data', () {
      expect(
        _eval(const {'path': 'task.completed', 'op': 'matches'}, const {}),
        isTrue,
      );
    });
  });

  group('visibility in render', () {
    testWidgets('a condition controls whether the node is on screen', (tester) async {
      final doc = docWith([
        textNode('Завжди', id: 'always'),
        textNode(
          'Тільки для завершених',
          id: 'done',
          visibleIf: const {'path': 'task.completed', 'op': 'isTrue'},
        ),
      ]);

      await pumpDocument(tester, doc, data: const {'task.completed': false});
      expect(find.text('Завжди'), findsOneWidget);
      expect(find.text('Тільки для завершених'), findsNothing);

      await pumpDocument(tester, doc, data: const {'task.completed': true});
      expect(find.text('Тільки для завершених'), findsOneWidget);
    });

    testWidgets('a hidden node leaves no gap behind', (tester) async {
      Map<String, Object?> column(Object? visibleIf) => {
        'id': 'col',
        'type': 'Column',
        'props': {'gap': 'xl', 'align': 'start'},
        'children': [
          textNode('перший', id: 'a'),
          textNode('другий', id: 'b', visibleIf: visibleIf),
          textNode('третій', id: 'c'),
        ],
      };

      int gaps() => tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .where((box) => box.height == 24)
          .length;

      await pumpDocument(tester, docWith([column(null)]));
      expect(gaps(), 2);

      await pumpDocument(
        tester,
        docWith([
          column(const {'path': 'task.completed', 'op': 'isTrue'}),
        ]),
      );
      // It would be 2 if the renderer hid the child while keeping its place in the list.
      expect(gaps(), 1);
    });

    testWidgets('a condition works inside both Row and Wrap', (tester) async {
      Map<String, Object?> row(bool wrap) => {
        'id': 'row',
        'type': 'Row',
        'props': {
          'gap': 'sm',
          'align': 'center',
          'justify': 'start',
          'wrap': wrap,
        },
        'children': [
          textNode('видимий', id: 'a'),
          textNode(
            'схований',
            id: 'b',
            visibleIf: const {'path': 'user.points', 'op': 'gt', 'value': 9000},
          ),
        ],
      };

      for (final wrap in [false, true]) {
        await pumpDocument(tester, docWith([row(wrap)]), data: sampleScreenData);
        expect(find.text('видимий'), findsOneWidget);
        expect(find.text('схований'), findsNothing, reason: 'wrap: $wrap');
      }
    });

    testWidgets('the `Screen` root has no condition - it is always visible', (tester) async {
      // The schema deliberately has no `visibleIf` on the root node:
      // a screen that can hide itself is an empty screen with no explanation.
      final doc = loadFixture('minimal-screen');
      expect(rootOf(doc), isA<ScreenNode>());

      await pumpDocument(tester, doc);
      expect(find.text('Привіт'), findsOneWidget);
    });

    testWidgets('progress fixture: the «Active» badge depends on data', (tester) async {
      // `visibleIf: task.completed isFalse` - on the sample data (task
      // in progress) the badge is present, and on the opposite data it disappears.
      final doc = loadFixture('task-progress-screen');

      await pumpDocument(tester, doc, data: sampleScreenData);
      expect(find.text('Active'), findsOneWidget);

      await pumpDocument(tester, doc, data: {...sampleScreenData, 'task.completed': true});
      expect(find.text('Active'), findsNothing);
    });
  });
}
