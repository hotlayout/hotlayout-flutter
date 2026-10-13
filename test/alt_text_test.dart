/// THE DESCRIPTION OF A PICTURE AND AN ICON (schema 9.19.0, `AltText`): a plain string, translated under the key of the
/// field, or a string of the document (a binding, a template, a wrapped literal).
///
/// The card named by a description is held by `composition_cases_test.dart` (`nameCases`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

_Json _image(Object? alt) => {
  'id': 'pic',
  'type': 'Image',
  'props': {'source': {'kind': 'url', 'url': 'https://example.com/a.png'}, 'alt': ?alt},
};

_Json _icon(Object? alt) => {
  'id': 'ico',
  'type': 'Icon',
  'props': {'name': 'gift', 'alt': ?alt},
};

UiDocument _localized(List<_Json> children, _Json uk) => UiDocument.fromJson({
  'schemaVersion': kSupportedSchemaVersion,
  'documentId': 'alt',
  'name': 'alt',
  'initialScreenId': 's',
  'screens': [
    {
      'screenId': 's',
      'name': 's',
      'root': {'id': 'root', 'type': 'Screen', 'props': <String, Object?>{}, 'children': children},
    },
  ],
  'localization': {
    'defaultLocale': 'en',
    'locales': ['en', 'uk'],
    'strings': {'uk': uk},
  },
});

/// Whether any semantics node carries exactly this label (a description names a picture node of its own).
bool _described(WidgetTester tester, String label) => find.bySemanticsLabel(RegExp(RegExp.escape(label))).evaluate().isNotEmpty;

void main() {
  testWidgets('a plain string is the description, as it always was', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpDocument(tester, docWith([_image('Summer sale'), _icon('Gifts')]));
    expect(_described(tester, 'Summer sale'), isTrue);
    expect(_described(tester, 'Gifts'), isTrue);
    expect(tester.getSemantics(find.bySemanticsLabel(RegExp('Summer sale')).first).flagsCollection.isImage, isTrue, reason: 'a picture says it is one');
    semantics.dispose();
  });

  testWidgets('a plain string is translated under the key of the field: <screen>/<node>/alt', (tester) async {
    final semantics = tester.ensureSemantics();
    final document = _localized([_image('Summer sale'), _icon('Gifts')], {'s/pic/alt': 'Літній розпродаж'});
    await pumpDocument(tester, document, locale: 'uk');
    expect(_described(tester, 'Літній розпродаж'), isTrue);
    expect(_described(tester, 'Summer sale'), isFalse);
    expect(_described(tester, 'Gifts'), isTrue, reason: 'no translation of this one: the default language');
    semantics.dispose();
  });

  testWidgets('a string of the document: a binding, with the fallback without data', (tester) async {
    final semantics = tester.ensureSemantics();
    final binding = {'kind': 'binding', 'path': 'offer.title', 'fallback': 'Offer'};
    await pumpDocument(tester, docWith([_image(binding)]));
    expect(_described(tester, 'Offer'), isTrue);
    await pumpDocument(tester, docWith([_image(binding)]), data: const {'offer.title': 'Black Friday'});
    expect(_described(tester, 'Black Friday'), isTrue);
    expect(_described(tester, 'Offer'), isFalse);
    semantics.dispose();
  });

  testWidgets('a string of the document: a template with a word, and a wrapped literal', (tester) async {
    final semantics = tester.ensureSemantics();
    final template = {
      'kind': 'template',
      'template': 'Sale until {date}',
      'values': {
        'date': {'kind': 'binding', 'path': 'offer.title', 'fallback': 'soon'},
      },
    };
    await pumpDocument(tester, docWith([_icon(template), _image({'kind': 'literal', 'value': 'Wrapped'})]), data: const {'offer.title': 'Friday'});
    expect(_described(tester, 'Sale until Friday'), isTrue);
    expect(_described(tester, 'Wrapped'), isTrue);
    semantics.dispose();
  });

  testWidgets('a binding is translated by its key: the template key of the field', (tester) async {
    final semantics = tester.ensureSemantics();
    final template = {
      'kind': 'template',
      'template': 'Sale until {date}',
      'values': {
        'date': {'kind': 'binding', 'path': 'offer.title', 'fallback': 'soon'},
      },
    };
    final document = _localized([_image(template)], {'s/pic/alt.template': 'Розпродаж до {date}'});
    await pumpDocument(tester, document, locale: 'uk', data: const {'offer.title': 'п’ятниці'});
    expect(_described(tester, 'Розпродаж до п’ятниці'), isTrue);
    semantics.dispose();
  });

  testWidgets('what is shown empty is decorative: no role and no name', (tester) async {
    final semantics = tester.ensureSemantics();
    final emptyBinding = {'kind': 'binding', 'path': 'offer.title', 'fallback': ''};
    for (final alt in <Object?>['', '   ', emptyBinding, {'kind': 'literal', 'value': ''}, 7, true, ['x'], {'kind': 'unknown'}, null]) {
      await pumpDocument(tester, docWith([_image(alt), _icon(alt)]));
      final nodes = tester.widgetList<Semantics>(find.byType(Semantics)).where((widget) => widget.properties.image == true || (widget.properties.label ?? '').isNotEmpty);
      expect(nodes.where((widget) => widget.properties.image == true), isEmpty, reason: 'alt $alt: not an image for the screen reader');
      await tester.pumpWidget(const SizedBox());
    }
    semantics.dispose();
  });

  testWidgets('the spaces of a description are collapsed like any shown text; an empty value from data is the fallback', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpDocument(tester, docWith([_image('  Summer \t  sale ')]));
    expect(_described(tester, 'Summer sale'), isTrue);
    final binding = {'kind': 'binding', 'path': 'offer.title', 'fallback': 'Offer'};
    await pumpDocument(tester, docWith([_image(binding)]), data: const {'offer.title': ''});
    expect(_described(tester, 'Offer'), isTrue, reason: 'an empty string from data is no value');
    semantics.dispose();
  });
}
