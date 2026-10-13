import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_demo/main.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/theme_contract.dart';
import 'package:hotlayout_flutter/src/render/icon_glyph.dart';

void main() {
  testWidgets('the demo shows exactly the document and works as in a presentation', (tester) async {
    final themeLoad = await ThemeLoad.fromBundle(assetPath: kThemeContractAsset);
    // The app takes its theme from the artifact, not from a hard-coded fallback: if
    // contract sync was forgotten, it shows up here and not in front of the user.
    expect(themeLoad.status, ThemeLoadStatus.ok, reason: themeLoad.detail);

    // The default document source is the network with a fallback to the bundled
    // copy. Under `flutter test` any HTTP request gets 400, so this test goes
    // through the FALLBACK path - and what is visible must be exactly the same as
    // when the document arrived over the network. A network with predictable
    // responses is covered by `document_source_test.dart`.
    await tester.pumpWidget(HotlayoutDemoApp(themeLoad: themeLoad));
    await tester.pumpAndSettle();

    Set<String> selected() => tester
        .widgetList<ChoiceOptionMark>(find.byType(ChoiceOptionMark))
        .where((mark) => mark.selected)
        .map((mark) => mark.optionValue)
        .toSet();

    // --- there is nothing from the app on screen
    expect(find.byType(AppBar), findsNothing, reason: 'an own app bar would duplicate the document AppBar');
    expect(find.byType(ChoiceChip), findsNothing, reason: 'a chip strip is scaffolding, not product');
    // The title is drawn by the document ITSELF, and there is exactly one.
    expect(find.text('Rewards'), findsOneWidget);
    expect(find.text('Autumn rewards'), findsOneWidget);

    // --- screen 1: reward choice (it is the initial one)
    expect(find.text('Choose your reward'), findsOneWidget);
    expect(find.byType(ChoiceOptionMark), findsNWidgets(3));
    // The initial choice arrived as DATA (`item.selectedId`), not from the document.
    expect(selected(), {'headphones'});

    // The point of it all: the choice switches by finger.
    await tester.ensureVisible(find.text('Travel backpack'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Travel backpack'));
    await tester.pump();
    expect(selected(), {'backpack'});

    // --- transition by button to the details screen
    await tester.ensureVisible(find.text('Confirm choice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm choice'));
    await tester.pumpAndSettle();

    // --- screen 2: reward details
    expect(find.text('Your points'), findsOneWidget);
    // The title arrived as a binding from document data (there is no network
    // catalog here: under `flutter test` any request gets 400).
    expect(find.text('Wireless headphones'), findsOneWidget);
    expect(find.text('Back to catalog'), findsOneWidget);

    // --- back by the details button: a plain `navigate`
    await tester.ensureVisible(find.text('Back to catalog'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back to catalog'));
    await tester.pumpAndSettle();
    expect(find.text('Choose your reward'), findsOneWidget);

    // --- back by the arrow of the document's top bar
    await tester.tap(find.byKey(kAppBarBackGlyphKey));
    await tester.pumpAndSettle();
    expect(find.text('Your points'), findsOneWidget);

    // --- the scaffolding is still there, behind a gesture
    await tester.longPress(find.byKey(const ValueKey('demo-service-corner')));
    await tester.pumpAndSettle();
    expect(find.text('Service panel'), findsOneWidget);
    // Document state is visible in the panel: a fallback must not be silent.
    expect(find.text('Document'), findsOneWidget);

    // There are more sources in the panel than fit in the sheet (network + six
    // fixtures), so one has to scroll to the bundled ones. Scrolling is a property of
    // the sheet, not of the test: it is the same on a phone.
    await tester.scrollUntilVisible(find.text('Minimal'), 80, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Minimal'));
    await tester.pumpAndSettle();
    expect(find.text('Привіт'), findsOneWidget);
    expect(find.text('Choose your reward'), findsNothing);

    expect(tester.takeException(), isNull);
  });
}
