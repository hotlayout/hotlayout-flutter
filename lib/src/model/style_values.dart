import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import 'bindable.dart';
import 'border_dash.dart';
import 'tokens.dart';

/// "Token or own value": the forms of style values in contract 9.0.0.
///
/// Mirror of the builder's `style-values.ts`. Before 9.0.0 a style field accepted only a token name, and
/// anything the theme lacked could not be built at all. Now each such field accepts a token OR a value,
/// but the value is a type from the schema with bounds, not an arbitrary string.
///
/// ONLY THE SHAPE IS HERE. What a token means is known by the theme (`RenderTheme.resolve...`), and the
/// answer "the theme declares no such name" also comes from it: since 9.0.0 a token name is a string
/// matching a pattern, not a member of an enum, so at PARSE time a known token can no longer be told from
/// an unknown one.
///
/// PARSING NEVER THROWS. A value of the wrong shape gives `null`, and the field reads as absent. A number
/// outside the schema bounds is CLAMPED to them: the builder cannot produce one, but the document may not
/// have been built by it, and a negative padding or an opacity of 1.5 is an assert in Flutter, not just an
/// ugly look.

// Bounds of numeric values: the same numbers as in `style-values.ts`.
const double kMaxSpacingPx = 128;
const double kMaxRadiusPx = 256;
const double kMinFontSizePx = 8;
const double kMaxFontSizePx = 96;
const double kMinLetterSpacingPx = -2;
const double kMaxLetterSpacingPx = 8;
const double kMinLineHeight = 0.8;
const double kMaxLineHeight = 3;
const double kMaxShadowOffsetPx = 64;
const double kMaxShadowBlurPx = 128;
const double kMaxShadowSpreadPx = 64;
const int kMaxShadowLayers = 4;
const double kStyleSizeMin = 1;
const double kStyleSizeMax = 1200;
const double kMinBorderWidthPx = 0.5;
const double kMaxBorderWidthPx = 16;
const int kMinGradientStops = 2;
const int kMaxGradientStops = 8;

/// Gradient angles: axis-aligned ("as in CSS") and "corner to corner".
const List<int> kAxisGradientAngles = [0, 90, 180, 270];
const List<int> kCornerGradientAngles = [45, 135, 225, 315];

/// Token name pattern (`x-tokens.namePattern`). A test guards the mirror.
const String kTokenNamePattern = r'^[a-z][a-zA-Z0-9]{0,39}$';
final RegExp _tokenName = RegExp(kTokenNamePattern);

/// Whether a string CAN be a token name. Whether the theme has such a name is a question for the
/// theme.
bool isTokenName(Object? raw) => raw is String && _tokenName.hasMatch(raw);

/// A key of an open map that the contract forbids (`__proto__`).
///
/// The schema rejects it with the name pattern (`propertyNames.pattern`), and Zod in the builder with its
/// own guard. In Dart it is an ordinary map key, so without this check the reader would silently accept
/// what the validator rejects. The reader does not validate the whole document, so it rejects the ENTRY
/// itself: the key does not get into the map.
bool isForbiddenKey(String key) => key == '__proto__';

double? _number(Object? raw) => raw is num && raw.isFinite ? raw.toDouble() : null;

/// A LITERAL WITHIN THE FIELD'S BOUNDS: mirror of the builder's `clampLiteral`.
///
///  * a number outside the bounds is clamped (`literalOutOfRange: 'clamp'`), infinity included: it is
///    "out of bounds", not "not a number";
///  * a NON-NUMBER where a number within bounds was expected (a string, `null`, `NaN`, an object) is the
///    field's LOWER BOUND (`nonNumericLiteral: 'lower-bound'`), not "the field does not apply" and not
///    zero. It is a number the schema allows anyway (`opacity: 'oops'` gives 0, `blur: null` gives 0),
///    and the same answer as for `NaN`: the safest is the one closest to switched off.
double _bounded(Object? raw, double min, double max) {
  if (raw is! num || raw.isNaN) return min;
  return raw.toDouble().clamp(min, max);
}

/// The same for a map field, but a field that is ABSENT FROM THE DOCUMENT altogether is not covered by
/// this rule (`null`): the field's default decides it.
double? _boundedAt(Map raw, String key, double min, double max) =>
    raw.containsKey(key) ? _bounded(raw[key], min, max) : null;

