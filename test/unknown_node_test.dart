import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';

import 'support/fixtures.dart';

/// A document with a widget this app version does not know — a routine situation for SDUI:
/// the admin already supports `Chart`, the mobile app does not yet.
UiDocument _docWithUnknownWidget() => docWith([
  textNode('До невідомого', id: 'before'),
  {
    'id': 'chart',
    'type': 'Chart',
    'props': {'series': 'weekly'},
    'children': [textNode('Всередині невідомого', id: 'inside')],
  },
  textNode('Після невідомого', id: 'after'),
]);

void main() {
  group('unknown widget type', () {
    test('parses into UnknownNode with the type and children preserved', () {
      final unknown = flatten(rootOf(_docWithUnknownWidget())).whereType<UnknownNode>().single;

      expect(unknown.type, 'Chart');
      expect(unknown.children.single, isA<TextNode>());
    });

    testWidgets('does not break rendering of the rest of the screen', (tester) async {
      await pumpDocument(tester, _docWithUnknownWidget());

      expect(tester.takeException(), isNull);
      expect(find.text('До невідомого'), findsOneWidget);
      expect(find.text('Після невідомого'), findsOneWidget);
      // Children of the unknown wrapper are real content; we do not drop them.
      expect(find.text('Всередині невідомого'), findsOneWidget);
      // In debug the document author sees a conspicuous badge with the type name.
      expect(find.textContaining('Chart'), findsOneWidget);
    });

    testWidgets('corrupted props of a known type give defaults, not an exception', (tester) async {
      final doc = docWith([
        {'id': 'txt', 'type': 'Text', 'props': null},
        {
          'id': 'nope',
          'type': 'Badge',
          'props': {'label': 'просто рядок', 'tone': 7},
        },
      ]);

      await pumpDocument(tester, doc);
      expect(tester.takeException(), isNull);
    });

    test('a document without a single usable screen — the only place where parsing fails', () {
      // The 4.0.0 rule was "a document without `root`". The root moved inside the
      // screens, so the rule moved with it.
      expect(
        () => UiDocument.fromJsonString(jsonEncode({'schemaVersion': '5.0.0'})),
        throwsFormatException,
      );
      expect(
        () => UiDocument.fromJson({
          'schemaVersion': '5.0.0',
          'documentId': 'empty',
          'name': 'Порожній',
          'initialScreenId': 'a',
          'screens': [
            {'screenId': 'a', 'name': 'Без кореня'},
          ],
        }),
        throwsFormatException,
      );
    });

    test('one broken screen does not sink the document', () {
      final doc = UiDocument.fromJson({
        'schemaVersion': '5.0.0',
        'documentId': 'half-broken',
        'name': 'Половина екранів',
        'initialScreenId': 'ok',
        'screens': [
          {'screenId': 'broken', 'name': 'Без кореня'},
          screenEntry('ok', [textNode('Живий екран')]),
        ],
      });

      expect(doc.screens, hasLength(1));
      expect(doc.initialScreen.screenId, 'ok');
    });
  });

  group('origin of an unknown widget (x-compatibility.widgets)', () {
    // The `widgets` map in the artifact exists precisely for this difference: without it
    // "a widget from the future" and "a manager's typo" look the same.
    test('a type from the catalogue added after the client version — from the future', () {
      expect(
        widgetOriginOf(
          'Chart',
          catalog: const {'Chart': '5.2.0', 'Text': '1.0.0'},
          readerVersion: '5.0.0',
        ),
        WidgetOrigin.fromFuture,
      );
    });

    test('a type absent from the catalogue — not the future but a broken document', () {
      expect(widgetOriginOf('Colunm'), WidgetOrigin.outsideContract);
      expect(widgetOriginOf('Chart'), WidgetOrigin.outsideContract);
    });

    test('a catalogue type not from the future — the renderer simply lags the contract', () {
      expect(widgetOriginOf('Text'), WidgetOrigin.contractual);
      expect(widgetOriginOf('Accordion', readerVersion: '5.0.0'), WidgetOrigin.contractual);
    });

    test('the explanation tells the cases apart in words, not only by enum', () {
      expect(
        describeWidgetOrigin('Chart', WidgetOrigin.fromFuture),
        contains('newer than this app'),
      );
      expect(
        describeWidgetOrigin('Colunm', WidgetOrigin.outsideContract),
        contains('is not in the contract'),
      );
    });
  });
}
