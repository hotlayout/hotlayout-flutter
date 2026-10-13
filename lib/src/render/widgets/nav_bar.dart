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
                  IconBox(box: theme.iconBox(IconSizeToken.md), icon: node.icon, color: color),
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
                IconBox(box: theme.iconBox(IconSizeToken.md), icon: node.icon, color: color),
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
    );
  }
}
