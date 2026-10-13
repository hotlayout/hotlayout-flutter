import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hotlayout_demo/main.dart';
import 'package:hotlayout_demo/collection_source.dart';
import 'package:hotlayout_flutter/src/data/document_source.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/theme_contract.dart';
import 'package:hotlayout_flutter/src/render/icon_glyph.dart';

/// Screen data scope - **on a real device, in a real app**.
///
/// Widget tests prove the layer mechanics on a model; here the same scenario
/// goes through the whole app: document -> renderer -> gesture -> host
/// catalog.
///
/// **WHAT IS NOT CHECKED HERE.** There is no assertion that a bound address turns into a
/// PAINTED pixel (`RawImage`, not a placeholder): `flutter test` cannot check that by
/// construction, since every `Image.network` there gets 400, and the product has no
/// media delivery of its own yet. Add that assertion here once our media storage exists.
///
/// The catalog is supplied by a local transport: what is verified is how records are LAID OUT
/// across screens, not the pipe. The pipe is guarded by `collection_source_test.dart`.
///
/// Run:
/// ```
/// flutter test integration_test/item_scope_test.dart -d <simulator udid>
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Catalog records - the same identifiers as the options in the document below.
  const List<(String, String)> items = [
    ('headphones', 'Wireless headphones'),
    ('backpack', 'Travel backpack'),
    ('coffee-set', 'Coffee set'),
  ];

  /// The catalog in the same shape storage returns it in.
  const String catalogJson = '''
  { "items": [
    { "id": "headphones", "name": "Wireless headphones",
      "task": { "title": "Make 5 card payments",
                "description": "Any amount, any merchant",
                "progress": 3, "target": 5 } },
    { "id": "backpack", "name": "Travel backpack",
      "task": { "title": "Set up a recurring payment",
                "description": "Any bill, any amount",
                "progress": 14, "target": 20 } },
    { "id": "coffee-set", "name": "Coffee set",
      "task": { "title": "Invite a friend",
                "description": "One invite is enough",
                "progress": 2, "target": 3 } }
  ] }
  ''';

  Map<String, Object?> bound(String path, Object fallback) => {
    'kind': 'binding',
    'path': path,
    'fallback': fallback,
  };

  Map<String, Object?> boundText(String id, String path, String fallback) => {
    'id': id,
    'type': 'Text',
    'props': {
      'content': bound(path, fallback),
      'typography': 'bodyM',
      'color': 'onSurface',
      'align': 'start',
      'overflow': 'ellipsis',
    },
  };

  /// An option row: the choice is marked with a radio.
  Map<String, Object?> row(String id, String name) => {
    'id': 'row-$id',
    'type': 'ListTile',
    'props': {
      'leading': {'kind': 'icon', 'icon': 'gift'},
      'title': {'kind': 'literal', 'value': name},
      'trailing': {'kind': 'radio', 'optionValue': id},
    },
  };

  final documentJson = jsonEncode({
    'schemaVersion': '8.0.0',
    'documentId': 'reward-catalog',
    'name': 'Каталог нагород — вхід екрана',
    'initialScreenId': 'list',
    'screens': [
      {
        'screenId': 'list',
        'name': 'Вибір нагороди',
        'root': {
          'id': 'list-root',
          'type': 'Screen',
          'props': {
            'background': {'kind': 'color', 'color': 'secondary'},
            'padding': 'none',
          },
          'children': [
            {
              'id': 'list-bar',
              'type': 'AppBar',
              'props': {
                'title': {'kind': 'literal', 'value': 'Rewards'},
                'showBack': false,
                'background': {'kind': 'color', 'color': 'surface'},
              },
            },
            {
              'id': 'list-column',
              'type': 'Column',
              'props': {'gap': 'sm', 'padding': 'md', 'align': 'start'},
              'children': [
                {
                  'id': 'item-choice',
                  'type': 'ChoiceGroup',
                  // The bound `value` is both read and write: a tap puts the record's `id`
                  // into this very path, and the details screen takes the record from there.
                  'props': {
                    'value': bound(kSelectedItemPath, 'headphones'),
                    'gap': 'none',
                    'padding': 'none',
                  },
                  'children': [for (final (id, name) in items) row(id, name)],
                },
                {
                  'id': 'confirm',
                  'type': 'Button',
                  // A transition WITHOUT parameters: which record to open is told by
                  // `item.selectedId`, not by the button.
                  'props': {
                    'label': {'kind': 'literal', 'value': 'Confirm choice'},
                    'variant': 'primary',
                    'action': {
                      'type': 'navigate',
                      'params': {'screenId': 'details'},
                    },
                    'fullWidth': true,
                  },
                },
              ],
            },
          ],
        },
      },
      {
        'screenId': 'details',
        'name': 'Задача нагороди',
        'root': {
          'id': 'details-root',
          'type': 'Screen',
          'props': {
            'background': {'kind': 'color', 'color': 'secondary'},
            'padding': 'none',
          },
          'children': [
            {
              'id': 'details-bar',
              'type': 'AppBar',
              'props': {
                'title': {'kind': 'literal', 'value': 'Rewards'},
                'showBack': true,
                'background': {'kind': 'color', 'color': 'surface'},
              },
            },
            {
              'id': 'details-column',
              'type': 'Column',
              'props': {'gap': 'sm', 'padding': 'md', 'align': 'start'},
              'children': [
                boundText('details-name', 'item.name', 'Нагорода місяця'),
                boundText('details-title', 'task.title', 'Задача місяця'),
                boundText('details-description', 'task.description', 'Умови задачі'),
                {
                  'id': 'details-progress',
                  'type': 'ProgressBar',
                  // Numbers must arrive as numbers: a string in `value` would give
                  // the fallback, and zero on a bar reads as "not started yet".
                  'props': {
                    'value': bound('task.progress', 0),
                    'max': bound('task.target', 1),
                    'color': 'primary',
                    'labelFormat': 'valueOfMax',
                  },
                },
              ],
            },
          ],
        },
      },
    ],
  });

  testWidgets('a tap on a record opens ITS task and ITS numbers', (tester) async {
    await tester.pumpWidget(
      HotlayoutDemoApp(
        themeLoad: await ThemeLoad.fromBundle(assetPath: kThemeContractAsset),
        // The document is its own, the catalog is its own, there is no network at all: the test is
        // green without internet, and that is a property, not luck.
        sources: [_InlineDocumentSource(documentJson)],
        collection: CollectionSource(
          url: Uri.parse('inline:items.json'),
          transport: const _InlineTransport(catalogJson),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // --- list: three rows, a mark on the one that arrived by binding
    expect(find.byType(ChoiceOptionMark), findsNWidgets(items.length));

    Future<void> openAndReturn(
      String name, {
      required String task,
      required String progress,
      required double fraction,
    }) async {
      // User interaction: a radio, then "Confirm choice".
      await tester.ensureVisible(find.text(name));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Confirm choice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm choice'));
      await tester.pumpAndSettle();

      // The task is exactly this record's.
      expect(find.text(task), findsOneWidget, reason: '$name: foreign task');
      expect(find.text(progress), findsOneWidget, reason: '$name: foreign numbers');
      // The title too, and it came from the catalog, not from the document.
      expect(find.text(name), findsOneWidget);
      expect(find.text('Нагорода місяця'), findsNothing, reason: '$name: scope did not arrive');
      // The progress bar is proof that the numbers arrived as numbers.
      expect(
        tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value,
        closeTo(fraction, 0.001),
        reason: '$name: progress not from data',
      );

      await tester.tap(find.byKey(kAppBarBackGlyphKey));
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceOptionMark), findsNWidgets(items.length), reason: 'returning to the list');
    }

    // The main claim of the whole work: one details screen, different entities.
    await openAndReturn(
      'Travel backpack',
      task: 'Set up a recurring payment',
      progress: '14 / 20',
      fraction: 14 / 20,
    );
    await openAndReturn(
      'Coffee set',
      task: 'Invite a friend',
      progress: '2 / 3',
      fraction: 2 / 3,
    );
    await openAndReturn(
      'Wireless headphones',
      task: 'Make 5 card payments',
      progress: '3 / 5',
      fraction: 3 / 5,
    );

    expect(tester.takeException(), isNull);
  });
}

/// A transport that returns a known body in advance. There is no network in this test.
final class _InlineTransport implements DocumentTransport {
  const _InlineTransport(this.body);

  final String body;

  @override
  Future<DocumentResponse> fetch(Uri url) async => (statusCode: 200, body: body);
}

/// A document baked into the test. No network is needed for it: we check the DATA, while
/// document delivery is guarded by `document_source_test.dart`.
final class _InlineDocumentSource implements DocumentSource {
  const _InlineDocumentSource(this.source);

  final String source;

  @override
  String get title => 'Документ тесту';

  @override
  bool get isRefreshable => false;

  @override
  DocumentSource? get seed => null;

  @override
  Future<DocumentLoad> load() async => DocumentLoad(
    document: UiDocument.fromJsonString(source),
    status: DocumentLoadStatus.bundled,
    detail: 'inline',
    receivedAt: DateTime.now(),
    signature: documentSignature(source),
  );
}
