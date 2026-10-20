import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_demo/main.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/theme_contract.dart';

/// System insets are the only thing the demo host draws on its own, so they are tested
/// separately from the presentation scenario.
///
/// One test per file is not an accident: the test brings up the WHOLE app, and
/// the document and theme are read from the bundle with real asynchronous input. A second
/// such test in the same file no longer gets the document - the loading indicator
/// stays on screen, i.e. an endless animation, and
/// `pumpAndSettle` never finishes. Strip styling is tested by the neighboring
/// file `demo_background_test.dart`, separately for exactly this reason.
void main() {
  testWidgets('the document does not go under the system insets', (tester) async {
    // A model with a notch: 59 on top, 34 at the bottom - exactly where the document would get lost
    // if the host drew it literally "full screen".
    const insets = EdgeInsets.only(top: 59, bottom: 34);
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    tester.view.viewPadding = const FakeViewPadding(top: 177, bottom: 102);
    tester.view.padding = const FakeViewPadding(top: 177, bottom: 102);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(HotlayoutDemoApp(themeLoad: await ThemeLoad.fromBundle(assetPath: kThemeContractAsset), sources: [fixtureSource('reward-catalog-screens')]));
    await tester.pumpAndSettle();

    final documentTop = tester.getTopLeft(find.text('Rewards')).dy;
    expect(documentTop, greaterThan(insets.top), reason: 'document title under the status bar');

    // The bottom edge of the document does not enter the home indicator strip.
    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final flowBottom = tester.getRect(find.byType(ScreenFlow)).bottom;
    expect(flowBottom, lessThanOrEqualTo(screenHeight - insets.bottom + 0.5));
  });
}
