/// Tabs: a strip of titles over panels, one of which is shown.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../model/layout_rules.dart';
import '../../model/node.dart';
import '../../model/node_style.dart';
import '../../model/tokens.dart';
import '../layout/quiet_flex.dart';
import '../motion.dart';
import '../screen_transitions.dart';
import '../tab_strip.dart';
import '../node_renderer.dart';
import '../tabs_scope.dart';
import 'column.dart';
import 'node_box.dart';

extension TabsWidgets on NodeRenderer {
  /// Tabs: a strip of titles and exactly one panel under it.
  ///
  /// WHY NOT `TabBar`/`TabBarView`. Both need a `TabController`, that is, a `TickerProvider` and a
  /// `DefaultTabController` somewhere above in the tree, while here the reader builds the tree
  /// from the document and has no right to impose an ancestor on the host. Also `TabBarView`
  /// takes ALL the available height, while a tab panel must be as tall as its content: a
  /// document is not obliged to fill the whole screen.
  ///
  /// THE STRIP SCROLLS: the contract says so, it is not the reader's taste. Otherwise five long
  /// titles on 360dp would be squeezed by one reader and clipped by another.
  ///
  /// The strip holds only VISIBLE panels: a tab removed by `visibleIf` does not exist on screen.
  Widget buildTabs(TabsNode node) {
    final tabs = visibleNodes(node.children).whereType<TabNode>().toList();
    if (tabs.isEmpty) return const SizedBox.shrink();

    /*
     * `initialTab` COUNTS ALL TABS in document order, including those hidden by `visibleIf`;
     * otherwise the number would shift together with the data. If the named tab is currently
     * hidden (`hiddenInitialTab`) OR the number is outside the list altogether (not an integer,
     * negative, greater than the last: `initialTabOutOfRange`), the FIRST VISIBLE tab opens. One
     * answer to both questions: `openTabIndex`.
     */
    final declared = node.children.whereType<TabNode>().toList();
    final opened = openTabIndex(node.initialTab, [for (final tab in declared) tab.isVisible(data)]);
    final initial = opened == null ? 0 : math.max(0, tabs.indexOf(declared[opened]));

    return TabsScope(
      // Keyed by node: rebuilding the tree with the same document must not bring back a tab the
      // user has already switched away from.
      key: ValueKey('sdui-tabs-${node.id}'),
      initialTab: initial,
      tabCount: tabs.length,
      builder: (open, select) => QuietColumn(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // The indicator slides to the open title (`TabStrip`); at rest each title draws its own.
            child: TabStrip(
              open: open,
              count: tabs.length,
              gap: theme.space(SpacingToken.lg),
              indicatorColor: theme.color(ColorToken.primary),
              indicatorThickness: theme.space(SpacingToken.xs),
              title: (index, {required indicator}) =>
                  _tabTitle(tabs[index], open: index == open, drawIndicator: indicator, onTap: () => select(index)),
            ),
          ),
          SizedBox(height: theme.space(SpacingToken.md)),
          /*
           * EXACTLY the open panel is drawn. The rest are not built at all: tabs have no state
           * that would need to survive switching, and building five lists from data for the sake
           * of one visible is expensive.
           *
           * Switching is a CROSS-FADE, which is why this is an `AnimatedSwitcher` and not an
           * `AnimatedSize`: panels replace each other in place rather than expand. The key is the
           * tab INDEX, because that is what changed; without a key Flutter would treat the new
           * panel as the same widget (both are `renderNode` results) and animate nothing.
           *
           * The height does jump if panels differ in length, and that is honest: animating it too
           * would make a long list "grow" at every tap on the strip.
           */
          // `Builder` exists only for the `context`: the renderer is not a widget, and the
          // system "reduce motion" setting can be read only from the tree.
          Builder(
            builder: (context) => AnimatedSwitcher(
              duration: transitionDurationOf(context, Motion.quick),
              switchInCurve: Motion.standard,
              switchOutCurve: Motion.standard,
              // `passthrough`: the panel is a column child and must receive the parent's content
              // width (`columnChildWidth`) as a tight constraint. The default stack (`loose`,
              // centered) would give it only its natural width.
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.passthrough,
                alignment: AlignmentDirectional.topStart,
                children: [...previous, ?current],
              ),
              child: open >= 0 && open < tabs.length
                  ? KeyedSubtree(key: ValueKey(open), child: renderNode(tabs[open], flow: Axis.vertical))
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  /// One title in the strip.
  ///
  /// The indicator under the label is ALWAYS there, just transparent on closed tabs. So the
  /// title's height does not depend on whether it is open, and the strip does not jump on tap.
  /// The bottom padding is smaller by exactly the indicator thickness, so the total height equals
  /// what the other readers compute (a `titleS` line plus two `sm`), built from the same
  /// tokens.
  Widget _tabTitle(TabNode tab, {required bool open, required bool drawIndicator, required VoidCallback onTap}) {
    final indicator = theme.space(SpacingToken.xs);
    final padding = theme.space(SpacingToken.sm);
    // The tab reads the named color in ITS OWN context: the title is its prop, although it is
    // drawn in the parent's strip.
    final own = inheriting(resolveNodeStyle(tab.style, tab.styleWhen, data, applicable: theme.applicableStyle));
    final color = open
        ? own.partColor(ColorToken.primary)
        : own.partColor(ColorToken.muted, secondary: true);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.only(top: padding, bottom: padding - indicator),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: indicator,
              color: open && drawIndicator ? theme.color(ColorToken.primary) : Colors.transparent,
            ),
          ),
        ),
        child: Text(
          text(tab.title),
          maxLines: 1,
          style: theme.text(TypographyToken.titleS).copyWith(color: color),
        ),
      ),
    );
  }

  /// A tab panel is a plain column. The title is not here: it is already drawn in the parent's
  /// strip.
  Widget buildTab(TabNode node) => buildChildColumn(node.children, gap: theme.space(SpacingToken.md), align: AlignToken.start);
}
