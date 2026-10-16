import 'package:flutter/foundation.dart';

import '../data/screen_data.dart';
import 'bindable.dart';
import 'motion_rules.dart';
import 'style_values.dart';
import 'text_emphasis.dart';
import 'visibility.dart';

/// The shared style of a node (schema 9.0.0): the look lives here and nowhere else.
///
/// Before 9.0.0 padding, radius, background and shadow lay in the `props` of individual widgets
/// (`Container.padding`, `Screen.background`, `Text.color`, ...), and `style` was a point override of
/// three fields. Now the shape is the same on EVERY widget, and those fields are gone from `props`: what
/// remains there is content, behaviour and the layout of children.
///
/// THERE ARE NO HIDDEN DEFAULTS (`x-style.hiddenDefaults: 'none'`). A node without `style` has no
/// background, padding, radius or shadow. The builder WRITES the usual look of a card into the document.
///
/// There is no rule "style beats props": text color no longer lives in two places, so there is nothing to
/// arbitrate, and the overlay of style onto `props` during parsing is gone with it.
///
/// THE VALUES HERE ARE REFERENCES ("token or value"), not pixels: the theme turns them into colors and
/// numbers (`RenderTheme.resolve...`), and it also answers "there is no such token", in which case the
/// property is simply not applied.
@immutable
final class NodeStyle {
  const NodeStyle({
    this.color,
    this.typography,
    this.fontStyle,
    this.textDecoration,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.minWidth,
    this.maxWidth,
    this.minHeight,
    this.maxHeight,
    this.radius,
    this.border,
    this.background,
    this.shadow,
    this.opacity,
    this.backdropBlur,
    this.textGradient,
  });

  /// Foreground color. INHERITED down the tree.
  final ColorRef? color;

  /// Typography style. INHERITED down the tree, as a whole rather than field by field.
  final TypographyRef? typography;

  /// Slant of text (9.17.0). INHERITED like color and font, each field separately; only `Text` reads it.
  /// `normal` is a real word: it cancels an inherited italic.
  final EmphasisFontStyle? fontStyle;

  /// Line under or through text (9.17.0). Inherited the same way; `none` cancels an inherited line.
  final EmphasisDecoration? textDecoration;

  final BoxSpacing? padding;
  final BoxSpacing? margin;

  /// Box sizes in dp: a number or a data binding.
  final BindableNumber? width;
  final BindableNumber? height;
  final BindableNumber? minWidth;
  final BindableNumber? maxWidth;
  final BindableNumber? minHeight;
  final BindableNumber? maxHeight;

  final BoxRadius? radius;
  final NodeBorder? border;
  final NodeBackground? background;
  final ShadowRef? shadow;

  /// 0…1.
  final double? opacity;

  /// Glass (9.20.0): blur of whatever is painted UNDER the box of the node, within its radius, in logical
  /// pixels (the standard deviation of a Gaussian blur, 1…40). Not inherited. `null` means no blur.
  final int? backdropBlur;

  /// A gradient on the glyphs of a text (9.23.0): a token of the theme or an own gradient. NOT inherited and read
  /// by `Text` only; `color` stays the fallback when it does not resolve.
  final GradientRef? textGradient;

  /// `null` if there is no style or no understandable field is left in it.
  ///
  /// Implements `unknownStyleField: 'ignore-field'`: a field this code does not know (a later minor will
  /// add it to `style`) is skipped and the rest of the style is drawn. The same goes for a known field of
  /// the wrong shape: one property is lost, not the whole look of the node.
  static NodeStyle? parse(Object? raw) {
    if (raw is! Map) return null;

    final style = NodeStyle(
      color: ColorRef.tryParse(raw['color']),
      typography: TypographyRef.tryParse(raw['typography']),
      fontStyle: readFontStyle(raw['fontStyle']),
      textDecoration: readDecoration(raw['textDecoration']),
      padding: BoxSpacing.tryParse(raw['padding']),
      margin: BoxSpacing.tryParse(raw['margin']),
      width: parseDimension(raw, 'width'),
      height: parseDimension(raw, 'height'),
      minWidth: parseDimension(raw, 'minWidth'),
      maxWidth: parseDimension(raw, 'maxWidth'),
      minHeight: parseDimension(raw, 'minHeight'),
      maxHeight: parseDimension(raw, 'maxHeight'),
      radius: BoxRadius.tryParse(raw['radius']),
      border: NodeBorder.tryParse(raw['border']),
      background: NodeBackground.tryParse(raw['background']),
      shadow: ShadowRef.tryParse(raw['shadow']),
      opacity: _boundedOpacity(raw),
      backdropBlur: backdropBlurOf(raw['backdropBlur']),
      textGradient: GradientRef.tryParse(raw['textGradient']),
    );

    return style.isEmpty ? null : style;
  }

