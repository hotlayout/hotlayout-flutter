import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../model/node_style.dart';
import '../model/part_style.dart';
import '../model/style_values.dart';
import '../model/tokens.dart';
import 'corner_gradient.dart';
import 'fallback_theme.dart';
import 'theme_contract.dart';
import 'theme_json.dart';
import 'theme_roles.dart';

export 'corner_gradient.dart' show CornerGradient;
export 'theme_roles.dart' show RoleColors, ThemeFontFamily, ThemeRole;

/// One theme: the values behind the token names a document refers to.
///
/// Obtain it from a [ThemeContract] and pass it to `renderDocument`. Its
/// lookup methods are used by the renderer; a host normally needs only [id],
/// [name], [brightness] and [toMaterialTheme].
///
/// The values arrive at runtime from the artifact `assets/contract/theme.json`, so a rebrand is a
/// file replacement for every platform at once rather than an app release. Only
/// [ThemeContract.fallback] is embedded, for when the artifact could not be read. Tokens the theme
/// contract deliberately does not describe (`align`, `icon`, `asset`, `iconSize`) stay in code:
/// the first are logical values that are the same everywhere, the rest are platform resources
/// that a rebrand changes by file, not by value.
@immutable
class RenderTheme {
  const RenderTheme({
    required this.colors,
    required this.spacing,
    required this.radii,
    required this.typography,
    required this.elevations,
    this.gradients = const <String, LinearGradient>{},
    this.badgeToneRoles = const <BadgeToneToken, ThemeRole>{},
    this.buttonVariantRoles = const <ButtonVariantToken, ThemeRole>{},
    this.id = 'inline',
    this.name = 'Unnamed theme',
    this.source = 'built in code',
    this.brightness = Brightness.light,
    this.provisional = const <String>{},
    this.origins = const <String, String>{},
    this.bodyFont,
    this.headingFont,
  });

  /// One theme from `themes[<id>]` of the artifact.
  ///
  /// Parsing is total: no field can throw. A token whose value is corrupt or missing simply does
  /// not enter the map, and the resolver then supplies a default ([color], [space], ...). The
  /// same rule as for the document: drawing with a default beats drawing nothing.
  factory RenderTheme.fromJson(Object? raw) => readRenderTheme(raw).withMissingFromBuiltIn();

  /// Parsing WITHOUT completing the core from the built-in theme: for the built-in theme itself
  /// (it has nothing to be completed from) and for tests that ask "what does THIS theme say".
  factory RenderTheme.fromJsonRaw(Object? raw) => readRenderTheme(raw);

  /// The built-in theme of the same brightness: what an incomplete theme is COMPLETED from
  /// (`partialThemeDefaults: 'built-in-theme-of-same-brightness'`).
  ///
  /// It comes from the contract snapshot ([kFallbackThemeContractJson]) and is read WITHOUT
  /// completion; otherwise the built-in theme would complete itself.
  static final Map<Brightness, RenderTheme> _builtIn = () {
    final themes = (kFallbackThemeContractJson['themes']! as Map).values.map(readRenderTheme).toList();
    return {
      for (final theme in themes) theme.brightness: theme,
    };
  }();

  /// The built-in theme matching this theme's brightness: a theme without its own `surface` must
  /// not get a foreign one. Black text from the built-in light theme on a dark background would be
  /// an invisible "default".
  RenderTheme get _builtInOfSameBrightness => _builtIn[brightness] ?? _builtIn.values.first;

