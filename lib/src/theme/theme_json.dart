/// Reads one theme of the theme contract from JSON. Total: a malformed value
/// leaves its token out and never throws.
library;

import 'package:flutter/material.dart';

import '../model/style_values.dart';
import '../model/tokens.dart';
import '../report/hotlayout_report.dart';
import '../report/report_hub.dart';
import 'fallback_theme.dart';
import 'render_theme.dart';

RenderTheme readRenderTheme(Object? raw) {
  final (theme, found) = ReportHub.collect(() => _readRenderTheme(raw));
  return theme.withReports(found);
}

RenderTheme _readRenderTheme(Object? raw) {
  final json = raw is Map ? Map<String, Object?>.from(raw) : const <String, Object?>{};
  final fit = _NumberFit(_builtInJsonOf(_brightness(json['brightness'], quiet: true)));
  final bodyFont = _font(json['fontFamilies'], 'body');
  final headingFont = _font(json['fontFamilies'], 'heading');

  return RenderTheme(
    id: json['id'] as String? ?? 'unknown',
    name: json['name'] as String? ?? '',
    source: json['source'] as String? ?? '',
    brightness: _brightness(json['brightness']),
    provisional: _stringSet(json['provisional']),
    origins: _stringMap(json['origins']),
    bodyFont: bodyFont,
    headingFont: headingFont,
    colors: _byName(json['color'], 'color', (raw, _) => _color(raw)),
    // The "zero of a scale" (`x-tokens.zeroScale`, `zeroScaleToken: 'none-is-zero'`): `none` is
    // zero, whatever the theme says. The schema does not let such a theme through, but a reader
    // of a newer minor version or of a hand-made theme does not validate, and node defaults rely
    // on the NAME: a theme with `none = 16` would change a screen where the author asked for "no
    // spacing".
    spacing: _zeroNone(
      _byName(json['spacing'], 'spacing', (raw, name) => fit.number(raw, 'spacing.$name', 0, _kMaxSpacing, ('spacing', name, null))),
    ),
    radii: _zeroNone(
      _byName(json['radius'], 'radius', (raw, name) => fit.number(raw, 'radius.$name', 0, _kMaxRadius, ('radius', name, null))),
    ),
    typography: _typography(json['typography'], body: bodyFont, heading: headingFont, fit: fit),
    elevations: _noShadowForNone(_byName(json['elevation'], 'elevation', (raw, name) => _shadows(raw, name, fit))),
    // The group is called `gradient`, singular, as in the theme contract, next to
    // `color`/`spacing`/`radius`.
    gradients: _byName(json['gradient'], 'gradient', (raw, name) => _gradient(raw, name, fit)),
    badgeToneRoles: _roleGroup(json['roles'], 'badgeTone', BadgeToneToken.values),
    buttonVariantRoles: _roleGroup(json['roles'], 'buttonVariant', ButtonVariantToken.values),
    numberReports: fit.reports,
  );
}

Map<String, Object?>? _builtInJsonOf(Brightness brightness) {
  for (final theme in (kFallbackThemeContractJson['themes']! as Map).values) {
    if (theme is Map && theme['brightness'] == brightness.name) return Map<String, Object?>.from(theme);
  }
  return null;
}

/// The numbers of a theme read within the bounds of its schema (`x-themeNumbers`). A number outside them, or
/// not finite, becomes the value of the same token and field in the built-in theme of the same brightness (for
/// spacing, radius, font size, line height, font weight and letter spacing, when that theme has one) and
/// otherwise the nearest bound. Every replacement is reported with its place and the word `built-in` or `bound`;
/// the numbers themselves are not, they come from the network.
final class _NumberFit {
  _NumberFit(this._builtIn);

  final Map<String, Object?>? _builtIn;
  final List<String> reports = [];

