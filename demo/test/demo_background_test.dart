import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_demo/main.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';
import 'package:hotlayout_flutter/src/theme/theme_contract.dart';

/// Styling the host draws under the insets (`demo-screen-backdrop`) and in the
/// status bar strip (`demo-top-strip`).
BoxDecoration _hostDecoration(WidgetTester tester, String key) =>
    tester.widget<DecoratedBox>(find.byKey(ValueKey(key))).decoration as BoxDecoration;

/// What making `AppBar.background` optional in 7.0.0 was for - but at the level of the
/// APP, not of a single widget.
///
/// A transparent bar alone gives nothing: if the host paints the status bar
/// strip, the screen gradient is cut anyway, just a few pixels higher. So the whole
/// stack has to be tested: document -> renderer -> host strips.
///
/// A separate file rather than a second test in `demo_host_test.dart`: both bring up
/// the whole app reading the bundle, and two such tests in one file hang -
/// the second never gets the document and stays on the loading indicator,
/// i.e. an endless animation.
void main() {
  testWidgets('inset strips follow the CURRENT screen, not the initial one', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    tester.view.viewPadding = const FakeViewPadding(top: 177, bottom: 102);
    tester.view.padding = const FakeViewPadding(top: 177, bottom: 102);
    addTearDown(tester.view.reset);

    final themeLoad = await ThemeLoad.fromBundle(assetPath: kThemeContractAsset);
    final theme = themeLoad.contract.defaultTheme;
    await tester.pumpWidget(HotlayoutDemoApp(themeLoad: themeLoad));
    await tester.pumpAndSettle();

    // The fixture's initial screen: solid background, a bar with its own background.
    expect(_hostDecoration(tester, 'demo-screen-backdrop').color, theme.color(ColorToken.secondary));
    expect(_hostDecoration(tester, 'demo-top-strip').color, theme.color(ColorToken.surface));

    await tester.ensureVisible(find.text('Confirm choice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm choice'));
    await tester.pumpAndSettle();

    // Details screen: a gradient over the whole area, including the insets…
    final backdrop = _hostDecoration(tester, 'demo-screen-backdrop');
    expect(backdrop.color, isNull);
    expect(backdrop.gradient, theme.gradient(GradientToken.brandBackdrop));

    // …and the status bar strip paints nothing of its own, because the bar on this screen
    // has no background either. An opaque strip would cut the gradient with a white band -
    // exactly what 7.0.0 got rid of.
    final strip = _hostDecoration(tester, 'demo-top-strip');
    expect(strip.color, isNull);
    expect(strip.gradient, isNull);
  });

  group('host strips: root state', () {
    final theme = RenderTheme.fallback();

    ScreenNode screen({Object? bar}) =>
        UiNode.parse({
              'id': 'root',
              'type': 'Screen',
              'props': const <String, Object?>{},
              'style': {
                'background': {'kind': 'color', 'color': 'surface'},
              },
              'styleWhen': [
                {
                  'when': {'path': 'user.isPremium', 'op': 'isTrue'},
                  'style': {
                    'background': {'kind': 'color', 'color': 'secondary'},
                  },
                },
              ],
              'children': [?bar],
            })
            as ScreenNode;

    test('when the state holds its background paints the strips; otherwise the base one', () {
      final root = screen();
      expect(
        hostScreenDecoration(root, theme, const ScreenData({'user.isPremium': false})).color,
        theme.color(ColorToken.surface),
      );
      expect(
        hostScreenDecoration(root, theme, const ScreenData({'user.isPremium': true})).color,
        theme.color(ColorToken.secondary),
      );
    });

    test('the bar state counts too; a background image gives nothing for the strips', () {
      final root = screen(
        bar: {
          'id': 'bar',
          'type': 'AppBar',
          'props': {
            'title': {'kind': 'literal', 'value': 'П'},
            'showBack': false,
          },
          'style': {
            'background': {'kind': 'color', 'color': 'surface'},
          },
          'styleWhen': [
            {
              'when': {'path': 'user.isPremium', 'op': 'isTrue'},
              'style': {
                'background': {
                  'kind': 'image',
                  'source': {'kind': 'url', 'url': 'https://example.com/a.png'},
                  'fit': 'cover',
                },
              },
            },
          ],
        },
      );
      expect(
        hostAppBarDecoration(root, theme, const ScreenData({'user.isPremium': false})).color,
        theme.color(ColorToken.surface),
      );
      final image = hostAppBarDecoration(root, theme, const ScreenData({'user.isPremium': true}));
      expect(image.color, isNull);
      expect(image.gradient, isNull);
    });
  });
}
