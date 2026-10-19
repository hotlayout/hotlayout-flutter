/// Icon drawings from the contract's icon set (schema 9.3.0).
///
/// How we draw and why: a private parser of the body (seven SVG elements, path data) into a
/// [Path] and a [CustomPainter], rather than `flutter_svg`, although that package is already a
/// dependency:
///
///  * FIRST FRAME. `flutter_svg` parses the string asynchronously (isolate/loader future), so
///    on the first frame the icon is missing and appears on the next one: flicker on every
///    screen and every list row, and a test that looks for the drawing right after
///    `pumpWidget` does not see it. A `Path` is built synchronously, so the icon is in the
///    same frame as the text beside it;
///  * COLOUR. The drawing carries no colour of its own: `currentColor` is the node's
///    foreground. Here it is simply the brush colour; in `flutter_svg` it is a `ColorFilter`
///    over a finished picture, i.e. one more layer per icon;
///  * TRUST BOUNDARY. The body format is a closed vocabulary: seven elements, their geometry,
///    three presentation attributes. The parser understands exactly that and nothing else: no
///    `href`, no `style`, no nesting;
///  * RELEASE BUILD. There is no longer an icon font for this set, so the font tree-shaker
///    (which has broken release builds before) does not touch these drawings.
///
/// Parsing cost: there is no point parsing all 332 bodies at start-up, since a screen usually
/// has a few icons. A body is parsed on first need and kept in a cache ([iconDrawingOf]); a
/// [Path] is immutable and shared by all instances.
library;

import '../report/report_hub.dart';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../model/icon_set.dart';
import '../model/tokens.dart';

/// One body element: the outline and how to paint it.
@immutable
final class IconShape {
  const IconShape({
    required this.path,
    required this.filled,
    required this.stroked,
    required this.strokeWidth,
  });

  /// In grid coordinates (24 x 24).
  final Path path;

  /// `fill='currentColor'`: filled with the foreground colour.
  final bool filled;

  /// There is a stroke unless the element said `stroke='none'`.
  final bool stroked;

  /// In grid units: its own `stroke-width` or `grid.strokeWidth`.
  final double strokeWidth;
}

/// A parsed icon body.
@immutable
final class IconDrawing {
  const IconDrawing(this.shapes);

  final List<IconShape> shapes;

  /// Bounds of all outlines in grid coordinates (without the line width).
  Rect get bounds {
    var all = shapes.first.path.getBounds();
    for (final shape in shapes.skip(1)) {
      all = all.expandToInclude(shape.path.getBounds());
    }
    return all;
  }
}

final Map<String, IconDrawing?> _drawings = {};

/// The drawing for an icon, or `null` when there is nothing to draw
/// ([IconToken.unknown]). Parsed on first need and remembered.
///
/// A body that fails to parse also gives `null` (and a log line) rather than an exception: the
/// set is bundled and checked by a test for every name, but a paint failure would take down
/// the host's screen over one glyph.
IconDrawing? iconDrawingOf(IconToken icon) {
  if (!icon.isKnown) return null;
  final name = icon.wire;
  if (_drawings.containsKey(name)) return _drawings[name];
  final body = kIconBodies[name];
  IconDrawing? drawing;
  if (body != null) {
    try {
      drawing = parseIconBody(body);
    } catch (error) {
      // ANY parse error, not just `FormatException`: a document may bring an icon from another
      // set, and a `RangeError` or `StateError` from Skia must not take down the host's screen; an
      // empty box is painted instead.
      ReportHub.ignored('icon "$name"', 'has a body this renderer cannot read ($error): an empty box is drawn');
    }
  }
  return _drawings[name] = drawing;
}

final RegExp _element = RegExp(r"<([a-z]+)((?:\s+[a-z][a-z0-9-]*='[^']*')*)\s*/>");
final RegExp _attribute = RegExp(r"([a-z][a-z0-9-]*)='([^']*)'");

