import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_demo/main.dart';
import 'package:hotlayout_demo/sample_data.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import '../../test/support/fixtures.dart';

/// The six frames of contract 9.19.0 open in the demo without an error, with the demo's own sample data
/// (dictionary 1.5.0): a card, money, a hero, choice controls, parts of a row and a field, a description
/// of a picture and an icon and a date from data.
void main() {
  const ids = [
    'composition-screens',
    'money-screens',
    'hero-screens',
    'choice-controls-screens',
    'parts-screens',
    'alt-icon-date-screens',
  ];

  test('the six frames are in the demo picker', () {
    expect(kFixtures.map((fixture) => fixture.id), containsAll(ids));
  });

  for (final id in ids) {
    testWidgets('$id draws with the sample data of the demo', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final UiDocument document = loadFixture(id);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: renderDocument(
              document,
              theme: RenderTheme.fallback(),
              data: sampleScreenData,
              now: DateTime.parse(kSampleNow),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(ScreenFlow), findsOneWidget);
    });
  }
}
