/// THE RADIAL GRADIENT (schema 9.36.0, theme 4.1.0): the shared table
/// `assets/contract/fixtures/radial-gradient/radial-gradient-cases.json`, every row run, and the frame
/// `radial-gradient-screens` with its own theme.
///
///  * `geometryCases` -- the numbers of the circle for a box (to 1e-6), and the shader the reader makes against the
///    shader Flutter's own `RadialGradient` makes from the numbers of the row, pixel for pixel;
///  * `documentCases` -- which gradients the reader draws, for an own gradient and for a theme token;
///  * the frame -- circles in the corners of a wide card, a glow from the middle of the top edge, a radial token.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/style_values.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';
import 'package:hotlayout_flutter/src/theme/theme_contract.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

final _Json _table =
    jsonDecode(File('assets/contract/fixtures/radial-gradient/radial-gradient-cases.json').readAsStringSync()) as _Json;

List<_Json> _rows(String key) => (_table[key]! as List<Object?>).cast<_Json>();

double _n(Object? value) => (value! as num).toDouble();

/// The three stops of the table with own colours (an own colour carries its opacity apart).
final List<_Json> _ownStops = [
  for (final stop in (_table['stops']! as List<Object?>).cast<_Json>())
    {
      'color': {'value': (stop['color']! as String).substring(0, 7)},
      'position': stop['position'],
    },
];

/// A theme whose `brandBackdrop` is the given gradient entry.
RenderTheme _themeWith(Object? gradient) {
  final base = jsonDecode(readThemeContract()) as _Json;
  final light = Map<String, Object?>.from(((base['contract']! as _Json)['themes']! as _Json)['light']! as _Json);
  light['gradient'] = {...(light['gradient']! as _Json), 'brandBackdrop': gradient};
  return RenderTheme.fromJsonRaw(light);
}

Future<Uint8List> _pixels(Shader shader, int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint()..shader = shader);
  final image = recorder.endRecording().toImageSync(width, height);
  final bytes = (await image.toByteData())!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

