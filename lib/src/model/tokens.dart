import 'package:flutter/foundation.dart';

import 'icon_set.dart';

/// A contract token is a NAME (`"md"`, `"primary"`), not a value.
/// Concrete px/hex values live in [RenderTheme]; only the vocabulary lives here.
abstract interface class WireToken {
  /// The string the token is written as in JSON. For most tokens it equals `name`, but not every
  /// contract value is a valid Dart identifier (for example `"16:9"`), so the wire name is kept
  /// separately.
  String get wire;
}

/// Resolves a token by name.
///
/// An unknown name is NOT an error: in server-driven UI the backend may introduce a new token
/// before the app learns to draw it. So instead of throwing, the fallback is returned and a
/// debug-mode log line is written.
T resolveToken<T extends WireToken>(List<T> values, Object? raw, T fallback) {
  if (raw is String) {
    for (final value in values) {
      if (value.wire == raw) return value;
    }
    if (kDebugMode) {
      debugPrint('[hotlayout] unknown token "$raw" → ${fallback.wire}');
    }
  }
  return fallback;
}

/*
 * THE SIX ENUMS BELOW ARE THE CORE, NOT THE WHOLE VOCABULARY (since 9.0.0).
 *
 * `SpacingToken`, `ColorToken`, `GradientToken`, `RadiusToken`, `TypographyToken` and
 * `ElevationToken` are not closed vocabularies: a name outside them may still be valid. Names are
 * declared by the THEME, and in a document a token is a string matching a pattern
 * (`x-tokens.namePattern`), so it cannot be parsed into an enum by construction: `brandCoral` is
 * legal if the project theme knows it.
 *
 * The enums remain for exactly what the reader refers to ITSELF: defaults of `props` fields,
 * the chrome of composite widgets (list row, tabs, bar), the inheritance root. This is the
 * mandatory theme core (`x-tokens.core`), the names a theme must have, and a test guards against
 * drift from the artifact.
 *
 * They have no `parse` method for that reason: "unknown name -> default" is decided not by
 * parsing but when a reference meets the theme (`RenderTheme.resolve...`).
 */
enum SpacingToken implements WireToken {
  none,
  xs,
  sm,
  md,
  lg,
  xl;

  @override
  String get wire => name;
}

enum ColorToken implements WireToken {
  primary,
  onPrimary,
  secondary,
  accent,
  surface,
  onSurface,
  muted,
  // Since 7.3.0. A separate token, not a shade of `muted`, and the difference is not cosmetic:
  // `muted` is the colour of secondary TEXT (it must stay readable), while `border` is a hairline
  // (it must be barely visible). One value for two roles inevitably spoils one of them: when
  // dividers were drawn in `muted` they looked like table borders, not section lines.
  border,
  success,
  warning,
  danger,
  // Since 8.19.0. ELEMENT states are not the same as the system states above.
  //
  // `success` reports an EVENT ("the operation succeeded"); `completed` describes the state of
  // the element itself ("this task is done"). Designs use different shades because the roles
  // differ: success must catch the eye, "done" must not.
  //
  // In the THEME these three are optional, and a missing value does NOT mean "draw it black":
  // the contract names what to fall back to (`kThemeColorFallbacks`), namely the tokens the
  // roles borrowed before the dedicated names existed. So an older theme looks in this reader
  // exactly as it always did.
  locked,
  inProgress,
  completed;

  @override
  String get wire => name;
}

/// Gradients of the theme core. As with the other tokens there are no values here: the angle and
/// stops live in the theme contract (`theme.gradient.<token>`).
enum GradientToken implements WireToken {
  brandBackdrop;

  @override
  String get wire => name;
}

enum RadiusToken implements WireToken {
  none,
  sm,
  md,
  lg,
  pill;

  @override
  String get wire => name;
}

enum TypographyToken implements WireToken {
  displayL,
  titleM,
  titleS,
  bodyM,
  bodyS,
  caption,
  numericL;

  @override
  String get wire => name;
}

enum ElevationToken implements WireToken {
  none,
  low,
  medium;

  @override
  String get wire => name;
}

enum AlignToken implements WireToken {
  start,
  center,
  end;

  @override
  String get wire => name;

  static AlignToken parse(Object? raw, {AlignToken fallback = start}) =>
      resolveToken(values, raw, fallback);
}

/// Diameter of the progress ring (since 8.7.0).
///
/// Separate from [IconSizeToken] although the values are the same three words: the scales
/// differ (an icon is measured by font size, a ring by spacing), and a shared enum would mean
/// that changing icon sizes silently moves the rings.
enum CircularSizeToken implements WireToken {
  sm,
  md,
  lg;

  @override
  String get wire => name;

  static CircularSizeToken parse(Object? raw, {CircularSizeToken fallback = md}) =>
      resolveToken(values, raw, fallback);
}

