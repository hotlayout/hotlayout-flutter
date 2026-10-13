import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hotlayout_demo/main.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/theme_contract.dart';
import 'package:hotlayout_flutter/src/render/icon_glyph.dart';

/// Presentation scenario on a real device.
///
/// What is valuable here and what `flutter test` does not give: the app comes up
/// IN FULL, with real asynchronous asset reading, real text rendering
/// and real gestures, and the document arrives by the same path as in the
/// demo (network with a fallback to the bundled copy).
///
/// **WHAT IS NOT CHECKED HERE.** There is no assertion that network photos are
/// painted: the product has no media delivery of its own yet, so there is nothing
/// to check. Add that assertion here once our media storage exists.
///
/// Run:
/// ```
/// flutter test integration_test/demo_flow_test.dart -d <simulator udid>
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// `pumpAndSettle` is not always suitable here: while an image loads from the network, an indicator
  /// spins on screen - an endless animation that "settle" never
  /// waits out. So we wait real time and pump a frame.
  Future<void> settle(WidgetTester tester, {int seconds = 3}) async {
    await tester.runAsync(() => Future<void>.delayed(Duration(seconds: seconds)));
    await tester.pump();
  }

  testWidgets('selection by finger and navigation in both directions', (tester) async {
    await tester.pumpWidget(HotlayoutDemoApp(themeLoad: await ThemeLoad.fromBundle(assetPath: kThemeContractAsset)));
    await settle(tester);

    Set<String> selected() => tester
        .widgetList<ChoiceOptionMark>(find.byType(ChoiceOptionMark))
        .where((mark) => mark.selected)
        .map((mark) => mark.optionValue)
        .toSet();

    // --- screen 1: exactly the document, no app scaffolding
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Choose your reward'), findsOneWidget);

    // --- dividers are drawn with the `border` token (7.3.0), using exactly the value
    // that lies in the BUILT theme artifact, not in a test fake. Previously they
    // took `muted` (the text color) and were additionally dimmed by alpha, so on a phone
    // they looked darker than in the builder. This is the difference sync was made for,
    // so it has to be checked where it is visible to the eye.
    final border = (await ThemeLoad.fromBundle(assetPath: kThemeContractAsset)).contract.defaultTheme.color(ColorToken.border);
    final hairlines = tester
        .widgetList<ColoredBox>(find.byType(ColoredBox))
        .where((box) => box.color == border);
    expect(hairlines, isNotEmpty, reason: 'no divider of the border color');
    expect(border, const Color(0xFFE5E7EB));

    // --- selection: arrives from data and moves by finger
    expect(find.byType(ChoiceOptionMark), findsNWidgets(3));
    expect(selected(), {'headphones'});

    await tester.tap(find.text('Travel backpack'));
    await tester.pump();
    expect(selected(), {'backpack'});

    await tester.tap(find.text('Coffee set'));
    await tester.pump();
    expect(selected(), {'coffee-set'});

    // --- transition by button to the details screen
    await tester.ensureVisible(find.text('Confirm choice'));
    await tester.pump();
    await tester.tap(find.text('Confirm choice'));
    await settle(tester);

    expect(find.text('Your points'), findsOneWidget);
    expect(find.text('Choose your reward'), findsNothing);

    // --- back by the document button (`navigate` to the catalog screen)
    await tester.ensureVisible(find.text('Back to catalog'));
    await tester.pump();
    await tester.tap(find.text('Back to catalog'));
    await settle(tester);
    expect(find.text('Choose your reward'), findsOneWidget);
    // The mark stays where the finger put it: a write to the bound path
    // lives as long as the screen stack does.
    expect(selected(), {'coffee-set'});

    // --- and by the document bar arrow - a step along the stack
    await tester.tap(find.byKey(kAppBarBackGlyphKey));
    await settle(tester, seconds: 1);
    expect(find.text('Your points'), findsOneWidget);
  });
}