  /// A theme in which every missing CORE value (`x-tokens.core`) is taken from the built-in theme
  /// of the same brightness (`partialTheme: 'resolve-missing-to-defaults'`).
  ///
  /// Mirrors `resolveMissingToDefaults` of the reference implementation. What is NOT filled in,
  /// as there:
  ///  * the three optional state colours: they have their own fallbacks ([kThemeColorFallbacks]),
  ///    and a built-in shade would bypass them;
  ///  * custom tokens: the built-in theme does not know them, and `missingCustomToken` applies;
  ///  * roles: `missingRole` says what to do about an absent role.
  ///
  /// It is done ONCE, on input, rather than at every place a colour is taken: resolution answers
  /// "what does THIS theme say", and its `null` is an honest "none".
  RenderTheme withMissingFromBuiltIn() {
    final base = _builtInOfSameBrightness;
    if (identical(base, this)) return this;

    Map<String, V> fill<V>(Map<String, V> own, Map<String, V> builtIn, Iterable<String> core) {
      final result = Map<String, V>.of(own);
      for (final name in core) {
        final value = builtIn[name];
        if (!result.containsKey(name) && value != null) result[name] = value;
      }
      return result;
    }

    return RenderTheme(
      id: id,
      name: name,
      source: source,
      brightness: brightness,
      provisional: provisional,
      origins: origins,
      bodyFont: bodyFont ?? base.bodyFont,
      headingFont: headingFont ?? base.headingFont,
      colors: fill(
        colors,
        base.colors,
        ColorToken.values.map((token) => token.wire).where((n) => !kThemeColorFallbacks.containsKey(n)),
      ),
      spacing: fill(spacing, base.spacing, SpacingToken.values.map((t) => t.wire)),
      radii: fill(radii, base.radii, RadiusToken.values.map((t) => t.wire)),
      typography: fill(typography, base.typography, TypographyToken.values.map((t) => t.wire)),
      elevations: fill(elevations, base.elevations, ElevationToken.values.map((t) => t.wire)),
      gradients: fill(gradients, base.gradients, GradientToken.values.map((t) => t.wire)),
      badgeToneRoles: badgeToneRoles,
      buttonVariantRoles: buttonVariantRoles,
    );
  }

  /// The embedded theme, for when the artifact could not be read.
  ///
  /// It is deliberately not a separate code path: it is the same [RenderTheme.fromJson] over the
  /// artifact snapshot, so the fallback cannot "work differently" from a fresh theme.
  factory RenderTheme.fallback() => ThemeContract.fallback().defaultTheme;

  /// The id of the theme in its contract.
  final String id;
  /// The name of the theme, for a theme picker.
  final String name;

  /// A note on where the values come from. Not shown to users.
  final String source;

  /// Whether this is a light or a dark theme.
  ///
  /// This is a contract field, not a guess from the brightness of `surface`. The host uses it to
  /// match a theme to the system mode, so "which theme is the dark one" is not baked into the app
  /// release.
  final Brightness brightness;

  /// Tokens whose values the design did not supply: chosen by hand on the builder side. This is
  /// data, so a host can, for example, avoid building a brand-critical screen on such a colour.
  final Set<String> provisional;

  /// `"color.primary"` to `"object-bg/brand/strong500"`: names of design system variables. The
  /// reader does not need them for drawing; they are for a person comparing a screen with the
  /// design source.
  final Map<String, String> origins;

  final ThemeFontFamily? bodyFont;
  final ThemeFontFamily? headingFont;

  /*
   * SIX DICTIONARIES, KEYED BY NAME RATHER THAN BY ENUM.
   *
   * The theme declares its own tokens: the core (`x-tokens.core`) is mandatory, the rest are the
   * project's own names (`brandCoral`, `card`, `xxl`). So the key here is a string. The enums in
   * `tokens.dart` remain the NAMES OF THE CORE: the reader uses them to name what it refers to
   * itself (field defaults, chrome of composite widgets, the inheritance root), and only those
   * may be assumed present.
   */
  final Map<String, Color> colors;
  final Map<String, double> spacing;
  final Map<String, double> radii;
  final Map<String, TextStyle> typography;
  final Map<String, List<BoxShadow>> elevations;

  /// Theme gradients, already translated to Flutter's coordinate system.
  ///
  /// An empty map is a normal state: a theme that describes no gradients simply draws none.
  /// Unlike roles, this does not make the theme unusable: without roles the reader does not know
  /// what to draw a badge with, while without a gradient it knows exactly: nothing.
  final Map<String, LinearGradient> gradients;

  /// Semantics to palette. It comes from the theme, not from code.
  final Map<BadgeToneToken, ThemeRole> badgeToneRoles;
  final Map<ButtonVariantToken, ThemeRole> buttonVariantRoles;

  /// Whether the theme carries roles for both badge tones and button variants.
  ///
  /// A theme without roles is still usable: an absent role is drawn neutrally (`missingRole`),
  /// because the reader keeps no hand-written default role map.
  bool get hasRoles => badgeToneRoles.isNotEmpty && buttonVariantRoles.isNotEmpty;

