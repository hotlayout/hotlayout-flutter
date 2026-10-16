/// Buttons, icon buttons and badges: role colours, sizes and an icon beside the
/// label.
library;

import 'package:flutter/material.dart';

import '../../model/form_rules.dart';
import '../../model/icon_from_data.dart';
import '../../model/layout_rules.dart';
import '../../model/node.dart';
import '../../model/node_style.dart';
import '../../model/style_values.dart';
import '../../model/swipe_confirm.dart' show kSwipeThumbGlyph, swipeRunnerOf;
import '../../model/tokens.dart';
import '../../model/visibility.dart';
import '../../theme/render_theme.dart';
import '../dashed_border.dart';
import '../icon_box.dart';
import '../key_repeat_guard.dart';
import '../layout/quiet_flex.dart';
import '../node_renderer.dart';
import '../render_scope.dart';
import '../screen_form.dart';
import '../swipe_confirm_button.dart';
import '../tap_target.dart';
import 'node_box.dart';
import 'write_control.dart';

extension ButtonWidgets on NodeRenderer {
  /// A button. Colors come from `theme.roles.buttonVariant`, not from code.
  ///
  /// **The widget also chooses by role, not by enum.** The difference "filled / outlined /
  /// nothing" is exactly what roles describe with slots. Therefore:
  ///  * a border present: `OutlinedButton` (with or without a fill);
  ///  * no border, a background present: `FilledButton`;
  ///  * neither background nor border: `TextButton`, **with no fill at all**, not a fill of
  ///    `transparent`. That is how `ghost` looks in the contract, and here the absence of a value
  ///    differs from a transparent color: CSS flattens this difference, Flutter does not
  ///    (`TextButton` has neither a background of its own nor a pressed state for it).
  ///
  /// **A node's own style overrides the role (schema 9.0.0).** The role provides the background,
  /// foreground and border BY DEFAULT; the node's own `style.background`, `color`, `border`,
  /// `radius`, `shadow`, `padding` and `typography` each override their slot and go onto the
  /// button, not onto a box around it. The choice of widget does not change: it looks at what
  /// results AFTER the overlay, so a `ghost` with its own background becomes a filled button.
  Widget buildButton(ButtonNode node, NodeStyle? own, {bool natural = false}) {
    final surface = _roleSurface(theme.buttonVariant(node.variant), own);
    // SIZE (schema 9.5.0) is a row of the `buttonSizes` table, in theme tokens; `md` is exactly
    // the pre-9.5.0 button. A node's own style is stronger, EACH FIELD SEPARATELY: `style.padding`
    // overrides the size's padding, `style.typography` the font.
    final geometry = buttonGeometryOf(node.size);
    final typography = surface.typography ?? theme.text(geometry.typography);
    final disabled = _pressDisabled(node.requiresFilled, node.disabledIf);
    final Widget button = node.confirmBySwipe
        ? _swipeTrack(node, own, surface, geometry, typography, disabled)
        : _roleButton(
            surface,
            onPressed: disabled ? null : () => emit(node.action, node.id),
            padding:
                surface.padding ??
                EdgeInsetsDirectional.symmetric(
                  horizontal: theme.space(geometry.inline),
                  vertical: theme.space(geometry.block),
                ),
            typography: typography,
            // The "icon + caption" pair is centered in the button TOGETHER, also in a full-width button:
            // the row is shrunk to its content and the button itself centers it.
            child: buildIconBesideText(
              Text(
                text(node.label),
                strutStyle: lineStrut(typography),
                // The caption is centered on a second line too (`buttonLabelAlign`).
                textAlign: TextAlign.center,
              ),
              icon: resolveIconToken(node.icon, node.iconPath, data.lookup),
              position: node.iconPosition,
              style: typography,
              color: surface.foreground,
            ),
          );

    // Look and place come from the document; the touch target is no smaller than 48 x 48 dp and
    // does not take part in layout.
    final target = withWriteControl(
      control: controlOfAction(node.action),
      name: text(node.label),
      disabled: disabled,
      onPress: () => emit(node.action, node.id),
      child: TapTarget(child: button),
    );
    return node.fullWidth && !natural ? SizedBox(width: double.infinity, child: target) : target;
  }

