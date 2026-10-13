/// The icon library (schema 9.3.0).
///
/// Before 9.3.0 the renderer drew ten icons with Material glyphs - that is, with DIFFERENT
/// drawings than the builder canvas - and put a star in place of an unfamiliar name.
/// Now the drawing is contract data: 332 SVG bodies that the renderer parses and draws
/// itself (`icon_glyph.dart`).
///
/// WHAT IS CHECKED HERE IS CHECKED IN PIXELS, NOT FIELDS. A test asking `painter.mirrored`
/// or `shape.filled` would compare the code with what we said about it. An arc
/// drawn the wrong way and an arrow flipped twice have correct fields.
/// So the drawing is rasterised and compared: with the same SVG parsed by an
/// INDEPENDENT parser (`flutter_svg`), and with its own mirror image.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart' show SvgStringLoader, vg;
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/icon_set.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/icon_glyph.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';
import 'support/icons.dart';

/// Raster in logical pixels x [ratio], RGBA.
final class _Raster {
  _Raster(this.width, this.height, this.bytes);

  final int width;
  final int height;
  final Uint8List bytes;

  int _at(int x, int y) => (y * width + x) * 4;

  Color pixel(int x, int y) {
    final i = _at(x, y);
    return Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]);
  }

  int alpha(int x, int y) => bytes[_at(x, y) + 3];

  _Raster crop(Rect rect) {
    final left = rect.left.round(), top = rect.top.round();
    final w = rect.width.round(), h = rect.height.round();
    final out = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      final from = _at(left, top + y);
      out.setRange(y * w * 4, (y + 1) * w * 4, bytes, from);
    }
    return _Raster(w, h, out);
  }

  _Raster flipped() {
    final out = Uint8List(bytes.length);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final from = _at(width - 1 - x, y), to = _at(x, y);
        out.setRange(to, to + 4, bytes, from);
      }
    }
    return _Raster(width, height, out);
  }

  /// Pixels that differ from [background] - the "ink".
  bool isInk(int x, int y, Color background) {
    final i = _at(x, y);
    final dr = bytes[i] - (background.r * 255).round();
    final dg = bytes[i + 1] - (background.g * 255).round();
    final db = bytes[i + 2] - (background.b * 255).round();
    return dr.abs() + dg.abs() + db.abs() > 48;
  }

  /// How many pixels are touched at all (raster on transparent).
  int get painted {
    var count = 0;
    for (var i = 3; i < bytes.length; i += 4) {
      if (bytes[i] > 24) count++;
    }
    return count;
  }

  int inkCount(Color background) {
    var count = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (isInk(x, y, background)) count++;
      }
    }
    return count;
  }

  /// Mean abscissa of the ink in the middle third of rows, from the centre, as a fraction
  /// of the width: positive - the tip points right. That is where a chevron's tip is.
  double tipX(Color background) {
    var sum = 0.0;
    var count = 0;
    for (var y = height * 5 ~/ 12; y < height * 7 ~/ 12; y++) {
      for (var x = 0; x < width; x++) {
        if (isInk(x, y, background)) {
          sum += x + 0.5;
          count++;
        }
      }
    }
    return count == 0 ? 0 : (sum / count - width / 2) / width;
  }

  /// The same for the vertical: positive - the tip points down.
  double tipY(Color background) {
    var sum = 0.0;
    var count = 0;
    for (var x = width * 5 ~/ 12; x < width * 7 ~/ 12; x++) {
      for (var y = 0; y < height; y++) {
        if (isInk(x, y, background)) {
          sum += y + 0.5;
          count++;
        }
      }
    }
    return count == 0 ? 0 : (sum / count - height / 2) / height;
  }
}

/// The fraction by which two rasters diverge: the sum of channel differences over the sum of
/// the first one's "ink". Zero - the same drawing; anti-aliased edges give hundredths.
double _difference(_Raster a, _Raster b) {
  expect((a.width, a.height), (b.width, b.height));
  var diff = 0, ink = 0;
  for (var i = 0; i < a.bytes.length; i++) {
    diff += (a.bytes[i] - b.bytes[i]).abs();
    ink += a.bytes[i] > b.bytes[i] ? a.bytes[i] : b.bytes[i];
  }
  return ink == 0 ? 0 : diff / ink;
}

Future<_Raster> _rasterOf(ui.Image image) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
  return _Raster(image.width, image.height, data.buffer.asUint8List());
}

/// A set drawing painted by OUR painter: black on transparent.
Future<_Raster> _ours(IconToken icon, int side, {bool mirrored = false, Color color = const Color(0xFF000000)}) =>
    _painted(iconDrawingOf(icon)!, side, mirrored: mirrored, color: color);

Future<_Raster> _painted(IconDrawing drawing, int side, {bool mirrored = false, Color color = const Color(0xFF000000)}) async {
  final recorder = ui.PictureRecorder();
  IconGlyphPainter(drawing: drawing, color: color, mirrored: mirrored)
      .paint(Canvas(recorder), Size.square(side.toDouble()));
  return _rasterOf(await recorder.endRecording().toImage(side, side));
}