  /// [number] in `[min, max]` as is; otherwise the replacement. `null` for anything that is not a number (and
  /// for NaN, which no JSON can carry). [builtIn] names where the built-in number lives: dictionary, token and an
  /// optional field; `null` says there is no built-in replacement for this place.
  double? number(Object? raw, String place, double min, double max, (String, String, String?)? builtIn) {
    if (raw is! num || raw.isNaN) return null;
    final value = raw.toDouble();
    if (value.isFinite && value >= min && value <= max) return value;
    final base = builtIn == null ? null : _builtInNumber(builtIn);
    if (base != null && base >= min && base <= max) {
      _report(place, 'built-in');
      return base;
    }
    _report(place, 'bound');
    return value < min ? min : max;
  }

  double? _builtInNumber((String, String, String?) at) {
    final dictionary = _builtIn?[at.$1];
    final token = dictionary is Map ? dictionary[at.$2] : null;
    final raw = at.$3 == null ? token : (token is Map ? token[at.$3] : null);
    return raw is num && raw.isFinite ? raw.toDouble() : null;
  }

  void _report(String place, String how) {
    reports.add('$place: $how');
    ReportHub.emit(InvalidThemeValuesReport(paths: ['$place ($how)']));
  }
}

Map<String, double> _zeroNone(Map<String, double> scale) {
  if (!scale.containsKey('none')) return scale;
  return {...scale, 'none': 0};
}

Map<String, List<BoxShadow>> _noShadowForNone(Map<String, List<BoxShadow>> scale) {
  if (!scale.containsKey('none')) return scale;
  return {...scale, 'none': const <BoxShadow>[]};
}

// ── Parsing ───────────────────────────────────────────────────────────────

/// A theme vocabulary by name: `{name: value}` to a map of parsed values.
///
/// A name outside the core is NORMAL (`customTokens: 'declared-by-theme'`): it is a custom token
/// of the project and goes into the map on a par with the core.
///
/// A corrupt value does not enter the map, and is then treated like a missing one: for the core,
/// the resolver default; for a custom name, an "unknown token".
Map<String, V> _byName<V>(Object? raw, String group, V? Function(Object? raw, String name) parse) {
  final result = <String, V>{};
  if (raw is! Map) return result;
  for (final entry in raw.entries) {
    final name = entry.key;
    if (name is! String) continue;
    // `__proto__` is not a token name: the schema rejects it via the name pattern, while in Dart
    // it would be an ordinary map key, so the reader would silently accept what the validator
    // rejects.
    if (isForbiddenKey(name)) {
      ReportHub.emit(InvalidThemeValuesReport(paths: ['$group.$name (forbidden name)']));
      continue;
    }
    final value = parse(entry.value, name);
    if (value == null) {
      ReportHub.emit(InvalidThemeValuesReport(paths: ['$group.$name (malformed)']));
      continue;
    }
    result[name] = value;
  }
  return result;
}

T? _tokenByWire<T extends WireToken>(List<T> values, String wire) {
  for (final value in values) {
    if (value.wire == wire) return value;
  }
  return null;
}

/// `'light' | 'dark'` to [Brightness]. An unknown value is the same case as an unknown token: the
/// default and a log line, not an exception.
Brightness _brightness(Object? raw, {bool quiet = false}) => switch (raw) {
  'light' => Brightness.light,
  'dark' => Brightness.dark,
  _ => () {
    if (raw != null && !quiet) ReportHub.emit(InvalidThemeValuesReport(paths: ['brightness (unknown "$raw")']));
    return Brightness.light;
  }(),
};

/// `roles.<group>` to a map of "semantic token to role".
///
/// Parsing is total: a missing group gives an empty map, and a role that is absent is drawn
/// neutrally later (`missingRole`) rather than throwing here.
Map<T, ThemeRole> _roleGroup<T extends WireToken>(
  Object? rawRoles,
  String group,
  List<T> values,
) {
  if (rawRoles is! Map) return const {};
  final rawGroup = rawRoles[group];
  if (rawGroup is! Map) return const {};
  // Role keys, unlike token names, are a CLOSED list: they are the values of `Badge.tone` and
  // `Button.variant` in the widget schema.
  final result = <T, ThemeRole>{};
  for (final entry in rawGroup.entries) {
    final key = entry.key;
    if (key is! String) continue;
    final token = _tokenByWire(values, key);
    final role = _role(entry.value);
    if (token == null || role == null) {
      ReportHub.emit(InvalidThemeValuesReport(paths: ['roles.$group.$key (unusable)']));
      continue;
    }
    result[token] = role;
  }
  return result;
}