  /// A button that is confirmed by a swipe (schema 9.22.0, `x-swipeConfirm`): a track in the box of the button
  /// (the surface and the size as usual, the inline padding not read) with a circular thumb at the inline start. The
  /// thumb is the background of the ROLE (the node's own `style.background` paints the track, not the thumb) and the
  /// picture on it the foreground of the role; a role without a background gives `primary` / `onPrimary`. The picture is
  /// the icon of the button, or `chevron-right`, in the font size of the label.
  Widget _swipeTrack(
    ButtonNode node,
    NodeStyle? own,
    RoleSurface surface,
    ButtonSizeGeometry geometry,
    TextStyle typography,
    bool disabled,
  ) {
    final role = theme.buttonVariant(node.variant);
    final roleFilled = role.background != null;
    final icon = resolveIconToken(node.icon, node.iconPath, data.lookup);
    return SwipeConfirmTrack(
      decorate: (content) => nodeSurface(
        color: surface.color,
        gradient: surface.gradient,
        image: surface.image,
        radius: surface.radius ?? theme.borderRadius(RadiusToken.md),
        shadow: surface.shadow,
        border: surface.border,
        blur: surface.blur,
        child: content,
      ),
      radius: surface.radius ?? theme.borderRadius(RadiusToken.md),
      label: text(node.label),
      typography: typography,
      labelColor: surface.foreground,
      verticalPadding: surface.padding?.vertical ?? 2 * theme.space(geometry.block),
      border: surface.border?.width ?? 0,
      inset: theme.space(SpacingToken.xs),
      thumbColor: roleFilled ? role.background! : theme.color(ColorToken.primary),
      glyphColor: roleFilled ? role.foreground : theme.color(ColorToken.onPrimary),
      glyph: icon == null || icon == IconToken.unknown ? IconToken.parse(kSwipeThumbGlyph) : icon,
      disabled: disabled,
      onActivate: () => (runner: swipeRunnerOf(node.action.handOver(data.lookup)), promise: emit(node.action, node.id)),
      focusColor: theme.color(ColorToken.primary),
    );
  }

  /// THE ICON BUTTON (schema 9.5.0, `x-style.layout.iconButton`): a circle with a picture in the
  /// center and no visible text.
  ///
  /// The geometry is the same size table as the button's: the content box is a SQUARE whose side
  /// is the size's font line, the picture is a square of the font size, the padding is the
  /// button's vertical padding of that size on ALL four sides, and the border is added to the
  /// side. So the side equals the height of a button of the same size (28 / 40 / 48 with the
  /// built-in theme), and it is not padded up to 44-48 dp: the touch target is the area around it
  /// ([TapTarget]), not the size.
  ///
  /// THE ACCESSIBLE NAME is `label` after translation and data substitution; it is not drawn on
  /// screen. A Material button already provides a semantics node with the button role; the name
  /// goes into it from the child, and the picture is hidden from screen readers. Without a label
  /// the name is the icon's name in words (`iconButtonWithoutLabel: 'draw-and-name-by-icon'`),
  /// and the button is drawn and works the same.
  Widget buildIconButton(IconButtonNode node, NodeStyle? own) {
    final surface = _roleSurface(theme.buttonVariant(node.variant), own);
    final geometry = buttonGeometryOf(node.size);
    final typography = surface.typography ?? theme.text(geometry.typography);
    final glyph = typography.fontSize ?? 0;
    final line = glyph * (typography.height ?? 1);
    final name = iconButtonNameOf(text(node.label), node.iconName);
    // The drawing may come from data (9.19.0); the accessible name stays the label.
    final icon = resolveIconToken(node.icon, node.iconPath, data.lookup)!;
    final disabled = _pressDisabled(node.requiresFilled, node.disabledIf);

    final button = _roleButton(
      surface,
      onPressed: disabled ? null : () => emit(node.action, node.id),
      padding: surface.padding ?? EdgeInsetsDirectional.all(theme.space(geometry.block)),
      typography: typography,
      // The radius is `pill`: a circle. `style.radius` makes the icon button square.
      defaultRadius: theme.borderRadius(RadiusToken.pill),
      child: Semantics(
        label: name.isEmpty ? null : name,
        child: ExcludeSemantics(
          // With a numeric `glyphSize` (schema 9.16.0) the content box is a square of that number
          // instead of a square of the font line, and the BUTTON'S BOX grows with it: the padding
          // is the same. The system font scale does not multiply the number. A named side of the
          // node clamps the picture (`OwnGlyphBox` is never larger than the space).
          child: node.glyphSize == null
              ? IconBox(box: Size.square(line), glyph: glyph, icon: icon, color: surface.foreground)
              : OwnGlyphBox(side: node.glyphSize!.toDouble(), icon: icon, color: surface.foreground),
        ),
      ),
    );
    return withWriteControl(
      control: controlOfAction(node.action),
      name: name,
      disabled: disabled,
      onPress: () => emit(node.action, node.id),
      child: TapTarget(child: button),
    );
  }