enum JustifyToken implements WireToken {
  start,
  center,
  end,
  between;

  @override
  String get wire => name;

  static JustifyToken parse(Object? raw, {JustifyToken fallback = start}) =>
      resolveToken(values, raw, fallback);
}

/// An icon name from the contract icon set (schema `IconToken`, 332 names since 9.3.0).
///
/// A class rather than an `enum`, since there are hundreds of names: the list is the keys of the
/// BUNDLED set (`kIconBodies`, generated from `contract/icons.json`), and a second hand-written
/// list of the same names would drift from it at the first minor version of the set.
///
/// An UNKNOWN NAME IS [unknown], NOT THE FIELD DEFAULT. A fallback such as `star` would draw a
/// foreign glyph that looks correct in place of any icon from a newer minor version. The policy
/// (`unknownIcon: 'empty-box-same-size'`) overrides the general `unknownToken`: there is no
/// drawing, the box stays. The same holds for a value that is not a string at all
/// (`unreadableIconValue: 'as-unknown-icon'`): an object, a number, `null`; a custom icon from
/// the media library would arrive that way in a future minor version.
@immutable
final class IconToken implements WireToken {
  const IconToken._(this.wire);

  /// An icon this reader cannot draw: an empty box of the same size. It deliberately carries no
  /// name; nothing needs to tell unknown icons apart, and the name was logged while parsing.
  static const IconToken unknown = IconToken._('');

  /// One instance per name: compared by identity, no custom `==`.
  static final Map<String, IconToken> _byName = {
    for (final name in kIconBodies.keys) name: IconToken._(name),
  };

  /// All names in the set, in artifact order.
  static List<IconToken> get values => List.unmodifiable(_byName.values);

  // The ten original names, for code and tests that name an icon themselves.
  static final IconToken star = _byName['star']!;
  static final IconToken trophy = _byName['trophy']!;
  static final IconToken gift = _byName['gift']!;
  static final IconToken target = _byName['target']!;
  static final IconToken clock = _byName['clock']!;
  static final IconToken check = _byName['check']!;

  /// The chevron of a row, of an expandable block and (turned half a revolution) of the app bar's
  /// "back" arrow; the contract uses this one name for all of them.
  static final IconToken chevron = _byName['chevron']!;
  static final IconToken user = _byName['user']!;
  static final IconToken info = _byName['info']!;
  static final IconToken lock = _byName['lock']!;

  @override
  final String wire;

  String get name => wire;

  /// Whether the bundled set has a drawing for this name.
  bool get isKnown => !identical(this, unknown);

  /// Whether the drawing is mirrored in right-to-left writing (`x-mirroredIcons`).
  bool get isMirrored => kMirroredIcons.contains(wire);

  /// Looks only among the names of the set: `toString`, `constructor` and `__proto__` are not
  /// icon names (a Dart `Map` has no inherited keys, but the contract names the rule and a test
  /// pins it).
  static IconToken parse(Object? raw) {
    final known = raw is String ? _byName[raw] : null;
    if (known != null) return known;
    if (kDebugMode) {
      debugPrint(
        raw is String
            ? '[hotlayout] unknown icon "$raw": empty box of the same size'
            : '[hotlayout] icon value is not a name (${raw.runtimeType}): empty box of the same size',
      );
    }
    return unknown;
  }

  @override
  String toString() => isKnown ? 'IconToken($wire)' : 'IconToken.unknown';
}

/// Two policy rows for an icon the reader cannot draw (9.3.0).
/// Mirror of `x-compatibility.policy`; the behaviour is pinned by `icon_library_test.dart`.
const Map<String, String> kIconPolicy = {
  'unknownIcon': 'empty-box-same-size',
  'unreadableIconValue': 'as-unknown-icon',
};

enum IconSizeToken implements WireToken {
  sm,
  md,
  lg;

  @override
  String get wire => name;

  static IconSizeToken parse(Object? raw, {IconSizeToken fallback = md}) =>
      resolveToken(values, raw, fallback);
}

/// The typography token an icon glyph of each size is set in.
///
/// Mirror of `x-style.layout.iconGlyphTypography`. The size is the `fontSize` of this token in
/// the CURRENT theme, not a number from code (`RenderTheme.iconSize`).
const Map<IconSizeToken, TypographyToken> kIconGlyphTypography = {
  IconSizeToken.sm: TypographyToken.bodyS,
  IconSizeToken.md: TypographyToken.titleM,
  IconSizeToken.lg: TypographyToken.displayL,
};

/// The icon box (`x-style.layout.iconGlyphBox`, 9.1.0): width is the `fontSize` of the size's
/// typography token, height is the LINE of that token (`fontSize x lineHeight`). The same rule
/// as in [RenderTheme.iconBox]; it is also data, so another reader takes it from the artifact
/// rather than from prose.
const Map<String, String> kIconGlyphBox = {
  'inline': 'typography-font-size',
  'block': 'typography-line-height',
};

