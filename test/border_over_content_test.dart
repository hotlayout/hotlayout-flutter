/// A solid border with a radius lies OVER the content, and the content is clipped by the inner edge of the border.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart';

import 'support/fixtures.dart';

Map<String, Object?> _card({Map<String, Object?>? radius}) => {
  'id': 'card',
  'type': 'Container',
  'props': <String, Object?>{},
  'style': {
    'width': 100,
    'height': 100,
    'radius': radius ?? 30,
    'border': {'width': 2, 'color': {'value': '#0000ff'}},
  },
  'children': [
    {
      'id': 'fill',
      'type': 'Container',
      'props': <String, Object?>{},
      'style': {
        'width': 100,
        'height': 100,
        'background': {'kind': 'color', 'color': {'value': '#ff0000'}},
      },
      'children': <Object?>[],
    },
  ],
};

void main() {
  for (final dir in [TextDirection.ltr, TextDirection.rtl]) {
    testWidgets('a full-size child never paints over the border, corners included ($dir)', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: dir,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 100,
                height: 100,
                child: renderDocument(UiDocumentBuilder.bare([_card()]), theme: RenderTheme.fallback(), data: const {}),
              ),
            ),
          ),
        ),
      );
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      final image = (await tester.runAsync(() => boundary.toImage()))!;
      final data = (await tester.runAsync(() => image.toByteData()))!;
      int pixel(int x, int y) {
        final i = (y * image.width + x) * 4;
        return (0xFF << 24) | (data.getUint8(i) << 16) | (data.getUint8(i + 1) << 8) | data.getUint8(i + 2);
      }

      const ox = 0;
      const oy = 0;
      expect(pixel(ox + 50, oy + 1), 0xFF0000FF, reason: 'edge: border');
      expect(pixel(ox + 50, oy + 50), 0xFFFF0000, reason: 'centre: content');
      const d = 30 - 29 * 0.7071067811865476;
      for (final (x, y) in [(d, d), (100 - d, d), (d, 100 - d), (100 - d, 100 - d)]) {
        // Antialiasing blends the arc with the background, never with the content's red.
        expect((pixel(ox + x.round(), oy + y.round()) >> 16) & 0xFF, lessThan(0x20), reason: 'corner arc at $x,$y');
      }
    });
  }
}