  /// Whether the token value was chosen by hand (it did not come from the design).
  bool isProvisional(String tokenPath) => provisional.contains(tokenPath);

  /// The colours of a badge tone in this theme.
  RoleColors badgeTone(BadgeToneToken token) =>
      _resolveRole(badgeToneRoles[token], 'roles.badgeTone.${token.wire}');

  /// The colours of a button variant in this theme.
  RoleColors buttonVariant(ButtonVariantToken token) =>
      _resolveRole(buttonVariantRoles[token], 'roles.buttonVariant.${token.wire}');

  /// A role the theme does not have: this **executes `missingRole: 'render-neutral'`** of
  /// `x-compatibility.policy`; it is not reader taste.
  ///
  /// The real case: the widget vocabulary and the theme contract are versioned INDEPENDENTLY, so
  /// a new badge tone may arrive with the schema before its role arrives with the theme. Drawing a
  /// neutral badge beats throwing away the whole theme over one tone. It deliberately has no
  /// background or border: inventing a colour would bring back a hand-written role map by the
  /// back door.
  ///
  /// A ROLE THAT NAMES A COLOUR THE THEME DOES NOT DECLARE (`unknownRoleColor:
  /// 'render-neutral'`) makes only THAT SLOT neutral: a background or border with a broken
  /// reference reads as absent, the foreground as the root colour (`onSurface`). The rest of the
  /// role stays: one broken slot is no reason to discard two sound ones.
  RoleColors _resolveRole(ThemeRole? role, String path) {
    if (role == null) {
      if (kDebugMode) debugPrint('[hotlayout] theme "$id" has no role "$path" → neutral look');
      return RoleColors(foreground: color(ColorToken.onSurface));
    }
    Color? slot(String? name, String label) {
      if (name == null) return null;
      final resolved = colorNamed(name);
      if (resolved == null && kDebugMode) {
        debugPrint('[hotlayout] theme "$id": role "$path" names color "$name" ($label), which the theme does not have');
      }
      return resolved;
    }

    return RoleColors(
      // `null` stays `null`: "no background" is not "a transparent background".
      background: slot(role.background, 'background'),
      foreground: slot(role.foreground, 'foreground') ?? color(ColorToken.onSurface),
      border: slot(role.border, 'border'),
    );
  }

  /// The colour of a CORE token. Resolution is always total: if the map is incomplete (the theme
  /// was read partially) a sensible default is returned instead of throwing
  /// (`partialTheme: 'resolve-missing-to-defaults'`).
  Color color(ColorToken token) =>
      colorNamed(token.wire) ?? colors[ColorToken.onSurface.wire] ?? Colors.black;

  /// A colour by NAME, or `null` if the theme does not declare that name.
  ///
  /// Mirrors `themeColor` in `resolve.ts`. Between "no value" and `null` there is exactly one
  /// step: the FALLBACK TOKEN from the contract (`x-optionalColors.fallbacks`). The three state
  /// colours are optional in a theme, and the contract names what they were drawn with before the
  /// dedicated names existed. There is no other substitution here: an invented colour would look
  /// like a correct one.
  Color? colorNamed(String name) {
    final own = colors[name];
    if (own != null) return own;
    final fallback = kThemeColorFallbacks[name];
    return fallback == null ? null : colors[fallback];
  }

  double space(SpacingToken token) => spacing[token.wire] ?? 0;

  double radius(RadiusToken token) => radii[token.wire] ?? 0;

  TextStyle text(TypographyToken token) =>
      typography[token.wire] ?? typography[TypographyToken.bodyM.wire] ?? const TextStyle(fontSize: 14);

  List<BoxShadow> elevation(ElevationToken token) => elevations[token.wire] ?? const [];

  // ── References from the document ("token or value") to theme values ─────
  //
  // Mirrors `resolve.ts` of the reference implementation, line by line. THE ONLY ANSWER TO
  // "NONE" IS `null`: a token the theme does not declare gives `null`, and the reader does NOT
  // APPLY the property (`tokenWithoutFieldDefault: 'omit-field'`). No function here substitutes a
  // "similar" token. A custom name missing from this theme is the same case
  // (`missingCustomToken: 'treat-as-unknown-token'`).