  /// AN ICON BESIDE TEXT (schema 9.5.0, `x-style.layout.iconBesideText`): ONE rule for three
  /// places: a button caption, a badge caption and the text of a row's trailing slot.
  ///
  ///  * the gap between the icon box and the text is [kIconBesideTextGap];
  ///  * the box center is on the center of the text LINE, not on the baseline;
  ///  * the color is the neighboring text's ([color]); the icon has none of its own;
  ///  * the order is LOGICAL: the parts stand in writing direction, and in RTL a `Row` under
  ///    `Directionality` swaps them, not this code. Mirroring of the PICTURE is separate and
  ///    happens exactly once, in `IconGlyph`, according to the contract's list.
  ///
  /// [box] is the icon box. For a button and a badge it comes from the caption's font ([style]:
  /// font size wide, line height tall), so the icon does not change the widget's HEIGHT and
  /// increases the width by exactly "font size + gap". A row slot names its own (a step of the icon
  /// scale).
  ///
  /// With [icon] `null` there is no field: text only. With [IconToken.unknown] the icon is named
  /// but cannot be drawn: the empty box and the gap REMAIN (`unknownIconBesideText:
  /// 'empty-box-keeps-gap'`). Empty text beside an icon removes nothing (`emptyTextBesideIcon:
  /// 'keep-icon-and-gap'`).
  ///
  /// The icon is decorative: it is not part of the button's accessible name.
  Widget buildIconBesideText(
    Widget label, {
    required IconToken? icon,
    required IconPositionToken position,
    required Color color,
    TextStyle? style,
    Size? box,
  }) {
    if (icon == null) return label;
    final glyph = style?.fontSize ?? 0;
    final picture = ExcludeSemantics(
      child: IconBox(
        box: box ?? Size(glyph, glyph * (style?.height ?? 1)),
        icon: icon,
        color: color,
      ),
    );
    final gap = SizedBox(width: theme.space(kIconBesideTextGap));
    // The text shrinks when the pair lacks room (a narrow "full width" button); the icon and the
    // gap do not.
    final words = Flexible(child: label);
    return QuietRow(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: position == IconPositionToken.end ? [words, gap, picture] : [picture, gap, words],
    );
  }

  /// THE CAPTION LINE is EXACTLY `font size x multiplier` of the font, whatever the script.
  ///
  /// The contract's button and badge height is "caption line + padding + border" (28 / 40 / 48).
  /// `TextStyle.height` does not hold this by itself: a glyph missing from the theme's font family
  /// (Arabic, Devanagari) is drawn by a fallback font with its own ascent and descent, and the line
  /// grows: an Arabic `lg` button came out 51 dp against 48 elsewhere, where CSS `line-height`
  /// fixes the line. In tests there is a single font, so the difference is not visible there.
  StrutStyle lineStrut(TextStyle typography) => StrutStyle(
    fontFamily: typography.fontFamily,
    fontSize: typography.fontSize,
    height: typography.height,
    forceStrutHeight: true,
  );

  /// A Material button over a role surface, shared by `Button` and `IconButton`.
  ///
  /// **The widget is chosen by role, not by enum.** The difference "filled / outlined / nothing" is
  /// exactly what roles describe with slots:
  ///  * a border present: `OutlinedButton` (with or without a fill);
  ///  * no border, a background present: `FilledButton`;
  ///  * neither: `TextButton`, **with no fill at all**, not a fill of `transparent` (that is how
  ///    `ghost` looks in the contract).
  ///
  /// [defaultRadius] is the radius when there is no own one: `md` for a button, `pill` for an icon
  /// button. `null` for a button without background and border keeps the Material shape, which is
  /// visible only at the moment of a press.
  Widget _roleButton(
    RoleSurface surface, {
    required VoidCallback? onPressed,
    required EdgeInsetsGeometry padding,
    required TextStyle typography,
    required Widget child,
    BorderRadiusGeometry? defaultRadius,
  }) {
    final body = _roleButtonBody(
      surface,
      onPressed: onPressed,
      padding: padding,
      typography: typography,
      defaultRadius: defaultRadius,
      child: child,
    );
    // A DISABLED button (schema 9.14.0, `form.button`): opacity 0.5 on the WHOLE widget, the same
    // theme role (the theme has no `disabled` group), no action, no `track`, no press feedback:
    // `onPressed: null`. It stays in the focus order and in the semantics tree with `enabled:
    // false`: a person and a screen reader must be able to find it and hear that it is
    // unavailable. It does not say why.
    if (onPressed == null) return DisabledPress(child: body);
    return KeyRepeatGuard(child: body);
  }

