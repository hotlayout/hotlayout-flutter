/// The app bar: back arrow or leading node, title and actions.
library;

import 'package:flutter/material.dart';

import '../../model/action.dart';
import '../../model/media_chrome_rules.dart';
import '../../model/node.dart';
import '../../model/tokens.dart';
import '../app_bar_layout.dart';
import '../icon_glyph.dart';
import '../layout/quiet_flex.dart';
import '../node_renderer.dart';
import '../render_scope.dart';
import '../tap_target.dart';
import '../width_class_scope.dart';
import 'button.dart';
import 'nav_bar.dart';
import 'node_box.dart';

extension AppBarWidgets on NodeRenderer {
  /// The app bar. The "back" arrow is `navigate.back`, and this is not a cosmetic choice: in the
  /// contract `showBack` is a flag WITHOUT an action, so the reader had to define "back" itself.
  /// It does so in the only way that invents no new behavior: the same action a button already
  /// performs, with the same degradation: a step back in the document's stack, and from the first
  /// screen, to the host.
  ///
  /// The bar has no background of its own: since schema 9.0.0 it lives in `style.background` and
  /// is drawn by the shared box. A bar without a style is TRANSPARENT, so the screen background
  /// (and its gradient) reaches the very top.
  Widget buildAppBar(AppBarNode node, {int? contentMax, NavBarNode? nav, bool? titleHidden}) {
    final subtitle = node.subtitle == null ? null : text(node.subtitle!);
    // App bar actions (schema 9.9.0): children of type `IconButton` in document order, ordinary
    // icon buttons with everything they have (role, size, style, name, action, touch target). A
    // child of any other type is NOT drawn (`appBarChildren`); an action hidden by a condition
    // takes no space, since `visibleNodes` filters it out. The first two VISIBLE ones are drawn
    // (`appBarExtraActions: 'draw-first-two'`): with eight actions the title would have zero
    // width.
    //
    // Since 9.16.0 an action is an icon button WITHOUT the `zone` field. A child with the field is
    // the node of the leading zone (`appBarLeadingOf`): the FIRST one in document order,
    // regardless of its position among the children. It does not count toward the limit of two
    // actions, and a second such child is not drawn anywhere.
    final kinds = <({String type, BarZone? zone})>[
      for (final child in node.children)
        (
          type: child is ButtonNode ? 'Button' : (child is IconButtonNode ? 'IconButton' : 'other'),
          zone: child is ButtonNode ? child.zone : (child is IconButtonNode ? child.zone : null),
        ),
    ];
    final leadingIndex = appBarLeadingIndex(kinds);
    final leadingNode = leadingIndex == null ? null : node.children[leadingIndex];
    final shown = appBarLeadingShown(leadingNode?.isVisible(data), node.showBack);
    final actions = [
      for (final child in visibleNodes([
        for (final i in appBarActionIndexes(kinds)) node.children[i],
      ]).take(kAppBarMaxDrawnActions))
        renderNode(child, flow: Axis.horizontal),
    ];
    // There is no built-in padding around the bar: the vertical `sm` is the registry's
    // `defaultStyle`, which the builder writes into the document.
    //
    // The title and subtitle are CENTERED in their block, separated by `xs`; the subtitle uses
    // `bodyS`. With `titleAlign: start` (schema 9.16.0) the block's lines start at the writing
    // direction's start; without it they are centered in the block, as before 9.16.0.
    final titleStart = node.titleAlign == AppBarTitleAlign.start;
    final titles = QuietColumn(
      crossAxisAlignment: titleStart ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text(node.title),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: titleStart ? TextAlign.start : TextAlign.center,
          style: theme.text(TypographyToken.titleM).copyWith(color: partColor(ColorToken.onSurface)),
        ),
        if (subtitle != null && subtitle.isNotEmpty) ...[
          SizedBox(height: theme.space(SpacingToken.xs)),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: titleStart ? TextAlign.start : TextAlign.center,
            style: theme
                .text(TypographyToken.bodyS)
                .copyWith(color: partColor(ColorToken.muted, secondary: true)),
          ),
        ],
      ],
    );
    // The arrow's place is an `xl` square with an `md` glyph in the middle. There is no
    // counterweight opposite the arrow (`appBarTitleRoom`): the title sits at the center of the
    // BAR while it fits, and a long one takes all the room between the zones. [AppBarLayout]
    // provides the layout and formulas according to the `appBarCases` table.
    final side = theme.space(SpacingToken.xl);
    final back = Semantics(
      button: true,
      label: labels.back,
      child: TapTarget(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => emit(const ButtonAction(ButtonAction.navigateBack), node.id),
          child: SizedBox.square(
            dimension: side,
            child: Center(
              /*
               * THE "BACK" ARROW is the icon set's `chevron` ROTATED BY HALF A TURN. `IconGlyph`
               * mirrors it by itself according to the contract's list, exactly once: in RTL the
               * chevron points left, half a turn, and the arrow points right, toward where the
               * user came from. There is no direction correction of its own here, and there must
               * not be.
               */
              child: RotatedBox(
                quarterTurns: 2,
                child: IconGlyph(
                  IconToken.chevron,
                  key: kAppBarBackGlyphKey,
                  size: theme.iconSize(IconSizeToken.md),
                  color: partColor(ColorToken.onSurface),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // The leading zone (schema 9.16.0): a VISIBLE node replaces the arrow whatever `showBack`
    // says; if a condition hides it, `showBack` applies. The node has no built-in "back": what it
    // does is said by its own action, and the system "back" stays with the host.
    final Widget? leading = switch (shown) {
      AppBarLeadingShown.node => _leadingNode(leadingNode!),
      AppBarLeadingShown.back => back,
      AppBarLeadingShown.none => null,
    };
    // THE NAVIGATION BAR IN THE APP BAR (schema 9.18.0): its items are part of the trailing zone,
    // before the actions. The bar has no box here (background, border, padding, shadow, radius and
    // node size are not read); items inherit the color and font named on it, as at the bottom.
    final navGroup = nav == null ? null : wideNavGroupFor(nav);
    return ContentColumn(
      maxWidth: contentMax,
      child: AppBarLayout(
        hasBack: leading != null,
        leadingIsNode: shown == AppBarLeadingShown.node,
        titleAlign: node.titleAlign,
        hasNav: navGroup != null,
        backSide: side,
        gap: theme.space(SpacingToken.sm),
        actionGap: theme.space(SpacingToken.xs),
        // `titleShown: 'scrolled'` (9.21.0): at rest the block keeps its place and is not painted, but stays in the
        // semantics tree as the name of the screen (`Opacity(0)` with `alwaysIncludeSemantics`, not `Visibility`).
        children: [
          ?leading,
          if (titleHidden == null) titles else Opacity(opacity: titleHidden ? 0 : 1, alwaysIncludeSemantics: true, child: titles),
          ?navGroup,
          ...actions,
        ],
      ),
    );
  }

  /// The node of the app bar's leading zone: an ordinary button or icon button, drawn by the same
  /// path as anywhere else on a screen (role, size, style, name, action, `track`). Its width is
  /// NATURAL, even for a `fullWidth` button ("full width" has nothing to mean here: the zone is as
  /// wide as the node, and no wider than half the bar). It does not inherit a color named on the
  /// bar, just like an action.
  Widget _leadingNode(ChildNode node) => node is ButtonNode
      ? styledNode(node, Slot.free, (renderer, own) => renderer.buildButton(node, own, natural: true))
      : renderNode(node, flow: Axis.horizontal);
}
