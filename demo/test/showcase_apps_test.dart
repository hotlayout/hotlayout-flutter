import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_demo/main.dart';
import 'package:hotlayout_demo/showcase.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/theme/theme_contract.dart';

import '../../test/support/fixtures.dart';

/// The three showcase apps (Obsidian, Sunny, Orbit) bundled with the demo.
void main() {
  test('Obsidian is the default of the demo and every app has its files', () {
    expect(kStartFixture, 'obsidian');
    expect(kFixtures.take(3).map((fixture) => fixture.id), [
      'obsidian',
      'sunny',
      'orbit',
    ]);
    for (final app in kShowcaseApps) {
      expect(kFixtureThemeAssets[app.id], app.themeAsset);
      for (final path in [app.documentAsset, app.themeAsset, app.dataAsset]) {
        expect(File(path).existsSync(), isTrue, reason: path);
      }
      final doc = UiDocument.fromJsonString(
        File(app.documentAsset).readAsStringSync(),
      );
      expect(doc.screens, isNotEmpty, reason: app.id);
      final theme = ThemeLoad.parse(File(app.themeAsset).readAsStringSync());
      expect(
        theme.status,
        ThemeLoadStatus.ok,
        reason: '${app.id}: ${theme.detail}',
      );
    }
  });

  test(
    'pictures are fetched from the product site only; the package default is untouched',
    () {
      expect(
        showcaseImageUrl('/landing/demo/obsidian/avatar.webp'),
        'https://hotlayout.com/landing/demo/obsidian/avatar.webp',
      );
      expect(
        showcaseImageUrl('https://hotlayout.com/landing/demo/orbit/sky.webp'),
        'https://hotlayout.com/landing/demo/orbit/sky.webp',
      );
      expect(showcaseImageUrl('https://example.com/x.png'), isNull);
      expect(showcaseImageUrl('//example.com/x.png'), isNull);
      expect(showcaseImageUrl('http://hotlayout.com/x.png'), isNull);
      expect(showcaseImageUrl('https://hotlayout.com.evil.test/x.png'), isNull);
    },
  );

  test(
    'the answers merge the lists of records into the data map, by language and by scenario',
    () async {
      final bundle = diskAssetBundle();
      final obsidian = await ShowcaseData.load(
        kShowcaseApps[0],
        bundle: bundle,
      );
      expect(obsidian.now.isUtc, isTrue);
      expect(obsidian.forLocale('en')['user.fullName'], isNotNull);
      expect(obsidian.forLocale('en')['quests'], isA<List<Object?>>());
      // `uk-UA` -> `uk`; an unknown language -> the first answer (English).
      expect(obsidian.forLocale('uk-UA'), same(obsidian.answers['uk']));
      expect(obsidian.forLocale('zz'), same(obsidian.answers['en']));

      final orbit = await ShowcaseData.load(kShowcaseApps[2], bundle: bundle);
      expect(
        orbit.answers.keys,
        containsAll(['default', 'newMember', 'afterPayment']),
      );
      expect(
        orbit.forLocale('ar', scenario: 'newMember'),
        same(orbit.answers['newMember']),
      );
      expect(orbit.forLocale('en')['missions'], isA<List<Object?>>());
    },
  );

  test(
    'the sample data of the web showcase is the very file the demo bundles',
    () {
      final raw =
          jsonDecode(File(kShowcaseApps[0].dataAsset).readAsStringSync())
              as Map<String, Object?>;
      expect(raw.keys, containsAll(['now', 'en', 'uk', 'ar']));
    },
  );

  testWidgets(
    'the demo draws Obsidian edge to edge: no banner, no fallback tag',
    (tester) async {
      tester.view.physicalSize = const Size(393 * 3, 852 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final app = kShowcaseApps[0];
      final themeLoad = await ThemeLoad.fromBundle(
        bundle: diskAssetBundle(),
        assetPath: app.themeAsset,
      );
      await tester.pumpWidget(
        HotlayoutDemoApp(
          themeLoad: themeLoad,
          sources: [
            fixtureSource(app.id, title: app.title, bundle: diskAssetBundle()),
          ],
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.text('Alex Morgan'), findsOneWidget);
      expect(find.byType(CheckedModeBanner), findsNothing);
      expect(find.byKey(const ValueKey('demo-fallback-dot')), findsNothing);
    },
  );
}
