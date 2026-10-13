import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';

import 'support/fixtures.dart';

/// NAMED ENTRY POINTS (8.10.0): `screenId` is local to a document, so a deep link
/// cannot be expressed; from outside a screen is not addressable, because the
/// pair "document + screen" is not a concept of the
/// contract.
///
/// The main thing checked here is the behaviour with a NAME THAT DOES NOT EXIST. An entry name
/// outlives the document: it has already gone out in a push and a banner and will come back
/// a week later, when the document has been updated.
void main() {
  UiDocument twoScreens({Map<String, String>? entryPoints}) => UiDocument.fromJson({
    'schemaVersion': UiDocument.supportedSchemaVersion,
    'documentId': 'flow',
    'name': 'Потік',
    'initialScreenId': 'home',
    'entryPoints': ?entryPoints,
    'screens': [
      screenEntry('home', [textNode('Головна', id: 'home-text')]),
      screenEntry('rewards', [textNode('Нагороди', id: 'rewards-text')]),
    ],
  });

  group('model', () {
    test('entries are parsed into a map', () {
      final doc = twoScreens(entryPoints: {'rewards': 'rewards'});

      expect(doc.entryPoints, {'rewards': 'rewards'});
      expect(doc.screenByEntry('rewards')?.screenId, 'rewards');
    });

    test('a document without entries has an empty map, not null', () {
      // An empty map is the most common case and no poorer: a document without entries
      // opens from the start screen, as it always did.
      expect(twoScreens().entryPoints, isEmpty);
    });

    test('broken pairs are skipped silently instead of breaking the document', () {
      // The builder will not emit this, but the document comes from the network. An entry
      // is addressing, not content: a document with one broken entry is better
      // opened from the start screen than not opened at all.
      final doc = UiDocument.fromJson({
        'schemaVersion': UiDocument.supportedSchemaVersion,
        'documentId': 'flow',
        'name': 'Потік',
        'initialScreenId': 'home',
        'entryPoints': {'rewards': 42, '': 'home', 'ok': 'rewards'},
        'screens': [
          screenEntry('home', [textNode('Головна', id: 'home-text')]),
          screenEntry('rewards', [textNode('Нагороди', id: 'rewards-text')]),
        ],
      });

      expect(doc.entryPoints, {'ok': 'rewards'});
    });
  });

  group('which screen opens', () {
    test('an entry is named - its screen opens', () {
      final doc = twoScreens(entryPoints: {'rewards': 'rewards'});

      expect(doc.screenForEntry('rewards').screenId, 'rewards');
    });

    test('nothing named - the start screen', () {
      expect(twoScreens(entryPoints: {'rewards': 'rewards'}).screenForEntry(null).screenId, 'home');
    });

    /*
     * `unknownEntryPoint: 'use-initial'` from the contract policy. Showing the
     * start screen is better than an empty window: the user is not at fault -
     * the name went stale, not them.
     */
    test('a name that does not exist gives the start screen, not emptiness', () {
      final doc = twoScreens(entryPoints: {'rewards': 'rewards'});

      expect(doc.screenForEntry('promo-2024').screenId, 'home');
    });

    test('an entry pointing to a screen that does not exist is also the start screen', () {
      // The document was updated, the screen removed, and the map not cleaned. The builder
      // catches this (`unknown_screen_ref`), but a document outlives validation.
      final doc = twoScreens(entryPoints: {'rewards': 'no-such-screen'});

      expect(doc.screenForEntry('rewards').screenId, 'home');
    });
  });

  group('render', () {
    testWidgets('the document opens from the named entry', (tester) async {
      await pumpDocument(tester, twoScreens(entryPoints: {'rewards': 'rewards'}), entry: 'rewards');

      expect(find.text('Нагороди'), findsOneWidget);
      expect(find.text('Головна'), findsNothing);
    });

    testWidgets('without an entry - the start screen, as always', (tester) async {
      await pumpDocument(tester, twoScreens(entryPoints: {'rewards': 'rewards'}));

      expect(find.text('Головна'), findsOneWidget);
    });

    testWidgets('changing the entry restarts the flow', (tester) async {
      // The host changes the entry when the user arrived through a different link. Keeping
      // the old history would mean "back" into someone else's flow.
      final doc = twoScreens(entryPoints: {'rewards': 'rewards'});

      await pumpDocument(tester, doc);
      expect(find.text('Головна'), findsOneWidget);

      await pumpDocument(tester, doc, entry: 'rewards');
      expect(find.text('Нагороди'), findsOneWidget);
    });
  });
}
