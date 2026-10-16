/// LIVE DATA AND NEW VERSIONS: what a running app hands the flow while the user
/// is in the middle of it.
///
/// A live app does three things the fixtures never do: its data arrives from a
/// stream and changes under an open screen, a new version of the document is
/// published while the user is three screens deep, and the theme is republished
/// too. None of this may throw the user back to the first screen, and none of
/// it is a "screen shown" event, except when the screen the user is on no
/// longer exists.
///
/// The rules are those of `@hotlayout/react`: the stack belongs to the
/// `documentId` and the entry, not to the document object; a new version that
/// keeps every screen of the stack changes nothing but the content; one that
/// lost a screen of the stack starts the flow again from its entry
/// (`stackScreenGone: 'restart-from-entry'`). The session of the reader lives
/// as long as the flow (`documentId` and entry), and an entry of it yields as
/// soon as the host's data at the same path changes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/action.dart';
import 'package:hotlayout_flutter/src/model/action_catalog.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';
import 'package:hotlayout_flutter/src/theme/theme_contract.dart';

import 'support/fixtures.dart';
import 'support/inputs.dart';

Json _navigate(String screenId) => {
  'type': ButtonAction.navigate,
  'params': {ButtonAction.screenIdParam: screenId},
};

Json _boundText(String id, String path, {String fallback = '—'}) => {
  'id': id,
  'type': 'Text',
  'props': {
    'content': {'kind': 'binding', 'path': path, 'fallback': fallback},
  },
};

/// Three screens: a home with the balance, a details page with a switch and a
/// name field, and a modal sheet. [detailsTitle] changes between versions;
/// [withDetails] `false` is a version that dropped the details page.
UiDocument _orbit({
  String documentId = 'orbit',
  String detailsTitle = 'Details v1',
  bool withDetails = true,
  String homeTitle = 'Home',
}) => docWithScreens([
  screenEntry('home', [
    textNode(homeTitle, id: 'home-title'),
    _boundText('balance', 'user.points'),
    buttonNode('Open details', action: _navigate('details'), id: 'to-details'),
  ]),
  if (withDetails)
    screenEntry('details', [
      textNode(detailsTitle, id: 'details-title'),
      _boundText('details-balance', 'user.points'),
      toggleNode('Switch', id: 'push', label: 'Push', path: 'settings.push'),
      {
        ...plainText('push-on', 'Push is on'),
        'visibleIf': {'path': 'settings.push', 'op': 'isTrue'},
      },
      textFieldNode(id: 'nick', label: 'Nickname', path: 'form.nick'),
      buttonNode('Open sheet', action: _navigate('sheet'), id: 'to-sheet'),
    ]),
  screenEntry('sheet', [textNode('Sheet', id: 'sheet-title')], presentation: 'modal'),
], initialScreenId: 'home', documentId: documentId);

/// What the host holds and changes: the document, the theme and the data.
class _Host {
  _Host({required this.document, required this.data, RenderTheme? theme}) : theme = theme ?? RenderTheme.fallback();

  UiDocument document;
  RenderTheme theme;
  Map<String, Object?> data;
  String? entry;

  final shown = <ScreenShown>[];
  final writes = <(String, Object)>[];
  final controller = ScreenFlowController();
  StateSetter? _setState;