  /// Opacity: outside 0..1 it is clamped, a non-number is zero (the lower bound of the field); a field
  /// absent from the document is not affected. An explicit `null` also means "no field"
  /// (`nullNumericField: 'absent'`): otherwise a node with `"opacity": null` became invisible.
  static double? _boundedOpacity(Map raw) {
    final value = raw['opacity'];
    if (value == null) return null;
    if (value is! num || value.isNaN) return 0;
    return value.toDouble().clamp(0, 1).toDouble();
  }

  bool get isEmpty =>
      color == null &&
      typography == null &&
      fontStyle == null &&
      textDecoration == null &&
      padding == null &&
      margin == null &&
      width == null &&
      height == null &&
      minWidth == null &&
      maxWidth == null &&
      minHeight == null &&
      maxHeight == null &&
      radius == null &&
      border == null &&
      background == null &&
      shadow == null &&
      opacity == null &&
      backdropBlur == null &&
      textGradient == null;

  /// This style over [base], FIELD BY FIELD AT THE TOP LEVEL (`x-style.caseMerge: 'top-level-fields'`).
  ///
  /// A state with `padding` replaces `padding` WHOLE, not by sides; a state with `border` replaces both
  /// width and color. Deep merging has no way to say "this state has NO top padding", and above all two
  /// readers would have to decide the same way where the merge stops.
  NodeStyle over(NodeStyle? base) {
    if (base == null) return this;
    return NodeStyle(
      color: color ?? base.color,
      typography: typography ?? base.typography,
      fontStyle: fontStyle ?? base.fontStyle,
      textDecoration: textDecoration ?? base.textDecoration,
      padding: padding ?? base.padding,
      margin: margin ?? base.margin,
      width: width ?? base.width,
      height: height ?? base.height,
      minWidth: minWidth ?? base.minWidth,
      maxWidth: maxWidth ?? base.maxWidth,
      minHeight: minHeight ?? base.minHeight,
      maxHeight: maxHeight ?? base.maxHeight,
      radius: radius ?? base.radius,
      border: border ?? base.border,
      background: background ?? base.background,
      shadow: shadow ?? base.shadow,
      opacity: opacity ?? base.opacity,
      backdropBlur: backdropBlur ?? base.backdropBlur,
      textGradient: textGradient ?? base.textGradient,
    );
  }

  /// This style without the fields named in [names] (`unset` of a width layer, 9.19.0): "no field", which is what the
  /// node has without it. A name that is not a field of the style is skipped. `null` when no field is left.
  NodeStyle? without(Set<String> names) {
    if (names.isEmpty) return this;
    bool keep(String name) => !names.contains(name);
    final rest = NodeStyle(
      color: keep('color') ? color : null,
      typography: keep('typography') ? typography : null,
      fontStyle: keep('fontStyle') ? fontStyle : null,
      textDecoration: keep('textDecoration') ? textDecoration : null,
      padding: keep('padding') ? padding : null,
      margin: keep('margin') ? margin : null,
      width: keep('width') ? width : null,
      height: keep('height') ? height : null,
      minWidth: keep('minWidth') ? minWidth : null,
      maxWidth: keep('maxWidth') ? maxWidth : null,
      minHeight: keep('minHeight') ? minHeight : null,
      maxHeight: keep('maxHeight') ? maxHeight : null,
      radius: keep('radius') ? radius : null,
      border: keep('border') ? border : null,
      background: keep('background') ? background : null,
      shadow: keep('shadow') ? shadow : null,
      opacity: keep('opacity') ? opacity : null,
      backdropBlur: keep('backdropBlur') ? backdropBlur : null,
      textGradient: keep('textGradient') ? textGradient : null,
    );
    return rest.isEmpty ? null : rest;
  }

