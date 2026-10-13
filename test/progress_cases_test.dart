/// Shared case table for the PROGRESS BAR AND RING (schema 9.7.0), run entirely through the renderer.
///
/// There is ONE table for all readers (`fixtures/progress/progress-cases.json`),
/// and the test reads the artifact itself: a row added in the constructor starts
/// being checked here after a `cp`, with no edits to this file. No rows are
/// skipped silently: `readerOnly` rows (documents the constructor will not
/// build - an unknown size word, a token the theme does not declare, a wrong
/// shape) are just as mandatory for the reader.
///
/// FIVE GROUPS, each run two ways - through the rule and through a real
/// node on screen:
///  1. `ratioCases` - the fill ratio: the `progressRatio` function on raw
///     values and (where both are numbers) a bar and a ring with literals;
///  2. `ringCases` - diameter, thickness, box: `ringGeometry` on the style
///     fields that APPLY (`applied`), and the ring in a real place
///     (free, a row child with weight, a full-stack layer);
///  3. `arcCases` - arc start, direction and sweep in both writing directions;
///  4. `barCases` - track, fill, radii, which side it grows from:
///     what the bar painted (the `paints` matcher), not a formula;
///  5. `paintCases` - track and fill colour (solid or gradient, its
///     stops on the scale) on the bar AND on the ring.
///
/// Three 9.11.0 groups (segmented bar): `segmentCases` -
/// step geometry and state, `segmentPaintCases` - the colour of the current and
/// of the unfilled steps, `segmentGradientCases` - the gradient line along the filled ones.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/progress_rules.dart';
import 'package:hotlayout_flutter/src/model/style_values.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/render/progress_paint.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