/// `{background?, foreground, border?}` to [ThemeRole].
///
/// A role without `foreground` is unusable: it is the one slot without which text cannot be
/// drawn. A missing `background`/`border` is, on the contrary, a normal state ("no fill", "no
/// border"), and reaches the reader as `null`.
ThemeRole? _role(Object? raw) {
  if (raw is! Map) return null;
  final foreground = raw['foreground'];
  if (foreground is! String) return null;
  final background = raw['background'];
  final border = raw['border'];
  // Slot names are any colours of THIS theme, so only the shape is checked here. Whether the name
  // exists in the palette is established by `_resolveRole`: the palette is not yet assembled
  // into a theme while the role is parsed.
  return ThemeRole(
    foreground: foreground,
    background: background is String ? background : null,
    border: border is String ? border : null,
  );
}

double? _number(Object? raw) => raw is num ? raw.toDouble() : null;

// The bounds of `x-schema` for every number of a theme. A value outside them (or not finite) is a corrupt
// value: it never reaches a `TextStyle`, a padding or a constraint, where infinity or a huge number breaks layout.
const double _kMaxSpacing = 128;
const double _kMaxRadius = 256;

/// `#rrggbb` or `#rrggbbaa` to a colour. The format is strict, as it is in `x-schema`.
///
/// ALPHA IS LAST IN THE CONTRACT (`colorAlpha: 'rrggbbaa-alpha-last'`), as in CSS, while Flutter's
/// `Color(int)` expects it FIRST (`0xAARRGGBB`). So eight digits cannot be passed to the
/// constructor as is: `#ff7a5980` would become a nearly opaque teal instead of a half-transparent
/// coral, and nothing would fail.
Color? _color(Object? raw) {
  if (raw is! String || !raw.startsWith('#')) return null;
  if (raw.length != 7 && raw.length != 9) return null;
  final rgb = int.tryParse(raw.substring(1, 7), radix: 16);
  if (rgb == null) return null;
  if (raw.length == 7) return Color(0xFF000000 | rgb);
  final alpha = int.tryParse(raw.substring(7), radix: 16);
  if (alpha == null) return null;
  return Color((alpha << 24) | rgb);
}

/// `#rrggbb` without alpha: the colour of a theme shadow layer. A shadow's opacity is a separate
/// field, and the contract gives no second place for it.
Color? _opaqueColor(Object? raw) => raw is String && raw.length == 7 ? _color(raw) : null;

Set<String> _stringSet(Object? raw) =>
    raw is List ? Set.unmodifiable(raw.whereType<String>()) : const <String>{};

Map<String, String> _stringMap(Object? raw) {
  if (raw is! Map) return const <String, String>{};
  final result = <String, String>{};
  for (final entry in raw.entries) {
    if (entry.key is String && !isForbiddenKey(entry.key as String) && entry.value is String) {
      result[entry.key as String] = entry.value as String;
    }
  }
  return Map.unmodifiable(result);
}

ThemeFontFamily? _font(Object? raw, String role) {
  if (raw is! Map) return null;
  final json = raw[role];
  if (json is! Map) return null;
  final primary = json['primary'];
  if (primary is! String) return null;
  final fallback = json['fallback'];
  return ThemeFontFamily(
    primary: primary,
    fallback: fallback is List
        ? List.unmodifiable(fallback.whereType<String>())
        : const <String>[],
  );
}