  /// The same style with a different radius (a sheet shown as a window, 9.18.0: the bottom corners take
  /// the radius of the top ones, `sheetWindowRadius`).
  NodeStyle withRadius(BoxRadius? value) => NodeStyle(
    color: color,
    typography: typography,
    fontStyle: fontStyle,
    textDecoration: textDecoration,
    padding: padding,
    margin: margin,
    width: width,
    height: height,
    minWidth: minWidth,
    maxWidth: maxWidth,
    minHeight: minHeight,
    maxHeight: maxHeight,
    radius: value,
    border: border,
    background: background,
    shadow: shadow,
    opacity: opacity,
    backdropBlur: backdropBlur,
    textGradient: textGradient,
  );

  /// The style of a screen root: without `margin` and sizes (`screenBoxFields: 'ignore'`). Schema 9.0.0
  /// does not give them to a screen, but the document may not have been built by the builder, so the
  /// renderer has to ignore them rather than execute them.
  NodeStyle? get forScreen {
    final rest = NodeStyle(
      color: color,
      typography: typography,
      fontStyle: fontStyle,
      textDecoration: textDecoration,
      padding: padding,
      radius: radius,
      border: border,
      background: background,
      shadow: shadow,
      opacity: opacity,
      backdropBlur: backdropBlur,
    );
    return rest.isEmpty ? null : rest;
  }

  /// The style of the BOX around a widget with a role: without the seven fields that, on `Button` and
  /// `Badge`, lie on the surface of the widget itself (`x-style.roles.overridableBy`).
  ///
  /// Mirror of the builder's `boxStyleOf`. A separate function because this is where readers would
  /// diverge: one would put `style.background` both on the button and on the rectangle behind it.
  NodeStyle? get withoutRoleSurface {
    final rest = NodeStyle(
      margin: margin,
      width: width,
      height: height,
      minWidth: minWidth,
      maxWidth: maxWidth,
      minHeight: minHeight,
      maxHeight: maxHeight,
      opacity: opacity,
    );
    return rest.isEmpty ? null : rest;
  }
}

/// The `style` fields that, for a widget with a role, describe ITS SURFACE rather than the box.
/// Mirror of `x-style.roles.overridableBy`; a test guards against drift.
const List<String> kRoleStyleKeys = [
  'background',
  'color',
  'border',
  'radius',
  'shadow',
  'padding',
  'typography',
];

/// Border width of a role (`x-style.roles.roleBorderWidth`): the theme has none.
const double kRoleBorderWidth = 1;

/// Widgets with a role: which prop names the role and in which `theme.roles` group it lies. Mirror of
/// `x-style.roles.widgets`.
const Map<String, ({String prop, String group})> kRoleWidgets = {
  'Button': (prop: 'variant', group: 'buttonVariant'),
  // Since 9.5.0 the icon button reads the same group as the button.
  'IconButton': (prop: 'variant', group: 'buttonVariant'),
  'Badge': (prop: 'tone', group: 'badgeTone'),
};

/// Who reads the inherited foreground. Mirror of `x-style.readers`.
const Map<String, List<String>> kTextStyleReaders = {
  'color': ['Text', 'Icon', 'ListTile', 'AppBar', 'Tab', 'NavItem', 'Accordion'],
  'typography': ['Text'],
};

