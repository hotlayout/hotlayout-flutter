/// Round ends of the bar and the ring (schema 9.21.0, `cap: 'round'`): the group `capCases` of the shared
/// table `fixtures/progress/progress-cases.json`, every row run two ways -- through the rule, and through a real
/// node on screen (the `paints` matcher: what was painted, not a formula).
///
/// Around the table: the mirror of the artifact block `x-style.layout.progressCap`, what a node without the field
/// or with an unknown word looks like (exactly as before), the segments of a bar, and a gradient on a dot.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/progress_cap.dart';
import 'package:hotlayout_flutter/src/model/progress_rules.dart';
import 'package:hotlayout_flutter/src/render/progress_paint.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

void main() {
  final table = jsonDecode(File('assets/contract/fixtures/progress/progress-cases.json').readAsStringSync()) as _Row;
  final schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Row;
  final rows = (table['capCases']! as List<Object?>).cast<_Row>();
  final rings = rows.where((row) => row['widget'] == 'CircularProgress').toList();
  final bars = rows.where((row) => row['widget'] == 'ProgressBar').toList();
  final theme = RenderTheme.fromJson({
    ...(table['theme']! as _Row),
    'id': 'progress-cases',
    'name': 'Progress cases',
    'brightness': 'light',
  });

  double number(Object? value) => (value! as num).toDouble();

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  _Row ringNode(double diameter, double thickness, double ratio, {Object? cap = 'round', Map<String, Object?>? extra}) => {
    'id': 'ring',
    'type': 'CircularProgress',
    'props': {
      'value': {'kind': 'literal', 'value': ratio * 100},
      'max': {'kind': 'literal', 'value': 100},
      'color': 'primary',
      'size': 'md',
      'labelFormat': 'none',
      'thickness': thickness,
      'cap': ?cap,
      ...?extra,
    },
    'style': {'width': diameter, 'height': diameter},
  };

  _Row barNode(double ratio, double thickness, {Object? cap = 'round', Map<String, Object?>? extra}) => {
    'id': 'bar',
    'type': 'ProgressBar',
    'props': {
      'value': {'kind': 'literal', 'value': ratio * 100},
      'max': {'kind': 'literal', 'value': 100},
      'color': 'primary',
      'labelFormat': 'none',
      'thickness': thickness,
      'cap': ?cap,
      ...?extra,
    },
  };

  test('capCases: 20 rows (13 of the ring, 7 of the bar), unique names, only known fields', () {
    expect(rows, hasLength(20));
    expect(rings, hasLength(13));
    expect(bars, hasLength(7));
    expect(rows.map((row) => row['name']).toSet(), hasLength(20));
    for (final row in rows) {
      final known = row['widget'] == 'CircularProgress'
          ? {'name', 'widget', 'ratio', 'diameter', 'thickness', 'expected'}
          : {'name', 'widget', 'ratio', 'track', 'thickness', 'expected'};
      expect(row.keys.toSet().difference(known), isEmpty, reason: '${row['name']}: unknown field');
    }
  });

  test('x-style.layout.progressCap: the mirror against the artifact', () {
    final block = ((schema['x-style']! as _Row)['layout']! as _Row)['progressCap']! as _Row;
    expect(block['prop'], kProgressCapRules['prop']);
    expect(block['on'], ['ProgressBar', 'CircularProgress']);
    expect(block['words'], ProgressCap.values.map((cap) => cap.wire));
    expect(block['unknownWord'], kProgressCapRules['unknownWord']);
    expect(block['cases'], 'contract/fixtures/progress/progress-cases.json#capCases');
    expect((block['refines']! as List).length, 4);
  });

  group('capCases, ring: ends of the arc', () {
    for (final row in rings) {
      final name = row['name']! as String;
      final expected = row['expected']! as _Row;
      final ratio = number(row['ratio']);
      final diameter = number(row['diameter']);
      final thickness = number(row['thickness']);

      test('rule: $name', () {
        final geometry = ringCapGeometry(ratio, diameter, thickness);
        expect(geometry.kind.name, expected['kind']);
        expect(geometry.startDeg, closeTo(number(expected['startDeg']), 1e-6));
        expect(geometry.endDeg, closeTo(number(expected['endDeg']), 1e-6));
        expect(geometry.capAngle, closeTo(number(expected['capAngle']), 1e-6));
      });

      testWidgets('screen: $name', (tester) async {
        phone(tester);
        await pumpDocument(tester, docWith([ringNode(diameter, thickness, ratio)]), theme: theme);
        expect(tester.takeException(), isNull);
        final render = tester.renderObject<RenderBox>(find.descendant(of: find.byType(RingPlacement), matching: find.byType(CustomPaint)).first);
        final center = Offset(render.size.width / 2, render.size.height / 2);
        final stroke = math.min(thickness, diameter / 2);
        final radius = (diameter - stroke) / 2;
        final kind = expected['kind'];
        if (kind == 'none') {
          expect(render, isNot(paints..arc()), reason: 'nothing over the track');
          if (stroke <= 0) expect(render, paintsNothing);
          return;
        }
        // The same arithmetic as the painter: the matcher compares positions exactly.
        final capAngle = ringCapGeometry(ratio, diameter, thickness).capAngle;
        final sweep = ringArc(ratio).sweepDeg * math.pi / 180;
        Offset onRing(double angle) => center + Offset(math.sin(angle), -math.cos(angle)) * radius;

        if (kind == 'full') {
          expect(render, paints..circle(x: center.dx, y: center.dy, radius: radius)..circle(x: center.dx, y: center.dy, radius: radius));
          expect(render, isNot(paints..arc()), reason: 'no ends, no seam');
        } else if (kind == 'dot') {
          final at = onRing(capAngle);
          expect(render, paints..circle(x: center.dx, y: center.dy, radius: radius)..circle(x: at.dx, y: at.dy, radius: stroke / 2));
          expect(render, isNot(paints..arc()), reason: 'a dot is not an arc');
        } else {
          final end = sweep - capAngle;
          expect(
            render,
            paints
              ..circle(x: center.dx, y: center.dy, radius: radius)
              ..arc(
                rect: Rect.fromCircle(center: center, radius: radius),
                startAngle: -math.pi / 2 + capAngle,
                sweepAngle: end - capAngle,
                useCenter: false,
                strokeWidth: stroke,
                strokeCap: StrokeCap.round,
              ),
          );
        }
      });
    }
  });

  group('capCases, bar: fill and radius of the ends', () {
    for (final row in bars) {
      final name = row['name']! as String;
      final expected = row['expected']! as _Row;
      final ratio = number(row['ratio']);
      final trackInline = number(row['track']);
      final thickness = number(row['thickness']);

      test('rule: $name', () {
        expect(barCapFillInline(trackInline, thickness, ratio), closeTo(number(expected['fillInline']), 1e-9));
        expect(barCapRadius(thickness), closeTo(number(expected['radius']), 1e-9));
        final geometry = BarGeometry.of(trackInline: trackInline, thickness: thickness, ratio: ratio, pill: 72, roundEnds: true);
        expect(geometry.fillInline, closeTo(number(expected['fillInline']), 1e-9));
        expect(geometry.trackRadius, closeTo(number(expected['radius']), 1e-9));
        expect(geometry.fillRadius, closeTo(number(expected['radius']), 1e-9));
      });

      testWidgets('screen: $name', (tester) async {
        phone(tester);
        await pumpDocument(
          tester,
          docWith([
            {
              'id': 'holder',
              'type': 'Container',
              'props': {'gap': 'none'},
              'style': {'width': trackInline},
              'children': [barNode(ratio, thickness)],
            },
          ]),
          theme: theme,
        );
        expect(tester.takeException(), isNull);
        final render = tester.renderObject<RenderBox>(find.byType(ProgressTrack));
        final radius = Radius.circular(number(expected['radius']));
        final track = RRect.fromRectAndRadius(Offset.zero & render.size, radius);
        final fillInline = number(expected['fillInline']);
        if (fillInline <= 0) {
          expect(render, paints..rrect(rrect: track));
          expect(render, isNot(paints..clipRRect()), reason: 'no fill');
          return;
        }
        final fill = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, fillInline, thickness), radius);
        expect(render, paints..rrect(rrect: track)..save()..clipRRect(rrect: track)..rrect(rrect: fill)..restore());
      });
    }
  });

  group('without the field the ends are as before 9.21.0', () {
    test('the word is read; an unknown word, a number and a wrong case are no field', () {
      expect(ProgressCap.parse('round'), ProgressCap.round);
      for (final raw in <Object?>['butt', 'Round', 'square', 5, true, null, ['round'], {'cap': 'round'}]) {
        expect(ProgressCap.parse(raw), isNull, reason: '$raw');
      }
    });

    for (final cap in <Object?>[null, 'square', 'Round', 3]) {
      testWidgets('a ring with cap=$cap: a butt arc, no ends', (tester) async {
        phone(tester);
        await pumpDocument(tester, docWith([ringNode(96, 8, 0.25, cap: cap)]), theme: theme);
        final render = tester.renderObject<RenderBox>(find.descendant(of: find.byType(RingPlacement), matching: find.byType(CustomPaint)).first);
        final center = Offset(render.size.width / 2, render.size.height / 2);
        expect(
          render,
          paints
            ..circle(x: center.dx, y: center.dy, radius: 44)
            ..arc(startAngle: -math.pi / 2, sweepAngle: math.pi / 2, strokeCap: StrokeCap.butt),
        );
      });

      testWidgets('a bar with cap=$cap: the radius is the theme pill clamped to half the thickness', (tester) async {
        phone(tester);
        await pumpDocument(tester, docWith([barNode(0.4, 16, cap: cap)]), theme: theme);
        final render = tester.renderObject<RenderBox>(find.byType(ProgressTrack));
        final track = RRect.fromRectAndRadius(Offset.zero & render.size, const Radius.circular(8));
        expect(render, paints..rrect(rrect: track));
        final node = ((docWith([barNode(0.4, 16, cap: cap)]).initialScreen.root as ScreenNode).children.single) as ProgressBarNode;
        expect(node.cap, isNull);
      });
    }
  });

  group('round ends: the rest', () {
    testWidgets('a bar with steps: every step has half-circle ends', (tester) async {
      phone(tester);
      await pumpDocument(tester, docWith([barNode(0.5, 8, extra: {'segments': 4})]), theme: theme);
      final render = tester.renderObject<RenderBox>(find.byType(ProgressTrack));
      final gap = theme.spacing[kProgressSegmentGap]!;
      final cut = segmentGeometry(trackInline: render.size.width, thickness: 8, ratio: 0.5, segments: 4, gap: gap, pill: 72, roundEnds: true)!;
      expect(cut.radius, 4, reason: 'half of the thickness, not the theme pill');
      final step = RRect.fromRectAndRadius(Rect.fromLTWH(cut.starts[3], 0, cut.inline, 8), const Radius.circular(4));
      expect(render, paints..rrect()..rrect()..rrect()..rrect(rrect: step));
    });

    test('a gradient end takes the colour of the gradient at its centre', () {
      const colors = [Color(0xFFFF0000), Color(0xFF0000FF)];
      expect(gradientColorAt(colors, const [0, 1], 0), colors.first);
      expect(gradientColorAt(colors, const [0, 1], 1), colors.last);
      expect(gradientColorAt(colors, const [0, 1], 0.5), Color.lerp(colors.first, colors.last, 0.5));
      expect(gradientColorAt(colors, const [0.25, 0.75], 0.1), colors.first, reason: 'before the first stop');
      expect(gradientColorAt(colors, const [0.25, 0.75], 0.9), colors.last, reason: 'after the last stop');
    });

    testWidgets('a ring with a gradient: the arc is square, the two ends are circles of their own colour', (tester) async {
      phone(tester);
      await pumpDocument(
        tester,
        docWith([
          ringNode(96, 8, 0.5, extra: {'gradient': {'angle': 90, 'stops': [{'color': 'primary', 'position': 0}, {'color': 'accent', 'position': 1}]}}),
        ]),
        theme: theme,
      );
      final render = tester.renderObject<RenderBox>(find.descendant(of: find.byType(RingPlacement), matching: find.byType(CustomPaint)).first);
      expect(render, paints..circle()..arc(strokeCap: StrokeCap.butt)..circle(radius: 4)..circle(radius: 4));
    });
  });
}