/// The size a glyph is drawn at when `Icon.size` is unknown (`x-style.layout.defaultIconSize`).
const IconSizeToken kDefaultIconSize = IconSizeToken.md;

/// Icons that are PARTS of a list row: the document gives them no size, so the contract names
/// the scale step (`x-style.layout.listTileIconSizes`).
const IconSizeToken kListTileLeadingIconSize = IconSizeToken.md;
const IconSizeToken kListTileTrailingIconSize = IconSizeToken.sm;

enum AssetToken implements WireToken {
  logo,
  banner,
  placeholder;

  @override
  String get wire => name;

  static AssetToken parse(Object? raw, {AssetToken fallback = placeholder}) =>
      resolveToken(values, raw, fallback);
}

/// The direction in which a `Container` lays out its children (since 8.1.0).
///
/// The default is `column`, which is why this was a minor change: a document without the field
/// is drawn as before. The cross axis is the same as in `Column`/`Row`.
enum ContainerDirectionToken implements WireToken {
  column,
  row;

  @override
  String get wire => name;

  static ContainerDirectionToken parse(Object? raw, {ContainerDirectionToken fallback = column}) =>
      resolveToken(values, raw, fallback);
}

enum AspectRatioToken implements WireToken {
  square('1:1', 1),
  wide('16:9', 16 / 9),
  classic('4:3', 4 / 3);

  const AspectRatioToken(this.wire, this.ratio);

  @override
  final String wire;
  final double ratio;

  static AspectRatioToken parse(Object? raw, {AspectRatioToken fallback = wide}) =>
      resolveToken(values, raw, fallback);
}

/// How an image fits its box (since 8.11.0).
///
/// The values are named as in CSS and in `BoxFit`, and that is deliberate: the builder draws the
/// same picture with `object-fit`, so a "our word -> theirs" map would be a third place where two
/// readers could diverge.
///
/// `BoxFit` itself deliberately stays out of this file: the token vocabulary knows nothing about
/// widgets; it says WHICH words exist, not how they are drawn.
enum ImageFitToken implements WireToken {
  cover,
  contain;

  @override
  String get wire => name;

  static ImageFitToken parse(Object? raw, {ImageFitToken fallback = cover}) =>
      resolveToken(values, raw, fallback);
}

/// How a screen is presented (since 8.12.0): as a page that replaces the previous screen, or as a
/// modal sheet laid over it.
///
/// `modal` does NOT mean "small": the contract names no size at all, since size is a matter of
/// content and platform. Here it is a bottom sheet (`showModalBottomSheet` in Material); on the
/// web the same document may appear as a centred dialog. Both readers stay correct because the
/// contract states only one thing: the previous screen stays in place and visible beneath it.
enum ScreenPresentationToken implements WireToken {
  page,
  modal;

  @override
  String get wire => name;

  static ScreenPresentationToken parse(Object? raw, {ScreenPresentationToken fallback = page}) =>
      resolveToken(values, raw, fallback);
}

enum ButtonVariantToken implements WireToken {
  primary,
  secondary,
  ghost;

  @override
  String get wire => name;

  static ButtonVariantToken parse(Object? raw, {ButtonVariantToken fallback = primary}) =>
      resolveToken(values, raw, fallback);
}

enum BadgeToneToken implements WireToken {
  neutral,
  success,
  warning,
  danger,
  accent;

  @override
  String get wire => name;

  static BadgeToneToken parse(Object? raw, {BadgeToneToken fallback = neutral}) =>
      resolveToken(values, raw, fallback);
}

/// The axis of an element, stated explicitly by the document (`Spacer`, `Divider`).
///
/// `horizontal` means the element lies horizontally (a full-width strip that takes up height in
/// a stack); `vertical` is the opposite. The axis is stated by the contract, not inferred from
/// where the node is inserted.
enum OrientationToken implements WireToken {
  horizontal,
  vertical;

  @override
  String get wire => name;

  static OrientationToken parse(Object? raw, {OrientationToken fallback = horizontal}) =>
      resolveToken(values, raw, fallback);
}

enum TextOverflowToken implements WireToken {
  clip,
  ellipsis,
  visible;

  @override
  String get wire => name;

  static TextOverflowToken parse(Object? raw, {TextOverflowToken fallback = ellipsis}) =>
      resolveToken(values, raw, fallback);
}

enum ProgressLabelFormatToken implements WireToken {
  valueOfMax,
  percent,
  none;

  @override
  String get wire => name;

  static ProgressLabelFormatToken parse(
    Object? raw, {
    ProgressLabelFormatToken fallback = valueOfMax,
  }) => resolveToken(values, raw, fallback);
}
