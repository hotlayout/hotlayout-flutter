import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_demo/main.dart';
import 'package:hotlayout_demo/showcase.dart';
import 'package:hotlayout_flutter/src/theme/theme_contract.dart';
import 'package:integration_test/integration_test.dart';

/// Screenshots of the showcase apps on a device, one per screen reached by taps, named
/// `<app>-<screen>-flutter`. Run with `flutter drive` (see `test_driver/integration_test.dart`):
///
/// ```
/// SHOT_DIR=shots flutter drive --driver=test_driver/integration_test.dart \
///   --target=integration_test/showcase_shots_test.dart -d <simulator udid> \
///   --dart-define=locale=en --dart-define=ONLY=obsidian
/// ```
const String _only = String.fromEnvironment('ONLY');

/// App -> screen name -> the texts tapped one after another from a fresh start. An empty list is
/// the first screen.
const Map<String, Map<String, List<String>>> _flows = {
  'obsidian': {
    'home': [],
    'quest': ['Coffee week'],
    'rewards': ['Rewards'],
    'profile': ['Profile'],
  },
  'sunny': {
    'home': [],
    'quest': ['Coffee week'],
    'rewards': ['Rewards'],
    'profile': ['Profile'],
  },
  'orbit': {
    'home': [],
    'missions': ['Missions'],
    'rewards': ['Rewards'],
    'orbit': ['Orbit'],
    'notifications': ['sem:Notifications'],
    'history': ['History'],
    'mission': ['Missions', 'Coffee constellation'],
    'reward': ['Rewards', 'Coffee for a week'],
    'peek': ['Missions', 'long:Coffee constellation'],
    'streak': ['c:Streak · 6'],
    'levels': ['Orbit', 'Galaxy'],
  },
};

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester, {int seconds = 3}) async {
    await tester.runAsync(
      () => Future<void>.delayed(Duration(seconds: seconds)),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  for (final app in kShowcaseApps) {
    if (_only.isNotEmpty && _only != app.id) continue;
    testWidgets('${app.id} screens', (tester) async {
      for (final flow in _flows[app.id]!.entries) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          HotlayoutDemoApp(
            themeLoad: await ThemeLoad.fromBundle(assetPath: app.themeAsset),
            sources: [fixtureSource(app.id, title: app.title)],
          ),
        );
        await settle(tester);
        for (final label in flow.value) {
          if (label.startsWith('sem:')) {
            await tester.tap(
              find.bySemanticsLabel(label.substring(4)).first,
              warnIfMissed: false,
            );
          } else if (label.startsWith('long:')) {
            final target = find.text(label.substring(5)).first;
            await tester.ensureVisible(target);
            await tester.longPress(target, warnIfMissed: false);
          } else {
            final target =
                (label.startsWith('c:')
                        ? find.textContaining(label.substring(2))
                        : find.text(label))
                    .first;
            await tester.ensureVisible(target);
            await tester.tap(target, warnIfMissed: false);
          }
          await settle(tester, seconds: 2);
        }
        debugPrint(
          'SHOT-CHECK ${flow.key} quest-button=${find.text('Continue quest').evaluate().length}',
        );
        await binding.convertFlutterSurfaceToImage();
        await tester.pump(const Duration(milliseconds: 300));
        await binding.takeScreenshot('${app.id}-${flow.key}-flutter');
      }
    });
  }
}