void main() {
  final table =
      jsonDecode(File('assets/contract/fixtures/progress/progress-cases.json').readAsStringSync())
          as Map<String, Object?>;
  List<_Row> rowsOf(String name) => (table[name]! as List<Object?>).cast<_Row>();
  final ratioCases = rowsOf('ratioCases');
  final ringCases = rowsOf('ringCases');
  final arcCases = rowsOf('arcCases');
  final barCases = rowsOf('barCases');
  final paintCases = rowsOf('paintCases');
  final segmentCases = rowsOf('segmentCases');
  final segmentPaintCases = rowsOf('segmentPaintCases');
  final segmentGradientCases = rowsOf('segmentGradientCases');
  final segmentPlaceCases = rowsOf('segmentPlaceCases');

  final theme = RenderTheme.fromJson({
    ...(table['theme']! as Map<String, Object?>),
    'id': 'progress-cases',
    'name': 'Progress cases',
    'brightness': 'light',
  });
  final unit = theme.spacing[kRingSizeUnit]!;
  final pill = theme.radii['pill']!;

  test('the table is read in full, and every field of it is known to this test', () {
    expect(ratioCases, hasLength(15));
    expect(ringCases, hasLength(33));
    expect(arcCases, hasLength(5));
    expect(barCases, hasLength(12));
    expect(paintCases, hasLength(21));
    expect(segmentCases, hasLength(21));
    expect(segmentPaintCases, hasLength(6));
    expect(segmentGradientCases, hasLength(3));
    expect(segmentPlaceCases, hasLength(6));
    const known = {
      'ratioCases': {'name', 'value', 'max', 'readerOnly', 'expect'},
      'ringCases': {'name', 'props', 'style', 'applied', 'readerOnly', 'expect'},
      'arcCases': {'name', 'ratio', 'direction', 'expect'},
      'barCases': {'name', 'props', 'trackInline', 'ratio', 'direction', 'readerOnly', 'expect'},
      'paintCases': {'name', 'props', 'ratio', 'readerOnly', 'expect'},
      'segmentCases': {'name', 'props', 'trackInline', 'value', 'max', 'direction', 'readerOnly', 'expect'},
      'segmentPaintCases': {'name', 'props', 'readerOnly', 'expect'},
      'segmentGradientCases': {'name', 'props', 'trackInline', 'value', 'max', 'expect'},
      'segmentPlaceCases': {'name', 'props', 'placeInline', 'expect'},
    };
    for (final entry in known.entries) {
      final rows = rowsOf(entry.key);
      for (final row in rows) {
        expect(row.keys.toSet().difference(entry.value), isEmpty, reason: '${entry.key}/${row['name']}: unknown field');
      }
      expect(rows.map((row) => row['name']).toSet(), hasLength(rows.length), reason: '${entry.key}: names are unique');
    }
    // The values the test reads from the table's theme are the ones written in the table.
    expect(unit, 24);
    expect(pill, 72);
    expect(theme.spacing['sm'], 8);
  });

  // ───────────────────────────────────────────────────────── helpers ──

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  _Row ringNode(Map<String, Object?> props, {Map<String, Object?>? style, Object? value = 50, Object? max = 100}) => {
    'id': 'ring',
    'type': 'CircularProgress',
    'props': {
      'value': {'kind': 'literal', 'value': value},
      'max': {'kind': 'literal', 'value': max},
      'color': 'primary',
      'size': 'md',
      'labelFormat': 'none',
      ...props,
    },
    'style': ?style,
  };

  _Row barNode(Map<String, Object?> props, {Object? value = 50, Object? max = 100}) => {
    'id': 'bar',
    'type': 'ProgressBar',
    'props': {
      'value': {'kind': 'literal', 'value': value},
      'max': {'kind': 'literal', 'value': max},
      'color': 'primary',
      'labelFormat': 'none',
      ...props,
    },
  };

  Color hex(String value, double opacity) =>
      Color(0xFF000000 | int.parse(value.substring(1), radix: 16)).withValues(alpha: opacity);

  void expectColor(Color actual, Color expected, String reason) {
    expect(actual.r, closeTo(expected.r, 1 / 255), reason: '$reason: red');
    expect(actual.g, closeTo(expected.g, 1 / 255), reason: '$reason: green');
    expect(actual.b, closeTo(expected.b, 1 / 255), reason: '$reason: blue');
    expect(actual.a, closeTo(expected.a, 1 / 255), reason: '$reason: opacity');
  }

  /// What the table says about the paint, versus what is in the widget.
  void expectPaint(ProgressFill fill, Color actualTrack, Map<String, Object?> expected, double ratio, String reason) {
    final trackExpect = expected['track']! as Map<String, Object?>;
    expectColor(actualTrack, hex(trackExpect['hex']! as String, (trackExpect['opacity']! as num).toDouble()), '$reason: track');
    final fillExpect = expected['fill']! as Map<String, Object?>;
    if (fillExpect['kind'] == 'color') {
      expect(fill.isGradient, isFalse, reason: '$reason: solid fill');
      expectColor(fill.color!, hex(fillExpect['hex']! as String, (fillExpect['opacity']! as num).toDouble()), '$reason: fill');
      return;
    }
    expect(fill.isGradient, isTrue, reason: '$reason: fill is a gradient');
    final stops = (fillExpect['stops']! as List<Object?>).cast<_Row>();
    expect(fill.colors, hasLength(stops.length), reason: '$reason: stops');
    for (var i = 0; i < stops.length; i += 1) {
      expectColor(fill.colors![i], hex(stops[i]['hex']! as String, (stops[i]['opacity']! as num).toDouble()), '$reason: stop colour $i');
      // The position in the document is along the FILLED part; on the scale it is `p × ratio`.
      expect(fill.positions![i] * ratio, closeTo((stops[i]['at']! as num).toDouble(), 1e-9), reason: '$reason: stop $i on the scale');
    }
  }

  // ─────────────────────────────────────────────────────── ratioCases ──

  group('ratioCases — fill ratio', () {
    for (final row in ratioCases) {
      final name = row['name']! as String;
      final expected = (row['expect']! as num).toDouble();

      test('rule: $name', () {
        expect(progressRatio(row['value'], row['max']), closeTo(expected, 1e-12));
      });

      // A screen where both numbers are numbers: `null` and a string in a literal the reader
      // turns into the binding's fallback before the scale, so this is not a scale
      // question (the table row is checked by the rule above).
      if (row['value'] is num && row['max'] is num) {
        testWidgets('bar and ring: $name', (tester) async {
          phone(tester);
          await pumpDocument(
            tester,
            docWith([barNode(const {}, value: row['value'], max: row['max']), ringNode(const {}, value: row['value'], max: row['max'])]),
            theme: theme,
          );
          expect(tester.takeException(), isNull);
          expect(tester.widget<ProgressTrack>(find.byType(ProgressTrack)).ratio, closeTo(expected, 1e-9));
          final painter = tester.widget<CustomPaint>(find.descendant(of: find.byType(RingPlacement), matching: find.byType(CustomPaint))).painter! as RingPainter;
          expect(painter.ratio, closeTo(expected, 1e-9));
        });
      }
    }
  });

  // ──────────────────────────────────────────────────────── ringCases ──

  RingBoxInput inputOf(_Row row) {
    final props = row['props']! as Map<String, Object?>;
    final style = (row['style']! as Map<String, Object?>).cast<String, Object?>();
    final applied = (row['applied'] as Map<String, Object?>?) ?? const {};
    final inline = applied['width'] != false;
    final block = applied['height'] != false;
    double? px(String key, bool applies) => applies ? (style[key] as num?)?.toDouble() : null;
    // `padding` in the table is one number for all sides.
    final padding = (style['padding'] as num?)?.toDouble() ?? 0;
    final thicknessRef = readProgressThickness(props['thickness']);
    return RingBoxInput(
      size: props['size'] as String?,
      unit: unit,
      thickness: (thicknessRef == null ? null : theme.resolveSpacing(thicknessRef)) ?? theme.spacing['sm']!,
      width: px('width', inline),
      minWidth: px('minWidth', inline),
      maxWidth: px('maxWidth', inline),
      height: px('height', block),
      minHeight: px('minHeight', block),
      maxHeight: px('maxHeight', block),
      paddingInline: 2 * padding,
      paddingBlock: 2 * padding,
      border: (style['border'] as num?)?.toDouble() ?? 0,
    );
  }

  group('ringCases — diameter, thickness, box', () {
    for (final row in ringCases) {
      final name = row['name']! as String;
      final expected = row['expect']! as Map<String, Object?>;
      final applied = (row['applied'] as Map<String, Object?>?) ?? const {};

      test('rule: $name', () {
        final geometry = ringGeometry(inputOf(row));
        expect(geometry.diameter, closeTo((expected['diameter']! as num).toDouble(), 1e-9), reason: 'diameter');
        expect(geometry.thickness, closeTo((expected['thickness']! as num).toDouble(), 1e-9), reason: 'thickness');
        if (expected['boxInline'] != null) {
          expect(geometry.boxInline, closeTo((expected['boxInline']! as num).toDouble(), 1e-9), reason: 'box along the row');
        }
        if (expected['boxBlock'] != null) {
          expect(geometry.boxBlock, closeTo((expected['boxBlock']! as num).toDouble(), 1e-9), reason: 'box across');
        }
      });

      testWidgets('screen: $name', (tester) async {
        phone(tester);
        final props = row['props']! as Map<String, Object?>;
        final style = (row['style']! as Map<String, Object?>).cast<String, Object?>();
        // Table style: `padding` and `border` are numbers; a border needs a colour.
        final nodeStyle = <String, Object?>{
          ...style,
          if (style['border'] != null) 'border': {'width': style['border'], 'color': 'primary'},
        };
        final node = ringNode(props, style: nodeStyle.isEmpty ? null : nodeStyle);

        // Where the ring sits: a size from the parent does not name a diameter.
        final List<_Row> children;
        if (applied['width'] == false && applied['height'] == false) {
          children = [
            {
              'id': 'stack',
              'type': 'Stack',
              'props': {'alignHorizontal': 'center', 'alignVertical': 'center'},
              'children': [
                {'id': 'base', 'type': 'Container', 'props': {'gap': 'none'}, 'style': {'width': 300, 'height': 300}, 'children': <_Row>[]},
                {...node, 'fill': true},
              ],
            },
          ];
        } else if (applied['width'] == false) {
          children = [
            {
              'id': 'row',
              'type': 'Row',
              'props': {'gap': 'none', 'align': 'center', 'justify': 'start', 'wrap': false},
              'children': [
                {...node, 'weight': 1},
              ],
            },
          ];
        } else {
          children = [node];
        }
        await pumpDocument(tester, docWith(children), theme: theme);
        expect(tester.takeException(), isNull);

        final placement = find.byType(RingPlacement);
        final paint = find.descendant(of: placement, matching: find.byType(CustomPaint));
        final d = tester.getSize(paint.first).width;
        final painter = tester.widget<CustomPaint>(paint.first).painter! as RingPainter;
        final expectedDiameter = (expected['diameter']! as num).toDouble();

        expect(d, closeTo(expectedDiameter, 0.01), reason: 'diameter on screen');
        expect(tester.getSize(paint.first).height, closeTo(expectedDiameter, 0.01), reason: 'a circle, not an ellipse');
        expect(painter.thickness, closeTo((expected['thickness']! as num).toDouble(), 0.01), reason: 'thickness on screen');

        final box = tester.getRect(placement);
        final circle = tester.getRect(paint.first);
        expect(circle.center.dx, closeTo(box.center.dx, 0.01), reason: 'centred in its place, along');
        expect(circle.center.dy, closeTo(box.center.dy, 0.01), reason: 'centred in its place, across');

        // The content box is the node box minus padding and border.
        final padding = (style['padding'] as num?)?.toDouble() ?? 0;
        final frame = ((style['border'] as num?)?.toDouble() ?? 0) + padding;
        if (expected['boxInline'] != null) {
          expect(box.width, closeTo(math.max(0, (expected['boxInline']! as num).toDouble() - 2 * frame), 0.01), reason: 'box along the row');
        }
        if (expected['boxBlock'] != null) {
          expect(box.height, closeTo(math.max(0, (expected['boxBlock']! as num).toDouble() - 2 * frame), 0.01), reason: 'box across');
        }
        if (expected['freeInline'] != null) {
          expect(box.width - d, closeTo((expected['freeInline']! as num).toDouble(), 0.01), reason: 'free space along');
        }
        if (expected['freeBlock'] != null) {
          expect(box.height - d, closeTo((expected['freeBlock']! as num).toDouble(), 0.01), reason: 'free space across');
        }
      });
    }
  });

  // ───────────────────────────────────────────────────────── arcCases ──

  group('arcCases — ring arc', () {
    for (final row in arcCases) {
      final name = row['name']! as String;
      final expected = row['expect']! as Map<String, Object?>;
      final ratio = (row['ratio']! as num).toDouble();

      test('rule: $name', () {
        final arc = ringArc(ratio);
        expect(arc.startDeg, closeTo((expected['startDeg']! as num).toDouble(), 1e-9));
        expect(arc.sweepDeg, closeTo((expected['sweepDeg']! as num).toDouble(), 1e-9));
      });

      testWidgets('screen: $name', (tester) async {
        phone(tester);
        await pumpDocument(
          tester,
          docWith([ringNode(const {'thickness': 12}, value: ratio * 100)]),
          theme: theme,
          // The ring is NOT mirrored: in right-to-left writing the arc is the same.
          locale: row['direction'] == 'rtl' ? 'ar' : 'en',
        );
        final render = tester.renderObject<RenderBox>(find.descendant(of: find.byType(RingPlacement), matching: find.byType(CustomPaint)).first);
        final d = render.size.width;
        final center = Offset(d / 2, d / 2);
        final sweep = (expected['sweepDeg']! as num).toDouble() * math.pi / 180;
        if (sweep <= 0) {
          // Nothing is filled: only the track.
          expect(render, paints..circle(x: center.dx, y: center.dy, radius: (d - 12) / 2));
          expect(render, isNot(paints..arc()), reason: 'no arc');
          return;
        }
        // The start is at the top (-π/2), the sweep is clockwise (positive).
        expect(
          render,
          paints
            ..circle(x: center.dx, y: center.dy, radius: (d - 12) / 2)
            ..arc(
              rect: Rect.fromCircle(center: center, radius: (d - 12) / 2),
              startAngle: -math.pi / 2,
              sweepAngle: sweep,
              useCenter: false,
              strokeWidth: 12,
            ),
        );
      });
    }
  });

  // ───────────────────────────────────────────────────────── barCases ──

  group('barCases — track, fill, radii', () {
    for (final row in barCases) {
      final name = row['name']! as String;
      final expected = row['expect']! as Map<String, Object?>;
      final props = row['props']! as Map<String, Object?>;
      final trackInline = (row['trackInline']! as num).toDouble();
      final ratio = (row['ratio']! as num).toDouble();
      final rtl = row['direction'] == 'rtl';

      test('rule: $name', () {
        final thicknessRef = readProgressThickness(props['thickness']);
        final thickness = (thicknessRef == null ? null : theme.resolveSpacing(thicknessRef)) ?? theme.spacing['sm']!;
        final geometry = BarGeometry.of(trackInline: trackInline, thickness: thickness, ratio: ratio, pill: pill);
        expect(geometry.trackBlock, closeTo((expected['trackBlock']! as num).toDouble(), 1e-9), reason: 'track height');
        expect(geometry.fillInline, closeTo((expected['fillInline']! as num).toDouble(), 1e-9), reason: 'fill length');
        expect(geometry.trackRadius, closeTo((expected['trackRadius']! as num).toDouble(), 1e-9), reason: 'track radius');
        expect(geometry.fillRadius, closeTo((expected['fillRadius']! as num).toDouble(), 1e-9), reason: 'fill radius');
      });

      testWidgets('screen: $name', (tester) async {
        phone(tester);
        // A bar in a column stretches to the box width: a `Container` with a
        // named width gives the track exactly `trackInline`.
        await pumpDocument(
          tester,
          docWith([
            {
              'id': 'holder',
              'type': 'Container',
              'props': {'gap': 'none'},
              'style': {'width': trackInline},
              'children': [barNode(props, value: ratio * 100)],
            },
          ]),
          theme: theme,
          locale: rtl ? 'ar' : 'en',
        );
        expect(tester.takeException(), isNull);

        final finder = find.byType(ProgressTrack);
        final box = tester.getRect(finder);
        final render = tester.renderObject<RenderBox>(finder);
        final trackBlock = (expected['trackBlock']! as num).toDouble();
        final fillInline = (expected['fillInline']! as num).toDouble();
        expect(box.width, closeTo(trackInline, 0.01), reason: 'track over the whole given length');
        expect(box.height, closeTo(trackBlock, 0.01), reason: 'track height');

        if (trackBlock == 0) {
          // Zero thickness: no track, no fill; the same box.
          expect(render, paintsNothing);
          return;
        }
        final trackRadius = (expected['trackRadius']! as num).toDouble();
        final fillRadius = (expected['fillRadius']! as num).toDouble();
        final track = RRect.fromRectAndRadius(Offset.zero & box.size, Radius.circular(trackRadius));
        expect(expected['fillFrom'], rtl ? 'right' : 'left', reason: 'table and direction agree');

        if (fillInline <= 0) {
          expect(render, paints..rrect(rrect: track));
          expect(render, isNot(paints..clipRRect()), reason: 'no fill');
          return;
        }
        final left = rtl ? box.width - fillInline : 0.0;
        final fill = RRect.fromRectAndRadius(Rect.fromLTWH(left, 0, fillInline, trackBlock), Radius.circular(fillRadius));
        // The track is under everything; the fill is clipped by the track and lies on top.
        expect(
          render,
          paints
            ..rrect(rrect: track)
            ..save()
            ..clipRRect(rrect: track)
            ..rrect(rrect: fill)
            ..restore(),
        );
      });
    }
  });

  // ─────────────────────────────────────────────────────── paintCases ──

  group('paintCases — track and fill paint', () {
    for (final row in paintCases) {
      final name = row['name']! as String;
      final expected = row['expect']! as Map<String, Object?>;
      final props = row['props']! as Map<String, Object?>;
      final ratio = (row['ratio']! as num).toDouble();

      test('rule: $name', () {
        final paint = theme.resolveProgressPaint(
          color: FieldColor.parse(props['color'], fieldDefault: ColorToken.primary),
          trackColor: ColorRef.tryParse(props['trackColor']),
          gradient: GradientRef.tryParse(props['gradient']),
        );
        final fill = paint.colors == null ? ProgressFill.solid(paint.fill!) : ProgressFill.gradient(paint.colors!, paint.positions!);
        expectPaint(fill, paint.track, expected, ratio, name);
      });

      testWidgets('bar and ring: $name', (tester) async {
        phone(tester);
        await pumpDocument(tester, docWith([barNode(props, value: ratio * 100), ringNode(props, value: ratio * 100)]), theme: theme);
        expect(tester.takeException(), isNull);

        final bar = tester.widget<ProgressTrack>(find.byType(ProgressTrack));
        expectPaint(bar.fill, bar.trackColor, expected, ratio, '$name (bar)');

        final ring = tester.widget<CustomPaint>(find.descendant(of: find.byType(RingPlacement), matching: find.byType(CustomPaint))).painter! as RingPainter;
        expectPaint(ring.fill, ring.trackColor, expected, ratio, '$name (ring)');
      });
    }
  });

  // ──────────────────────────────────────────────── segmented bar (9.11.0) ──

  /// A stepped bar in a container `trackInline` wide: the track gets exactly that.
  Future<void> pumpSteps(WidgetTester tester, Map<String, Object?> props, double trackInline, Object? value, Object? max,
      {String locale = 'en'}) async {
    phone(tester);
    await pumpDocument(
      tester,
      docWith([
        {
          'id': 'holder',
          'type': 'Container',
          'props': {'gap': 'none'},
          'style': {'width': trackInline},
          'children': [barNode(props, value: value, max: max)],
        },
      ]),
      theme: theme,
      locale: locale,
    );
    expect(tester.takeException(), isNull);
  }

  final xs = theme.spacing[kProgressSegmentGap]!;

  group('segmentCases — step geometry and state', () {
    for (final row in segmentCases) {
      final name = row['name']! as String;
      final props = row['props']! as Map<String, Object?>;
      final expected = row['expect'] as Map<String, Object?>?;
      final trackInline = (row['trackInline']! as num).toDouble();
      final value = row['value'] as num;
      final max = row['max'] as num;
      final rtl = row['direction'] == 'rtl';
      final ratio = progressRatio(value, max);
      final thicknessRef = readProgressThickness(props['thickness']);
      final thickness = (thicknessRef == null ? null : theme.resolveSpacing(thicknessRef)) ?? theme.spacing['sm']!;

      SegmentGeometry? geometryOf() {
        final steps = readSegments(props['segments']);
        if (steps == null) return null;
        return segmentGeometry(trackInline: trackInline, thickness: thickness, ratio: ratio, segments: steps, gap: xs, pill: pill);
      }

      test('rule: $name', () {
        final geometry = geometryOf();
        if (expected == null) {
          expect(geometry, isNull);
          return;
        }
        expect(geometry, isNotNull);
        expect(geometry!.inline, closeTo((expected['inline']! as num).toDouble(), 1e-9));
        final starts = expected['starts'] as List<Object?>?;
        if (starts != null) {
          expect(geometry.starts, hasLength(starts.length));
          for (var i = 0; i < starts.length; i += 1) {
            expect(geometry.starts[i], closeTo((starts[i]! as num).toDouble(), 1e-9), reason: 'start of step $i');
          }
        }
        expect(geometry.filled, expected['filled']);
        expect(geometry.current, expected['current']);
        expect(
          geometry.states.map((state) => const {SegmentState.filled: 'f', SegmentState.current: 'c', SegmentState.unfilled: 'u'}[state]).join(),
          expected['states'],
        );
        expect(geometry.radius, closeTo((expected['radius']! as num).toDouble(), 1e-9));
        expect(geometry.filledInline, closeTo((expected['filledInline']! as num).toDouble(), 1e-9));
        expect(expected['fillFrom'], rtl ? 'right' : 'left');
      });

      testWidgets('screen: $name', (tester) async {
        await pumpSteps(tester, props, trackInline, value, max, locale: rtl ? 'ar' : 'en');
        final track = tester.widget<ProgressTrack>(find.byType(ProgressTrack));
        final finder = find.byType(ProgressTrack);
        final box = tester.getRect(finder);
        final render = tester.renderObject<RenderBox>(finder);
        expect(box.width, closeTo(trackInline, 0.01));
        if (expected == null) {
          // The step is unreadable or narrower than a pixel: a solid bar.
          if (readSegments(props['segments']) == null) expect(track.segments, isNull);
          expect(render, paints..rrect(), reason: 'solid track');
          expect(render, isNot(paintsExactlyCountTimes(#drawRRect, readSegments(props['segments']) ?? 99)), reason: 'not steps');
          return;
        }
        final inline = (expected['inline']! as num).toDouble();
        final radius = (expected['radius']! as num).toDouble();
        final states = expected['states']! as String;
        final steps = states.length;
        final geometry = geometryOf()!;
        var pattern = paints;
        final primary = hex('#4f46e5', 1);
        final unfilled = hex('#eef0f6', 1);
        for (var i = 0; i < steps; i += 1) {
          final left = rtl ? box.width - geometry.starts[i] - inline : geometry.starts[i];
          final rrect = RRect.fromRectAndRadius(Rect.fromLTWH(left, 0, inline, box.height), Radius.circular(radius));
          // There is no track under the gaps: each step is its own rectangle, one draw call.
          pattern = pattern..rrect(rrect: rrect, color: states[i] == 'f' ? primary : unfilled);
        }
        expect(render, pattern);
        expect(render, paintsExactlyCountTimes(#drawRRect, steps), reason: 'no track under the gaps');
      });
    }
  });

  group('segmentPlaceCases — the look of the bar is decided by the PLACE width', () {
    for (final row in segmentPlaceCases) {
      final name = row['name']! as String;
      final props = row['props']! as Map<String, Object?>;
      final place = (row['placeInline']! as num).toDouble();
      final expected = row['expect']! as Map<String, Object?>;
      final steps = readSegments(props['segments'])!;
      final isSteps = expected['kind'] == 'steps';

      test('rule: $name', () {
        expect(segmentsMinInline(steps, xs), (expected['ownMinInline']! as num).toDouble());
        expect(segmentsAreSteps(steps, xs, place), isSteps);
        // The look at `max(place, own minimum)` is the same as in the place.
        expect(segmentsAreSteps(steps, xs, math.max(place, segmentsMinInline(steps, xs))), isSteps);
        final geometry = segmentGeometry(trackInline: place, thickness: 8, ratio: 0.5, segments: steps, gap: xs, pill: pill);
        expect(geometry == null, !isSteps);
        if (isSteps) expect(geometry!.inline, closeTo((expected['inline']! as num).toDouble(), 1e-9));
      });

      testWidgets('screen: $name', (tester) async {
        // A place `placeInline` wide: a box with a named width.
        phone(tester);
        await pumpDocument(
          tester,
          docWith([
            {
              'id': 'place',
              'type': 'Container',
              'props': {'direction': 'column', 'gap': 'none'},
              'style': {'width': place},
              'children': [
                {
                  'id': 'bar',
                  'type': 'ProgressBar',
                  'props': {'value': {'kind': 'literal', 'value': 6}, 'max': {'kind': 'literal', 'value': 12}, 'color': 'primary', 'labelFormat': 'none', ...props},
                },
              ],
            },
          ]),
          theme: theme,
        );
        expect(tester.takeException(), isNull);
        final render = tester.renderObject<RenderBox>(find.byType(ProgressTrack));
        expect(render.size.width, closeTo(place, 0.01));
        // Steps - one rectangle per step; solid - track and fill.
        expect(render, isSteps ? paintsExactlyCountTimes(#drawRRect, steps) : isNot(paintsExactlyCountTimes(#drawRRect, steps)));
      });
    }

    // Place "width by content": a natural-width row sizes the
    // bar by its CONTENT (`IntrinsicWidth`), and the width is its own minimum, not zero.
    // This width decides the look (step 0 - solid), and layout is single-pass: more
    // frames change nothing (in the web reader the loop "steps -> 44 -> solid -> 0 ->
    // steps" was what repainted the bar every frame).
    Map<String, Object?> bar12() => {
      'id': 'bar',
      'type': 'ProgressBar',
      'props': {'value': {'kind': 'literal', 'value': 6}, 'max': {'kind': 'literal', 'value': 12}, 'color': 'primary', 'labelFormat': 'none', 'segments': 12},
    };

    testWidgets('a stepped bar in a natural-width row: 44 = (12 - 1) × gap, solid, stable', (tester) async {
      phone(tester);
      await pumpDocument(
        tester,
        docWith([
          {
            'id': 'row',
            'type': 'Row',
            'props': {'gap': 'none', 'align': 'start', 'justify': 'start', 'wrap': false},
            'children': [
              {
                'id': 'chip',
                'type': 'Container',
                'props': {'direction': 'row', 'gap': 'none'},
                'children': [bar12()],
              },
              {'id': 'sibling', 'type': 'Text', 'props': {'content': {'kind': 'literal', 'value': 'x'}}},
            ],
          },
        ]),
        theme: theme,
      );
      expect(tester.takeException(), isNull);
      final finder = find.byType(ProgressTrack);
      final first = tester.getSize(finder);
      expect(first.width, closeTo(11 * xs, 0.01), reason: '(N - 1) × gap');
      expect(tester.renderObject<RenderBox>(finder), isNot(paintsExactlyCountTimes(#drawRRect, 12)), reason: 'step 0 - a solid bar');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(tester.getSize(finder), first, reason: 'the width does not change from frame to frame');
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'the bar does not repaint itself');
    });

    testWidgets('the same node in a stack in the middle of a column: the screen gives the place - steps, stable width', (tester) async {
      phone(tester);
      await pumpDocument(
        tester,
        docWith([
          {
            'id': 'stack',
            'type': 'Stack',
            'props': {'alignHorizontal': 'center', 'alignVertical': 'center'},
            'children': [bar12()],
          },
        ]),
        theme: theme,
      );
      expect(tester.takeException(), isNull);
      final finder = find.byType(ProgressTrack);
      final first = tester.getSize(finder);
      expect(first.width, greaterThan(11 * xs + 12), reason: 'steps are not narrower than a pixel');
      expect(tester.renderObject<RenderBox>(finder), paintsExactlyCountTimes(#drawRRect, 12));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getSize(finder), first);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('segmentPaintCases — colour of the current and the unfilled steps', () {
    for (final row in segmentPaintCases) {
      final name = row['name']! as String;
      final props = row['props']! as Map<String, Object?>;
      final expected = row['expect']! as Map<String, Object?>;
      final current = expected['current'] as Map<String, Object?>?;
      final unfilled = expected['unfilled']! as Map<String, Object?>;

      test('rule: $name', () {
        final ref = ColorRef.tryParse(props['currentColor']);
        final color = ref == null ? null : theme.resolveColor(ref);
        if (current == null) {
          expect(color, isNull);
        } else {
          expectColor(color!, hex(current['hex']! as String, (current['opacity']! as num).toDouble()), name);
        }
        final track = props['trackColor'] == null ? null : theme.resolveColor(ColorRef.tryParse(props['trackColor'])!);
        expectColor(track ?? theme.color(ColorToken.secondary), hex(unfilled['hex']! as String, (unfilled['opacity']! as num).toDouble()), '$name: unfilled');
      });

      testWidgets('screen: $name', (tester) async {
        // The third step of six is the current one.
        await pumpSteps(tester, props, 320, 2, 6);
        final track = tester.widget<ProgressTrack>(find.byType(ProgressTrack));
        expect(track.segments, 6);
        if (current == null) {
          expect(track.currentColor, isNull, reason: 'same as the unfilled one');
        } else {
          expectColor(track.currentColor!, hex(current['hex']! as String, (current['opacity']! as num).toDouble()), name);
        }
        expectColor(track.trackColor, hex(unfilled['hex']! as String, (unfilled['opacity']! as num).toDouble()), '$name: unfilled');
        // The drawn current step: its own colour or the unfilled colour.
        final render = tester.renderObject<RenderBox>(find.byType(ProgressTrack));
        final paintedCurrent = current == null ? hex(unfilled['hex']! as String, (unfilled['opacity']! as num).toDouble()) : hex(current['hex']! as String, (current['opacity']! as num).toDouble());
        final step = (320 - 5 * xs) / 6;
        var pattern = paints;
        for (var i = 0; i < 6; i += 1) {
          final rrect = RRect.fromRectAndRadius(Rect.fromLTWH(i * (step + xs), 0, step, 8), const Radius.circular(4));
          pattern = pattern..rrect(rrect: rrect, color: i < 2 ? hex('#4f46e5', 1) : (i == 2 ? paintedCurrent : hex(unfilled['hex']! as String, (unfilled['opacity']! as num).toDouble())));
        }
        expect(render, pattern);
      });
    }
  });

  group('segmentGradientCases — gradient along the filled steps', () {
    for (final row in segmentGradientCases) {
      final name = row['name']! as String;
      final props = row['props']! as Map<String, Object?>;
      final expected = row['expect']! as Map<String, Object?>;
      final trackInline = (row['trackInline']! as num).toDouble();
      final value = row['value']! as num;
      final max = row['max']! as num;

      testWidgets('screen: $name', (tester) async {
        await pumpSteps(tester, props, trackInline, value, max);
        final track = tester.widget<ProgressTrack>(find.byType(ProgressTrack));
        final geometry = segmentGeometry(
          trackInline: trackInline,
          thickness: 8,
          ratio: progressRatio(value, max),
          segments: props['segments']! as int,
          gap: xs,
          pill: pill,
        )!;
        // The line runs from the start of the first step to the end of the last FILLED one.
        expect(expected['lineFrom'], 0);
        expect(geometry.filledInline, closeTo((expected['lineTo']! as num).toDouble(), 1e-9));
        final stops = (expected['stops']! as List<Object?>).cast<_Row>();
        expect(track.fill.isGradient, isTrue);
        for (var i = 0; i < stops.length; i += 1) {
          expectColor(track.fill.colors![i], hex(stops[i]['hex']! as String, 1), '$name: stop colour $i');
          expect(track.fill.positions![i] * geometry.filledInline, closeTo((stops[i]['at']! as num).toDouble(), 1e-9), reason: 'stop $i');
        }
        // Drawn: each filled step is a separate rectangle with ONE shader
        // shared by all, the gaps cut out (nothing is painted between steps).
        final render = tester.renderObject<RenderBox>(find.byType(ProgressTrack));
        final recorded = TestRecordingPaintingContext(TestRecordingCanvas());
        render.paint(recorded, Offset.zero);
        final calls = (recorded.canvas as TestRecordingCanvas).invocations
            .map((call) => call.invocation)
            .where((call) => call.memberName == #drawRRect)
            .toList();
        expect(calls, hasLength(props['segments']! as int));
        final paints = [for (final call in calls) call.positionalArguments[1] as Paint];
        final filledPaints = paints.take(geometry.filled).toList();
        expect(filledPaints.every((paint) => paint.shader != null), isTrue, reason: 'filled ones use the gradient');
        expect(filledPaints.every((paint) => identical(paint.shader, filledPaints.first.shader)), isTrue, reason: 'one paint (one shader) for all filled steps');
        expect(paints.skip(geometry.filled).every((paint) => paint.shader == null), isTrue, reason: 'the rest have no gradient');
        expect(expected['gapsCutOut'], isTrue);
      });
    }
  });
}
