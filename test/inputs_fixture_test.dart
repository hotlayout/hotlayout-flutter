/// FIXTURE `inputs-screens` (schema 9.13.0, a frame like the builder preview for fields):
/// a profile form (name, email, phone with a host error, consent, a button
/// at the bottom) and settings (switches, a multi-line field) - in English,
/// Ukrainian and Arabic, at 320 and 393. The table (`input_cases_test.dart`) covers
/// individual rules; here it is everything together, with a real gesture.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/inputs.dart';
import 'package:hotlayout_flutter/src/render/screen_zones.dart';

import 'support/fixtures.dart';

/// Screen data are SAMPLES of the data dictionary 1.3.0 (the field with an error on the phone -
/// as in the fixture and in the builder preview frame).
Map<String, Object?> _sampleData() {
  final artifact = (jsonDecode(File('assets/contract/data-contract.json').readAsStringSync()) as Map).cast<String, Object?>();
  final contract = (artifact['contract']! as Map).cast<String, Object?>();
  return {
    for (final entry in (contract['paths']! as List<Object?>).cast<Map<String, Object?>>())
      if ((entry['path']! as String).startsWith('form.') || (entry['path']! as String).startsWith('settings.'))
        entry['path']! as String: entry['sampleValue'],
  };
}

void _view(WidgetTester tester, double width, double height) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

const _names = {
  'en': (name: 'Full name', email: 'Email', phone: 'Phone', save: 'Save', error: 'Enter the number with the country code'),
  'uk': (name: 'Ім’я та прізвище', email: 'Електронна пошта', phone: 'Телефон', save: 'Зберегти', error: 'Enter the number with the country code'),
  'ar': (name: 'الاسم الكامل', email: 'البريد الإلكتروني', phone: 'رقم الهاتف', save: 'حفظ', error: 'Enter the number with the country code'),
};

void main() {
  final doc = loadFixture('inputs-screens');
  final data = _sampleData();

  test('fixture: two screens, schema 9.13.0, three languages, in the fixture catalogue', () {
    expect(doc.schemaVersion, '9.13.0');
    expect(doc.screens.map((s) => s.screenId), ['profile', 'settings']);
    expect(doc.initialScreenId, 'profile');
    expect(fixtureIds, contains('inputs-screens'));
    expect(data.keys, containsAll(['form.fullName', 'form.email', 'form.phone', 'form.phoneError', 'form.comment', 'form.agreed', 'settings.notifications', 'settings.marketing']));
  });

  for (final locale in ['en', 'uk', 'ar']) {
    for (final size in [const Size(320, 568), const Size(393, 852)]) {
      final tag = '$locale, ${size.width.round()}';
      final words = _names[locale]!;

      testWidgets('$tag: profile form - three fields, consent, a button at the bottom, the error in place of the hint', (tester) async {
        _view(tester, size.width, size.height);
        await pumpDocument(tester, doc, data: data, locale: locale, onAction: (_, _) {});
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(find.byType(InputTextField), findsNWidgets(3));
        expect(find.byType(InputToggle), findsOneWidget);
        expect(find.text(words.name), findsOneWidget, reason: 'the label is on screen, in the preview language');
        expect(find.text(words.email), findsOneWidget);
        expect(find.text(words.phone), findsOneWidget);
        // The host error stands in place of the phone hint; the email hint remains.
        expect(find.text(words.error), findsOneWidget);
        expect(find.textContaining(locale == 'en' ? 'The courier calls' : (locale == 'uk' ? 'Кур’єр' : 'المندوب')), findsNothing);
        // The "Save" button appears with consent (`visibleIf`) - until the box is ticked there is no pinned
        // block and no zone either: the bar and the body.
        expect(find.text(words.save), findsNothing);
        final zones = tester.renderObject<RenderScreenZones>(find.byType(ScreenZones).last);
        expect(zones.childCount, 2, reason: 'bar and body - there is no bottom zone without a block');
      });

      testWidgets('$tag: typed text reaches the dependent screen text, consent hides the hint', (tester) async {
        _view(tester, size.width, size.height);
        final writes = <(String, Object?)>[];
        await pumpDocument(tester, doc, data: data, locale: locale, onAction: (_, _) {}, onWrite: (p, v) => writes.add((p, v)));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'Olena');
        await tester.pump();
        expect(find.text('Olena'), findsWidgets, reason: 'the field and the echo of "form.fullName" under the heading');
        expect(writes.last, ('form.fullName', 'Olena'));
        // The "tick the box" hint is visible until there is consent, and disappears with it.
        final hint = find.textContaining(locale == 'en' ? 'Tick the box' : (locale == 'uk' ? 'Поставте позначку' : 'ضع'));
        expect(hint, findsOneWidget);
        await tester.ensureVisible(find.byType(InputToggle));
        await tester.tap(find.byType(InputToggle));
        await tester.pumpAndSettle();
        expect(writes.last, ('form.agreed', true));
        expect(hint, findsNothing);
        // With consent the button appeared: pinned (`pin: bottom`) at the bottom of the screen, outside the scroll.
        final save = tester.getRect(find.text(words.save));
        expect(save.bottom, lessThanOrEqualTo(size.height));
        expect(save.bottom, greaterThan(size.height - 80));
        final zones = tester.renderObject<RenderScreenZones>(find.byType(ScreenZones).last);
        expect(zones.childCount, 4, reason: 'bar, body, pinned block, "bottom"');
      });

      testWidgets('$tag: settings - the marketing switch is disabled together with notifications, the note is conditional', (tester) async {
        _view(tester, size.width, size.height);
        final settings = UiDocument.fromJson({...jsonFixture('inputs-screens'), 'initialScreenId': 'settings'});
        await pumpDocument(tester, settings, data: data, locale: locale, onAction: (_, _) {});
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(InputToggle), findsNWidgets(2));
        expect(find.byType(InputTextField), findsOneWidget);
        final marketing = find.byType(InputToggle).last;
        double opacity() => tester.widgetList<Opacity>(find.descendant(of: marketing, matching: find.byType(Opacity))).fold(1.0, (a, o) => a * o.opacity);
        expect(opacity(), 1, reason: 'notifications on - marketing is available');
        await tester.tap(find.byType(InputToggle).first);
        await tester.pump();
        expect(opacity(), 0.5, reason: 'notifications off - marketing is disabled');
        // Multi-line field: three lines, noticeable height.
        expect(tester.widget<EditableText>(find.byType(EditableText)).maxLines, 3);
      });
    }
  }

  testWidgets('in Arabic: checkbox square on the right, phone aligned right, digits left to right', (tester) async {
    _view(tester, 320, 568);
    await pumpDocument(tester, doc, data: data, locale: 'ar', onAction: (_, _) {});
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byKey(const ValueKey('sdui-checkbox-box')));
    expect(box.center.dx, greaterThan(160), reason: 'the square at the start of the line = on the right');
    final phone = tester.widget<EditableText>(find.byType(EditableText).at(2));
    expect(phone.textAlign, TextAlign.right);
    expect(phone.textDirection, TextDirection.ltr);
  });
}
