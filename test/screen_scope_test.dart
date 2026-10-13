import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/demo_data.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/bindable.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/render/progress_paint.dart';

import 'support/fixtures.dart';

/// Screen data scope (8.1.0): "a screen has no input".
///
/// The main thing checked here is not the layer mechanics but the consequence: two rows of
/// one list open ONE details screen and show DIFFERENT entities. Previously the data
/// dictionary was one for the whole document, so the details came out the same each time,
/// however many records the list had.
///
/// Since 9.2.0 list rows are instances of ONE `Repeater` template, not two separate nodes
/// with different literals in `params`: before that the test passed only because the
/// parameters of each row were different, while in a real list they are identical and the
/// host could not tell which row was tapped. Now the row carries a record
/// (`ScreenScopeRequest.record`), and the host picks the rest of the entity by it. The rule
/// table is `record_scope_test.dart`.
void main() {
  /// The catalog in the same form in which it arrives from the network.
  const String catalogJson = '''
  { "items": [
    { "id": "headphones", "name": "Wireless headphones",
      "image": "https://cdn.example.com/items/headphones.png",
      "task": { "title": "Make 5 card payments",
                "description": "Any amount, any merchant",
                "progress": 3, "target": 5 } },
    { "id": "backpack", "name": "Travel backpack",
      "image": "https://cdn.example.com/items/backpack.png",
      "task": { "title": "Set up a recurring payment",
                "description": "Any bill, any amount",
                "progress": 14, "target": 20 } }
  ] }
  ''';

  final catalog = CollectionCatalog.parse(catalogJson);

  /// Screen entry in model tests: the record the screen is opened with (`item.id`
  /// of the list row), plus a data reader.
  ScreenScopeRequest entry({
    String? itemId,
    Map<String, Object?> data = const {},
  }) => (
    params: const {},
    record: itemId == null ? null : {kRecordIdPath: itemId},
    read: (path) => path == kRecordIdPath && itemId != null ? itemId : data[path],
  );

  /// Document data - one for all screens, as before 8.1.0.
  const Map<String, Object?> documentData = {
    'campaign.title': 'Autumn rewards',
    'item.name': 'Gift card',
  };

  /// List records as the host gives them in `data`: ONE collection from which
  /// `Repeater` draws rows.
  const List<Map<String, Object?>> rows = [
    {'id': 'headphones', 'name': 'Wireless headphones'},
    {'id': 'backpack', 'name': 'Travel backpack'},
  ];

  /// A "list -> details" document: rows are instances of ONE template with an identical
  /// `navigate` action (identical `params` everywhere), and only the record tells them apart.
  ///
  /// A function, not a ready object: `ScreenFlow` resets the stack only on a NEW document
  /// (`identical`), so two openings in a row in one test must start from different
  /// instances - otherwise the second tap would happen on the details screen already.
  UiDocument listToDetails() => docWithScreens(
    initialScreenId: 'list',
    [
      screenEntry('list', [
        {
          'id': 'rows',
          'type': 'Repeater',
          'props': {'source': 'rows', 'item': 'item', 'direction': 'column', 'gap': 'none'},
          'children': [
            {
              'id': 'row',
              'type': 'ListTile',
              'props': {
                'leading': {'kind': 'none'},
                'title': {'kind': 'binding', 'path': 'item.name', 'fallback': 'Reward'},
                'trailing': {'kind': 'none'},
                'action': {
                  'type': 'navigate',
                  'params': {'screenId': 'details'},
                },
              },
            },
          ],
        },
      ]),
      screenEntry('details', [
        textNode('—', id: 'title', extra: {
          'content': {'kind': 'binding', 'path': 'task.title', 'fallback': 'Задача місяця'},
        }),
        textNode('—', id: 'name', extra: {
          'content': {'kind': 'binding', 'path': 'item.name', 'fallback': 'Нагорода місяця'},
        }),
        textNode('—', id: 'progress', extra: {
          'content': {'kind': 'binding', 'path': 'task.description', 'fallback': '0 / 0'},
        }),
      ]),
    ],
  );

  /// Document data plus the row collection.
  Map<String, Object?> listData([List<Map<String, Object?>> records = rows]) => {
    ...documentData,
    'rows': records,
  };

  group('data scope layers', () {
    test('params.* is not data: there is no special prefix (9.2.0)', () {
      // Before 9.2.0 this was a private renderer path. The contract does not allow it
      // (`navigateParams: 'for-host-not-data'`), so `params.itemId` is an ordinary
      // path with no value, and only what lies in the layers under that key remains.
      expect(const ScreenData.scoped(document: documentData).lookup('params.itemId'), isNull);
      expect(
        const ScreenData.scoped(document: {'params.itemId': 'x'}).lookup('params.itemId'),
        'x',
        reason: 'like any document key: there is no special channel in either direction',
      );
    });

    test('a record beats the host scope and the document data; the rest it reads from them', () {
      final data = ScreenData.scoped(
        document: documentData,
        record: const {'item.name': 'Row name'},
        scope: catalog.scopeFor(entry(itemId: 'backpack')),
      );

      expect(data.lookup('item.name'), 'Row name');
      expect(data.lookup('task.target'), 20);
      expect(data.lookup('campaign.title'), 'Autumn rewards');
    });

    test('the screen scope beats the document data but does not hide it', () {
      final data = ScreenData.scoped(
        document: documentData,
        scope: catalog.scopeFor(entry(itemId: 'backpack')),
      );

      // The entity of this screen.
      expect(data.lookup('item.name'), 'Travel backpack');
      expect(data.lookup('task.target'), 20);
      // A document value absent from the scope stays available.
      expect(data.lookup('campaign.title'), 'Autumn rewards');
    });

    test('without a scope the screen sees exactly what it saw before 8.1.0', () {
      const scoped = ScreenData.scoped(document: documentData);
      const plain = ScreenData(documentData);

      for (final path in ['item.name', 'campaign.title', 'task.title']) {
        expect(scoped.lookup(path), plain.lookup(path), reason: path);
      }
    });

    test('task.* is shorthand for item.task.*', () {
      final data = ScreenData.scoped(
        scope: catalog.scopeFor(entry(itemId: 'headphones')),
      );

      expect(data.lookup('task.progress'), data.lookup('item.task.progress'));
      expect(data.lookup('task.progress'), 3);
    });
  });

  group('on screen', () {
    testWidgets('two different rows of ONE list give two different tasks', (tester) async {
      Future<void> openDetails(String row) async {
        // Every opening starts from scratch: a new copy of the same document does not
        // reset the stack (9.8.0), so we remove the previous flow ourselves.
        await tester.pumpWidget(const SizedBox());
        await pumpDocument(
          tester,
          listToDetails(),
          data: listData(),
          scopeFor: catalog.scopeFor,
        );
        await tester.tap(find.text(row));
        await tester.pumpAndSettle();
      }

      await openDetails('Wireless headphones');
      expect(find.text('Make 5 card payments'), findsOneWidget);
      expect(find.text('Wireless headphones'), findsOneWidget);
      expect(find.text('Any amount, any merchant'), findsOneWidget);

      await openDetails('Travel backpack');
      expect(find.text('Set up a recurring payment'), findsOneWidget);
      expect(find.text('Travel backpack'), findsOneWidget);
      expect(find.text('Any bill, any amount'), findsOneWidget);
      // The most important assertion of the group: the previous task did not "stick" on screen.
      expect(find.text('Make 5 card payments'), findsNothing);
      expect(find.text('Any amount, any merchant'), findsNothing);
    });

    testWidgets('no catalog - the screen is whole, with the document fallback in it', (tester) async {
      // The "network did not answer" scenario: `CollectionCatalog.empty` is exactly what
      // the source returns on any failure.
      await pumpDocument(
        tester,
        listToDetails(),
        data: listData(),
        scopeFor: CollectionCatalog.empty.scopeFor,
      );
      await tester.tap(find.text('Wireless headphones'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // The task has nowhere to come from - the document `fallback` works.
      expect(find.text('Задача місяця'), findsOneWidget);
      expect(find.text('0 / 0'), findsOneWidget);
      // The title comes from the ROW RECORD (the list row carries it itself, no catalog
      // needed), not from the document sample `Gift card`.
      expect(find.text('Wireless headphones'), findsOneWidget);
      expect(find.text('Gift card'), findsNothing);
      // Neither an empty screen nor an indicator: both are forbidden by the display
      // policy - see `DocumentSource.seed`.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(Text), findsWidgets);
    });

    testWidgets('a record that is not in the catalog - also a fallback', (tester) async {
      await pumpDocument(
        tester,
        listToDetails(),
        data: listData(const [
          {'id': 'ніякого-такого', 'name': 'Невідома нагорода'},
        ]),
        scopeFor: catalog.scopeFor,
      );
      await tester.tap(find.text('Невідома нагорода'));
      await tester.pumpAndSettle();

      expect(find.text('Задача місяця'), findsOneWidget);
    });

    testWidgets('a transition outside a list draws the same as before 8.1.0', (tester) async {
      // The same document, the same screen, but the button is outside the list and
      // carries no record.
      // If anything changes here, it changes in already built documents too,
      // which use no new features - and that must not happen.
      final plain = docWithScreens(
        initialScreenId: 'list',
        [
          screenEntry('list', [
            buttonNode('Далі', action: {
              'type': 'navigate',
              'params': {'screenId': 'details'},
            }),
          ]),
          screenEntry('details', [
            textNode('—', id: 'name', extra: {
              'content': {'kind': 'binding', 'path': 'item.name', 'fallback': 'Нагорода місяця'},
            }),
          ]),
        ],
      );

      await pumpDocument(tester, plain, data: documentData, scopeFor: catalog.scopeFor);
      await tester.tap(find.text('Далі'));
      await tester.pumpAndSettle();

      // A value from the DOCUMENT dictionary, not from the catalog: there is no record,
      // hence no scope.
      expect(find.text('Gift card'), findsOneWidget);
    });
  });

  group('types are not lost on the way', () {
    testWidgets('ProgressBar takes NUMBERS from the catalog, not strings', (tester) async {
      // `value` and `max` are bound to `task.progress` / `task.target`.
      // If the adapter "normalised" them into strings, the bar would show the fallback and
      // nobody would notice: 0 looks like "not started yet".
      await pumpDocument(
        tester,
        docWithScreens(
          initialScreenId: 'list',
          [
            screenEntry('list', [
              {
                'id': 'rows',
                'type': 'Repeater',
                'props': {'source': 'rows', 'item': 'item', 'direction': 'column', 'gap': 'none'},
                'children': [
                  buttonNode('Далі', action: const {
                    'type': 'navigate',
                    'params': {'screenId': 'details'},
                  }),
                ],
              },
            ]),
            screenEntry('details', [
              {
                'id': 'bar',
                'type': 'ProgressBar',
                'props': {
                  'value': {'kind': 'binding', 'path': 'task.progress', 'fallback': 0},
                  'max': {'kind': 'binding', 'path': 'task.target', 'fallback': 1},
                  'color': 'primary',
                  'labelFormat': 'valueOfMax',
                },
              },
            ]),
          ],
        ),
        data: listData(const [
          {'id': 'backpack'},
        ]),
        scopeFor: catalog.scopeFor,
      );
      await tester.tap(find.text('Далі'));
      await tester.pumpAndSettle();

      expect(tester.widget<ProgressTrack>(find.byType(ProgressTrack)).ratio,
          closeTo(14 / 20, 0.001));
      // The caption has no `.0` tail either: the number stayed a number all the way.
      expect(find.text('14 / 20'), findsOneWidget);
    });
  });

  group('a radio choice leads to the details of the chosen one', () {
    /// A catalog document in miniature: a choice group bound to
    /// `item.selectedId`, and a button with a plain `navigate` WITHOUT parameters.
    UiDocument chooseAndConfirm() => docWithScreens(
      initialScreenId: 'list',
      [
        screenEntry('list', [
          choiceGroupNode(
            [
              optionNode('Wireless headphones', optionValue: 'headphones'),
              optionNode('Travel backpack', optionValue: 'backpack'),
            ],
            value: const {
              'kind': 'binding',
              'path': 'item.selectedId',
              'fallback': 'gift-card',
            },
          ),
          buttonNode('Підтвердити вибір', action: const {
            'type': 'navigate',
            'params': {'screenId': 'details'},
          }),
        ]),
        screenEntry('details', [
          textNode('—', id: 'title', extra: {
            'content': {'kind': 'binding', 'path': 'task.title', 'fallback': 'Задача місяця'},
          }),
          textNode('—', id: 'name', extra: {
            'content': {'kind': 'binding', 'path': 'item.name', 'fallback': 'Нагорода місяця'},
          }),
          buttonNode('Назад', id: 'back', action: const {'type': 'navigate.back'}),
        ]),
      ],
    );

    testWidgets('tap the radio, confirm - you see ITS task', (tester) async {
      await pumpDocument(
        tester,
        chooseAndConfirm(),
        data: documentData,
        scopeFor: catalog.scopeFor,
      );

      await tester.tap(find.text('Travel backpack'));
      await tester.pump();
      await tester.tap(find.text('Підтвердити вибір'));
      await tester.pumpAndSettle();

      expect(find.text('Set up a recurring payment'), findsOneWidget);
      expect(find.text('Travel backpack'), findsOneWidget);
    });

    testWidgets('went back, chose another, went again - a new task', (tester) async {
      // The most important thing about the record: it lives as long as the screen stack.
      // If the choice died with the group node, the second pass would show the
      // document's initial value.
      final doc = chooseAndConfirm();
      await pumpDocument(tester, doc, data: documentData, scopeFor: catalog.scopeFor);

      await tester.tap(find.text('Travel backpack'));
      await tester.pump();
      await tester.tap(find.text('Підтвердити вибір'));
      await tester.pumpAndSettle();
      expect(find.text('Set up a recurring payment'), findsOneWidget);

      // Going back is `navigate.back`, i.e. the same mechanism as the
      // app bar arrow in the document.
      await tester.tap(find.text('Назад'));
      await tester.pumpAndSettle();
      // The choice is in place: the radio stayed where the finger put it.
      expect(find.text('Travel backpack'), findsOneWidget);

      await tester.tap(find.text('Wireless headphones'));
      await tester.pump();
      await tester.tap(find.text('Підтвердити вибір'));
      await tester.pumpAndSettle();

      expect(find.text('Make 5 card payments'), findsOneWidget);
      expect(find.text('Set up a recurring payment'), findsNothing);
    });

    testWidgets('nothing chosen - details show the record from the document', (tester) async {
      // The binding `fallback` is `gift-card`, and it is absent from the test catalog,
      // so the scope is empty and the document fallbacks work. This is exactly how the
      // document behaved before 8.1.0.
      await pumpDocument(
        tester,
        chooseAndConfirm(),
        data: documentData,
        scopeFor: catalog.scopeFor,
      );
      await tester.tap(find.text('Підтвердити вибір'));
      await tester.pumpAndSettle();

      expect(find.text('Задача місяця'), findsOneWidget);
      expect(find.text('Gift card'), findsOneWidget);
    });
  });

  group('reward-catalog-screens showcase: row, radio, "back" (9.2.0)', () {
    // A catalog from the network: records the host picks by identifier. The names
    // deliberately differ from the list rows (`sampleItems`) - they show WHERE the
    // details text comes from: the row record or the host scope.
    final shop = CollectionCatalog.parse('''
    { "items": [
      { "id": "backpack", "name": "Catalog backpack" },
      { "id": "coffee-set", "name": "Catalog coffee set" }
    ] }
    ''');

    Future<void> open(WidgetTester tester) => pumpDocument(
      tester,
      loadFixture('reward-catalog-screens'),
      data: sampleScreenData,
      scopeFor: shop.scopeFor,
    );

    Future<void> tapText(WidgetTester tester, String text) async {
      await tester.ensureVisible(find.text(text));
      await tester.pumpAndSettle();
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }

    testWidgets('the "Popular" row opens the details of ITS OWN product; "back" and another row - another one', (tester) async {
      await open(tester);

      await tapText(tester, 'Canvas backpack');
      // Title and description - from the row RECORD (they are not in the host catalog).
      expect(find.text('Canvas backpack'), findsOneWidget);
      expect(find.text('Fits a 15-inch laptop'), findsOneWidget);
      expect(find.text('Bluetooth speaker'), findsNothing);

      await tapText(tester, 'Back to catalog');
      await tapText(tester, 'Coffee grinder set');
      expect(find.text('Coffee grinder set'), findsOneWidget);
      expect(find.text('Two cups and a grinder'), findsOneWidget);
      expect(find.text('Canvas backpack'), findsNothing);
    });

    testWidgets('a radio on one product + a row of another - details of the row', (tester) async {
      await open(tester);

      await tapText(tester, 'Travel backpack'); // radio
      await tapText(tester, 'Coffee grinder set'); // list row

      // The record beats the session: the screen is about the product that was tapped.
      expect(find.text('Coffee grinder set'), findsOneWidget);
      expect(find.text('Catalog backpack'), findsNothing);
    });

    testWidgets('"Back to catalog" + another radio + "Confirm choice" - details of the chosen one', (tester) async {
      await open(tester);

      await tapText(tester, 'Canvas backpack'); // row -> details with a record
      await tapText(tester, 'Back to catalog'); // page WITHOUT a record
      await tapText(tester, 'Coffee set'); // radio
      await tapText(tester, 'Confirm choice');

      // No record: the entity is picked by the host by what is chosen in the session.
      expect(find.text('Catalog coffee set'), findsOneWidget);
      expect(find.text('Canvas backpack'), findsNothing);
    });
  });

  group('binding image source', () {
    ImageSource sourceOf(Map<String, Object?> raw) => ImageSource.parse(raw);

    test('the address comes from data', () {
      final resolved = sourceOf({
        'kind': 'binding',
        'path': 'item.image',
        'fallback': 'placeholder',
      }).resolve(
        ScreenData.scoped(
          scope: catalog.scopeFor(entry(itemId: 'backpack')),
        ),
      );

      expect((resolved as ImageUrl).url, 'https://cdn.example.com/items/backpack.png');
    });

    test('no data - the fallback is an asset TOKEN, not an address', () {
      final resolved = sourceOf({
        'kind': 'binding',
        'path': 'item.image',
        'fallback': 'banner',
      }).resolve(ScreenData.empty);

      // There is no fallback address - which is why the fallback here is of a different type than
      // the value, and the `ResolvedImage` union does not let one forget it.
      expect(resolved, isA<ImageAsset>());
      expect((resolved as ImageAsset).asset.wire, 'banner');
    });
  });
}
