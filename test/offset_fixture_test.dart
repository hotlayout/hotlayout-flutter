/// The `offset-screens` fixture (schema 9.10.0): stack overlays and in-flow
/// pulls on a real screen, in English, Ukrainian and Arabic, at 320 and 393.
/// The case table (`offset_cases_test.dart`) covers individual rules; this
/// file covers them all together.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/render/layer_place.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';

import 'support/fixtures.dart';

void _view(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1100);
  addTearDown(tester.view.reset);
}

RenderBox _outer(WidgetTester tester, String text, bool Function(RenderObject) parentIs, int nth) {
  RenderObject? node = tester.renderObject(find.text(text));
  var seen = 0;
  while (node != null) {
    if (node.parent != null && parentIs(node.parent!)) {
      if (seen == nth) break;
      seen += 1;
    }
    node = node.parent;
  }
  return node! as RenderBox;
}

void main() {
  final doc = loadFixture('offset-screens');

  test('fixture: two screens, six overlays and four pulled nodes', () {
    expect(doc.screens.map((s) => s.screenId), ['overlap', 'details']);
    expect(doc.schemaVersion, '9.10.0');
  });

  for (final locale in ['en', 'uk', 'ar']) {
    for (final width in [320.0, 393.0]) {
      testWidgets('screen "overlap", $locale, ${width.round()}: five overlays, no exceptions', (tester) async {
        _view(tester, width);
        await pumpDocument(tester, doc, locale: locale);
        expect(tester.takeException(), isNull);
        expect(find.byType(LayerPlace), findsNWidgets(5));
        final places = tester.renderObjectList<RenderLayerPlace>(find.byType(LayerPlace)).toList();
        // The "×2" badge sticks out past the tile; the ribbon is rotated 45° (sign follows direction).
        expect(places.where((p) => p.geometry!.protrudes), isNotEmpty);
        final angles = places.map((p) => p.geometry!.angle.abs()).toList();
        expect(angles, contains(45));
      });
    }
  }

  testWidgets('the sheet overlaps the header by 24 (pull: xl), avatars overlap by 12', (tester) async {
    _view(tester, 393);
    await pumpDocument(tester, doc);
    double column(RenderBox b) => (b.parentData! as ContainerBoxParentData<RenderBox>).offset.dy;
    final hero = _outer(tester, 'Weekly quest', (p) => p is RenderStretchColumn, 1);
    final sheet = _outer(tester, 'A badge on the corner, chips on the edge', (p) => p is RenderStretchColumn, 1);
    expect(column(sheet), closeTo(column(hero) + hero.size.height - 24, 0.5));

    final a = _outer(tester, 'A', (p) => p is RenderRowLayout, 0);
    final b = _outer(tester, 'B', (p) => p is RenderRowLayout, 0);
    final ra = a.localToGlobal(Offset.zero) & a.size;
    final rb = b.localToGlobal(Offset.zero) & b.size;
    expect(rb.left, closeTo(ra.right - 12, 0.5));
  });

  testWidgets('Arabic: avatar "ب" sits 12 to the left of the right edge of "أ", not to the right', (tester) async {
    _view(tester, 393);
    await pumpDocument(tester, doc, locale: 'ar');
    final a = _outer(tester, 'أ', (p) => p is RenderRowLayout, 0);
    final b = _outer(tester, 'ب', (p) => p is RenderRowLayout, 0);
    final ra = a.localToGlobal(Offset.zero) & a.size;
    final rb = b.localToGlobal(Offset.zero) & b.size;
    expect(rb.right, closeTo(ra.left + 12, 0.5));
  });

  testWidgets('screen "details": the NEW ribbon sits in the start corner, rotated counter-clockwise', (tester) async {
    _view(tester, 393);
    await pumpDocument(tester, doc);
    await tester.ensureVisible(find.text('Claim 100 points'));
    await tester.tap(find.text('Claim 100 points'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final place = tester.renderObjectList<RenderLayerPlace>(find.byType(LayerPlace)).last;
    expect(place.geometry!.angle, -45);
    expect(place.geometry!.protrudes, isTrue);
  });
}