/// Geometry attributes of each element (`format.elements` of the artifact).
const Map<String, Set<String>> _geometry = {
  'path': {'d'},
  'circle': {'cx', 'cy', 'r'},
  'ellipse': {'cx', 'cy', 'rx', 'ry'},
  'rect': {'x', 'y', 'width', 'height', 'rx', 'ry'},
  'line': {'x1', 'y1', 'x2', 'y2'},
  'polyline': {'points'},
  'polygon': {'points'},
};

/// Parses an icon body: a sequence of self-closing elements.
///
/// Throws [FormatException] on anything the format does not name: an unknown element or
/// attribute, text between elements, a presentation value outside the vocabulary. Drawing
/// "whatever came out" would show the wrong glyph.
IconDrawing parseIconBody(String body) {
  final shapes = <IconShape>[];
  var position = 0;
  for (final match in _element.allMatches(body)) {
    if (match.start != position) {
      throw FormatException('unexpected text in icon body', body, position);
    }
    position = match.end;
    final tag = match.group(1)!;
    final allowed = _geometry[tag];
    if (allowed == null) throw FormatException('unknown element <$tag>', body, match.start);

    var filled = false;
    var stroked = true;
    var strokeWidth = kIconGridStrokeWidth;
    final geometry = <String, String>{};
    for (final attribute in _attribute.allMatches(match.group(2)!)) {
      final name = attribute.group(1)!;
      final value = attribute.group(2)!;
      switch (name) {
        case 'fill':
          if (value != 'currentColor') throw FormatException("fill='$value'", body, match.start);
          filled = true;
        case 'stroke':
          if (value != 'none') throw FormatException("stroke='$value'", body, match.start);
          stroked = false;
        case 'stroke-width':
          strokeWidth = _number(value, body);
          if (strokeWidth <= 0) throw FormatException("stroke-width='$value'", body, match.start);
        default:
          if (!allowed.contains(name)) {
            throw FormatException('unknown attribute $name on <$tag>', body, match.start);
          }
          geometry[name] = value;
      }
    }
    shapes.add(
      IconShape(
        path: _pathOf(tag, geometry, body),
        filled: filled,
        stroked: stroked,
        strokeWidth: strokeWidth,
      ),
    );
  }
  if (position != body.length) throw FormatException('unexpected text in icon body', body, position);
  if (shapes.isEmpty) throw FormatException('empty icon body', body);
  return IconDrawing(List.unmodifiable(shapes));
}

double _number(String text, String body) {
  final value = double.tryParse(text.trim());
  if (value == null || !value.isFinite) throw FormatException('not a number: "$text"', body);
  return value;
}