/// Typography is assembled separately from the rest: a `TextStyle` depends not only on its own
/// entry but on `fontFamilies`, since `role` selects the family.
Map<String, TextStyle> _typography(
  Object? raw, {
  required ThemeFontFamily? body,
  required ThemeFontFamily? heading,
  required _NumberFit fit,
}) =>
    _byName<TextStyle>(raw, 'typography', (item, name) {
      if (item is! Map) return null;
      double? field(String key, double min, double max) =>
          fit.number(item[key], 'typography.$name.$key', min, max, ('typography', name, key));
      final fontSize = field('fontSize', 8, 96);
      if (fontSize == null) return null;
      // An optional field that is present but is not a number makes the whole style corrupt: the token is
      // dropped and the built-in value applies, rather than a style the theme never described.
      final lineHeight = item['lineHeight'] == null ? null : field('lineHeight', 0.8, 3);
      if (item['lineHeight'] != null && lineHeight == null) return null;
      final letterSpacing = item['letterSpacing'] == null ? 0.0 : field('letterSpacing', -2, 8);
      if (letterSpacing == null) return null;
      final weight = item['fontWeight'] == null ? null : field('fontWeight', 100, 900);
      final fontWeight = weight == null ? null : themeFontWeight(weight);
      if (item['fontWeight'] != null && fontWeight == null) return null;
      final family = item['role'] == 'heading' ? heading : body;
      return TextStyle(
        fontFamily: family?.primary,
        fontFamilyFallback: family?.fallback,
        fontSize: fontSize,
        // `lineHeight` in the contract is a MULTIPLIER of `fontSize`; `TextStyle.height` in
        // Flutter is also a multiplier, so the value maps one to one. The match is lucky, not
        // guaranteed: the contract does not name the unit.
        height: lineHeight,
        fontWeight: fontWeight,
        // The unit is LOGICAL PIXELS, so the value maps to `TextStyle.letterSpacing` one to one,
        // with no multiplication by the font size. The contract names the unit explicitly
        // (`lengthUnit: 'logical-pixels'`), unlike `lineHeight`, where the match was only lucky.
        //
        // An entry without the field means "the font's normal tracking", and that is an
        // explicit ZERO. `null` would mean something else, "inherit": the text would get the
        // default Material letter spacing (0.25 dp per character in `bodyMedium`), which the
        // theme never named. A thirty-character line would be 7.5 dp wider than in the builder
        // and would wrap where the builder did not.
        letterSpacing: letterSpacing,
      );
    })..updateAll((token, style) {
      final features = _platformFontFeatures[token];
      return features == null ? style : style.copyWith(fontFeatures: features);
    });

/// A numeric weight 100..900 to [FontWeight]. Intermediate values (e.g. 450 from a variable font)
/// are rounded to the nearest hundred: Flutter's `FontWeight` is discrete. Not finite, or outside 100..900, is `null`.
FontWeight? themeFontWeight(Object? raw) {
  if (raw is! num || !raw.isFinite || raw < 100 || raw > 900) return null;
  final step = (raw / 100).round().clamp(1, 9);
  return FontWeight.values[step - 1];
}

/// A contract gradient to a [LinearGradient].
///
/// **Angle.** In the contract it is in degrees "as in CSS": 0 deg runs bottom to top, 90 deg left
/// to right, 180 deg top to bottom. Flutter specifies direction not by angle but by a pair of
/// [Alignment]s, and the translation is a lookup table, not trigonometry:
/// `gradientAngleSpace: 'axis-aligned-only'` restricts the angle to the allowed set that can be
/// drawn exactly. Computing a vector `(sin t, -cos t)` would give only an APPROXIMATE direction
/// for diagonals, because CSS measures the angle against the real box geometry while [Alignment]
/// uses a normalised one. An angle outside the list means a theme from the future or a corrupt
/// one, and it yields no gradient (the same degradation as `unorderedGradient: 'ignore'`).
///
/// **Stops.** The contract promises that `position` values ascend, but JSON Schema cannot express
/// that, so a schema validator will not stop such a document. It is checked here, not to
/// duplicate the validator but because Skia draws unordered stops unpredictably, and a silently
/// wrong gradient is worse than a missing one. An unusable gradient yields `null` and follows the
/// same path as an unknown token: it is not drawn.
LinearGradient? _gradient(Object? raw, String name, _NumberFit fit) {
  if (raw is! Map) return null;
  final angle = _number(raw['angle']);
  final rawStops = raw['stops'];
  if (angle == null || rawStops is! List) return null;

  final colors = <Color>[];
  final stops = <double>[];
  for (final (index, item) in rawStops.indexed) {
    if (item is! Map) continue;
    final color = _color(item['color']);
    final position = fit.number(item['position'], 'gradient.$name.stops[$index].position', 0, 1, null);
    if (color == null || position == null) continue;
    // The contract guarantees ascending positions; if the guarantee is broken there is no
    // gradient at all, not "a gradient, but a different one". Equal positions are ORDERED
    // (`gradientStopOrder: 'non-descending'`): that is a hard colour edge, not a violation.
    if (stops.isNotEmpty && position < stops.last) {
      ReportHub.emit(InvalidThemeValuesReport(paths: ['gradient.$name (stops do not ascend)']));
      return null;
    }
    colors.add(color);
    stops.add(position);
  }
  // `minItems: 2` in the schema: a single stop is just a colour, and drawing it as a gradient
  // makes no sense.
  if (colors.length < 2) return null;

  final direction = RenderTheme.gradientDirection(angle);
  if (direction == null) {
    ReportHub.emit(InvalidThemeValuesReport(paths: ['gradient.$name (angle is not one of the eight allowed)']));
    return null;
  }

  return themeLinearGradient(
    angle,
    direction,
    colors: List.unmodifiable(colors),
    stops: List.unmodifiable(stops),
  );
}

