/// FIXTURE `survey-screens` (schema 9.14.0): a three-step survey and a thank-you screen —
/// in English, Ukrainian and Arabic, at 320 and 393. The table
/// (`form_cases_test.dart`) covers individual rules; here it is all together, with a real
/// gesture: "empty → choice → next → name → 12a → 12 → next → consent".
///
/// The screen is drawn WITHOUT host data (`data: const {}`): with the dictionary's sample data
/// the form is already filled, and the button would never be disabled.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';

import 'support/fixtures.dart';

Map<String, String> _words(String locale) {
  final raw = jsonDecode(readFixture('survey-screens')) as Map<String, Object?>;
  final strings = ((raw['localization']! as Map)['strings']! as Map).cast<String, Object?>();
  return locale == 'en' ? const {} : (strings[locale]! as Map).cast<String, String>();
}

/// A node's label in a language: the translation by key `screen/node/field` or the source one.
String _label(String locale, String screen, String node, String fallback) =>
    _words(locale)['$screen/$node/label'] ?? fallback;

void _view(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

Finder _button(String label) => find.ancestor(
  of: find.descendant(of: find.byWidgetPredicate((w) => w is ButtonStyleButton), matching: find.text(label)),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

bool _disabled(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(_button(label).first).onPressed == null;

Future<void> _type(WidgetTester tester, int field, String text) async {
  final finder = find.byType(TextField).at(field);
  await tester.showKeyboard(finder);
  await tester.pump();
  await tester.showKeyboard(finder);
  await tester.enterText(finder, text);
  await tester.pump();
}

void main() {
  final doc = loadFixture('survey-screens');

  test('fixture: four screens, schema 9.14.0, three languages, in the fixture catalogue', () {
    expect(doc.schemaVersion, '9.14.0');
    expect(doc.screens.map((s) => s.screenId), ['goal', 'details', 'consent', 'done']);
    expect(doc.initialScreenId, 'goal');
    expect(fixtureIds, contains('survey-screens'));
    expect(doc.versionVerdict.canRender, isTrue);
  });

  for (final locale in ['en', 'uk', 'ar']) {
    for (final size in [const Size(320, 568), const Size(393, 852)]) {
      final tag = '$locale, ${size.width.round()}';

      testWidgets('$tag: walk-through empty → choice → next → name → 12a → 12 → next → consent (age 12: cannot send)', (tester) async {
        _view(tester, size);
        final writes = <(String, Object)>[];
        await pumpDocument(tester, doc, data: const {}, locale: locale, onAction: (_, _) {}, onWrite: (p, v) => writes.add((p, v)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Step 1: nothing chosen — "Next" is disabled.
        final next1 = _label(locale, 'goal', 'goal-next', 'Next');
        expect(_disabled(tester, next1), isTrue, reason: 'nothing chosen');
        await tester.tap(find.byType(ChoiceOptionMark).first);
        await tester.pumpAndSettle();
        expect(writes.last, ('survey.goal', 'rewards'));
        expect(_disabled(tester, next1), isFalse, reason: 'a choice enables the button at once');
        await tester.tap(_button(next1));
        await tester.pumpAndSettle();

        // Step 2: name and age are required; "12a" is not a number.
        final next2 = _label(locale, 'details', 'details-next', 'Next');
        expect(_disabled(tester, next2), isTrue);
        await _type(tester, 0, 'Olena');
        expect(_disabled(tester, next2), isTrue, reason: 'age not given yet');
        await _type(tester, 1, '12');
        expect(writes.last, ('survey.age', 12));
        expect(_disabled(tester, next2), isFalse);
        await _type(tester, 1, '12a');
        expect(writes.last, ('survey.age', ''), reason: 'the number became a non-number: empty string');
        expect(_disabled(tester, next2), isTrue, reason: '"12a" is not a number');
        await _type(tester, 1, '12');
        expect(writes.last, ('survey.age', 12));
        expect(_disabled(tester, next2), isFalse);
        await tester.tap(_button(next2));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Step 3: without consent "Send" is disabled; with consent — only from age 16.
        final send = _label(locale, 'consent', 'send', 'Send answers');
        expect(_disabled(tester, send), isTrue);
        await tester.tap(find.byKey(const ValueKey('sdui-checkbox-box')));
        await tester.pumpAndSettle();
        expect(writes.last, ('survey.agreed', true));
        expect(_disabled(tester, send), isTrue, reason: 'consent given, but 12 < 16: disabledIf');
        expect(find.textContaining(locale == 'en' ? 'people of 16' : (locale == 'uk' ? '16' : '16')), findsWidgets);
      });

      testWidgets('$tag: age 18 and consent — "Send" enables and leads to the thank-you screen', (tester) async {
        _view(tester, size);
        await pumpDocument(tester, doc, data: const {}, locale: locale, onAction: (_, _) {});
        await tester.pumpAndSettle();
        await tester.tap(find.byType(ChoiceOptionMark).first);
        await tester.pumpAndSettle();
        await tester.tap(_button(_label(locale, 'goal', 'goal-next', 'Next')));
        await tester.pumpAndSettle();
        await _type(tester, 0, 'Olena');
        await _type(tester, 1, '18');
        await tester.tap(_button(_label(locale, 'details', 'details-next', 'Next')));
        await tester.pumpAndSettle();
        final send = _label(locale, 'consent', 'send', 'Send answers');
        await tester.tap(find.byKey(const ValueKey('sdui-checkbox-box')));
        await tester.pumpAndSettle();
        expect(_disabled(tester, send), isFalse);
        await tester.tap(_button(send));
        await tester.pumpAndSettle();
        expect(find.text(send), findsNothing, reason: 'moved to the thank-you screen');
        expect(find.text(_label(locale, 'done', 'again', 'Start over')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$tag: with the dictionary 1.4.0 sample data the form is filled — buttons enabled', (tester) async {
        _view(tester, size);
        final artifact = (jsonDecode(File('assets/contract/data-contract.json').readAsStringSync()) as Map).cast<String, Object?>();
        final contract = (artifact['contract']! as Map).cast<String, Object?>();
        final data = {
          for (final entry in (contract['paths']! as List<Object?>).cast<Map<String, Object?>>())
            if ((entry['path']! as String).startsWith('survey.')) entry['path']! as String: entry['sampleValue'],
        };
        expect(data.keys, containsAll(['survey.goal', 'survey.name', 'survey.age', 'survey.comment', 'survey.agreed']));
        expect(data['survey.age'], isA<num>());
        await pumpDocument(tester, doc, data: data, locale: locale, onAction: (_, _) {});
        await tester.pumpAndSettle();
        expect(_disabled(tester, _label(locale, 'goal', 'goal-next', 'Next')), isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Arabic: a label with an asterisk — one right-to-left text, the number field left to right', (tester) async {
    _view(tester, const Size(320, 568));
    await pumpDocument(tester, doc, data: const {}, locale: 'ar', entry: null, onAction: (_, _) {});
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ChoiceOptionMark).first);
    await tester.pumpAndSettle();
    await tester.tap(_button(_label('ar', 'goal', 'goal-next', 'Next')));
    await tester.pumpAndSettle();
    final labels = tester.widgetList<RichText>(find.byType(RichText)).where((w) => w.text.toPlainText().endsWith('*')).toList();
    expect(labels, hasLength(2), reason: 'name and age — two asterisks');
    for (final label in labels) {
      expect(Directionality.of(tester.element(find.byWidget(label))), TextDirection.rtl);
    }
    final age = tester.widget<EditableText>(find.byType(EditableText).at(1));
    expect(age.textDirection, TextDirection.ltr, reason: 'a number is typed left to right');
    expect(age.textAlign, TextAlign.right, reason: 'but aligned from the start of the screen');
  });

  testWidgets('document without the required key: UiDocument.fromJson reads the fixture losslessly', (tester) async {
    final json = jsonDecode(readFixture('survey-screens')) as Map<String, Object?>;
    final back = UiDocument.fromJson(json);
    expect(back.screens, hasLength(4));
  });
}