/// WHICH PARTS OF A WIDGET TAKE THE NAMED COLOR, and with what strength.
///
/// Mirror of `x-style.colorParts`. `whenUnnamed` says what to draw with until nobody has named a
/// color: `root` is the root color (`onSurface`), `built-in` is the widget's own color, as before 9.0.0.
/// `primary` is the named color as is, `secondary` is the same with the opacity
/// [kSecondaryPartOpacity].
const Map<String, ({String whenUnnamed, Map<String, String> parts})> kColorParts = {
  'Text': (whenUnnamed: 'root', parts: {'content': 'primary'}),
  'Icon': (whenUnnamed: 'root', parts: {'glyph': 'primary'}),
  'ListTile': (
    whenUnnamed: 'built-in',
    parts: {
      'title': 'primary',
      'subtitle': 'secondary',
      'leadingIcon': 'primary',
      'trailingText': 'primary',
      'trailingIcon': 'primary',
      'chevron': 'secondary',
    },
  ),
  'AppBar': (
    whenUnnamed: 'built-in',
    parts: {'title': 'primary', 'subtitle': 'secondary', 'backIcon': 'primary'},
  ),
  'Tab': (whenUnnamed: 'built-in', parts: {'activeTitle': 'primary', 'inactiveTitle': 'secondary'}),
  'NavItem': (whenUnnamed: 'built-in', parts: {'activeItem': 'primary', 'inactiveItem': 'secondary'}),
  'Accordion': (whenUnnamed: 'built-in', parts: {'title': 'primary', 'chevron': 'secondary'}),
};

/// The `style` fields that `ScreenStyle` does not have (`x-style.screenExcluded`): a screen takes the
/// place the host gave it, so the fields around the box and the sizes do not belong to it. Mirror; a test
/// guards against drift.
const List<String> kScreenExcludedStyleKeys = [
  'margin',
  'width',
  'height',
  'minWidth',
  'maxWidth',
  'minHeight',
  'maxHeight',
];

/// Opacity of secondary parts (`x-style.secondaryOpacity`).
const double kSecondaryPartOpacity = 0.6;

/// The root of inheritance (`x-style.root`): text that nobody said anything to.
const String kRootTextColor = 'onSurface';
const String kRootTypography = 'bodyM';

/// ONE STATE of a node (schema 8.9.0): a condition and the style that applies while it holds.
///
/// The condition is the SAME as in `visibleIf`, by contract decision rather than coincidence: a second
/// notion of a condition would mean a second set of operators and a second chance for them to diverge
/// from the first.
@immutable
final class StyleCase {
  const StyleCase({required this.when, required this.style});

  final VisibilityCondition when;
  final NodeStyle style;

  static List<StyleCase> parseList(Object? raw) {
    if (raw is! List) return const [];
    final cases = <StyleCase>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final when = VisibilityCondition.parse(entry['when']);
      final style = NodeStyle.parse(entry['style']);
      // A state without a condition or without a style means nothing. The schema does not produce them, but
      // the document comes from the network, and silently skipping one is better than drawing a "state" that
      // differs in nothing.
      if (when == null || style == null) continue;
      cases.add(StyleCase(when: when, style: style));
    }
    return cases;
  }
}

/// THE STYLE A NODE IS DRAWN WITH NOW: the base plus the first state whose condition holds.
///
/// Mirror of the builder's `resolveNodeStyle`, and they cannot diverge, or a locked card would be gray
/// on the web and branded on a phone.
///
/// THE FIRST, NOT THE NARROWEST: states in a real document overlap ("progress > 0" and "progress =
/// 100"), and there is nothing to measure the specificity of a condition with. The order is set by the
/// manager and is visible in the JSON.
///
/// AN OVERLAY, NOT A REPLACEMENT: the base `style` may set the font for all states, and a state only the
/// color. The overlay is by top-level field, see [NodeStyle.over].
///
/// Asked at RENDER time, not parse time: which state is in effect depends on the DATA, and data changes
/// without the document being re-read.
///
/// [applicable] is the THEME (`x-style.unknownTokenInCase: 'keep-base-field'`): a field of a STATE that
/// this theme will not apply (an unknown token, a background whose color or gradient the theme does not
/// declare) is dropped BEFORE the overlay onto the base style, and the node's BASE value stays in
/// effect. Otherwise a state would replace the field first and it would then fail to apply, so a token
/// removed from the theme erased even a working base color in that state. Mirror of the builder's
/// `resolveNodeStyleInTheme`. Without a theme (`null`) the state is overlaid as is.
NodeStyle? resolveNodeStyle(
  NodeStyle? base,
  List<StyleCase> cases,
  ScreenData data, {
  NodeStyle? Function(NodeStyle style)? applicable,
}) {
  for (final entry in cases) {
    if (!entry.when.evaluate(data)) continue;
    final overlay = applicable == null ? entry.style : applicable(entry.style);
    return overlay == null ? base : overlay.over(base);
  }
  return base;
}