  /// A colour reference to a colour.
  ///
  /// Opacities MULTIPLY: a tint `{token, opacity: 0.5}` of a half-transparent theme colour
  /// (`#rrggbb80`) gives a quarter, not a half.
  Color? resolveColor(ColorRef ref) => switch (ref) {
    TokenColorRef(:final token, :final opacity) => _faded(colorNamed(token), opacity),
    CustomColorRef(:final color, :final opacity) => _faded(color, opacity),
  };

  static Color? _faded(Color? color, double opacity) =>
      color == null || opacity == 1 ? color : color.withValues(alpha: color.a * opacity);

  /// The colour of a PART of a widget: a `props` field with a default (divider line, bar fill). An
  /// unknown token gives the FIELD DEFAULT: `unknownToken: 'fallback-to-field-default'`.
  Color fieldColor(FieldColor field) {
    final resolved = resolveColor(field.ref);
    if (resolved != null) return resolved;
    if (kDebugMode) {
      debugPrint('[hotlayout] theme "$id" has no color ${field.ref} → ${field.fieldDefault.wire}');
    }
    return color(field.fieldDefault);
  }

  /// A spacing in logical pixels, or `null` if there is no such token.
  double? resolveSpacing(ScaleRef ref) => ref.value ?? spacing[ref.token];

  /// The spacing of a `props` field with a default (gap, spacer, divider margin). An unknown
  /// token gives the FIELD default, as in [fieldColor].
  double fieldSpacing(FieldSpacing field) => resolveSpacing(field.ref) ?? space(field.fieldDefault);

  /// A radius in logical pixels, or `null` if there is no such token.
  double? resolveRadius(ScaleRef ref) => ref.value ?? radii[ref.token];

  /// The insets of a box. A side that is not named is zero; sides are LOGICAL, so the result is
  /// an [EdgeInsetsDirectional].
  ///
  /// There are two rules for an unknown token, and the difference lies in the SHAPE of the
  /// document value:
  ///  * one value for all sides (`padding: 'huge'`): the field is not applied, `null`
  ///    (`unknownBoxToken: 'omit-field'`);
  ///  * a per-side shape is ALWAYS applied: each unknown side is zero and the rest apply, even if
  ///    all are unknown (`unknownSideToken: 'side-is-zero'`). For a widget with a role this is
  ///    the difference between "keep the button's built-in padding" and "remove it".
  EdgeInsetsDirectional? resolveBoxSpacing(BoxSpacing? value) {
    if (value == null) return null;
    final top = _maybe(value.top, resolveSpacing);
    final end = _maybe(value.end, resolveSpacing);
    final bottom = _maybe(value.bottom, resolveSpacing);
    final start = _maybe(value.start, resolveSpacing);
    // A single value that did not resolve means the field is not applied.
    if (value.isSingleValue && top == null) return null;
    return EdgeInsetsDirectional.only(
      top: top ?? 0,
      end: end ?? 0,
      bottom: bottom ?? 0,
      start: start ?? 0,
    );
  }

  static double? _maybe(ScaleRef? ref, double? Function(ScaleRef ref) resolve) =>
      ref == null ? null : resolve(ref);

  /// The radii of a box: logical corners, so a [BorderRadiusDirectional]. The unknown-token rules
  /// are the same as in [resolveBoxSpacing].
  BorderRadiusDirectional? resolveBoxRadius(BoxRadius? value) {
    if (value == null) return null;
    final topStart = _maybe(value.topStart, resolveRadius);
    final topEnd = _maybe(value.topEnd, resolveRadius);
    final bottomEnd = _maybe(value.bottomEnd, resolveRadius);
    final bottomStart = _maybe(value.bottomStart, resolveRadius);
    if (value.isSingleValue && topStart == null) return null;
    return BorderRadiusDirectional.only(
      topStart: Radius.circular(topStart ?? 0),
      topEnd: Radius.circular(topEnd ?? 0),
      bottomEnd: Radius.circular(bottomEnd ?? 0),
      bottomStart: Radius.circular(bottomStart ?? 0),
    );
  }

