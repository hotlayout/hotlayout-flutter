import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_demo/main.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/theme_contract.dart';

import '../../test/support/fixtures.dart';

/// The survey in the demo starts with an EMPTY form: "Next" is disabled until the required fields are
/// filled. Dictionary samples (`survey.*`) used to prefill the form, and the comment in `main.dart`
/// about "deliberately empty" data was untrue.
void main() {
  testWidgets('survey: fields are empty, the "Next" button is disabled', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final themeLoad = await ThemeLoad.fromBundle(bundle: diskAssetBundle(), assetPath: kThemeContractAsset);
    await tester.pumpWidget(
      HotlayoutDemoApp(
        themeLoad: themeLoad,
        sources: [fixtureSource('survey-screens', title: 'Опитування', bundle: diskAssetBundle())],
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pumpAndSettle();

    expect(find.byType(ScreenFlow), findsOneWidget);
    // No sample value in the fields.
    for (final field in tester.widgetList<EditableText>(find.byType(EditableText))) {
      expect(field.controller.text, isEmpty);
    }
    expect(find.text('Alex'), findsNothing);
    expect(find.text('More rewards for books, please'), findsNothing);
    // The button is disabled: `ButtonStyleButton` has no press handler.
    final next = find.ancestor(
      of: find.descendant(of: find.byWidgetPredicate((w) => w is ButtonStyleButton), matching: find.text('Next')),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    expect(tester.widget<ButtonStyleButton>(next.first).onPressed, isNull);
  });
}
