import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_demo/collection_source.dart';

import 'package:hotlayout_flutter/src/render/render_document.dart';

import '../../test/support/network.dart';

/// Screen entry in tests: the record the screen was opened with, plus a data reader.
///
/// [itemId] is the `item.id` of a list row's record (since 9.2.0 the renderer hands the record
/// to the host itself, not as a transition parameter).
ScreenScopeRequest entry({
  String? itemId,
  Map<String, Object?> data = const {},
}) => (
  params: const {},
  record: itemId == null ? null : {kRecordIdPath: itemId},
  read: (path) => path == kRecordIdPath && itemId != null ? itemId : data[path],
);

/// Collection source - what fills the screen scope.
///
/// The one main property guarded here: **it cannot break the presentation**.
/// No network, a timeout, 403, garbage instead of JSON - all of these yield an empty
/// catalog, i.e. a screen with the document's `fallback`. It is the same policy as for
/// the document (fall back instead of failing), except that the floor here is the document
/// itself: it always has something to show without data.
void main() {
  const String catalogJson = '''
  { "items": [
    { "id": "backpack", "name": "Travel backpack",
      "image": "https://cdn.example.com/items/backpack.png",
      "description": "Fits a 15-inch laptop", "price": 3200,
      "task": { "title": "Set up a recurring payment",
                "description": "Any bill, any amount",
                "progress": 14, "target": 20, "status": "inProgress" } }
  ] }
  ''';

  CollectionSource sourceOn(FakeDocumentTransport transport) => CollectionSource(
    url: Uri.parse('https://example.com/items.json'),
    transport: transport,
    timeout: const Duration(milliseconds: 50),
  );

  group('parsing', () {
    test('a catalog record becomes a data scope with two entries', () {
      final scope = CollectionCatalog.parse(catalogJson).scopeFor(entry(itemId: 'backpack'));

      // The record itself - under the prefix of its entity…
      expect((scope['item']! as Map)['name'], 'Travel backpack');
      // …and the nested entity under ITS OWN name, i.e. as a synonym of the path.
      expect((scope['task']! as Map)['target'], 20);
    });

    test('numbers stay numbers and are not turned into strings', () {
      // `ProgressBar.value` and `max` are numbers. The string "14" would be a type
      // error there, not a value: the adapter carries values verbatim and
      // "normalizes" nothing.
      final task =
          CollectionCatalog.parse(catalogJson).scopeFor(entry(itemId: 'backpack'))['task']!
              as Map;

      expect(task['progress'], isA<num>());
      expect(task['target'], isA<num>());
      expect(task['progress'], 14);
      expect(task['target'], 20);
      expect(task['status'], 'inProgress');
      expect(task['description'], 'Any bill, any amount');
    });

    test('record absent or unknown gives an empty scope', () {
      final catalog = CollectionCatalog.parse(catalogJson);

      expect(catalog.scopeFor(entry()), isEmpty);
      expect(catalog.scopeFor(entry(itemId: '')), isEmpty);
      expect(catalog.scopeFor(entry(itemId: 'нема-такого')), isEmpty);
    });

    test('record is taken from item.selectedId when the screen is opened without one', () {
      // The second interaction: a radio plus a button without parameters. This is how
      // the catalog screen in the fixture is built.
      final catalog = CollectionCatalog.parse(catalogJson);
      final scope = catalog.scopeFor(
        entry(data: const {'item.selectedId': 'backpack'}),
      );

      expect((scope['item']! as Map)['name'], 'Travel backpack');
    });

    test('row record is stronger than the selection', () {
      // Rule order: the row's record beats what is left from a selection.
      // Otherwise a tap on a list row would show not the record that was tapped.
      final catalog = CollectionCatalog.parse('''
      { "items": [ {"id": "a", "name": "A"}, {"id": "b", "name": "B"} ] }
      ''');
      final scope = catalog.scopeFor(
        entry(itemId: 'a', data: const {'item.selectedId': 'b'}),
      );

      expect((scope['item']! as Map)['name'], 'A');
    });

    test('garbage, non-JSON and a foreign shape give an empty catalog, not an exception', () {
      for (final source in ['<html>404</html>', '[]', '{}', '{"items": 7}', '']) {
        expect(CollectionCatalog.parse(source).isEmpty, isTrue, reason: source);
      }
    });

    test('a record without id is skipped, the rest stay', () {
      final catalog = CollectionCatalog.parse('''
      { "items": [ {"name": "Без id"}, {"id": "ok", "name": "Ок"} ] }
      ''');

      expect(catalog.length, 1);
      expect(catalog.contains('ok'), isTrue);
    });
  });

  group('reading', () {
    test('200 with a body gives a catalog', () async {
      final catalog = await sourceOn(FakeDocumentTransport.replying(200, catalogJson)).load();

      expect(catalog.length, 1);
      expect(catalog.contains('backpack'), isTrue);
    });

    test('network did not answer: empty catalog, not an exception', () async {
      final catalog = await sourceOn(FakeDocumentTransport.silent()).load();

      expect(catalog.isEmpty, isTrue);
    });

    test('request did not happen: empty catalog', () async {
      final catalog = await sourceOn(
        FakeDocumentTransport.failing(const SocketExceptionStub()),
      ).load();

      expect(catalog.isEmpty, isTrue);
    });

    test('non-200 response code gives an empty catalog', () async {
      for (final code in [403, 404, 500]) {
        final catalog = await sourceOn(FakeDocumentTransport.replying(code, '')).load();
        expect(catalog.isEmpty, isTrue, reason: '$code');
      }
    });
  });
}

/// A failure of the "no connection" kind. Its own type rather than `SocketException`, so the test does not
/// pull in `dart:io`: the code under test catches any `Object`, and that
/// is the rule being verified here.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();

  @override
  String toString() => 'немає зв\'язку';
}