  /// A typography reference to the theme style with overrides applied.
  ///
  /// An override replaces exactly its own field. `lineHeight` stays a MULTIPLIER and multiplies
  /// the already overridden font size, which Flutter does by itself since `TextStyle.height` is
  /// also a multiplier. The family always comes from the token; with no token there is no style,
  /// even if overrides are named (there is nothing to override).
  TextStyle? resolveTypography(TypographyRef ref) {
    final base = typography[ref.token];
    if (base == null) return null;
    return base.copyWith(
      fontSize: ref.fontSize,
      fontWeight: ref.fontWeight == null ? null : themeFontWeight(ref.fontWeight),
      height: ref.lineHeight,
      letterSpacing: ref.letterSpacing,
    );
  }

  /// A gradient reference to a [LinearGradient].
  ///
  /// A custom gradient with a stop on an unknown token is not drawn AT ALL, rather than drawn
  /// "without that stop": without it, it is a different gradient that would look intentional.
  /// Unordered stops: `unorderedGradient: 'omit-field'`.
  LinearGradient? resolveGradient(GradientRef ref) {
    switch (ref) {
      case TokenGradientRef(:final token):
        final value = gradients[token];
        if (value == null && kDebugMode) {
          debugPrint('[hotlayout] theme "$id" has no gradient "$token" → no background drawn');
        }
        return value;
      case CustomGradientRef(:final angle, :final stops):
        final direction = gradientDirection(angle);
        if (direction == null || !ref.isOrdered) return null;
        final colors = <Color>[];
        for (final stop in stops) {
          final color = resolveColor(stop.color);
          if (color == null) return null;
          colors.add(color);
        }
        return themeLinearGradient(
          angle,
          direction,
          colors: colors,
          stops: [for (final stop in stops) stop.position],
        );
    }
  }

  /// The PAINT OF A PROGRESS SCALE (since 9.7.0): the colour of the track and of the fill, solid
  /// or gradient. Mirrors `resolveProgressPaint` of the reference implementation.
  ///
  /// Track: `trackColor`, and without it, with an unknown token or of the wrong shape, `secondary`
  /// (`defaultTrackColor`). Fill: `gradient` if it resolved, otherwise `color` with the FIELD
  /// default. A gradient that did not resolve (no such token, stops going backwards, a stop on an
  /// unknown colour) disappears ENTIRELY and the fill is solid. The gradient ANGLE is not read
  /// (`gradient.angle: 'ignored'`): the scale supplies the direction, so an angle that
  /// [resolveGradient] would reject for a background is no reason to refuse here.
  ({Color track, Color? fill, List<Color>? colors, List<double>? positions}) resolveProgressPaint({
    required FieldColor color,
    ColorRef? trackColor,
    GradientRef? gradient,
  }) {
    final track =
        (trackColor == null ? null : resolveColor(trackColor)) ??
        this.color(ColorToken.secondary);

    if (gradient != null) {
      final stops = _progressGradientStops(gradient);
      if (stops != null) {
        return (
          track: track,
          fill: null,
          colors: [for (final stop in stops) stop.color],
          positions: [for (final stop in stops) stop.position],
        );
      }
    }
    return (track: track, fill: fieldColor(color), colors: null, positions: null);
  }

  List<({Color color, double position})>? _progressGradientStops(GradientRef ref) {
    switch (ref) {
      case TokenGradientRef(:final token):
        final value = gradients[token];
        if (value == null) return null;
        final colors = value.colors;
        final positions = value.stops;
        if (positions == null || positions.length != colors.length) return null;
        return [for (var i = 0; i < colors.length; i += 1) (color: colors[i], position: positions[i])];
      case CustomGradientRef(:final stops):
        if (!ref.isOrdered) return null;
        final result = <({Color color, double position})>[];
        for (final stop in stops) {
          final color = resolveColor(stop.color);
          if (color == null) return null;
          result.add((color: color, position: stop.position));
        }
        return result;
    }
  }

