import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart';
import 'package:hotlayout_flutter_example/backend.dart';
import 'package:hotlayout_flutter_example/main.dart';

void main() {
  testWidgets('the bundled document is drawn with the host data', (tester) async {
    tester.view.physicalSize = const Size(430, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Assets are read outside the fake clock of a widget test.
    await tester.runAsync(() async {
      final themeLoad = await ThemeLoad.fromBundle(assetPath: themeAsset);
      expect(themeLoad.status, ThemeLoadStatus.ok);

      await tester.pumpWidget(
        MaterialApp(
          home: HotLayoutScreen(
            source: const BundledDocumentSource(title: 'Bundled copy', assetPath: documentAsset),
            themeLoad: themeLoad,
            data: backendData,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.byType(ScreenFlow), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Make 5 card payments'), findsOneWidget);

    await tester.tap(find.text('Invite a friend'));
    await tester.pump();
    expect(find.text('Your share sheet opens here'), findsOneWidget);

    // A list row tells the host which reward it is about (schema 9.2.0).
    await tester.tap(find.text('Redeem').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('City backpack'));
    await tester.tap(find.text('City backpack'));
    // The previous snack bar is hidden first; give the new one time to slide in.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Redeem City backpack (backpack)?'), findsOneWidget);
  });
}