  Future<void> pump(WidgetTester tester) async {
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              _setState = setState;
              return renderDocument(
                document,
                theme: theme,
                data: data,
                entry: entry,
                controller: controller,
                onScreenShown: shown.add,
                onWrite: (path, value) => writes.add((path, value)),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The host's `setState`: one rebuild with the new inputs, as a stream listener would do.
  Future<void> update(WidgetTester tester, void Function() change) async {
    _setState!(change);
    await tester.pumpAndSettle();
  }
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  group('new data (a stream of the host)', () {
    testWidgets('the open screen shows the new value; the stack, the session and the field stay; no show event', (tester) async {
      final host = _Host(document: _orbit(), data: {'user.points': 120});
      await host.pump(tester);
      await _tap(tester, 'Open details');
      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Ann');
      await tester.pumpAndSettle();
      final shownBefore = host.shown.length;

      await host.update(tester, () => host.data = {'user.points': 450});

      expect(find.text('450'), findsOneWidget);
      expect(find.text('Details v1'), findsOneWidget);
      expect(host.controller.currentScreenId, 'details');
      expect(host.controller.canGoBack, isTrue);
      expect(find.text('Push is on'), findsOneWidget, reason: 'the session is not reset by new data');
      expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, 'Ann');
      expect(host.shown, hasLength(shownBefore), reason: 'new data is not a show');
    });

    testWidgets('a nested map from a database works the same as a flat one', (tester) async {
      final host = _Host(document: _orbit(), data: {'user': {'points': 1}});
      await host.pump(tester);
      await _tap(tester, 'Open details');
      await host.update(tester, () => host.data = {'user': {'points': 2}});
      expect(find.text('2'), findsOneWidget);
      expect(host.controller.currentScreenId, 'details');
    });

    testWidgets('a session entry yields when the host changes the value at its path', (tester) async {
      final host = _Host(document: _orbit(), data: {'settings.push': false});
      await host.pump(tester);
      await _tap(tester, 'Open details');
      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();
      expect(find.text('Push is on'), findsOneWidget);

      // Another device turned push off on the server after this one turned it on: the data now
      // says something new about the path, and the screen follows the data.
      await host.update(tester, () => host.data = {'settings.push': true});
      await host.update(tester, () => host.data = {'settings.push': false});
      expect(find.text('Push is on'), findsNothing);
    });

    testWidgets('the host echoing the written value back changes nothing on the screen', (tester) async {
      final host = _Host(document: _orbit(), data: {'settings.push': false});
      await host.pump(tester);
      await _tap(tester, 'Open details');
      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();
      expect(host.writes.single, ('settings.push', true));

      await host.update(tester, () => host.data = {'settings.push': true});
      expect(find.text('Push is on'), findsOneWidget);
    });

    testWidgets('data that does not touch the written path leaves the session entry alone', (tester) async {
      final host = _Host(document: _orbit(), data: {'settings.push': false, 'user.points': 1});
      await host.pump(tester);
      await _tap(tester, 'Open details');
      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();

      await host.update(tester, () => host.data = {'settings.push': false, 'user.points': 2});
      expect(find.text('Push is on'), findsOneWidget);
    });

    testWidgets('a yielded entry does not come back when the data returns to the old value', (tester) async {
      final host = _Host(document: _orbit(), data: {'settings.push': false});
      await host.pump(tester);
      await _tap(tester, 'Open details');
      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();

      await host.update(tester, () => host.data = {});
      expect(find.text('Push is on'), findsNothing);
      await host.update(tester, () => host.data = {'settings.push': false});
      expect(find.text('Push is on'), findsNothing);
    });
  });

  group('a new version of the same document', () {
    testWidgets('keeps the stack when every screen of it is still there, and shows the new content', (tester) async {
      final host = _Host(document: _orbit(), data: const {});
      await host.pump(tester);
      await _tap(tester, 'Open details');
      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Ann');
      await tester.pumpAndSettle();
      final shownBefore = host.shown.length;

      await host.update(tester, () => host.document = _orbit(detailsTitle: 'Details v2'));

      expect(find.text('Details v2'), findsOneWidget);
      expect(find.text('Details v1'), findsNothing);
      expect(host.controller.currentScreenId, 'details');
      expect(find.text('Push is on'), findsOneWidget);
      expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, 'Ann');
      expect(host.shown, hasLength(shownBefore), reason: 'a new version that keeps the stack is not a show');

      // "Back" still leads to the home of the NEW version.
      await host.update(tester, () => host.document = _orbit(detailsTitle: 'Details v2', homeTitle: 'Home v2'));
      expect(host.controller.goBack(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Home v2'), findsOneWidget);
    });

    testWidgets('keeps a modal sheet open over the page it was opened from', (tester) async {
      final host = _Host(document: _orbit(), data: const {});
      await host.pump(tester);
      await _tap(tester, 'Open details');
      await _tap(tester, 'Open sheet');
      expect(host.controller.currentScreenId, 'sheet');

      await host.update(tester, () => host.document = _orbit(detailsTitle: 'Details v2'));
      expect(host.controller.currentScreenId, 'sheet');
      expect(find.text('Sheet'), findsOneWidget);
      expect(find.text('Details v2'), findsOneWidget, reason: 'the page under the sheet is the new version');
    });

    testWidgets('that lost a screen of the stack starts from the entry screen, with one `entry` show', (tester) async {
      final host = _Host(document: _orbit(), data: const {'settings.push': false});
      await host.pump(tester);
      await _tap(tester, 'Open details');
      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();
      final shownBefore = host.shown.length;

      await host.update(tester, () => host.document = _orbit(withDetails: false));

      expect(host.controller.currentScreenId, 'home');
      expect(host.controller.canGoBack, isFalse);
      expect(find.text('Home'), findsOneWidget);
      expect(host.shown, hasLength(shownBefore + 1));
      expect(host.shown.last.cause, ScreenShownCause.entry);
      expect(host.shown.last.depth, 1);

      // The flow is the same (`documentId` and entry), and so is the session: a version that
      // brings the details page back shows what the user had written.
      await host.update(tester, () => host.document = _orbit(detailsTitle: 'Details v3'));
      await _tap(tester, 'Open details');
      expect(find.text('Push is on'), findsOneWidget);
    });

    testWidgets('a different documentId is a new flow: stack and session start over', (tester) async {
      final host = _Host(document: _orbit(), data: const {'settings.push': false});
      await host.pump(tester);
      await _tap(tester, 'Open details');
      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();

      await host.update(tester, () => host.document = _orbit(documentId: 'other'));
      expect(host.controller.currentScreenId, 'home');
      expect(host.shown.last.cause, ScreenShownCause.entry);
      expect(host.shown.last.documentId, 'other');

      await _tap(tester, 'Open details');
      expect(find.text('Push is on'), findsNothing);
    });

    testWidgets('a re-parsed copy of the same JSON is nothing at all', (tester) async {
      final host = _Host(document: _orbit(), data: const {});
      await host.pump(tester);
      await _tap(tester, 'Open details');
      final shownBefore = host.shown.length;
      for (var i = 0; i < 3; i += 1) {
        await host.update(tester, () => host.document = _orbit());
      }
      expect(host.controller.currentScreenId, 'details');
      expect(host.shown, hasLength(shownBefore));
    });
  });

  group('a new theme', () {
    testWidgets('repaints the open screen and keeps the stack, the session and the field', (tester) async {
      final contract = ThemeContract.fallback();
      final light = contract.themeForBrightness(Brightness.light);
      final dark = contract.themeForBrightness(Brightness.dark);
      final host = _Host(document: _orbit(), data: const {}, theme: light);
      await host.pump(tester);
      await _tap(tester, 'Open details');
      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Ann');
      await tester.pumpAndSettle();
      final before = screenDecoration(tester).color;
      final shownBefore = host.shown.length;

      await host.update(tester, () => host.theme = dark);

      expect(screenDecoration(tester).color, isNot(before));
      expect(host.controller.currentScreenId, 'details');
      expect(find.text('Push is on'), findsOneWidget);
      expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, 'Ann');
      expect(host.shown, hasLength(shownBefore));
    });
  });
}
