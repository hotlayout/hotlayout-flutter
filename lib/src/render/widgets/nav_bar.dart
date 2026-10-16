/// The navigation bar: at the bottom, at the top on a wide screen, and its items.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../model/bottom_zone_rules.dart';
import '../../model/layout_rules.dart';
import '../../model/node.dart';
import '../../model/node_style.dart';
import '../../model/tokens.dart';
import '../icon_box.dart';
import '../key_repeat_guard.dart';
import '../node_renderer.dart';
import '../press_feedback.dart';
import '../../model/press_feedback.dart';
import '../render_scope.dart';
import '../wide_nav_group.dart';
import '../width_class_scope.dart';
import 'button.dart';
import 'node_box.dart';

extension NavBarWidgets on NodeRenderer {
  /// The bar's items that the reader draws (`navBar.items`): the first five VISIBLE ones.
  List<NavItemNode> _navItemsOf(NavBarNode node) =>
      visibleNodes(node.children).whereType<NavItemNode>().take(kNavBarMaxItems).toList();

  /// The group of navigation items placed at the TOP (schema 9.18.0): in the app bar or in its own
  /// strip. `null` means nothing to draw (no items). The reader inherits the color named on the
  /// bar itself but does not draw its box; only [buildTopNavBar] does that.
  Widget? wideNavGroupFor(NavBarNode nav) {
    final items = _navItemsOf(nav);
    if (items.isEmpty) return null;
    final navOwn = resolveNodeStyle(nav.style, nav.styleWhen, data, applicable: theme.applicableStyle);
    return inheriting(navOwn)._wideNavGroup(items);
  }

  Widget _wideNavGroup(List<NavItemNode> items) {
    final box = theme.iconBox(IconSizeToken.md);
    // The group itself sets the "navigation" landmark; the bar is not a `tablist`.
    return WideNavGroup(
      labels: [for (final item in items) text(item.label)],
      labelStyle: theme.text(TypographyToken.bodyM),
      paddingInline: theme.space(SpacingToken.md),
      iconWidth: box.width,
      gap: theme.space(SpacingToken.xs),
      between: theme.space(SpacingToken.xs),
      children: [
        for (final item in items)
          () {
            final own = resolveNodeStyle(item.style, item.styleWhen, data, applicable: theme.applicableStyle);
            return inheriting(own)._wideNavItem(item);
          }(),
      ],
    );
  }

