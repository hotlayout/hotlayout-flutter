/// Progress bar and ring (9.7.0): what the case table does not measure in
/// numbers is PIXELS. The ring gradient's seam and sweep direction are only
/// visible in a rendered frame: the contract calls `SweepGradient` with
/// `GradientRotation(-π/2)` feasible "by API", not verified.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/render/progress_paint.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

void main() {
  Map<String, Object?> ring(Map<String, Object?> props, {double value = 100}) => {
    'id': 'ring',
    'type': 'CircularProgress',
    'props': {
      'value': {'kind': 'literal', 'value': value},
      'max': {'kind': 'literal', 'value': 100},
      'color': 'primary',
      'size': 'lg',
      'labelFormat': 'none',
      ...props,
    },
  };

  Future<Color> pixel(WidgetTester tester, Finder finder, Offset local) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
    final image = (await tester.runAsync(() => boundary.toImage()))!;
    final data = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
    final origin = tester.getTopLeft(finder);
    final x = (origin.dx + local.dx).round();
    final y = (origin.dy + local.dy).round();
    final i = (y * image.width + x) * 4;
    return Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
  }

  testWidgets('ring gradient: seam at the top, colors run clockwise', (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: const ValueKey('shot'),
          child: Scaffold(
            body: renderDocument(
              docWith([
                ring({
                  'thickness': 16,
                  'gradient': {
                    'angle': 90,
                    'stops': [
                      {'color': {'value': '#ff0000'}, 'position': 0},
                      {'color': {'value': '#0000ff'}, 'position': 1},
                    ],
                  },
                }),
              ]),
              theme: RenderTheme.fallback(),
              data: const {},
            ),
          ),
        ),
      ),
    );
    final finder = find.descendant(of: find.byType(RingPlacement), matching: find.byType(CustomPaint));
    final d = tester.getSize(finder).width; // 96
    final mid = 8.0; // middle of a stroke 16 thick
    // Slightly right of the top is the arc start: red; slightly left is its
    // end (full circle): blue.
    final right = await pixel(tester, finder, Offset(d / 2 + 4, mid));
    final left = await pixel(tester, finder, Offset(d / 2 - 4, mid));
    expect(right.r, greaterThan(0.8));
    expect(right.b, lessThan(0.2));
    expect(left.b, greaterThan(0.8));
    expect(left.r, lessThan(0.2));
    // Right edge of the circle (3 o'clock) is a quarter of the way: more red than blue.
    final three = await pixel(tester, finder, Offset(d - mid, d / 2));
    expect(three.r, greaterThan(three.b));
    // Bottom is halfway: in between.
    final six = await pixel(tester, finder, Offset(d / 2, d - mid));
    expect((six.r - six.b).abs(), lessThan(0.15));
  });

  testWidgets('bar label sits at the logical end of the track', (tester) async {
    tester.view.physicalSize = const Size(390, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final (locale, atEnd) in [('en', true), ('ar', false)]) {
      await pumpDocument(
        tester,
        docWith([
          {
            'id': 'bar',
            'type': 'ProgressBar',
            'props': {
              'value': {'kind': 'literal', 'value': 50},
              'max': {'kind': 'literal', 'value': 100},
              'color': 'primary',
              'labelFormat': 'percent',
            },
          },
        ]),
        locale: locale,
      );
      final track = tester.getRect(find.byType(ProgressTrack));
      final label = tester.getRect(find.text('50%'));
      if (atEnd) {
        expect(label.right, closeTo(track.right, 0.5), reason: locale);
      } else {
        expect(label.left, closeTo(track.left, 0.5), reason: locale);
      }
    }
  });
}