Path _pathOf(String tag, Map<String, String> attributes, String body) {
  double read(String name, [double? fallback]) {
    final raw = attributes[name];
    if (raw == null) {
      if (fallback != null) return fallback;
      throw FormatException('<$tag> without $name', body);
    }
    return _number(raw, body);
  }

  // A measure that is never negative: `r`, `rx`, `ry`, `width`, `height`. A negative value is
  // not a drawing, rather than "the opposite" or "zero".
  double size(String name, [double? fallback]) {
    final value = read(name, fallback);
    if (value < 0) throw FormatException('negative $name="$value" on <$tag>', body);
    return value;
  }

  switch (tag) {
    case 'path':
      return parseSvgPathData(attributes['d'] ?? (throw FormatException('<path> without d', body)));
    case 'circle':
      return Path()..addOval(Rect.fromCircle(center: Offset(read('cx', 0), read('cy', 0)), radius: size('r')));
    case 'ellipse':
      return Path()..addOval(
        Rect.fromCenter(center: Offset(read('cx', 0), read('cy', 0)), width: size('rx') * 2, height: size('ry') * 2),
      );
    case 'rect':
      final rect = Rect.fromLTWH(read('x', 0), read('y', 0), size('width'), size('height'));
      // Of the two corner-radius measures, a missing one equals the other (SVG).
      final hasRx = attributes.containsKey('rx');
      final hasRy = attributes.containsKey('ry');
      if (!hasRx && !hasRy) return Path()..addRect(rect);
      final rx = hasRx ? size('rx') : size('ry');
      final ry = hasRy ? size('ry') : size('rx');
      return Path()..addRRect(
        RRect.fromRectAndRadius(
          rect,
          Radius.elliptical(math.min(rx, rect.width / 2), math.min(ry, rect.height / 2)),
        ),
      );
    case 'line':
      return Path()
        ..moveTo(read('x1', 0), read('y1', 0))
        ..lineTo(read('x2', 0), read('y2', 0));
    case 'polyline':
    case 'polygon':
      final scanner = _Scanner(attributes['points'] ?? (throw FormatException('<$tag> without points', body)));
      final path = Path();
      var first = true;
      while (scanner.hasMore) {
        final x = scanner.number();
        final y = scanner.number();
        first ? path.moveTo(x, y) : path.lineTo(x, y);
        first = false;
      }
      if (first) throw FormatException('<$tag> without points', body);
      if (tag == 'polygon') path.close();
      return path;
  }
  throw FormatException('unknown element <$tag>', body);
}

/// Reader of numbers from SVG path data.
///
/// Numbers are glued without a separator where the grammar allows: `M12 2.5l2.9 6.2`,
/// `a1 1 0 0 1-14 0`, `1.5.5` (that is `1.5` and `.5`), and arc flags are one digit each
/// (`a1 1 0 011 1`). `double.parse` on pieces between spaces cannot parse this.
final class _Scanner {
  _Scanner(this.source);

  final String source;
  int position = 0;

  static bool _isSeparator(int unit) => unit == 0x20 || unit == 0x2c || unit == 0x09 || unit == 0x0a || unit == 0x0d;
  static bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

  void skip() {
    while (position < source.length && _isSeparator(source.codeUnitAt(position))) {
      position++;
    }
  }

  bool get hasMore {
    skip();
    return position < source.length;
  }

  /// The next character is a command letter (not the start of a number).
  bool get atCommand {
    skip();
    if (position >= source.length) return false;
    final unit = source.codeUnitAt(position) | 0x20;
    return unit >= 0x61 && unit <= 0x7a;
  }

  String command() => source[position++];

  double number() {
    skip();
    final start = position;
    if (position < source.length && (source[position] == '-' || source[position] == '+')) position++;
    var digits = 0;
    while (position < source.length && _isDigit(source.codeUnitAt(position))) {
      position++;
      digits++;
    }
    if (position < source.length && source[position] == '.') {
      position++;
      while (position < source.length && _isDigit(source.codeUnitAt(position))) {
        position++;
        digits++;
      }
    }
    if (digits == 0) throw FormatException('number expected', source, start);
    if (position < source.length && (source[position] == 'e' || source[position] == 'E')) {
      // The exponent counts only if a number really follows it; otherwise it is not ours.
      var ahead = position + 1;
      if (ahead < source.length && (source[ahead] == '-' || source[ahead] == '+')) ahead++;
      if (ahead < source.length && _isDigit(source.codeUnitAt(ahead))) {
        while (ahead < source.length && _isDigit(source.codeUnitAt(ahead))) {
          ahead++;
        }
        position = ahead;
      }
    }
    final value = double.parse(source.substring(start, position));
    if (!value.isFinite) throw FormatException('number out of range', source, start);
    return value;
  }

  /// An arc flag: exactly one digit, `0` or `1`, with no separator after it.
  bool flag() {
    skip();
    if (position < source.length) {
      final char = source[position];
      if (char == '0' || char == '1') {
        position++;
        return char == '1';
      }
    }
    throw FormatException('arc flag expected', source, position);
  }
}