/// An axis-aligned angle gives a plain [LinearGradient]; a diagonal one gives a [CornerGradient]
/// with the exact geometry of CSS `to <corner>`.
LinearGradient themeLinearGradient(
  double angle,
  ({Alignment begin, Alignment end}) direction, {
  required List<Color> colors,
  required List<double> stops,
}) => kCornerGradientAngles.contains(angle)
    ? CornerGradient(begin: direction.begin, end: direction.end, colors: colors, stops: stops)
    : LinearGradient(begin: direction.begin, end: direction.end, colors: colors, stops: stops);

/// A contract shadow to a [BoxShadow]. Colour and opacity are separate in the contract (as in
/// Figma); Flutter has a single alpha channel.
List<BoxShadow>? _shadows(Object? raw, String name, _NumberFit fit) {
  if (raw is! List) return null;
  final shadows = <BoxShadow>[];
  for (final (index, item) in raw.indexed) {
    if (item is! Map) continue;
    double? field(String key, double min, double max) =>
        item[key] == null ? 0.0 : fit.number(item[key], 'elevation.$name[$index].$key', min, max, null);
    final color = _opaqueColor(item['color']);
    final opacity = fit.number(item['opacity'], 'elevation.$name[$index].opacity', 0, 1, null);
    final offsetX = field('offsetX', -64, 64);
    final offsetY = field('offsetY', -64, 64);
    final blur = field('blur', 0, 128);
    final spread = field('spread', -64, 64);
    // A layer with a corrupt number is left out whole.
    if (color == null || opacity == null || offsetX == null || offsetY == null || blur == null || spread == null) continue;
    shadows.add(
      BoxShadow(
        color: Color.fromARGB(
          (opacity.clamp(0, 1) * 255).round(),
          (color.r * 255).round(),
          (color.g * 255).round(),
          (color.b * 255).round(),
        ),
        offset: Offset(offsetX, offsetY),
        blurRadius: blur,
        spreadRadius: spread,
      ),
    );
  }
  // An empty list means "no shadow", not "no value": `elevation.none` is written as `[]` in the
  // contract and must reach the reader that way.
  //
  // The REVERSAL is deliberate. `x-compatibility.policy.shadowOrder` says `first-is-nearest` (CSS
  // order: the first shadow is nearest to the viewer), while Flutter paints `boxShadow` in list
  // order, so the LAST one ends up on top. The list must be reversed, otherwise two shadows of
  // one level swap depth silently.
  return List.unmodifiable(shadows.reversed);
}

/// A platform overlay on top of the contract.
///
/// The theme contract distinguishes scales only as `role: body | heading`; "numeric" cannot be
/// derived from it, although `numericL` exists precisely for tabular figures (so that scores in
/// a progress bar do not jump sideways when the value changes). Until the contract can say so,
/// the rule stays here, explicit and in one place rather than scattered through the renderer.
const Map<String, List<FontFeature>> _platformFontFeatures = {
  'numericL': [FontFeature.tabularFigures()],
};