  /// A shadow reference to layers in Flutter's PAINT order (see the reversal in `theme_json.dart`).
  ///
  /// An empty list is a legitimate answer ("no shadow", token `none`), and it is not the same as
  /// `null` ("the theme does not know such a shadow").
  List<BoxShadow>? resolveShadow(ShadowRef ref) {
    switch (ref) {
      case TokenShadowRef(:final token):
        return elevations[token];
      case CustomShadowRef(:final layers):
        final shadows = <BoxShadow>[];
        for (final layer in layers) {
          final color = resolveColor(layer.color);
          if (color == null) return null;
          shadows.add(
            BoxShadow(
              color: color,
              offset: Offset(layer.offsetX, layer.offsetY),
              blurRadius: layer.blur,
              spreadRadius: layer.spread,
            ),
          );
        }
        // The same reversal as for a theme shadow: `first-is-nearest`.
        return shadows.reversed.toList(growable: false);
    }
  }

  /// The style of a PART without the fields this theme will not apply (an unknown token), or `null` if nothing is
  /// left (`x-style.layout.partStyle.unknownToken`: the key is skipped).
  PartStyle? applicablePartStyle(PartStyle style) {
    final applicable = PartStyle(
      color: style.color != null && resolveColor(style.color!) != null ? style.color : null,
      typography: style.typography != null && resolveTypography(style.typography!) != null ? style.typography : null,
    );
    return applicable.isEmpty ? null : applicable;
  }

  /// The style of a STATE without the fields this theme will not apply, or `null` if nothing is
  /// left to apply (`x-style.unknownTokenInCase: 'keep-base-field'`).
  ///
  /// Mirrors `isApplicable` in `resolveNodeStyleInTheme` of the reference implementation. A field
  /// is "not applied" when the theme cannot resolve its reference: there is no such token, or a
  /// background/border names a colour or gradient the theme does not declare. A per-side shape
  /// (`padding: {top: ...}`) is ALWAYS applied, since it is not a "single value" and an unknown
  /// side in it is zero.
  NodeStyle? applicableStyle(NodeStyle style) {
    final background = style.background;
    final border = style.border;
    final applicable = NodeStyle(
      color: style.color != null && resolveColor(style.color!) != null ? style.color : null,
      typography: style.typography != null && resolveTypography(style.typography!) != null
          ? style.typography
          : null,
      // The theme does not resolve emphasis words; they do not need it.
      fontStyle: style.fontStyle,
      textDecoration: style.textDecoration,
      padding: resolveBoxSpacing(style.padding) == null ? null : style.padding,
      margin: resolveBoxSpacing(style.margin) == null ? null : style.margin,
      radius: resolveBoxRadius(style.radius) == null ? null : style.radius,
      border: border != null && resolveColor(border.color) != null ? border : null,
      background: switch (background) {
        ColorBackground(:final color) when resolveColor(color) == null => null,
        GradientBackground(:final gradient) when resolveGradient(gradient) == null => null,
        _ => background,
      },
      shadow: style.shadow != null && resolveShadow(style.shadow!) != null ? style.shadow : null,
      width: style.width,
      height: style.height,
      minWidth: style.minWidth,
      maxWidth: style.maxWidth,
      minHeight: style.minHeight,
      maxHeight: style.maxHeight,
      opacity: style.opacity,
    );
    return applicable.isEmpty ? null : applicable;
  }

  /// A core gradient by token, or `null` if the theme does not describe it.
  ///
  /// `null` rather than a default: an invented gradient cannot be told from a real one, so
  /// drawing nothing beats drawing the wrong thing.
  LinearGradient? gradient(GradientToken token) => resolveGradient(TokenGradientRef(token.wire));

  /// A node background to a decoration WITHOUT the image: a colour or a gradient.
  ///
  /// For a host that needs to paint something with the same background as a document node (such
  /// as the system bars around the screen). Only the reader itself draws an image background: it
  /// is not a theme value but a network resource with its own states. `null`, an unknown token
  /// and an image give an empty decoration.
  BoxDecoration backgroundDecoration(NodeBackground? background) => BoxDecoration(
    color: switch (background) {
      ColorBackground(:final color) => resolveColor(color),
      _ => null,
    },
    gradient: switch (background) {
      GradientBackground(:final gradient) => resolveGradient(gradient),
      _ => null,
    },
  );

  BorderRadius borderRadius(RadiusToken token) => BorderRadius.circular(radius(token));