/// An OPTIONAL numeric field of a map (`nullNumericField: 'absent'`): an explicit `null` is the same as
/// a missing field, and the field's default decides it. A non-number (a string, an object) is still the
/// lower bound: `null` in the contract means "nothing was said", not "something untrue was said".
///
/// REQUIRED fields (a gradient stop position, `border.width`, `opacity` in `{token, opacity}`, a binding's
/// `fallback`) do not have this rule: there `null` stays "not a number" ([_boundedAt]).
double? _optionalAt(Map raw, String key, double min, double max) =>
    raw[key] == null ? null : _bounded(raw[key], min, max);

/// `#rrggbb` gives an opaque color. The canonical form of an own color in the DOCUMENT: opacity is
/// there a separate `opacity` field.
Color? _hex6(Object? raw) {
  if (raw is! String || raw.length != 7 || !raw.startsWith('#')) return null;
  final value = int.tryParse(raw.substring(1), radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}

/// A COLOR REFERENCE, in three forms told apart by structure: a token string, `{token, opacity}` (a
/// shade of a token) and `{value, opacity?}` (an own value).
@immutable
sealed class ColorRef {
  const ColorRef();

  /// A reference to a core token, for field defaults and the renderer's own chrome.
  const factory ColorRef.token(String name) = TokenColorRef;

  static ColorRef? tryParse(Object? raw) {
    if (raw is String) return isTokenName(raw) ? TokenColorRef(raw) : null;
    if (raw is! Map) return null;
    if (raw['value'] != null) {
      final color = _hex6(raw['value']);
      // `opacity` of an own value is optional: an explicit `null` means no field.
      final opacity = _optionalAt(raw, 'opacity', 0, 1);
      return color == null ? null : CustomColorRef(color, opacity: opacity ?? 1);
    }
    final token = raw['token'];
    if (!isTokenName(token)) return null;
    // `opacity` of a token shade is required: `null` here is not a number.
    final opacity = _boundedAt(raw, 'opacity', 0, 1);
    return TokenColorRef(token as String, opacity: opacity ?? 1);
  }
}

/// A theme token, possibly with opacity ("10 % of the brand color").
final class TokenColorRef extends ColorRef {
  const TokenColorRef(this.token, {this.opacity = 1});

  final String token;
  final double opacity;

  @override
  bool operator ==(Object other) =>
      other is TokenColorRef && other.token == token && other.opacity == opacity;

  @override
  int get hashCode => Object.hash(token, opacity);

  @override
  String toString() => opacity == 1 ? 'ColorRef($token)' : 'ColorRef($token × $opacity)';
}

/// An own value: in the dark theme it is the same as in the light one.
final class CustomColorRef extends ColorRef {
  const CustomColorRef(this.color, {this.opacity = 1});

  /// An opaque color; the opacity is in [opacity].
  final Color color;
  final double opacity;

  @override
  bool operator ==(Object other) =>
      other is CustomColorRef && other.color == color && other.opacity == opacity;

  @override
  int get hashCode => Object.hash(color, opacity);

  @override
  String toString() => 'ColorRef(value $color × $opacity)';
}

/// A spacing or a radius: a scale token name or a number of logical pixels.
///
/// One type for two scales on purpose: their shape is the same (`SpacingRef`, `RadiusRef`), they differ
/// only in the bound and in which theme map the name is looked up in, which the call site says.
@immutable
final class ScaleRef {
  const ScaleRef.token(String this.token) : value = null;
  const ScaleRef.value(double this.value) : token = null;

  final String? token;
  final double? value;

  static ScaleRef? tryParse(Object? raw, {required double max}) {
    if (raw is String) return isTokenName(raw) ? ScaleRef.token(raw) : null;
    // A number (infinity included) is clamped; anything else that is not a string is a broken shape, and
    // the call site says what to do with it: a side of a shape equals zero (`malformedSideValue`), a single
    // value means the field does not apply (`unknownBoxToken`).
    return raw is num ? ScaleRef.value(_bounded(raw, 0, max)) : null;
  }

  @override
  bool operator ==(Object other) => other is ScaleRef && other.token == token && other.value == value;

  @override
  int get hashCode => Object.hash(token, value);

  @override
  String toString() => 'ScaleRef(${token ?? value})';
}

/// A whole number in [min]..[max], or `null`: no fraction, no string, and a number out of range is not clamped (the
/// caller falls back to its own default).
int? wholeNumberIn(Object? raw, int min, int max) {
  final value = raw is double && raw == raw.truncateToDouble() ? raw.toInt() : raw;
  return value is int && value >= min && value <= max ? value : null;
}

/// A radius of a `props` field of the part of a widget: a token name or a whole number of pixels within the radius
/// bound (`RadiusRef`). Unlike a style field, a number out of range or of another form is NOT clamped: it is no
/// radius (`null`) and the part keeps its built-in one.
ScaleRef? strictRadiusRef(Object? raw) {
  if (raw is String) return isTokenName(raw) ? ScaleRef.token(raw) : null;
  final pixels = wholeNumberIn(raw, 0, kMaxRadiusPx.toInt());
  return pixels == null ? null : ScaleRef.value(pixels.toDouble());
}

/// A SPACING AS A `props` FIELD WITH A DEFAULT: the gap between children, a spacer's size, a
/// divider's margin.
///
/// The reference travels together with ITS FIELD'S DEFAULT, and that is not a convenience. The policy
/// `unknownToken: 'fallback-to-field-default'` says "the field's default, not the type's", and whether a
/// token is unknown is learned only against the theme, i.e. at paint time, far from where it is known
/// which field this is. If the render step named the default, a field would have two defaults in two
/// files (for a broken value and for an unknown token), and they would diverge silently.
@immutable
final class FieldSpacing {
  const FieldSpacing(this.ref, this.fieldDefault);

  /// A value of the wrong shape reads as the field default: the same policy, only it takes effect before
  /// the turn of the theme comes.
  factory FieldSpacing.parse(Object? raw, {required SpacingToken fieldDefault}) => FieldSpacing(
    ScaleRef.tryParse(raw, max: kMaxSpacingPx) ?? ScaleRef.token(fieldDefault.wire),
    fieldDefault,
  );

  final ScaleRef ref;
  final SpacingToken fieldDefault;
}

/// THE COLOR OF A PART OF A WIDGET as a `props` field with a default: a divider's line, the fill of a
/// bar and of a ring. The default travels with the reference for the same reason as in
/// [FieldSpacing].
@immutable
final class FieldColor {
  const FieldColor(this.ref, this.fieldDefault);

  factory FieldColor.parse(Object? raw, {required ColorToken fieldDefault}) =>
      FieldColor(ColorRef.tryParse(raw) ?? ColorRef.token(fieldDefault.wire), fieldDefault);

  final ColorRef ref;
  final ColorToken fieldDefault;
}

/// A side of a shape with sides: a broken value (`{top: 'Bad!'}`) reads as an unknown token, so the
/// side is zero and the shape applies (`unknownSideToken: 'side-is-zero'`). A missing side is `null`.
ScaleRef? _side(Map raw, String key, double max) {
  if (!raw.containsKey(key)) return null;
  return ScaleRef.tryParse(raw[key], max: max) ?? const ScaleRef.token('');
}

/// Box paddings: one value for all sides or per side.
///
/// Sides are LOGICAL (`start` / `end`) because right-to-left writing exists; a side that is not named
/// equals zero (`x-style.unnamedSide: 'zero'`).
@immutable
final class BoxSpacing {
  const BoxSpacing.all(ScaleRef value)
    : top = value,
      end = value,
      bottom = value,
      start = value,
      isSingleValue = true;
  const BoxSpacing.sides({this.top, this.end, this.bottom, this.start}) : isSingleValue = false;

  /// The document named ONE value for all sides rather than a shape with sides. The distinction matters:
  /// an unknown token in a single value is a field that does not apply (`unknownBoxToken: 'omit-field'`),
  /// whereas a shape with sides always applies, and every unknown side in it is zero
  /// (`unknownSideToken: 'side-is-zero'`).
  final bool isSingleValue;

  final ScaleRef? top;
  final ScaleRef? end;
  final ScaleRef? bottom;
  final ScaleRef? start;

  static BoxSpacing? tryParse(Object? raw) {
    if (raw is! Map) {
      final all = ScaleRef.tryParse(raw, max: kMaxSpacingPx);
      return all == null ? null : BoxSpacing.all(all);
    }
    final sides = BoxSpacing.sides(
      top: _side(raw, 'top', kMaxSpacingPx),
      end: _side(raw, 'end', kMaxSpacingPx),
      bottom: _side(raw, 'bottom', kMaxSpacingPx),
      start: _side(raw, 'start', kMaxSpacingPx),
    );
    // `padding: {}` says exactly the same as a missing field.
    final empty = sides.top == null && sides.end == null && sides.bottom == null && sides.start == null;
    return empty ? null : sides;
  }

  @override
  bool operator ==(Object other) =>
      other is BoxSpacing &&
      other.top == top &&
      other.end == end &&
      other.bottom == bottom &&
      other.start == start &&
      other.isSingleValue == isSingleValue;

  @override
  int get hashCode => Object.hash(top, end, bottom, start, isSingleValue);
}

/// Box radii: one value for all corners or per (logical) corner.
@immutable
final class BoxRadius {
  const BoxRadius.all(ScaleRef value)
    : topStart = value,
      topEnd = value,
      bottomEnd = value,
      bottomStart = value,
      isSingleValue = true;
  const BoxRadius.corners({this.topStart, this.topEnd, this.bottomEnd, this.bottomStart})
    : isSingleValue = false;

  /// One value for all corners; mirror of [BoxSpacing.isSingleValue].
  final bool isSingleValue;

  final ScaleRef? topStart;
  final ScaleRef? topEnd;
  final ScaleRef? bottomEnd;
  final ScaleRef? bottomStart;

  static BoxRadius? tryParse(Object? raw) {
    if (raw is! Map) {
      final all = ScaleRef.tryParse(raw, max: kMaxRadiusPx);
      return all == null ? null : BoxRadius.all(all);
    }
    final corners = BoxRadius.corners(
      topStart: _side(raw, 'topStart', kMaxRadiusPx),
      topEnd: _side(raw, 'topEnd', kMaxRadiusPx),
      bottomEnd: _side(raw, 'bottomEnd', kMaxRadiusPx),
      bottomStart: _side(raw, 'bottomStart', kMaxRadiusPx),
    );
    final empty =
        corners.topStart == null &&
        corners.topEnd == null &&
        corners.bottomEnd == null &&
        corners.bottomStart == null;
    return empty ? null : corners;
  }

  @override
  bool operator ==(Object other) =>
      other is BoxRadius &&
      other.topStart == topStart &&
      other.topEnd == topEnd &&
      other.bottomEnd == bottomEnd &&
      other.bottomStart == bottomStart &&
      other.isSingleValue == isSingleValue;

  @override
  int get hashCode => Object.hash(topStart, topEnd, bottomEnd, bottomStart, isSingleValue);
}

/// A typography style: a token or a token WITH ADJUSTMENTS.
///
/// There is deliberately no own style "from scratch": the typeface is always given by a token, so a
/// change of the brand font remains one edit of the theme.
@immutable
final class TypographyRef {
  const TypographyRef(this.token, {this.fontSize, this.fontWeight, this.lineHeight, this.letterSpacing});

  final String token;
  final double? fontSize;

  /// 100..900. The theme converts it to a [FontWeight], the same way as for a token's weight.
  final int? fontWeight;

  /// A MULTIPLIER of the font size, as in the theme.
  final double? lineHeight;
  final double? letterSpacing;

  static TypographyRef? tryParse(Object? raw) {
    if (raw is String) return isTokenName(raw) ? TypographyRef(raw) : null;
    if (raw is! Map || !isTokenName(raw['token'])) return null;
    return TypographyRef(
      raw['token'] as String,
      fontSize: _optionalAt(raw, 'fontSize', kMinFontSizePx, kMaxFontSizePx),
      fontWeight: _optionalAt(raw, 'fontWeight', 100, 900)?.round(),
      lineHeight: _optionalAt(raw, 'lineHeight', kMinLineHeight, kMaxLineHeight),
      letterSpacing: _optionalAt(raw, 'letterSpacing', kMinLetterSpacingPx, kMaxLetterSpacingPx),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TypographyRef &&
      other.token == token &&
      other.fontSize == fontSize &&
      other.fontWeight == fontWeight &&
      other.lineHeight == lineHeight &&
      other.letterSpacing == letterSpacing;

  @override
  int get hashCode => Object.hash(token, fontSize, fontWeight, lineHeight, letterSpacing);

  @override
  String toString() => 'TypographyRef($token)';
}

/// A SIZE: a number in dp or a data binding (`Dimension`).
///
/// The type is the same as for bound numbers elsewhere in the contract ([BindableNumber]): the binding
/// shape is the same, and a literal here is simply a number.
BindableNumber? parseDimension(Map raw, String key) {
  // An explicit `null` means no field (`nullNumericField: 'absent'`).
  if (raw[key] == null) return null;
  final value = raw[key];
  if (value is Map) {
    if (value['kind'] == 'binding' && value['path'] is String) {
      // A binding without a fallback has nothing to draw with when there is no data, and "no data" is a
      // normal state for it.
      final fallback = _boundedAt(value, 'fallback', kStyleSizeMin, kStyleSizeMax);
      return fallback == null ? null : BoundNumber(value['path'] as String, fallback);
    }
    return null;
  }
  // A literal: out of bounds gives the bound, a non-number gives the lower bound (1 dp).
  return LiteralNumber(_bounded(value, kStyleSizeMin, kStyleSizeMax));
}

/// A border: width and color, THE SAME on all sides.
@immutable
final class NodeBorder {
  const NodeBorder({required this.width, required this.color, this.dashed = false});

  final double width;
  final ColorRef color;

  /// A dashed line (schema 9.22.0, `style: 'dashed'`). No field or any other word is solid.
  final bool dashed;

  static NodeBorder? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final width = _boundedAt(raw, 'width', kMinBorderWidthPx, kMaxBorderWidthPx);
    final color = ColorRef.tryParse(raw['color']);
    if (width == null || color == null) return null;
    return NodeBorder(width: width, color: color, dashed: isDashedBorderWord(raw['style']));
  }

  @override
  bool operator ==(Object other) =>
      other is NodeBorder && other.width == width && other.color == color && other.dashed == dashed;

  @override
  int get hashCode => Object.hash(width, color, dashed);
}

/// One stop of an own gradient.
typedef GradientStopRef = ({ColorRef color, double position});

/// A gradient: a theme token or an own value of the same shape as in the theme, with the difference that
/// the stop colors here are REFERENCES.
@immutable
sealed class GradientRef {
  const GradientRef();

  static GradientRef? tryParse(Object? raw) {
    if (raw is String) return isTokenName(raw) ? TokenGradientRef(raw) : null;
    if (raw is! Map) return null;
    final angle = _number(raw['angle']);
    final rawStops = raw['stops'];
    if (angle == null || rawStops is! List) return null;
    if (rawStops.length < kMinGradientStops || rawStops.length > kMaxGradientStops) return null;

    final stops = <GradientStopRef>[];
    for (final item in rawStops) {
      if (item is! Map) return null;
      final color = ColorRef.tryParse(item['color']);
      // A position outside 0..1 is clamped and a non-number is zero (the lower bound); a stop with no
      // position at all cancels the gradient.
      final position = _boundedAt(item, 'position', 0, 1);
      // A gradient without one stop is a DIFFERENT gradient and would look as if intended. So a broken stop
      // cancels the whole gradient.
      if (color == null || position == null) return null;
      stops.add((color: color, position: position));
    }
    return CustomGradientRef(angle: angle, stops: List.unmodifiable(stops));
  }
}

final class TokenGradientRef extends GradientRef {
  const TokenGradientRef(this.token);

  final String token;

  @override
  bool operator ==(Object other) => other is TokenGradientRef && other.token == token;

  @override
  int get hashCode => token.hashCode;

  @override
  String toString() => 'GradientRef($token)';
}

final class CustomGradientRef extends GradientRef {
  const CustomGradientRef({required this.angle, required this.stops});

  /// The angle in degrees. What to do with it if it is outside the eight allowed values is decided by the
  /// theme (there will be no gradient), not by parsing: the angle is a number and its shape is correct.
  final double angle;
  final List<GradientStopRef> stops;

  /// Whether the stops are in ascending order. A violation means `unorderedGradient: 'omit-field'`: the
  /// gradient is not drawn at all.
  bool get isOrdered {
    for (var index = 1; index < stops.length; index += 1) {
      if (stops[index].position < stops[index - 1].position) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is CustomGradientRef && other.angle == angle && listEquals(other.stops, stops);

  @override
  int get hashCode => Object.hash(angle, Object.hashAll(stops));
}

/// One layer of an own shadow. The opacity lives in the color REFERENCE, not in a separate field next
/// to it as in the theme.
@immutable
final class ShadowLayerRef {
  const ShadowLayerRef({
    required this.offsetX,
    required this.offsetY,
    required this.blur,
    required this.spread,
    required this.color,
  });

  final double offsetX;
  final double offsetY;
  final double blur;
  final double spread;
  final ColorRef color;

  static ShadowLayerRef? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final color = ColorRef.tryParse(raw['color']);
    if (color == null) return null;
    return ShadowLayerRef(
      // A field absent from the layer altogether is zero; a broken one is the lower bound.
      offsetX: _optionalAt(raw, 'offsetX', -kMaxShadowOffsetPx, kMaxShadowOffsetPx) ?? 0,
      offsetY: _optionalAt(raw, 'offsetY', -kMaxShadowOffsetPx, kMaxShadowOffsetPx) ?? 0,
      blur: _optionalAt(raw, 'blur', 0, kMaxShadowBlurPx) ?? 0,
      spread: _optionalAt(raw, 'spread', -kMaxShadowSpreadPx, kMaxShadowSpreadPx) ?? 0,
      color: color,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ShadowLayerRef &&
      other.offsetX == offsetX &&
      other.offsetY == offsetY &&
      other.blur == blur &&
      other.spread == spread &&
      other.color == color;

  @override
  int get hashCode => Object.hash(offsetX, offsetY, blur, spread, color);
}

/// A shadow: a shadow token or an own list of layers (the first is the nearest).
@immutable
sealed class ShadowRef {
  const ShadowRef();

  static ShadowRef? tryParse(Object? raw) {
    if (raw is String) return isTokenName(raw) ? TokenShadowRef(raw) : null;
    if (raw is! List || raw.isEmpty || raw.length > kMaxShadowLayers) return null;
    final layers = <ShadowLayerRef>[];
    for (final item in raw) {
      final layer = ShadowLayerRef.tryParse(item);
      // The same reason as for the gradient: a shadow without one layer is a different shadow.
      if (layer == null) return null;
      layers.add(layer);
    }
    return CustomShadowRef(List.unmodifiable(layers));
  }
}

final class TokenShadowRef extends ShadowRef {
  const TokenShadowRef(this.token);

  final String token;

  @override
  bool operator ==(Object other) => other is TokenShadowRef && other.token == token;

  @override
  int get hashCode => token.hashCode;
}

final class CustomShadowRef extends ShadowRef {
  const CustomShadowRef(this.layers);

  final List<ShadowLayerRef> layers;

  @override
  bool operator ==(Object other) => other is CustomShadowRef && listEquals(other.layers, layers);

  @override
  int get hashCode => Object.hashAll(layers);
}

/// A node background is a discriminated union: color, gradient or image.
///
/// A union rather than three optional fields: "the background is a color, or a gradient, or an image" is
/// visible both to ajv (`oneOf` with `const kind`) and to the Dart compiler.
@immutable
sealed class NodeBackground {
  const NodeBackground();

  /// `null` means no background: a value of the wrong shape reads as a missing field. There is no default
  /// here and cannot be one: contract 9.0.0 has no hidden look defaults (`x-style.hiddenDefaults: 'none'`).
  static NodeBackground? tryParse(Object? raw) {
    if (raw is! Map) {
      if (kDebugMode && raw != null) {
        debugPrint('[hotlayout] background "$raw" is not a union object, ignored');
      }
      return null;
    }
    switch (raw['kind']) {
      case 'color':
        final color = ColorRef.tryParse(raw['color']);
        return color == null ? null : ColorBackground(color);
      case 'gradient':
        final gradient = GradientRef.tryParse(raw['gradient']);
        return gradient == null ? null : GradientBackground(gradient);
      case 'image':
        if (raw['source'] is! Map) return null;
        return ImageBackground(ImageSource.parse(raw['source']), fit: ImageFitToken.parse(raw['fit']));
      default:
        if (kDebugMode) debugPrint('[hotlayout] unknown background.kind "${raw['kind']}", ignored');
        return null;
    }
  }
}

final class ColorBackground extends NodeBackground {
  const ColorBackground(this.color);

  final ColorRef color;

  @override
  bool operator ==(Object other) => other is ColorBackground && other.color == color;

  @override
  int get hashCode => Object.hash('color', color);

  @override
  String toString() => 'ColorBackground($color)';
}

final class GradientBackground extends NodeBackground {
  const GradientBackground(this.gradient);

  final GradientRef gradient;

  @override
  bool operator ==(Object other) => other is GradientBackground && other.gradient == gradient;

  @override
  int get hashCode => Object.hash('gradient', gradient);

  @override
  String toString() => 'GradientBackground($gradient)';
}

/// An image background: the same [ImageSource] as the `Image` widget has, plus `fit`.
final class ImageBackground extends NodeBackground {
  const ImageBackground(this.source, {required this.fit});

  final ImageSource source;
  final ImageFitToken fit;
}
