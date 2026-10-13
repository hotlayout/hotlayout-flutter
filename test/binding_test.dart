import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/bindable.dart';

import 'support/fixtures.dart';

void main() {
  group('binding', () {
    test('value comes from the data when the path exists', () {
      final value = BindableString.parse({
        'kind': 'binding',
        'path': 'task.title',
        'fallback': 'Задача місяця',
      }).resolve(const ScreenData({'task.title': 'Spend 500 with your card'}));

      expect(value, 'Spend 500 with your card');
    });

    test('fallback is used when the path is missing', () {
      final value = BindableString.parse({
        'kind': 'binding',
        'path': 'task.title',
        'fallback': 'Задача місяця',
      }).resolve(ScreenData.empty);

      expect(value, 'Задача місяця');
    });

    test('numbers do not carry a trailing .0', () {
      final value = BindableString.parse({
        'kind': 'binding',
        'path': 'user.points',
        'fallback': '0',
      }).resolve(const ScreenData({'user.points': 1240}));

      expect(value, '1240');
    });

    test('nested JSON is addressed by the same path', () {
      final value = BindableString.parse({
        'kind': 'binding',
        'path': 'item.name',
        'fallback': '—',
      }).resolve(
        const ScreenData({
          'item': {'name': 'Travel backpack'},
        }),
      );

      expect(value, 'Travel backpack');
    });

    test('BindableNumber: data, fallback and numeric string', () {
      final bound = BindableNumber.parse({
        'kind': 'binding',
        'path': 'task.progress',
        'fallback': 0,
      });

      expect(bound.resolve(const ScreenData({'task.progress': 150000})), 150000);
      expect(bound.resolve(ScreenData.empty), 0);
      expect(bound.resolve(const ScreenData({'task.progress': '42'})), 42);
    });

    testWidgets('the screen shows the value from the data, and the fallback without it', (tester) async {
      final doc = loadFixture('task-progress-screen');
      // The app bar sits outside the scroll view, so "the body" is the scroll view.
      // We search inside the BODY: the fixture's top bar has the title "Task of
      // the month" -- the same string as the task title fallback -- and without
      // this restriction the test would check the bar, not the binding.
      Finder inBody(String text) => find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.text(text),
      );

      await pumpDocument(tester, doc, data: const {'task.title': 'Spend 500 with your card'});
      expect(inBody('Spend 500 with your card'), findsOneWidget);
      expect(inBody('Task of the month'), findsNothing);

      await pumpDocument(tester, doc);
      expect(inBody('Task of the month'), findsOneWidget);
    });
  });
}