  /// The navigation bar's OWN TOP STRIP (schema 9.18.0): used when there is no app bar zone and
  /// the bar is placed at the top. It is an app-bar-like zone: fixed at the top, not scrolling,
  /// edge to edge (it has no root padding). Built-in look: `surface` background, a 1 `border` line
  /// at the BOTTOM; a named `style.background` and `style.border` replace them. Items start at the
  /// row start in the screen's content column. Height is the item plus the line.
  ///
  /// [topInset] is the top safe inset (9.19.0, `safeTop.wideOwnNavBar`): it stands INSIDE the strip,
  /// above the items, so the strip's background covers the status bar.
  Widget buildTopNavBar(NavBarNode node, NodeStyle? own, {int? contentMax, double topInset = 0}) {
    final line = own?.border == null;
    final lineWidth = line ? kNavBarLineWidth : 0.0;
    final group = wideNavGroupFor(node);
    return Container(
      decoration: own?.background == null ? BoxDecoration(color: theme.color(ColorToken.surface)) : null,
      foregroundDecoration: line
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(width: lineWidth, color: theme.color(ColorToken.border)),
              ),
            )
          : null,
      child: Padding(
        padding: EdgeInsets.only(top: topInset, bottom: lineWidth),
        child: ContentColumn(
          maxWidth: contentMax,
          // A tight column width: the group decides the mode (with labels or pictures only) by it.
          child: SizedBox(width: double.infinity, child: group ?? const SizedBox.shrink()),
        ),
      ),
    );
  }

  /// The glyph of an item, with the dot on it when the item's `badgeWhen` holds (schema 9.22.0). The same in
  /// the bar at the bottom and in the one at the top; the item's size does not change and the item does not clip it.
  Widget _itemGlyph(NavItemNode node, Color color) {
    final box = theme.iconBox(IconSizeToken.md);
    final glyph = IconBox(box: box, icon: node.icon, color: color);
    final condition = node.badgeWhen;
    if (condition == null) return glyph;
    return NavBadgeMotion(
      shown: condition.evaluate(data),
      builder: (context, scale, opacity) =>
          NavBadgeMark(box: box, color: theme.color(ColorToken.accent), scale: scale, opacity: opacity, child: glyph),
      plain: glyph,
    );
  }

  /// The navigation item overlay: hover and press are transparent, keyboard focus is visible.
  WidgetStateProperty<Color?> _navOverlay() => WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.focused)
        ? theme.color(ColorToken.primary).withValues(alpha: 0.12)
        : Colors.transparent,
  );

  /// An item of the bar placed at the TOP: the picture and the label IN A ROW, of natural width
  /// (`wideNav.item`). Color, active item, tap and semantics are the same as the bottom bar's
  /// ([_navItem]). In the "pictures only" mode the label is not drawn but remains the item's
  /// accessible name (`overflow.hiddenLabel`).
  Widget _wideNavItem(NavItemNode node) {
    final active = isActiveNavAction(node.action.type, node.action.params, shownScreenId);
    final color = active ? partColor(ColorToken.primary) : partColor(ColorToken.muted, secondary: true);
    final style = theme.text(TypographyToken.bodyM).copyWith(color: color);
    final label = text(node.label);
    final name = iconButtonNameOf(label, node.iconName);
    return KeyRepeatGuard(
      child: Semantics(
        button: true,
        selected: active,
        label: name.isEmpty ? null : name,
        onTap: () => emit(node.action, node.id),
        excludeSemantics: true,
        // A transparent `Material` UNDER the item: the ink splash is painted on the nearest one.
        child: Material(
          type: MaterialType.transparency,
          child: PressFeedback(
            kind: pressFeedbackKindOf(node),
            child: InkWell(
            key: ValueKey('sdui-nav-item-${node.id}'),
            // The contract names no hover or press look for an item, and the other readers draw
            // none: Material's gray hover backdrop (web, desktop) is not a contract state. Only
            // the keyboard focus indication remains.
            overlayColor: _navOverlay(),
            splashFactory: NoSplash.splashFactory,
            onTap: () => emit(node.action, node.id),
            child: Padding(
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: theme.space(SpacingToken.md),
                vertical: theme.space(SpacingToken.sm),
              ),
              child: Row(
                children: [
                  _itemGlyph(node, color),
                  // The gap lives INSIDE the flexible part: in the "pictures only" mode it has no
                  // room left, and the gap disappears together with the label (the item's width is
                  // padding, picture, padding).
                  Flexible(
                    child: ClipRect(
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(start: theme.space(SpacingToken.xs)),
                        child: Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          strutStyle: lineStrut(style),
                          style: style,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }

  /// The NAVIGATION BAR (schema 9.12.0, `x-style.layout.navBar`). Items are `NavItem` children in
  /// document order; the VISIBLE ones divide the width equally (up to five, the rest are not drawn:
  /// `navBarExtraItems`), in reading direction: the first item at the start, so in right-to-left
  /// writing it is on the right (this is done by `Row` under `Directionality`, not by this code).
  ///
  /// Built-in look: `surface` background and a 1 top line in `border`. A named `style.background`
  /// and `style.border` REPLACE them (the shared node box draws those, so the built-in is simply
  /// not set); the line counts toward the bar's height, so without it the bar is one pixel
  /// shorter. The line is painted OVER the items and takes no separate space in their row: an item
  /// extends under it, so the touch target really spans the bar's full height.
  ///
  /// The safe area inset ([safeBottom]) goes UNDER the items INSIDE the bar: the background
  /// extends to the physical bottom. The bar is a navigation landmark, not a `tablist`.
  Widget buildNavBar(NavBarNode node, NodeStyle? own, {required double safeBottom, required bool zone, int? contentMax}) {
    final items = visibleNodes(node.children).whereType<NavItemNode>().take(kNavBarMaxItems).toList();
    final line = own?.border == null;
    final lineWidth = line ? kNavBarLineWidth : 0.0;
    final row = ContentColumn(
      maxWidth: contentMax,
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: styledNode(item, Slot.free, (renderer, _) => renderer._navItem(item, lineWidth: lineWidth)),
            ),
        ],
      ),
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      // Only the bottom-zone bar is a navigation landmark: a second one on the screen (not the
      // root's last child) would give two unnamed labels of the same role, which Flutter treats as
      // an error in debug.
      role: zone ? SemanticsRole.navigation : null,
      child: Container(
        decoration: own?.background == null ? BoxDecoration(color: theme.color(ColorToken.surface)) : null,
        foregroundDecoration: line
            ? BoxDecoration(
                border: Border(top: BorderSide(width: lineWidth, color: theme.color(ColorToken.border))),
              )
            : null,
        // A transparent `Material` UNDER the items: the ink splash is painted on the nearest one,
        // and without it the bar's background would cover it.
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [row, if (safeBottom > 0) SizedBox(height: safeBottom)],
          ),
        ),
      ),
    );
  }

  /// A bar item: the icon ABOVE the label, centered on both axes; padding `sm` / `xs`, gap `xs`;
  /// an `md` icon step, a `bodyS` label on one line truncated with an ellipsis (`navBar.item`).
  /// The active item (`isActiveNavAction`) is `primary`, the rest `muted`; the icon has the same
  /// color. A named color applies to the active item as is and to the rest with transparency
  /// (`colorParts.NavItem`).
  ///
  /// The touch target is the whole share at full height; the item is a button named by its label
  /// (`selected` marks the active one). A tap runs its action by the same path as a button
  /// (`emit`): the active item does nothing special, since the stack is already that screen and
  /// `navigate.section` itself produces neither a change nor an event.
  Widget _navItem(NavItemNode node, {required double lineWidth}) {
    final active = isActiveNavAction(node.action.type, node.action.params, shownScreenId);
    final color = active ? partColor(ColorToken.primary) : partColor(ColorToken.muted, secondary: true);
    final style = theme.text(TypographyToken.bodyS).copyWith(color: color);
    final label = text(node.label);
    final name = iconButtonNameOf(label, node.iconName);
    final side = theme.space(SpacingToken.xs);
    final block = theme.space(SpacingToken.sm);
    return KeyRepeatGuard(
      child: Semantics(
        button: true,
        selected: active,
        label: name.isEmpty ? null : name,
        onTap: () => emit(node.action, node.id),
        excludeSemantics: true,
        child: PressFeedback(
          kind: pressFeedbackKindOf(node),
          child: InkWell(
          key: ValueKey('sdui-nav-item-${node.id}'),
          overlayColor: _navOverlay(),
          splashFactory: NoSplash.splashFactory,
          onTap: () => emit(node.action, node.id),
          child: Padding(
            padding: EdgeInsetsDirectional.only(top: block + lineWidth, bottom: block, start: side, end: side),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _itemGlyph(node, color),
                SizedBox(height: theme.space(SpacingToken.xs)),
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    strutStyle: lineStrut(style),
                    style: style,
                  ),
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}

/// A dot on the top corner of an item's glyph on the side of the end of the line (schema 9.22.0, `navBadge`): the
/// centre on the corner of the glyph, the right one in left-to-right writing and the left one in right-to-left. The
/// glyph is a square the size of the font in the middle of the box of the row, so its top lies `(row - font) / 2`
/// below the top of the box. The dot is a picture: it is not announced, and it takes no room.
class NavBadgeMark extends StatelessWidget {
  const NavBadgeMark({
    super.key,
    required this.box,
    required this.color,
    required this.child,
    this.scale = 1,
    this.opacity = 1,
  });

  /// The scale and the opacity of the dot at this moment of its appearance or fading (9.24.0).
  final double scale;
  final double opacity;

  /// The box of the glyph before the system font scale.
  final Size box;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final textScale = box.width == 0 ? 1.0 : scaler.scale(box.width) / box.width;
    final width = box.width * textScale;
    final height = box.height * textScale;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final dot = navBadgeBoxOf(glyphLeft: 0, glyphTop: (height - width) / 2, glyphSize: width, rtl: rtl);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          left: dot.left,
          top: dot.top,
          width: dot.size,
          height: dot.size,
          child: ExcludeSemantics(
            child: Opacity(
              opacity: opacity,
              // A matrix, not `Transform.scale`: at the start of the flash the scale is exactly 0.
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(scale, scale, 1),
                child: DecoratedBox(decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The motion of the dot (schema 9.24.0, `navBadgeMotion`): when the condition of an item changes its answer WHILE
/// the screen is shown, the dot appears with a flash (0 to 1.25 to 1 over 320 ms) or fades (200 ms, kept in place
/// until the end). The first show of the item, a screen shown again (a new state) and "reduce motion" show or hide
/// the dot at once. A new change starts its own motion from its start. The item does not change size or name.
class NavBadgeMotion extends StatefulWidget {
  const NavBadgeMotion({super.key, required this.shown, required this.builder, required this.plain});

  /// Whether the condition holds now.
  final bool shown;

  /// Draws the item with the dot at the given scale and opacity.
  final Widget Function(BuildContext context, double scale, double opacity) builder;

  /// The item without the dot.
  final Widget plain;

  @override
  State<NavBadgeMotion> createState() => _NavBadgeMotionState();
}

class _NavBadgeMotionState extends State<NavBadgeMotion> with SingleTickerProviderStateMixin {
  late final AnimationController _clock;
  NavBadgeChange _moving = NavBadgeChange.none;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(vsync: this)..addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(NavBadgeMotion old) {
    super.didUpdateWidget(old);
    final change = navBadgeChangeOf(
      shownBefore: true,
      before: old.shown,
      after: widget.shown,
      reducedMotion: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
    );
    _moving = change;
    if (change == NavBadgeChange.none) {
      _clock.stop();
      return;
    }
    final ms = change == NavBadgeChange.appear ? kNavBadgeAppearMs : kNavBadgeDisappearMs;
    _clock.duration = Duration(milliseconds: ms);
    _clock.forward(from: 0).whenCompleteOrCancel(() {
      if (mounted && _clock.isCompleted) setState(() => _moving = NavBadgeChange.none);
    });
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _clock.value * (_moving == NavBadgeChange.appear ? kNavBadgeAppearMs : kNavBadgeDisappearMs);
    return switch (_moving) {
      NavBadgeChange.appear => widget.builder(context, navBadgeAppearScaleAt(t), 1),
      NavBadgeChange.disappear => widget.builder(context, 1, navBadgeDisappearOpacityAt(t)),
      NavBadgeChange.none => widget.shown ? widget.builder(context, 1, 1) : widget.plain,
    };
  }
}
