import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_demo/main.dart';
import 'package:hotlayout_flutter/src/theme/theme_contract.dart';

/// Language switch in the service panel (7.2.0).
///
/// A separate file with one test, for the same reason as `demo_background_test`:
/// two tests that bring up the whole app reading the bundle hang in one
/// file on another zone's cached `Future`.
///
/// What is tested is the PRESENTATION, not the model: that a translation gets substituted
/// is guarded by `localization_test.dart`. The question here is different - whether a person
/// at a demo can switch the language without changing the phone's language and without restarting
/// the app.
void main() {
  testWidgets('the document language is switched from the service panel', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final themeLoad = await ThemeLoad.fromBundle(assetPath: kThemeContractAsset);
    await tester.pumpWidget(
      HotlayoutDemoApp(
        themeLoad: themeLoad,
        sources: [fixtureSource('localized-promo', title: 'Промо')],
      ),
    );
    await tester.pumpAndSettle();

    // The test locale is `en_US`, and the document chose exactly it: `en` is in the list
    // of languages and is the default one there. This already checks the
    // automatic choice, not only the manual one.
    expect(find.text('Weekend offer'), findsOneWidget);
    expect(find.text('October 2026'), findsOneWidget);

    // A long press in the status bar strip is the way into the service panel.
    await tester.longPress(find.byKey(const ValueKey('demo-service-corner')));
    await tester.pumpAndSettle();

    expect(find.text('Document language'), findsOneWidget);
    // The panel is a list, and the language rows are BELOW the document and data
    // catalog state. `ListView` builds children lazily, so one has to reach the row the way
    // a finger does: otherwise the test would check not "the language can be switched" but
    // "the panel did not manage to grow".
    await tester.scrollUntilVisible(
      find.text('de — translations: 8'),
      120,
      // There are two scrollables on screen - the document under the sheet and the sheet itself;
      // the second is needed, otherwise the test would scroll the document.
      scrollable: find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    // The language label says how many translations it has: that is what separates "full"
    // from "partial", and at a demo that question comes first.
    expect(find.text('de — translations: 8'), findsOneWidget);

    await tester.tap(find.text('de — translations: 8'));
    await tester.pumpAndSettle();

    expect(find.text('Wochenendangebot'), findsOneWidget);
    expect(find.text('Weekend offer'), findsNothing);
    // German is complete - none of the default-language literals is left on screen.
    expect(find.text('October 2026'), findsNothing);
  });
}