/// TIGHT outline bounds - by the points of the line itself. `Path.getBounds` also counts
/// the control points of curves and arcs, so it does not fit "where did the arc go".
Rect _tight(Path path) {
  Rect? bounds;
  for (final metric in path.computeMetrics()) {
    const steps = 400;
    for (var i = 0; i <= steps; i++) {
      final point = metric.getTangentForOffset(metric.length * i / steps)!.position;
      final dot = Rect.fromLTWH(point.dx, point.dy, 0, 0);
      bounds = bounds == null ? dot : bounds.expandToInclude(dot);
    }
  }
  return bounds!;
}

Matcher _rect(double left, double top, double right, double bottom) => isA<Rect>()
    .having((r) => r.left, 'left', closeTo(left, 0.01))
    .having((r) => r.top, 'top', closeTo(top, 0.01))
    .having((r) => r.right, 'right', closeTo(right, 0.01))
    .having((r) => r.bottom, 'bottom', closeTo(bottom, 0.01));

/// The same drawing through `flutter_svg`: a root from the grid + the body is the string
/// a web reader would put into `<svg>`. An independent parser of paths and arcs.
Future<_Raster> _reference(String name, int side) async {
  final svg =
      "<svg xmlns='http://www.w3.org/2000/svg' viewBox='${kIconGrid['viewBox']}' fill='${kIconGrid['fill']}' "
      "stroke='black' stroke-width='${kIconGrid['strokeWidth']}' stroke-linecap='${kIconGrid['strokeLinecap']}' "
      "stroke-linejoin='${kIconGrid['strokeLinejoin']}'>${kIconBodies[name]!.replaceAll('currentColor', 'black')}</svg>";
  final info = await vg.loadPicture(SvgStringLoader(svg), null);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(side / kIconGridSize);
  canvas.drawPicture(info.picture);
  final raster = await _rasterOf(await recorder.endRecording().toImage(side, side));
  info.picture.dispose();
  return raster;
}

/// Snapshot of everything painted under the nearest repaint boundary.
Future<(_Raster, double)> _screen(WidgetTester tester, {double ratio = 4}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: ratio)))!;
  final raster = (await tester.runAsync(() => _rasterOf(image)))!;
  return (raster, ratio);
}

/// Raster of one widget's rectangle.
Future<_Raster> _shot(WidgetTester tester, Finder finder) async {
  final (raster, ratio) = await _screen(tester);
  final rect = tester.getRect(finder);
  return raster.crop(Rect.fromLTWH(rect.left * ratio, rect.top * ratio, rect.width * ratio, rect.height * ratio));
}

Map<String, Object?> _iconNode(Object? name, {String size = 'md', String id = 'icon', Map<String, Object?>? style, bool withName = true}) => {
  'id': id,
  'type': 'Icon',
  'props': {if (withName) 'name': name, 'size': size},
  'style': ?style,
};

/// Values in place of an icon name that the reader cannot draw.
const List<(String, Object?)> _unreadable = [
  ('unknown name', 'no-such-icon'),
  ('object (this is how an icon from the media library would arrive)', {'kind': 'media', 'url': 'https://example.com/a.svg'}),
  ('number', 42),
  ('null', null),
  ('list', ['star']),
  ('object prototype name: toString', 'toString'),
  ('object prototype name: constructor', 'constructor'),
  ('object prototype name: __proto__', '__proto__'),
  ('Dart name: hashCode', 'hashCode'),
  ('empty string', ''),
  ('name with a space', ' star'),
  ('name in a different case', 'Star'),
];