/// SVG path data (`d`) → [Path]. Handles ALL commands: `M L H V C S Q T A Z` in absolute and
/// relative form, implicit command repetition, smooth curves (`S`, `T`: reflection of the
/// previous control point) and elliptical arcs.
///
/// Everything is computed here in absolute coordinates rather than with the relative methods
/// of [Path]: `S`/`T` need the previous control point either way.
Path parseSvgPathData(String data) {
  final scanner = _Scanner(data);
  final path = Path();
  var x = 0.0, y = 0.0; // current point
  var startX = 0.0, startY = 0.0; // start of the subpath
  // Last control point of a cubic / quadratic curve; `null` means the previous command was not
  // a curve of the same kind, so there is nothing to reflect.
  double? cubicX, cubicY, quadX, quadY;
  String? command;

  while (scanner.hasMore) {
    if (scanner.atCommand) {
      command = scanner.command();
    } else if (command == null) {
      throw FormatException('path data must start with a command', data);
    } else if (command == 'M') {
      command = 'L'; // pairs after `M` are `L`
    } else if (command == 'm') {
      command = 'l';
    } else if (command == 'Z' || command == 'z') {
      throw FormatException('number after closepath', data, scanner.position);
    }

    final relative = command == command.toLowerCase();
    final dx = relative ? x : 0.0;
    final dy = relative ? y : 0.0;
    double? nextCubicX, nextCubicY, nextQuadX, nextQuadY;

    switch (command.toUpperCase()) {
      case 'M':
        x = scanner.number() + dx;
        y = scanner.number() + dy;
        startX = x;
        startY = y;
        path.moveTo(x, y);
      case 'L':
        x = scanner.number() + dx;
        y = scanner.number() + dy;
        path.lineTo(x, y);
      case 'H':
        x = scanner.number() + dx;
        path.lineTo(x, y);
      case 'V':
        y = scanner.number() + dy;
        path.lineTo(x, y);
      case 'C':
        final x1 = scanner.number() + dx, y1 = scanner.number() + dy;
        final x2 = scanner.number() + dx, y2 = scanner.number() + dy;
        x = scanner.number() + dx;
        y = scanner.number() + dy;
        path.cubicTo(x1, y1, x2, y2, x, y);
        nextCubicX = x2;
        nextCubicY = y2;
      case 'S':
        final x1 = cubicX == null ? x : 2 * x - cubicX, y1 = cubicY == null ? y : 2 * y - cubicY;
        final x2 = scanner.number() + dx, y2 = scanner.number() + dy;
        x = scanner.number() + dx;
        y = scanner.number() + dy;
        path.cubicTo(x1, y1, x2, y2, x, y);
        nextCubicX = x2;
        nextCubicY = y2;
      case 'Q':
        final x1 = scanner.number() + dx, y1 = scanner.number() + dy;
        x = scanner.number() + dx;
        y = scanner.number() + dy;
        path.quadraticBezierTo(x1, y1, x, y);
        nextQuadX = x1;
        nextQuadY = y1;
      case 'T':
        final x1 = quadX == null ? x : 2 * x - quadX, y1 = quadY == null ? y : 2 * y - quadY;
        x = scanner.number() + dx;
        y = scanner.number() + dy;
        path.quadraticBezierTo(x1, y1, x, y);
        nextQuadX = x1;
        nextQuadY = y1;
      case 'A':
        final rx = scanner.number().abs(), ry = scanner.number().abs();
        final rotation = scanner.number();
        final largeArc = scanner.flag();
        final sweep = scanner.flag();
        x = scanner.number() + dx;
        y = scanner.number() + dy;
        if (rx == 0 || ry == 0) {
          path.lineTo(x, y); // SVG: an arc with a zero radius is a line segment
        } else {
          // `rotation` in [Path.arcToPoint] is in degrees, as in SVG; radii too small for the chord are
          // enlarged by the engine itself (SVG rule F.6.6).
          path.arcToPoint(
            Offset(x, y),
            radius: Radius.elliptical(rx, ry),
            rotation: rotation,
            largeArc: largeArc,
            clockwise: sweep,
          );
        }
      case 'Z':
        path.close();
        x = startX;
        y = startY;
      default:
        throw FormatException('unknown path command "$command"', data, scanner.position);
    }
    cubicX = nextCubicX;
    cubicY = nextCubicY;
    quadX = nextQuadX;
    quadY = nextQuadY;
  }
  return path;
}