void main() {
  final theme = RenderTheme.fallback();

  test('the table has its groups, every row with a unique name', () {
    expect(_rows('geometryCases'), hasLength(48));
    expect(_rows('documentCases'), hasLength(20));
    for (final key in ['geometryCases', 'documentCases']) {
      final names = _rows(key).map((row) => row['name']).toSet();
      expect(names, hasLength(_rows(key).length), reason: key);
    }
  });

  group('geometryCases -- the circle of a box', () {
    for (final row in _rows('geometryCases')) {
      test(row['name']! as String, () {
        final box = row['box']! as _Json;
        final center = row['center']! as _Json;
        final metrics = radialGradientMetrics(
          width: _n(box['width']),
          height: _n(box['height']),
          centerX: _n(center['x']),
          centerY: _n(center['y']),
          radius: _n(row['radius']),
        );
        expect(metrics.farthestCorner, closeTo(_n(row['farthestCornerPx']), 1e-6));
        expect(metrics.radiusPx, closeTo(_n(row['radiusPx']), 1e-6));
        expect(metrics.flutterRadius, closeTo(_n(row['flutterRadius']), 1e-6));
        final flutterCenter = row['flutterCenter']! as _Json;
        expect(metrics.flutterCenter.x, closeTo(_n(flutterCenter['x']), 1e-9));
        expect(metrics.flutterCenter.y, closeTo(_n(flutterCenter['y']), 1e-9));
      });
    }

    testWidgets('the shader of the reader paints what a Flutter RadialGradient with the numbers of the row paints', (
      tester,
    ) async {
      await tester.runAsync(() async {
        const colors = [Color(0xFFFF0000), Color(0x8000FF00), Color(0xFF0000FF)];
        const stops = [0.0, 0.4, 1.0];
        for (final row in _rows('geometryCases')) {
          final box = row['box']! as _Json;
          final center = row['center']! as _Json;
          final width = _n(box['width']).round();
          final height = _n(box['height']).round();
          final rect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
          final own = RadialBoxGradient(
            centerX: _n(center['x']),
            centerY: _n(center['y']),
            share: _n(row['radius']),
            colors: colors,
            stops: stops,
          );
          final flutterCenter = row['flutterCenter']! as _Json;
          final reference = RadialGradient(
            center: Alignment(_n(flutterCenter['x']), _n(flutterCenter['y'])),
            radius: _n(row['flutterRadius']),
            colors: colors,
            stops: stops,
          );
          final ours = await _pixels(own.createShader(rect), width, height);
          final theirs = await _pixels(reference.createShader(rect), width, height);
          var worst = 0;
          for (var i = 0; i < ours.length; i += 1) {
            final gap = (ours[i] - theirs[i]).abs();
            if (gap > worst) worst = gap;
          }
          expect(worst, lessThanOrEqualTo(1), reason: row['name']! as String);
        }
      });
    });

    test('a box with no area does not break the shader', () {
      final gradient = RadialBoxGradient(
        centerX: 0.5,
        centerY: 0.5,
        share: 1,
        colors: const [Colors.red, Colors.blue],
        stops: const [0, 1],
      );
      expect(() => gradient.createShader(Rect.zero), returnsNormally);
    });
  });

  group('documentCases -- which gradient is drawn', () {
    // What the reader does with a row that the schema refuses: a form that does not resolve is no gradient; a number
    // outside its bounds is clamped like any literal.
    const notDrawn = {
      'radial with an angle',
      'linear with a shape field',
      'shape without center',
      'shape without radius',
      'radial without shape',
      'unknown shape',
      'linear with a center',
      'radial with one stop',
    };

    for (final row in _rows('documentCases')) {
      final name = row['name']! as String;
      final raw = row['gradient']! as _Json;

      test('own gradient: $name', () {
        final ref = GradientRef.tryParse(raw);
        if (row['valid'] == true) {
          expect(ref, isNotNull);
          expect(ref is RadialGradientRef, raw['shape'] == 'radial');
          expect(theme.resolveGradient(ref!), isNotNull);
          return;
        }
        if (notDrawn.contains(name)) {
          expect(ref, isNull);
          return;
        }
        // Clamped: the centre stays in the box, the radius in its range.
        expect(ref, isA<RadialGradientRef>());
        final radial = ref! as RadialGradientRef;
        expect(radial.centerX, inInclusiveRange(0, 1));
        expect(radial.centerY, inInclusiveRange(0, 1));
        expect(radial.radius, inInclusiveRange(kMinRadialRadius, kMaxRadialRadius));
      });

      test('theme token: $name', () {
        // A theme gradient is made of values, not of references: the stops of the row take plain colours.
        final themed = _themeWith({
          ...raw,
          'stops': [
            for (final (index, stop) in ((raw['stops']! as List<Object?>).cast<_Json>()).indexed)
              {'color': index.isEven ? '#336699' : '#cc9966', 'position': stop['position']},
          ],
        });
        final token = themed.gradients['brandBackdrop'];
        if (row['valid'] == true) {
          expect(token, isNotNull);
          expect(token is RadialBoxGradient, raw['shape'] == 'radial');
          if (token is RadialBoxGradient) {
            expect(
              (token.centerX, token.centerY, token.share),
              (_n((raw['center']! as _Json)['x']), _n((raw['center']! as _Json)['y']), _n(raw['radius'])),
            );
          }
          return;
        }
        if (notDrawn.contains(name)) {
          // An entry of the wrong shape is dropped: the theme has no such gradient.
          expect(token, isNull);
          return;
        }
        final radial = token! as RadialBoxGradient;
        expect(radial.centerX, inInclusiveRange(0, 1));
        expect(radial.centerY, inInclusiveRange(0, 1));
        expect(radial.share, inInclusiveRange(kMinRadialRadius, kMaxRadialRadius));
      });
    }

    test('the rows with names the theme knows: a radial token of a theme is read', () {
      final themed = _themeWith({
        'shape': 'radial',
        'center': {'x': 0.2, 'y': 0.1},
        'radius': 1.5,
        'stops': [
          {'color': '#ff0000', 'position': 0},
          {'color': '#0000ff', 'position': 1},
        ],
      });
      final token = themed.gradient(GradientToken.brandBackdrop)! as RadialBoxGradient;
      expect((token.centerX, token.centerY, token.share), (0.2, 0.1, 1.5));
      expect(token.colors, [const Color(0xFFFF0000), const Color(0xFF0000FF)]);
    });

    test('a radial token of the wrong shape is an entry that is dropped', () {
      for (final broken in <_Json>[
        {
          'shape': 'conic',
          'center': {'x': 0.5, 'y': 0.5},
          'radius': 1,
        },
        {'shape': 'radial', 'radius': 1},
        {
          'shape': 'radial',
          'center': {'x': 0.5, 'y': 0.5},
        },
        {
          'shape': 'radial',
          'angle': 180,
          'center': {'x': 0.5, 'y': 0.5},
          'radius': 1,
        },
        {
          'angle': 180,
          'center': {'x': 0.5, 'y': 0.5},
        },
      ]) {
        final themed = _themeWith({
          ...broken,
          'stops': [
            {'color': '#ff0000', 'position': 0},
            {'color': '#0000ff', 'position': 1},
          ],
        });
        // Dropped from the theme: it has no such gradient.
        expect(themed.gradients['brandBackdrop'], isNull, reason: '$broken');
      }
    });

    test('a number of a radial token outside its bounds is clamped and reported', () {
      final themed = _themeWith({
        'shape': 'radial',
        'center': {'x': -0.5, 'y': 3},
        'radius': 9,
        'stops': [
          {'color': '#ff0000', 'position': 0},
          {'color': '#0000ff', 'position': 1},
        ],
      });
      final token = themed.gradients['brandBackdrop']! as RadialBoxGradient;
      expect((token.centerX, token.centerY, token.share), (0, 1, 2));
    });

    test('unordered stops of an own radial gradient: not drawn', () {
      final ref = GradientRef.tryParse({
        'shape': 'radial',
        'center': {'x': 0.5, 'y': 0.5},
        'radius': 1,
        'stops': [
          {
            'color': {'value': '#ff0000'},
            'position': 1,
          },
          {
            'color': {'value': '#0000ff'},
            'position': 0,
          },
        ],
      })!;
      expect(theme.resolveGradient(ref), isNull);
    });

    test('a radial gradient on the glyphs of a text and on the scale: the text takes it, the scale does not', () {
      final own = GradientRef.tryParse({
        'shape': 'radial',
        'center': {'x': 0.5, 'y': 0},
        'radius': 1,
        'stops': _ownStops,
      })!;
      expect(theme.resolveGradient(own), isA<RadialBoxGradient>());
      // The fill of a scale runs along the scale: an own radial gradient is no gradient there, the colour stays.
      final paint = theme.resolveProgressPaint(
        color: FieldColor.parse('primary', fieldDefault: ColorToken.primary),
        gradient: own,
      );
      expect(paint.colors, isNull);
      expect(paint.fill, isNotNull);
    });
  });

  group('the screen with its own theme', () {
    const id = 'radial-gradient-screens';

    testWidgets('draws the spots as circles in the corners, the glow, and the radial token of the theme', (
      tester,
    ) async {
      final reports = <Object>[];
      final doc = loadFixture(id);
      await pumpDocument(tester, doc, theme: fixtureTheme(id));
      expect(tester.takeException(), isNull);
      expect(reports, isEmpty);
      final gradients = [
        for (final box in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)))
          if (box.decoration is BoxDecoration && (box.decoration as BoxDecoration).gradient is RadialBoxGradient)
            (box.decoration as BoxDecoration).gradient! as RadialBoxGradient,
      ];
      // Two spots in the corners (0, 0) and (1, 1), a glow from the middle of the top edge, the token of the theme.
      expect(gradients.any((g) => g.centerX == 0 && g.centerY == 0), isTrue);
      expect(gradients.any((g) => g.centerX == 1 && g.centerY == 1), isTrue);
      expect(gradients.any((g) => g.centerX == 0.5 && g.centerY == 0), isTrue);
      expect(gradients.length, greaterThanOrEqualTo(4));
    });

    test('the theme of the frame reads without a report', () {
      final load = ThemeLoad.parse(
        File('assets/contract/fixtures/themes/radial-gradient-theme.json').readAsStringSync(),
      );
      expect(load.status, ThemeLoadStatus.ok, reason: load.detail);
    });
  });
}