  /// Whether the button is disabled: `disabledIf`, or `requiresFilled` on an unfilled form of its
  /// screen (`pressDisabledOf`). The form is computed only when a button asks about it, and once
  /// per screen.
  bool _pressDisabled(bool requiresFilled, VisibilityCondition? disabledIf) => isPressDisabled(
    requiresFilled: requiresFilled,
    disabledIf: disabledIf,
    data: data,
    formFilled: () => form?.filled ?? true,
  );

  Widget _roleButtonBody(
    RoleSurface surface, {
    required VoidCallback? onPressed,
    required EdgeInsetsGeometry padding,
    required TextStyle typography,
    required Widget child,
    BorderRadiusGeometry? defaultRadius,
  }) {
    final radius = surface.radius;
    final border = surface.border;
    final fallbackRadius = defaultRadius ?? theme.borderRadius(RadiusToken.md);
    final shape = RoundedRectangleBorder(borderRadius: radius ?? fallbackRadius);

    /*
     * A background a Material button cannot do (a gradient, an image or a custom shadow) is drawn
     * by `backgroundBuilder`: the button's standard extension point, a layer right under its
     * content. The button's own fill is then switched off. A plain color stays in
     * `backgroundColor`, so a button without a style of its own is built exactly as before schema
     * 9.0.0.
     */
    final decorated = surface.gradient != null || surface.image != null || surface.hasShadow || surface.blur != null;
    final backgroundBuilder = decorated
        ? (BuildContext context, Set<WidgetState> states, Widget? child) => nodeSurface(
            color: surface.color,
            gradient: surface.gradient,
            image: surface.image,
            radius: radius ?? fallbackRadius,
            shadow: surface.shadow,
            blur: surface.blur,
            child: child ?? const SizedBox.shrink(),
          )
        : null;
    final fill = decorated ? Colors.transparent : surface.color;

    /*
     * A BUTTON'S SIZE IS CONTENT PLUS PADDING PLUS BORDER, and nothing more.
     *
     * A Material button adds four things the document does not have, and each made a button on a
     * phone a different size from other readers':
     *
     *  - a minimum size of 64x40: "OK" became wider than its caption;
     *  - room for a finger: 48 dp tall of INVISIBLE padding around a shorter button (on phones
     *    only, so it is not visible on desktop);
     *  - platform density: on desktop the padding shrinks by 4 dp on each side, so `style.padding`
     *    did not act as written;
     *  - its own 24 dp padding and 14/500 caption instead of the size's padding and font, which
     *    other readers use to draw and measure the button.
     *
     * The border consumes layout pixels, as in the node box ([nodeBox]) and in CSS: in a Material
     * button it is painted OVER the padding and is not added to the size.
     */
    final inset = border == null ? padding : EdgeInsetsDirectional.all(border.width).add(padding);

    if (border != null) {
      // A dashed border (9.22.0) is painted over the button, inside its box; the Material button draws no side.
      final dashed = border is DashedBorderSide;
      final outlined = OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: fill,
          foregroundColor: surface.foreground,
          // Disabled uses the same colors; the opacity comes from the wrapper (`DisabledPress`).
          disabledBackgroundColor: fill,
          disabledForegroundColor: surface.foreground,
          disabledMouseCursor: SystemMouseCursors.basic,
          side: dashed ? BorderSide.none : border,
          shape: shape,
          padding: inset,
          textStyle: typography,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.standard,
          backgroundBuilder: backgroundBuilder,
        ),
        child: child,
      );
      return dashed ? DashedBorder(side: border, radius: radius ?? fallbackRadius, child: outlined) : outlined;
    }
    if (surface.hasBackground) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: fill,
          foregroundColor: surface.foreground,
          disabledBackgroundColor: fill,
          disabledForegroundColor: surface.foreground,
          disabledMouseCursor: SystemMouseCursors.basic,
          shape: shape,
          padding: inset,
          textStyle: typography,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.standard,
          backgroundBuilder: backgroundBuilder,
        ),
        child: child,
      );
    }
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: surface.foreground,
        disabledForegroundColor: surface.foreground,
        disabledMouseCursor: SystemMouseCursors.basic,
        // The shape of a button without a background and border is visible only at the moment of a
        // press, so the built-in one stays until the document (or the widget) names its own.
        shape: radius == null && defaultRadius == null ? null : shape,
        padding: inset,
        textStyle: typography,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        backgroundBuilder: backgroundBuilder,
      ),
      child: child,
    );
  }

  /// WHAT TO DRAW THE SURFACE OF A WIDGET WITH A ROLE: the theme role with the node's own style
  /// laid over it. Mirrors the reference `resolveRoleSurface`.
  ///
  /// EACH SLOT SEPARATELY: `style.background` changes the background and leaves the caption color
  /// alone. An own field that did not resolve (the token is not in the theme) is not applied, so
  /// the slot stays with the role instead of becoming empty.
  ///
  /// [own] is the style of the node ITSELF with its state applied. A color inherited from an
  /// ancestor does not get here by construction: the function does not accept it
  /// (`x-style.roles.inheritedColor: 'does-not-override-role'`).
  RoleSurface _roleSurface(RoleColors role, NodeStyle? own) {
    final background = own?.background;
    final ownColor = background is ColorBackground ? theme.resolveColor(background.color) : null;
    final ownGradient = background is GradientBackground ? theme.resolveGradient(background.gradient) : null;
    final ownImage = background is ImageBackground ? background : null;
    final overridden = ownColor != null || ownGradient != null || ownImage != null;

    final roleBorder = role.border;
    return RoleSurface(
      color: overridden ? ownColor : role.background,
      gradient: ownGradient,
      image: ownImage,
      foreground: (own?.color == null ? null : theme.resolveColor(own!.color!)) ?? role.foreground,
      border:
          borderSide(own?.border) ??
          (roleBorder == null ? null : BorderSide(color: roleBorder, width: kRoleBorderWidth)),
      radius: theme.resolveBoxRadius(own?.radius),
      shadow: own?.shadow == null ? null : theme.resolveShadow(own!.shadow!),
      padding: theme.resolveBoxSpacing(own?.padding),
      typography: own?.typography == null ? null : theme.resolveTypography(own!.typography!),
      blur: own?.backdropBlur,
    );
  }

  /// A badge. The tone is the document's semantics, the tone colors come from the theme through
  /// `theme.roles.badgeTone`; the reader has no tone `switch` of its own.
  ///
  /// `background`/`border` are optional here too: a theme may define a badge without a fill
  /// (`color: null` in [BoxDecoration] means no fill) or with a border. The reader must not
  /// silently drop what the theme said.
  ///
  /// A node's own style overrides the role just as for a button; see [_roleSurface]. Without it
  /// the badge is built as before schema 9.0.0: a pill with `md` / `xs` padding and a `caption`
  /// text style.
  Widget buildBadge(BadgeNode node, NodeStyle? own) {
    final surface = _roleSurface(theme.badgeTone(node.tone), own);
    final typography = surface.typography ?? theme.text(TypographyToken.caption);
    return nodeSurface(
      color: surface.color,
      gradient: surface.gradient,
      image: surface.image,
      radius: surface.radius ?? theme.borderRadius(RadiusToken.pill),
      shadow: surface.shadow,
      border: surface.border,
      blur: surface.blur,
      child: Padding(
        // The border consumes layout pixels, as in the node box.
        padding: EdgeInsetsDirectional.all(surface.border?.width ?? 0).add(
          surface.padding ??
              EdgeInsets.symmetric(
                horizontal: theme.space(kBadgePaddingInline),
                vertical: theme.space(kBadgePaddingBlock),
              ),
        ),
        // Since schema 9.5.0 a "chip" is a badge with an icon. The icon takes the caption's color
        // and font size; the badge stays text, not a control.
        child: buildIconBesideText(
          Text(
            text(node.label),
            style: typography.copyWith(color: surface.foreground),
            strutStyle: lineStrut(typography),
          ),
          icon: resolveIconToken(node.icon, node.iconPath, data.lookup),
          position: node.iconPosition,
          style: typography,
          color: surface.foreground,
        ),
      ),
    );
  }
}