  EdgeInsets padding(SpacingToken token) => EdgeInsets.all(space(token));

  /// The icon glyph size: the `fontSize` of the typography token of the CURRENT theme
  /// (`x-style.layout.iconGlyphTypography`: `sm` is `bodyS`, `md` is `titleM`, `lg` is
  /// `displayL`).
  ///
  /// The icon is set in a font, so it grows with the system scale exactly as the text beside it
  /// does; `IconGlyph` itself multiplies the side. Fixed constants would be a second copy of the
  /// measure that a rebrand changing the font scale would not touch.
  double iconSize(IconSizeToken token) =>
      text(kIconGlyphTypography[token] ?? kIconGlyphTypography[kDefaultIconSize]!).fontSize ?? 0;

  /// The icon BOX before system scaling: as wide as the font size, as tall as the token's LINE
  /// (`fontSize x lineHeight`, `x-style.layout.iconGlyphBox`). The glyph in it is a square of the
  /// font size, centred. Why a line and not a square: the icon is set in a font and stands next to
  /// a label of the same token, so a line with an icon and one without have the same height. The
  /// system font scale multiplies both sides; `IconBox` does that, since it needs a context.
  Size iconBox(IconSizeToken token) {
    final style = text(kIconGlyphTypography[token] ?? kIconGlyphTypography[kDefaultIconSize]!);
    final width = style.fontSize ?? 0;
    return Size(width, width * (style.height ?? 1));
  }

  /// A Material theme in the colors of this theme, for the `MaterialApp` or
  /// `Theme` around the document.
  ///
  /// It is built from the same tokens so that system widgets (app bar, ripple, chips) do not
  /// diverge from the document rendering.
  ThemeData toMaterialTheme() {
    final scheme = ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: color(ColorToken.primary),
      primary: color(ColorToken.primary),
      onPrimary: color(ColorToken.onPrimary),
      secondary: color(ColorToken.secondary),
      surface: color(ColorToken.surface),
      onSurface: color(ColorToken.onSurface),
      error: color(ColorToken.danger),
    );
    return ThemeData(brightness: brightness, colorScheme: scheme, useMaterial3: true);
  }

  @override
  String toString() => 'RenderTheme($id, "$name", ${brightness.name})';

  /// A contract angle to a pair of [Alignment]s. Exactly eight rows, as many as the angle `enum`
  /// values in the theme artifact (`gradientAngleSpace: 'axis-as-css-diagonal-corner-to-corner'`).
  ///
  /// AXIS angles (0 / 90 / 180 / 270) are "as in CSS": 0 deg runs bottom to top, 90 deg left to
  /// right. Both readers draw them exactly.
  ///
  /// DIAGONAL angles (45 / 135 / 225 / 315) are NOT degrees but "CORNER TO CORNER", clockwise from
  /// "up": 45 runs from the bottom left to the top right, 135 from the top left to the bottom
  /// right, 225 from the top right to the bottom left, 315 from the bottom right to the top left.
  /// That is how the angle maps onto [Alignment]: the start and end of the gradient sit in the
  /// CORNERS of the box, whatever its shape.
  ///
  /// All eight are PHYSICAL: they are not mirrored in right-to-left writing, because a gradient is
  /// a picture, not text. That is why this uses [Alignment], not `AlignmentDirectional`.
  ///
  /// The pair of [Alignment]s says only WHERE the start and end are. How the lines of equal colour
  /// lie between them on a non-square box is the business of [CornerGradient].
  static ({Alignment begin, Alignment end})? gradientDirection(double angle) => switch (angle) {
    0 => (begin: Alignment.bottomCenter, end: Alignment.topCenter),
    45 => (begin: Alignment.bottomLeft, end: Alignment.topRight),
    90 => (begin: Alignment.centerLeft, end: Alignment.centerRight),
    135 => (begin: Alignment.topLeft, end: Alignment.bottomRight),
    180 => (begin: Alignment.topCenter, end: Alignment.bottomCenter),
    225 => (begin: Alignment.topRight, end: Alignment.bottomLeft),
    270 => (begin: Alignment.centerRight, end: Alignment.centerLeft),
    315 => (begin: Alignment.bottomRight, end: Alignment.topLeft),
    _ => null,
  };

}
