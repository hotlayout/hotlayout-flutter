import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_demo/main.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/theme_contract.dart';

import '../../test/support/fixtures.dart';

/// The demo with `--dart-define=fixture=rewards-showcase-screens`: a fixture with its
/// OWN theme is read against it, not against the demo's published theme.
///
/// A separate file and ONE test: two tests that bring up the whole app hang in
/// one file (see `demo_background_test.dart`).
void main() {
  const id = 'rewards-showcase-screens';

  test('the demo fixture theme map matches the test map and points to existing files', () {
    expect(kFixtureThemeAssets, {
      for (final entry in fixtureThemeFiles.entries)
        entry.key: 'assets/contract/fixtures/${entry.value}.json',
    });
    expect(kFixtures.map((fixture) => fixture.id), contains(id));
  });

  testWidgets('the app draws the showcase with its own theme', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final themeLoad = await ThemeLoad.fromBundle(bundle: diskAssetBundle(), assetPath: kFixtureThemeAssets[id]!);
    expect(themeLoad.isFallback, isFalse, reason: themeLoad.detail);
    expect(themeLoad.contract.defaultTheme.colors.containsKey('brandText'), isTrue);

    await tester.pumpWidget(
      HotlayoutDemoApp(
        themeLoad: themeLoad,
        sources: [fixtureSource(id, title: 'Вітрина', bundle: diskAssetBundle())],
      ),
    );
    // The showcase document is over 50 KB in UTF-8, and `AssetBundle.loadString` decodes such
    // strings in a separate isolate, i.e. with real asynchronous input
    // that the test's fake time does not drive. We give it real time.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The showcase's initial screen is on screen, not a placeholder or a read error.
    expect(find.byType(ScreenFlow), findsOneWidget);
    expect(find.byType(Text), findsWidgets);
  });
}
