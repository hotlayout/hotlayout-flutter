import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_demo/main.dart';
import 'package:hotlayout_flutter/src/data/document_source.dart';
import 'package:hotlayout_flutter/src/theme/theme_contract.dart';

import '../../test/support/fixtures.dart';
import '../../test/support/network.dart';

/// Refreshing the document without restarting the app.
///
/// This is the main presentation requirement: the manager changes a screen in the builder, presses
/// "Publish" and sees the change in an app that is already running. There are two ways,
/// and both are tested here: return from background (automatic) and a double tap
/// in the service corner (explicit).
void main() {
  /// The app with a replaced network. The source list has exactly one, a network one:
  /// the test is about refreshing, not about switching sources.
  Future<FakeDocumentTransport> pumpApp(
    WidgetTester tester, {
    String? body,
    int statusCode = 200,
    FakeDocumentTransport? network,
  }) async {
    final transport =
        network ?? FakeDocumentTransport.replying(statusCode, body ?? publishedDocumentJson());
    await tester.pumpWidget(
      HotlayoutDemoApp(
        // Theme and bundled copy come from disk, not from `rootBundle`: otherwise a second
        // test in this file would hang on real asynchronous input.
        themeLoad: ThemeLoad.parse(readThemeContract()),
        sources: [
          PublishedDocumentSource(
            url: Uri.parse('https://example.test/published.json?alt=media'),
            fallback: fixtureSource(
              'minimal-screen',
              title: 'Вбудований',
              bundle: diskAssetBundle(),
            ),
            transport: transport,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    return transport;
  }

  /// A double tap in the status bar strip is an explicit "re-read".
  Future<void> doubleTapCorner(WidgetTester tester) async {
    final corner = find.byKey(const ValueKey('demo-service-corner'));
    await tester.tap(corner);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(corner);
    await tester.pumpAndSettle();
  }

  testWidgets('a double tap shows what was just published', (tester) async {
    final transport = await pumpApp(tester, body: publishedDocumentJson(text: 'Було так'));
    expect(find.text('Було так'), findsOneWidget);
    expect(transport.requests, hasLength(1));

    // The manager pressed "Publish" - storage already holds a different document.
    transport.respond = (_) async =>
        (statusCode: 200, body: publishedDocumentJson(text: 'Стало інакше'));

    await doubleTapCorner(tester);

    expect(transport.requests, hasLength(2), reason: 'the gesture must go to the network again');
    expect(find.text('Стало інакше'), findsOneWidget);
    expect(find.text('Було так'), findsNothing);
    // An explicit gesture gets a visible answer: otherwise it is unclear whether it went to the
    // network at all. The notice lives three seconds and disappears by itself.
    expect(find.textContaining('From network'), findsOneWidget);
  });

  testWidgets('returning from background refreshes the document, silently', (tester) async {
    final transport = await pumpApp(tester, body: publishedDocumentJson(text: 'До паузи'));
    expect(find.text('До паузи'), findsOneWidget);

    transport.respond = (_) async =>
        (statusCode: 200, body: publishedDocumentJson(text: 'Після паузи'));

    // The app was minimized and restored.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(transport.requests, hasLength(2));
    expect(find.text('Після паузи'), findsOneWidget);
    // Automatic refresh draws nothing over the document: the viewer made no gesture,
    // and a notice would be scaffolding in the frame.
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('while the network is silent the screen shows the bundled copy, not emptiness', (tester) async {
    // The worst case of a presentation: Wi-Fi is up but there is no response. There must be neither an empty
    // screen nor an indicator nobody can stop.
    await pumpApp(tester, network: FakeDocumentTransport.silent());

    expect(find.text('Привіт'), findsOneWidget, reason: 'the bundled copy is drawn immediately');
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // We wait longer than the timeout: it must fire by itself and leave on screen
    // the same thing that is already shown.
    await tester.pump(kDocumentFetchTimeout + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Привіт'), findsOneWidget);

    await tester.longPress(find.byKey(const ValueKey('demo-service-corner')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Network timed out'), findsOneWidget);
  });

  testWidgets('a fallback is visible in the service panel, not only in the console', (tester) async {
    // 404 is the "not published yet" state, i.e. what there will be at the start of a presentation.
    await pumpApp(tester, statusCode: 404, body: '{"error":{"code":404}}');

    // The presentation continues: the bundled copy is on screen, not an error or emptiness.
    expect(find.text('Привіт'), findsOneWidget);

    await tester.longPress(find.byKey(const ValueKey('demo-service-corner')));
    await tester.pumpAndSettle();

    expect(find.text('Service panel'), findsOneWidget);
    expect(
      find.textContaining('Not published yet'),
      findsOneWidget,
      reason: 'a silent fallback would mean "pressed Publish - nothing changed"',
    );
  });

  /*
   * A LIVE PRESENTATION FAILURE, as it happened.
   *
   * The manager changes a screen in the builder, presses "Refresh" on the phone and sees
   * the old one. The request really happened, the response really arrived - but storage
   * held the previous version. The "From network" notice hid this: it reported
   * on the TRIP, while the question was about the CHANGE.
   */
  testWidgets('a refresh without changes says so plainly instead of reporting "From network"', (tester) async {
    final transport = await pumpApp(tester, body: publishedDocumentJson(text: 'Те саме'));
    expect(find.text('Те саме'), findsOneWidget);

    // Storage returns exactly what is already shown: nothing was published in the builder.
    await doubleTapCorner(tester);

    expect(transport.requests, hasLength(2), reason: 'the gesture must go to the network');
    expect(find.textContaining('unchanged'), findsOneWidget);
    expect(
      find.textContaining('updated'),
      findsNothing,
      reason: '"updated" on an unchanged document is the very lie that makes the phone look guilty',
    );
  });

  testWidgets('a refresh with changes says so', (tester) async {
    final transport = await pumpApp(tester, body: publishedDocumentJson(text: 'Було'));
    transport.respond = (_) async => (statusCode: 200, body: publishedDocumentJson(text: 'Стало'));

    await doubleTapCorner(tester);

    expect(find.textContaining('updated'), findsOneWidget);
    expect(find.textContaining('unchanged'), findsNothing);
  });

  /*
   * A CONDITION, NOT AN EVENT. The notice lives three seconds, a fallback lasts until the network
   * gives a document. The dot is the only host scaffolding visible without gestures,
   * and that is why it appears exactly when what is on screen is NOT what is in storage.
   */
  testWidgets('a fallback is permanently visible on screen, without gestures or the panel', (tester) async {
    await pumpApp(tester, statusCode: 404, body: '{"error":{"code":404}}');

    expect(find.byKey(const ValueKey('demo-fallback-dot')), findsOneWidget);
  });

  testWidgets('a document from the network leaves no scaffolding on screen', (tester) async {
    await pumpApp(tester, body: publishedDocumentJson(text: 'З мережі'));

    expect(find.byKey(const ValueKey('demo-fallback-dot')), findsNothing);
  });

  testWidgets('the dot disappears as soon as the network returns the document', (tester) async {
    final transport = await pumpApp(tester, statusCode: 404, body: '{"error":{"code":404}}');
    expect(find.byKey(const ValueKey('demo-fallback-dot')), findsOneWidget);

    // The manager pressed "Publish" - now there is something at the address.
    transport.respond = (_) async => (statusCode: 200, body: publishedDocumentJson(text: 'Опубліковано'));
    await doubleTapCorner(tester);

    expect(find.text('Опубліковано'), findsOneWidget);
    expect(find.byKey(const ValueKey('demo-fallback-dot')), findsNothing);
  });
}