void main() {
  final theme = RenderTheme.fallback();
  final surface = theme.color(ColorToken.surface);

  group('body parsing', () {
    test('EVERY one of the 332 names parses, and the drawing lies within the grid', () {
      expect(IconToken.values, hasLength(332));
      for (final icon in IconToken.values) {
        final IconDrawing drawing;
        try {
          drawing = parseIconBody(kIconBodies[icon.wire]!);
        } on FormatException catch (error) {
          fail('${icon.wire}: ${error.message}');
        }
        expect(drawing.shapes, isNotEmpty, reason: icon.wire);
        // The drawing lies in the 24 x 24 canvas (with tolerance for line ends). An arc
        // in the wrong direction or a relative command read as absolute usually
        // pushes the outline out of it. The bounds are TIGHT: control points are not counted.
        for (final shape in drawing.shapes) {
          final bounds = _tight(shape.path);
          expect(bounds.left, greaterThanOrEqualTo(-0.01), reason: '${icon.wire}: $bounds');
          expect(bounds.top, greaterThanOrEqualTo(-0.01), reason: '${icon.wire}: $bounds');
          expect(bounds.right, lessThanOrEqualTo(kIconGridSize + 0.01), reason: '${icon.wire}: $bounds');
          expect(bounds.bottom, lessThanOrEqualTo(kIconGridSize + 0.01), reason: '${icon.wire}: $bounds');
        }
        expect(drawing.bounds.width + drawing.bounds.height, greaterThan(0), reason: '${icon.wire}: empty drawing');
        expect(iconDrawingOf(icon), isNotNull, reason: icon.wire);
      }
    });

    test('parsed on demand and only once: the same drawing for all instances', () {
      expect(identical(iconDrawingOf(IconToken.parse('flame')), iconDrawingOf(IconToken.parse('flame'))), isTrue);
      expect(iconDrawingOf(IconToken.unknown), isNull);
    });

    test('numbers glued without a separator', () {
      // `M12 2.5l2.9 6.2` - a command right against a number; `-4-2` - minus as a
      // separator; `.5.5` - two numbers; arc flags one digit each.
      expect(_tight(parseSvgPathData('M12 2.5l2.9 6.2')), _rect(12, 2.5, 14.9, 8.7));
      expect(_tight(parseSvgPathData('M1 1l.5.5')), _rect(1, 1, 1.5, 1.5));
      expect(_tight(parseSvgPathData('M20 5l-4-2')), _rect(16, 3, 20, 5));
      expect(_tight(parseSvgPathData('M1e1 2E0L12,4')), _rect(10, 2, 12, 4));
      // `0110` - flags `0`, `1` and the number `10`.
      expect(_tight(parseSvgPathData('M2 12a5 5 0 0110 0')), _rect(2, 7, 12, 12));
      expect(_tight(parseSvgPathData('M2 12a5 5 0 0 1 10 0')), _rect(2, 7, 12, 12));
    });

    test('arc: the sweep flag decides the direction, large-arc picks which of the two', () {
      // Semicircle from (2,12) to (22,12). `sweep=1` is clockwise on
      // screen (Y axis down), i.e. THROUGH THE TOP; `sweep=0` goes through the bottom.
      expect(_tight(parseSvgPathData('M2 12A10 10 0 0 1 22 12')), _rect(2, 2, 22, 12));
      expect(_tight(parseSvgPathData('M2 12A10 10 0 0 0 22 12')), _rect(2, 12, 22, 22));
      // A quarter and three quarters of the same circle of radius 10 between (12,2) and (22,12).
      expect(_tight(parseSvgPathData('M12 2A10 10 0 0 1 22 12')), _rect(12, 2, 22, 12));
      expect(_tight(parseSvgPathData('M12 2A10 10 0 1 0 22 12')), _rect(2, 2, 22, 22));
      // A relative arc equals the absolute one.
      expect(_tight(parseSvgPathData('M2 12a10 10 0 0 1 20 0')), _rect(2, 2, 22, 12));
      // Ellipse: unequal radii, zero rotation.
      expect(_tight(parseSvgPathData('M2 12A10 5 0 0 1 22 12')), _rect(2, 7, 22, 12));
      // A radius too small for the chord is enlarged to half the chord (SVG F.6.6).
      expect(_tight(parseSvgPathData('M2 12A1 1 0 0 1 22 12')), _rect(2, 2, 22, 12));
      // A zero radius is a line segment.
      expect(_tight(parseSvgPathData('M2 12A0 5 0 0 1 22 12')), _rect(2, 12, 22, 12));
    });

    test('implicit repetition, H/V, closing and shorthand curves', () {
      expect(_tight(parseSvgPathData('M1 1 5 1 5 5')), _rect(1, 1, 5, 5));
      expect(_tight(parseSvgPathData('m1 1 4 0 0 4')), _rect(1, 1, 5, 5));
      expect(_tight(parseSvgPathData('M1 1h4v4H1z')), _rect(1, 1, 5, 5));
      // After `z` the current point is the start of the subpath.
      expect(_tight(parseSvgPathData('M2 2h4v4zl-1 0')).left, closeTo(1, 0.01));
      // `t` reflects the control point of the previous `q`: the wave goes first
      // up (to 5), then the same amount DOWN (to 15).
      expect(_tight(parseSvgPathData('M0 10q5-10 10 0t10 0')), _rect(0, 5, 20, 15));
      // `s` is the same for a cubic: 10 +- 6.
      expect(_tight(parseSvgPathData('M0 10c0-8 10-8 10 0s10 8 10 0')), _rect(0, 4, 20, 16));
      // `s` without a previous cubic: the first control point is the current point.
      expect(_tight(parseSvgPathData('M0 0s0 10 10 10')).bottom, closeTo(10, 0.01));
    });

    test('anything outside the format vocabulary is a rejection, not "I will draw what I understood"', () {
      for (final body in [
        '',
        'text',
        "<script src='x'/>",
        "<image href='https://example.com/a.png'/>",
        "<path d='M0 0h1' style='fill:red'/>",
        "<path d='M0 0h1' onload='x'/>",
        "<path d='M0 0h1' fill='red'/>",
        "<path d='M0 0h1' stroke='url(#a)'/>",
        "<path d='M0 0h1' stroke-width='wide'/>",
        "<path d='M0 0h1'/>tail",
        "<g><path d='M0 0h1'/></g>",
        "<path d='M0 0h1'><title>x</title></path>",
        '<path d="M0 0h1"/>',
        "<path d='X0 0'/>",
        "<path d='10 10'/>",
        "<path d='M0 0a1 1 0 2 1 1 1'/>",
        "<circle cx='1' cy='1'/>",
        "<rect x='1' y='1' width='w' height='2'/>",
        "<polygon points=''/>",
        "<circle cx='1' cy='1' r='1' d='M0 0'/>",
      ]) {
        expect(() => parseIconBody(body), throwsFormatException, reason: body);
      }
    });
  });

  group('the drawing matches the independent SVG parser', () {
    /*
     * The most expensive and most valuable test of the file. A custom parser easily reads all
     * 332 bodies "without error" and draws an arc the wrong way: the grid bounds do not
     * always catch that. The same string a web reader puts into `<svg>` is drawn by
     * `flutter_svg` (a different path parser, arcs via curves), and the two rasters
     * must match. Differences at anti-aliased edges are hundredths.
     */
    testWidgets('all 332 icons: our raster = the flutter_svg raster', (tester) async {
      const side = 96;
      final worst = <String, double>{};
      await tester.runAsync(() async {
        for (final icon in IconToken.values) {
          final ours = await _ours(icon, side);
          final reference = await _reference(icon.wire, side);
          expect(ours.painted, greaterThan(side), reason: '${icon.wire}: nothing painted');
          final difference = _difference(ours, reference);
          if (difference > 0.04) worst[icon.wire] = difference;
        }
      });
      expect(worst, isEmpty, reason: 'drawings diverged from flutter_svg');
    });

    testWidgets('the test itself sees an error: a foreign drawing and a mirrored one do not match', (tester) async {
      await tester.runAsync(() async {
        final flame = await _ours(IconToken.parse('flame'), 96);
        expect(_difference(flame, await _reference('snowflake', 96)), greaterThan(0.5));
        expect(_difference(flame.flipped(), await _reference('flame', 96)), greaterThan(0.2));
      });
    });
  });

  group('fill, stroke and thickness', () {
    test('lock: a filled rectangle without a stroke and an outlined shackle', () {
      final lock = iconDrawingOf(IconToken.lock)!;
      expect(lock.shapes, hasLength(2));
      expect((lock.shapes[0].filled, lock.shapes[0].stroked), (true, false));
      expect((lock.shapes[1].filled, lock.shapes[1].stroked), (false, true));
      expect(lock.shapes[1].strokeWidth, kIconGridStrokeWidth);
    });

    test('check and chevron are thicker than x; filled AND stroked also occurs', () {
      final check = iconDrawingOf(IconToken.check)!.shapes.single;
      final chevron = iconDrawingOf(IconToken.chevron)!.shapes.single;
      final cross = iconDrawingOf(IconToken.parse('x'))!.shapes;
      expect(check.strokeWidth, 2.5);
      expect(chevron.strokeWidth, 2.5);
      expect(cross.every((shape) => shape.strokeWidth == 2), isTrue);
      final both = iconDrawingOf(IconToken.parse('tag'))!.shapes.where((shape) => shape.filled && shape.stroked);
      expect(both, isNotEmpty, reason: 'the dot in `tag` is filled and stroked');
    });

    testWidgets('in pixels: the lock body is solid, the `square` square is empty inside', (tester) async {
      await tester.runAsync(() async {
        const side = 96;
        final lock = await _ours(IconToken.lock, side);
        final circle = await _ours(IconToken.parse('circle'), side);
        // (12, 15.5) of the grid is the middle of the lock body: filled. The `circle` is
        // outline only: empty inside.
        expect(lock.alpha(48, 62), 255);
        expect(circle.alpha(48, 48), 0);
        expect(circle.alpha(48, 8), greaterThan(200));
        // The shackle is an outline: there is ink at (12, 3), and none inside the arc (12, 7).
        expect(lock.alpha(48, 12), greaterThan(200));
        expect(lock.alpha(48, 28), 0);
        // The own `stroke-width` works: the same dash at 2.5 is thicker than the grid dash.
        int thickness(_Raster raster) {
          var rows = 0;
          for (var y = 0; y < side; y++) {
            if (raster.alpha(side ~/ 2, y) > 127) rows++;
          }
          return rows;
        }

        final thin = await _painted(parseIconBody("<path d='M5 12h14'/>"), side);
        final thick = await _painted(parseIconBody("<path stroke-width='2.5' d='M5 12h14'/>"), side);
        expect(thickness(thin), 8);
        expect(thickness(thick), 10);
        // `stroke='none'` without a fill paints nothing; with a fill - only the body.
        final bare = await _painted(parseIconBody("<rect stroke='none' fill='currentColor' x='8' y='8' width='8' height='8'/>"), side);
        expect(bare.alpha(48, 48), 255);
        expect(bare.alpha(30, 48), 0, reason: 'no outline (half the thickness outward)');
        final outlined = await _painted(parseIconBody("<rect fill='currentColor' x='8' y='8' width='8' height='8'/>"), side);
        expect(outlined.alpha(30, 48), 255, reason: 'filled AND stroked');
      });
    });

    testWidgets('stroke thickness grows with the drawing, not stuck at two pixels', (tester) async {
      await tester.runAsync(() async {
        // The horizontal dash of `minus` (M5 12h14): thickness in pixels = 2/24 of the side.
        for (final side in [24, 96]) {
          final minus = await _ours(IconToken.parse('minus'), side);
          var thickness = 0;
          for (var y = 0; y < side; y++) {
            if (minus.alpha(side ~/ 2, y) > 127) thickness++;
          }
          expect(thickness, closeTo(side / 12, 1), reason: 'side $side');
        }
      });
    });

    testWidgets('a semi-transparent colour is applied ONCE: crossing strokes are not darker', (tester) async {
      await tester.runAsync(() async {
        // A cross is two strokes crossing at the centre. The row chevron takes its
        // colour with the secondary part opacity; without the layer the centre would be
        // twice as dense.
        final cross = await _ours(IconToken.parse('x'), 96, color: const Color(0x80000000));
        final centre = cross.alpha(48, 48);
        final arm = cross.alpha(32, 32);
        expect(arm, closeTo(128, 3));
        expect(centre, closeTo(128, 3));
      });
    });
  });

  group('colour is the node foreground', () {
    testWidgets('style.color recolours both stroke and fill', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          _iconNode('lock', size: 'lg', style: {'color': 'danger'}),
        ]),
        theme: theme,
      );
      final danger = theme.color(ColorToken.danger);
      expect(iconColorOf(tester, findIcon(IconToken.lock)), danger);

      final shot = await _shot(tester, findIcon(IconToken.lock));
      // The body (fill) and the shackle (stroke) are the same colour.
      final body = shot.pixel(shot.width ~/ 2, (shot.height * 15.5 / 24).round());
      final shackle = shot.pixel(shot.width ~/ 2, (shot.height * 3 / 24).round());
      expect(body, isSameColorAs(danger));
      expect(shackle, isSameColorAs(danger));
    });

    testWidgets('without its own colour - inherited from an ancestor; at the root - onSurface', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          _iconNode('flame', id: 'root-icon'),
          {
            'id': 'card',
            'type': 'Container',
            'props': const <String, Object?>{},
            'style': {'color': 'accent'},
            'children': [_iconNode('snowflake', id: 'inherited')],
          },
        ]),
        theme: theme,
      );
      expect(iconColorOf(tester, findIcon(IconToken.parse('flame'))), theme.color(ColorToken.onSurface));
      expect(iconColorOf(tester, findIcon(IconToken.parse('snowflake'))), theme.color(ColorToken.accent));
    });

    testWidgets('the drawing carries no colour of its own: all the ink is one colour', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          _iconNode('palette', size: 'lg', style: {'color': 'primary'}),
        ]),
        theme: theme,
      );
      final primary = theme.color(ColorToken.primary);
      final shot = await _shot(tester, findIcon(IconToken.parse('palette')));
      var solid = 0;
      for (var y = 0; y < shot.height; y++) {
        for (var x = 0; x < shot.width; x++) {
          final pixel = shot.pixel(x, y);
          // Solid ink (not an anti-aliased edge) is exactly the node colour.
          if (shot.isInk(x, y, surface) && (pixel.r - primary.r).abs() < 0.02) solid++;
        }
      }
      expect(solid, greaterThan(100));
    });
  });

  group('first frame', () {
    testWidgets('the icon is painted in the same frame as the document', (tester) async {
      // WITHOUT an extra `pump`: a drawing that appeared on the next frame
      // (asynchronous parsing) would not exist yet.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: renderDocument(docWith([_iconNode('flame', size: 'lg')]), theme: theme, data: const {}),
          ),
        ),
      );
      final glyph = findIcon(IconToken.parse('flame'));
      expect(glyph, findsOneWidget);
      expect(find.descendant(of: glyph, matching: find.byType(CustomPaint)), findsOneWidget);
      final shot = await _shot(tester, glyph);
      expect(shot.inkCount(surface), greaterThan(50));
    });
  });

  group('mirroring in right-to-left writing', () {
    /// All 332 drawings on one grid: cell positions are fixed, the writing
    /// direction changes only for the glyph itself.
    Future<List<_Raster>> cells(WidgetTester tester, TextDirection direction) async {
      const cell = 32.0;
      const columns = 25;
      final icons = IconToken.values;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            child: ColoredBox(
              color: const Color(0xFFFFFFFF),
              child: Stack(
                children: [
                  for (var i = 0; i < icons.length; i++)
                    Positioned(
                      left: (i % columns) * cell,
                      top: (i ~/ columns) * cell,
                      child: Directionality(
                        textDirection: direction,
                        child: IconGlyph(icons[i], size: cell, color: const Color(0xFF000000)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      final (raster, ratio) = await _screen(tester, ratio: 2);
      return [
        for (var i = 0; i < icons.length; i++)
          raster.crop(Rect.fromLTWH((i % columns) * cell * ratio, (i ~/ columns) * cell * ratio, cell * ratio, cell * ratio)),
      ];
    }

    testWidgets('every listed name is mirrored EXACTLY ONCE, the rest are untouched', (tester) async {
      final ltr = await cells(tester, TextDirection.ltr);
      final rtl = await cells(tester, TextDirection.rtl);
      const white = Color(0xFFFFFFFF);
      final icons = IconToken.values;
      var mirrored = 0;
      for (var i = 0; i < icons.length; i++) {
        final name = icons[i].wire;
        expect(ltr[i].inkCount(white), greaterThan(20), reason: '$name: nothing painted');
        final same = _difference(rtl[i], ltr[i]);
        if (kMirroredIcons.contains(name)) {
          mirrored++;
          final flipped = _difference(rtl[i], ltr[i].flipped());
          expect(flipped, lessThan(0.01), reason: '$name: in RTL this is not a mirror of the LTR drawing');
          // A drawing mirrored TWICE would match the original.
          expect(same, greaterThan(0.01), reason: '$name: in RTL the drawing did not change (mirrored twice or never)');
        } else {
          expect(same, 0, reason: '$name: not in the list, yet it changed in RTL');
        }
      }
      expect(mirrored, 29);
    });

    testWidgets('a mirror, not a rotation: `list-checks` keeps its ticks upward', (tester) async {
      await tester.runAsync(() async {
        final icon = IconToken.parse('list-checks');
        final plain = await _ours(icon, 96);
        final mirrored = await _ours(icon, 96, mirrored: true);
        expect(_difference(mirrored, plain.flipped()), lessThan(0.01));
      });
    });

    Map<String, Object?> localized(List<Map<String, Object?>> children) => {
      'schemaVersion': UiDocument.supportedSchemaVersion,
      'documentId': 'rtl',
      'name': 'rtl',
      'initialScreenId': 'inline',
      'screens': [screenEntry('inline', children)],
      'localization': {
        'defaultLocale': 'en',
        'locales': ['en', 'ar'],
        'strings': {
          'ar': {'t': 'عنوان'},
        },
      },
    };

    Map<String, Object?> keyed(String value) => {'kind': 'literal', 'value': value, 'key': 't'};

    for (final (locale, sign) in [('en', 1), ('ar', -1)]) {
      testWidgets('$locale: Icon widget - `arrow-right` points to the END of the line, `play` always points right', (tester) async {
        await pumpDocument(
          tester,
          UiDocument.fromJson(
            localized([
              {'id': 'txt', 'type': 'Text', 'props': {'content': keyed('Title')}},
              _iconNode('arrow-right', id: 'a', size: 'lg'),
              _iconNode('play', id: 'p', size: 'lg'),
            ]),
          ),
          theme: theme,
          locale: locale,
        );
        final arrow = await _shot(tester, findIcon(IconToken.parse('arrow-right')));
        final play = await _shot(tester, findIcon(IconToken.parse('play')));
        // The arrow tip is where the ink of the middle rows is offset from the centre.
        expect(arrow.tipX(surface).sign, 0.0 + sign, reason: 'arrow-right');
        // `play` is outside the list: the same drawing in both directions.
        final edge = _leftmostInk(play, surface) / play.width;
        expect(edge, lessThan(0.3), reason: 'the `play` triangle has its base on the left in both directions');
      });

      testWidgets('$locale: the AppBar "back" arrow points to the START of the line (in ar - right)', (tester) async {
        await pumpDocument(
          tester,
          UiDocument.fromJson(
            localized([
              {
                'id': 'bar',
                'type': 'AppBar',
                'props': {'title': keyed('Title'), 'showBack': true},
              },
            ]),
          ),
          theme: theme,
          locale: locale,
        );
        expect(findAppBarBack, findsOneWidget);
        expect(tester.widget<IconGlyph>(findAppBarBack).icon, IconToken.chevron);
        final back = await _shot(tester, findAppBarBack);
        // en: tip to the left (negative); ar: to the right - where we came from.
        expect(back.tipX(surface).sign, 0.0 - sign);
        expect(back.tipX(surface).abs(), greaterThan(0.08));
      });

      testWidgets('$locale: the row chevron points to the line end; the block chevron: collapsed - the same way, expanded - down', (tester) async {
        await pumpDocument(
          tester,
          UiDocument.fromJson(
            localized([
              {
                'id': 'tile',
                'type': 'ListTile',
                'props': {
                  'leading': {'kind': 'none'},
                  'title': keyed('Title'),
                  'trailing': {'kind': 'chevron'},
                },
              },
              {
                'id': 'acc',
                'type': 'Accordion',
                'props': {'title': {'kind': 'literal', 'value': 'Block'}, 'initiallyExpanded': false},
                'children': [
                  {'id': 'inside', 'type': 'Text', 'props': {'content': {'kind': 'literal', 'value': 'Inside'}}},
                ],
              },
            ]),
          ),
          theme: theme,
          locale: locale,
        );
        final chevrons = findIcon(IconToken.chevron);
        expect(chevrons, findsNWidgets(2));
        final row = await _shot(tester, chevrons.first);
        expect(row.tipX(surface).sign, 0.0 + sign, reason: 'row chevron');
        final collapsed = await _shot(tester, chevrons.last);
        expect(collapsed.tipX(surface).sign, 0.0 + sign, reason: 'collapsed block');

        await tester.tap(find.text('Block'));
        await tester.pumpAndSettle();
        expect(find.text('Inside'), findsOneWidget);
        final expanded = await _shot(tester, findIcon(IconToken.chevron).last);
        expect(expanded.tipY(surface), greaterThan(0.08), reason: 'expanded block - down, in both directions');
        expect(expanded.tipX(surface).abs(), lessThan(0.04));
      });
    }
  });

  group('an icon the reader cannot draw (unknownIcon, unreadableIconValue)', () {
    test('parsing: anything but a set name is IconToken.unknown, without an exception', () {
      for (final (label, value) in _unreadable) {
        expect(IconToken.parse(value), IconToken.unknown, reason: label);
      }
      expect(IconToken.unknown.isKnown, isFalse);
      expect(IconToken.unknown.isMirrored, isFalse);
      expect(iconDrawingOf(IconToken.unknown), isNull);
      // And a known name is exactly itself, not "the first of the list".
      expect(IconToken.parse('flame').wire, 'flame');
      expect(IconToken.parse('star'), IconToken.star);
    });

    for (final (label, value) in _unreadable) {
      testWidgets('Icon: $label - an empty box of the SAME size, no star', (tester) async {
        for (final size in ['sm', 'md', 'lg']) {
          await pumpDocument(tester, docWith([_iconNode('flame', size: size)]), theme: theme);
          final drawn = tester.getRect(find.byType(IconBox));

          await pumpDocument(tester, docWith([_iconNode(value, size: size)]), theme: theme);
          expect(tester.takeException(), isNull);
          expect(find.byType(IconBox), findsOneWidget, reason: 'the box remains');
          expect(tester.getRect(find.byType(IconBox)), drawn, reason: 'size $size');
          expect(tester.widget<IconGlyph>(find.byType(IconGlyph)).icon, IconToken.unknown);
          expect(findIcon(IconToken.star), findsNothing, reason: 'the field default is not substituted');
          expect(find.descendant(of: find.byType(IconGlyph), matching: find.byType(CustomPaint)), findsNothing);
          final shot = await _shot(tester, find.byType(IconBox));
          expect(shot.inkCount(surface), 0, reason: 'no drawing');
        }
      });
    }

    testWidgets('neighbours do not shift: a row with an unfamiliar icon is laid out like one with a familiar icon', (tester) async {
      Future<Rect> after(Object? name) async {
        await pumpDocument(
          tester,
          docWith([
            {
              'id': 'row',
              'type': 'Row',
              'props': {'gap': 'sm', 'align': 'center', 'justify': 'start', 'wrap': false, 'scrollable': false},
              'children': [_iconNode(name), textNode('Поруч')],
            },
            textNode('Під рядком', id: 'below'),
          ]),
          theme: theme,
        );
        return tester.getRect(find.text('Поруч')).expandToInclude(tester.getRect(find.text('Під рядком')));
      }

      final known = await after('flame');
      for (final (label, value) in _unreadable) {
        expect(await after(value), known, reason: label);
      }
    });

    testWidgets('no `name` field at all - the field default from the artifact (this is not an "unreadable value")', (tester) async {
      await pumpDocument(tester, docWith([_iconNode(null, withName: false)]), theme: theme);
      expect(tester.widget<IconGlyph>(find.byType(IconGlyph)).icon, IconToken.star);
    });

    testWidgets('a document with such icons parses whole and is not scared by the version', (tester) async {
      final doc = docWith([
        for (final (index, (_, value)) in _unreadable.indexed) _iconNode(value, id: 'i$index'),
        textNode('Решта екрана'),
      ]);
      expect(doc.isSupportedVersion, isTrue);
      expect(flattenDocument(doc).whereType<IconNode>(), hasLength(_unreadable.length));
      await pumpDocument(tester, doc, theme: theme);
      expect(tester.takeException(), isNull);
      expect(find.text('Решта екрана'), findsOneWidget);
    });
  });

  group('ListTile slots', () {
    Map<String, Object?> tile(Object? leading, Map<String, Object?> trailing) => {
      'id': 'tile',
      'type': 'ListTile',
      'props': {
        'leading': leading,
        'title': {'kind': 'literal', 'value': 'Рядок'},
        'trailing': trailing,
      },
    };
    Map<String, Object?> trailingText({Object? icon, bool withIcon = true}) => {
      'kind': 'text',
      'text': {'kind': 'literal', 'value': '+100'},
      if (withIcon) 'icon': icon,
    };

    testWidgets('both slots draw a NAME from the set, including a new one (not only the ten old ones)', (tester) async {
      await pumpDocument(
        tester,
        docWith([tile({'kind': 'icon', 'icon': 'flame'}, trailingText(icon: 'gem'))]),
        theme: theme,
      );
      final leading = findIcon(IconToken.parse('flame'));
      final trailing = findIcon(IconToken.parse('gem'));
      expect(leading, findsOneWidget);
      expect(trailing, findsOneWidget);
      expect((await _shot(tester, leading)).inkCount(surface), greaterThan(20));
      expect((await _shot(tester, trailing)).inkCount(surface), greaterThan(10));
      // Slot sizes did not change: leading is md, trailing is sm.
      expect(tester.widget<IconGlyph>(leading).size, theme.iconSize(IconSizeToken.md));
      expect(tester.widget<IconGlyph>(trailing).size, theme.iconSize(IconSizeToken.sm));
    });

    for (final (label, value) in _unreadable) {
      testWidgets('slots: $label - empty boxes of the same sizes, the row does not shift', (tester) async {
        await pumpDocument(
          tester,
          docWith([tile({'kind': 'icon', 'icon': 'trophy'}, trailingText(icon: 'star'))]),
          theme: theme,
        );
        final boxes = tester.widgetList(find.byType(IconBox)).map((w) => tester.getRect(find.byWidget(w))).toList();
        final title = tester.getRect(find.text('Рядок'));
        final amount = tester.getRect(find.text('+100'));
        expect(boxes, hasLength(2));

        await pumpDocument(
          tester,
          docWith([tile({'kind': 'icon', 'icon': value}, trailingText(icon: value))]),
          theme: theme,
        );
        expect(tester.takeException(), isNull);
        expect(
          tester.widgetList(find.byType(IconBox)).map((w) => tester.getRect(find.byWidget(w))).toList(),
          boxes,
          reason: 'both boxes are in place and of the same size',
        );
        expect(tester.getRect(find.text('Рядок')), title);
        expect(tester.getRect(find.text('+100')), amount);
        expect(findIcon(IconToken.star), findsNothing, reason: 'no star is substituted in the slots either');
        expect(findIcon(IconToken.trophy), findsNothing);
        for (final box in tester.widgetList(find.byType(IconBox))) {
          expect((await _shot(tester, find.byWidget(box))).inkCount(surface), 0);
        }
      });
    }

    testWidgets('an ABSENT trailing.icon - no icon, and no boxes either', (tester) async {
      await pumpDocument(tester, docWith([tile({'kind': 'none'}, trailingText(withIcon: false))]), theme: theme);
      expect(find.byType(IconBox), findsNothing);
      expect(find.byType(IconGlyph), findsNothing);
      expect(find.text('+100'), findsOneWidget);
    });

    test('model: a missing key and a key with null are different', () {
      TrailingText parse(Map<String, Object?> trailing) =>
          (flattenDocument(docWith([tile({'kind': 'none'}, trailing)])).whereType<ListTileNode>().single.trailing) as TrailingText;
      expect(parse(trailingText(withIcon: false)).icon, isNull);
      expect(parse(trailingText(icon: null)).icon, IconToken.unknown);
      expect(parse(trailingText(icon: 'gem')).icon!.wire, 'gem');
    });
  });

  group('icon-library-screens fixture', () {
    final doc = loadFixture('icon-library-screens');

    test('a 9.3.0 document parses, and EVERY set name in it is familiar', () {
      expect(doc.schemaVersion, '9.3.0');
      expect(doc.isSupportedVersion, isTrue);
      final icons = flattenDocument(doc).whereType<IconNode>().toList();
      expect(icons.where((node) => !node.name.isKnown), isEmpty);
      expect(icons.map((node) => node.name.wire).toSet(), IconToken.values.map((icon) => icon.wire).toSet());
    });

    for (final locale in ['en', 'ar']) {
      testWidgets('overview in language $locale paints without exceptions or overflows', (tester) async {
        tester.view.physicalSize = const Size(390 * 3, 3200 * 3);
        addTearDown(tester.view.reset);
        await pumpDocument(tester, doc, theme: theme, locale: locale);
        expect(tester.takeException(), isNull);
        expect(find.byType(IconGlyph), findsWidgets);
      });
    }

    testWidgets('the whole set catalogue paints', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 3200 * 3);
      addTearDown(tester.view.reset);
      final catalog = doc.screens.firstWhere((screen) => screen.screenId == 'catalog');
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: renderScreen(catalog, theme: theme, data: const {}))),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(IconGlyph), findsWidgets);
    });
  });
}

int _leftmostInk(_Raster raster, Color background) {
  for (var x = 0; x < raster.width; x++) {
    for (var y = 0; y < raster.height; y++) {
      if (raster.isInk(x, y, background)) return x;
    }
  }
  return raster.width;
}