/// An icon drawing from the contract's set: a square with side [size].
///
/// The side grows with the system font scale (`iconGlyphMeasure: 'typography-font-size'`),
/// just as a font glyph grew with `applyTextScaling`. In right-to-left writing an icon from
/// `x-mirroredIcons` is MIRRORED horizontally, here and only here: nobody flips a drawing from
/// data on its own (this is no longer a Material glyph's `matchTextDirection`), so a second
/// rule "for a particular place" would turn the arrow back.
///
/// [IconToken.unknown] gives an empty square of the SAME size
/// (`unknownIcon: 'empty-box-same-size'`).
class IconGlyph extends StatelessWidget {
  const IconGlyph(this.icon, {required this.size, required this.color, super.key});

  final IconToken icon;

  /// Side before the system font scale: the size token's font size.
  final double size;

  /// The node's foreground: both outline and fill use it.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final side = MediaQuery.textScalerOf(context).scale(size);
    final drawing = iconDrawingOf(icon);
    return SizedBox.square(
      dimension: side,
      child: drawing == null
          ? null
          : CustomPaint(
              painter: IconGlyphPainter(
                drawing: drawing,
                color: color,
                mirrored: icon.isMirrored && Directionality.maybeOf(context) == TextDirection.rtl,
              ),
            ),
    );
  }
}

/// Paints an [IconDrawing] into a square centred on the canvas.
class IconGlyphPainter extends CustomPainter {
  const IconGlyphPainter({required this.drawing, required this.color, required this.mirrored});

  final IconDrawing drawing;
  final Color color;

  /// Mirror horizontally around the centre (`scale(-1, 1)`) rather than rotate.
  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    if (side <= 0) return;
    /*
     * A semi-transparent colour goes through a layer. Secondary parts (a row's chevron) take a
     * named colour with opacity, while the drawing's elements overlap: a fill under its own
     * outline, the two strokes of a cross. Painted one by one with a translucent brush they would
     * leave darker spots at the crossings. On the web the drawing is a mask over a single fill,
     * so opacity applies ONCE to the union of the shapes; the layer gives the same result. An
     * opaque colour (nearly always) needs no layer.
     */
    final opaque = color.withValues(alpha: 1);
    if (color.a < 1) {
      canvas.saveLayer(Offset.zero & size, Paint()..color = color);
    } else {
      canvas.save();
    }
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    if (mirrored) {
      canvas.translate(side, 0);
      canvas.scale(-1, 1);
    }
    // 24 grid units equal the side: the outline width scales WITH the drawing; it is not "2
    // logical pixels".
    canvas.scale(side / kIconGridSize);
    final fill = Paint()
      ..color = opaque
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = opaque
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final shape in drawing.shapes) {
      if (shape.filled) canvas.drawPath(shape.path, fill);
      if (shape.stroked) canvas.drawPath(shape.path, stroke..strokeWidth = shape.strokeWidth);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(IconGlyphPainter oldDelegate) =>
      !identical(oldDelegate.drawing, drawing) || oldDelegate.color != color || oldDelegate.mirrored != mirrored;
}

/// Key of the app bar's "back" arrow drawing. It is the same drawing as a row's chevron and
/// the expandable block's (the set's `chevron`), so a test or host that needs the arrow finds
/// it by key rather than by appearance.
const Key kAppBarBackGlyphKey = ValueKey<String>('hotlayout-app-bar-back');
