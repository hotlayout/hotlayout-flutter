import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

/// A button with a border and a custom shadow keeps the shadow: the edge under the button is painted.
void main() {
  final theme = RenderTheme.fallback();

  Map<String, Object?> button(String variant) => {
    'id': 'b',
    'type': 'Button',
    'props': {
      'label': {'kind': 'literal', 'value': 'Go'},
      'variant': variant,
      'action': {'type': 'submit'},
      'fullWidth': false,
    },
    'style': {
      'height': 40,
      'radius': 'md',
      'background': {'kind': 'color', 'color': {'value': '#ffffff'}},
      'border': {'width': 2, 'color': 'border'},
      'shadow': [
        {'offsetX': 0, 'offsetY': 6, 'blur': 0, 'spread': 0, 'color': {'value': '#ff0000'}},
      ],
    },
  };

  // A node below the button: the screen body clips what lies below its last child.
  final spacer = {
    'id': 's',
    'type': 'Container',
    'props': <String, Object?>{},
    'style': {'height': 60},
    'children': <Object?>[],
  };

  Future<(ByteData, double, double, double)> shoot(WidgetTester tester, String variant) async {
    await pumpDocument(tester, UiDocumentBuilder.bare([button(variant), spacer]), theme: theme);
    final rect = tester.getRect(find.byType(OutlinedButton));
    late ByteData bytes;
    late int width;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
      final image = await boundary.toImage();
      width = image.width;
      bytes = (await image.toByteData())!;
    });
    return (bytes, rect.center.dx, rect.bottom, width.toDouble());
  }

  for (final variant in ['secondary', 'ghost']) {
    testWidgets('$variant button: the shadow edge shows under the border', (tester) async {
      final (data, x, bottom, width) = await shoot(tester, variant);
      // 3 px under the bottom edge lies inside the 6 px offset shadow.
      final i = (((bottom + 3).floor()) * width.toInt() + x.floor()) * 4;
      expect(data.getUint8(i), greaterThan(250), reason: 'red channel');
      expect(data.getUint8(i + 1), lessThan(5), reason: 'green channel: the pixel is the red shadow');
    });
  }
}
