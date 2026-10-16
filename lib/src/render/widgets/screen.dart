/// The screen: its zones (app bar, body, pinned block, navigation bar) and what
/// scrolls.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../model/bottom_zone_rules.dart';
import '../../model/node.dart';
import '../../model/node_style.dart';
import '../../model/screen_top_rules.dart';
import '../../model/scrolled_bar.dart';
import '../../model/tokens.dart';
import '../../model/wide_chrome_rules.dart';
import '../../model/width_class.dart';
import '../body_scroll_tracker.dart';
import '../modal_layer.dart';
import '../node_renderer.dart';
import '../render_scope.dart';
import '../screen_zones.dart';
import '../width_class_scope.dart';
import 'app_bar.dart';
import 'column.dart';
import 'nav_bar.dart';
import 'node_box.dart';

extension ScreenWidgets on NodeRenderer {
  /// The screen: the app bar on top, the rest scrolling.
  ///
  /// WHY NOT `Scaffold.appBar`. The contract's `AppBar` would map onto it almost literally, but
  /// a document is not obliged to fill the whole screen: the host may embed it in half a screen,
  /// a sheet or a tab, and then a `Scaffold` around a piece of someone else's UI would intrude on
  /// the app instead of rendering the document. So the app bar is simply the first strip of THIS
  /// tree: it does not scroll with the content (the point of a top bar) but does not claim the
  /// system bar, the status bar or the host's `Navigator` either.
  ///
  /// [shrink]: the screen is shown as a LAYER OVER the previous one (schema 8.12.0), so it takes
  /// the height of its content, not all the available height.
  ///
  /// That is the only difference: the bar, background, padding and scrolling are the same, which
  /// is why a modal layer is not a separate tree. When the content outgrows the sheet, the zone
  /// layout clamps the sheet to the available height and the same BODY scrolling applies, while
  /// the layer's app bar stays put (`modalOverflow`).
  Widget buildScreen(
    ScreenNode root, {
    bool shrink = false,
    bool window = false,
    WidthClass widthClass = WidthClass.compact,
  }) {
    // The reader IGNORES the root's `margin` and sizes (`screenBoxFields: 'ignore'`): the schema
    // has none on a screen, but a document may not have come from the builder.
    final own = resolveNodeStyle(root.style, root.styleWhen, data, applicable: theme.applicableStyle)?.forScreen;
    return inheriting(own)._screenBox(root, own, shrink: shrink, window: window, widthClass: widthClass);
  }

  /// The screen box. The model is the same as for any node, with two differences, both because
  /// the screen SCROLLS:
  ///
  ///  * `padding` goes INSIDE the scroll view, not around it: content must scroll under the
  ///    screen edge, not under the padding;
  ///  * `margin` and sizes (`width`, `height`, `min...`, `max...`) are not applied: the screen takes
  ///    the space the host gave it (`screenBoxFields: 'ignore'`, `x-style.screenExcluded`); they
  ///    are removed already in [buildScreen], before this method.
  ///
  /// A screen WITHOUT a style has neither background nor padding: the reader has no hidden
  /// defaults, and the usual look (`surface`, `md`) is written into the document by the builder.
  Widget _screenBox(
    ScreenNode root,
    NodeStyle? own, {
    required bool shrink,
    bool window = false,
    WidthClass widthClass = WidthClass.compact,
  }) {
    /*
     * THE THREE SCREEN ZONES (`x-style.layout.screen`).
     *
     * THE APP BAR ZONE is the root's first child BY THE DOCUMENT, if it is an `AppBar`. An app bar
     * hidden by a condition has NO zone (the top padding returns to the body), and the next node
     * does not become the app bar: the document is counted, not visibility. A second `AppBar`, or
     * one that is not first, is an ordinary body child, where it stands (`app_bar_misplaced`: the
     * builder would not publish that, but the reader does not discard it).
     *
     * THE APP BAR STAYS; only the body scrolls. The root padding is SHARED: the app bar gets the
     * top and side padding; the body gets the sides, the bottom and the screen GAP instead of the
     * top, inside the scroll view. At rest this is the same picture as "padding around a column".
     *
     * The root background lies under all the zones and does not scroll (the surrounding
     * `nodeBox`). The body area runs from the app bar's bottom edge down; whatever scrolls out of
     * it is clipped: through a transparent app bar the screen background shows, not the text.
     *
     * THE FIRST VISIBLE BODY CHILD, if PULLED (`pull`), raises the body area by its overlap
     * (`pull` minus the gap, not less than zero; not above the top of the screen). This always
     * applies, not only before scrolling, so there is no scroll listener. The body is drawn over
     * the app bar and catches taps in the overlap strip.
     */
    final children = root.children;
    final zones = screenChildrenByZone([
      for (final child in children)
        (
          type: child is AppBarNode ? 'AppBar' : (child is NavBarNode ? kNavBarType : 'other'),
          pin: child.pin,
        ),
    ], topPins: [for (final child in children) child.pinTop], bodyAtScreenTop: root.bodyTop == BodyTop.screenTop);
    final barDeclared = (zones.appBar == null ? null : children[zones.appBar!]);
    final AppBarNode? bar = barDeclared is AppBarNode && barDeclared.isVisible(data) ? barDeclared : null;
    // Body children BY THE DOCUMENT (hidden ones included): `buildChildColumn` filters them
    // itself, and list item numbering (schema 9.17.0) is counted over exactly this list;
    // otherwise a node hidden by a condition would not break the group.
    final bodySource = children.sublist(zones.bodyFrom, zones.bodyTo);
    // THE TOP ZONE (schema 9.24.0, `x-style.layout.topZone`): the run of children pinned to the top, right after
    // the app bar zone. By the document; the hidden ones take no room, and when all are hidden there is no zone.
    final topSource = children.sublist(zones.topFrom, zones.topTo);
    final topNodes = visibleNodes(topSource);
    final hasTop = topNodes.isNotEmpty;
    final body = visibleNodes(bodySource);
    /*
     * THE BOTTOM ZONE (schema 9.12.0, `x-style.layout.bottomZone`): the last child if it is a
     * `NavBar`, and, above it, the last child not counting the bar if its `pin` is `bottom`. Also
     * BY THE DOCUMENT, not by visibility: a hidden block has no zone (the bottom padding returns
     * to the body) and nobody else takes its place. `pull` on the pinned block is not read: it is
     * rendered by `buildChildColumn` without a parent. A screen shown as a LAYER does not draw the
     * bar (`navBarInModalLayer`).
     */
    final pinnedDeclared = (zones.pinned == null ? null : children[zones.pinned!]);
    final ChildNode? pinned = pinnedDeclared != null && pinnedDeclared.isVisible(data) ? pinnedDeclared : null;
    final navDeclared = (zones.navBar == null ? null : children[zones.navBar!]);
    final NavBarNode? nav = navDeclared is NavBarNode && navDeclared.isVisible(data) && !shrink ? navDeclared : null;
    /*
     * WHERE THE BAR STANDS (schema 9.18.0, `screenChromeIn`): on `compact`, and with
     * `widePlacement: 'bottom'`, in the bottom zone; on `medium` / `expanded` at the top: in the
     * SHOWN app bar (items in its trailing zone) or in its own strip in the app bar zone, when
     * there is no app bar or it is hidden. The document does not change; the place is chosen by
     * THIS screen's width class.
     */
    final navPlace = nav == null
        ? null
        : screenChromeIn(
            [
              for (final child in children)
                (type: child is AppBarNode ? 'AppBar' : (child is NavBarNode ? kNavBarType : 'other'), pin: child.pin),
            ],
            widthClass,
            navPlacement: nav.widePlacement,
            appBarShown: bar != null,
          ).navPlace;
    final NavBarNode? navBottom = navPlace == NavBarPlace.bottom ? nav : null;
    final NavBarNode? navInBar = navPlace == NavBarPlace.appBar ? nav : null;
    final NavBarNode? navOnTop = navPlace == NavBarPlace.top ? nav : null;
    if (kDebugMode) {
      for (final stray in body.whereType<AppBarNode>()) {
        debugPrint(
          '[hotlayout] `AppBar` (id=${stray.id}) is not the first child of `Screen`: '
          'drawn in place, but it does not become the top bar of the screen',
        );
      }
    }
    // THE BODY FROM THE TOP EDGE (schema 9.19.0, `Screen.props.bodyTop`): the field acts always, except
    // where the zone is taken by the navigation bar's own strip, which the content never goes under.
    final screenTop = bodyStartsAtScreenTop(
      root.bodyTop,
      bar != null ? TopZoneOwner.appBar : (navOnTop != null ? TopZoneOwner.navBar : TopZoneOwner.none),
    );
    final screenPadding = theme.resolveBoxSpacing(own?.padding);
    final padding = screenPadding ?? EdgeInsetsDirectional.zero;
    final gap = theme.fieldSpacing(root.gap);
    final barPadding = EdgeInsetsDirectional.only(top: padding.top, start: padding.start, end: padding.end);
    // The overlap: the first visible body child's `pull` minus the gap. Without an app bar there
    // is nothing to raise: the pulled child goes into the top padding.
    // From the top edge of the screen the pull raises nothing: there is nowhere above to raise the body.
    final firstPull = (bar == null && !hasTop) || body.isEmpty || screenTop ? 0.0 : pullOf(body.first, root);
    final overlap = math.max(0.0, firstPull - gap);
    // With a pinned block the body ends with the screen GAP instead of the bottom padding (a body
    // with no visible children has no gap); the padding itself goes under the block.
    final bodyBottom = pinned == null ? padding.bottom : (body.isEmpty ? 0.0 : gap);
    final bodyPadding = bar == null && !hasTop
        ? (pinned == null
              ? screenPadding
              : EdgeInsetsDirectional.only(top: padding.top, start: padding.start, end: padding.end, bottom: bodyBottom))
        : EdgeInsetsDirectional.only(
            // From the top edge: no screen gap above the first child, it stands at the very top.
            top: body.isEmpty || screenTop ? 0 : gap + overlap,
            start: padding.start,
            end: padding.end,
            bottom: bodyBottom,
          );

    // The gap between the root's children is a document field (`Screen.props.gap`), not a number
    // from code: the reader has no hidden defaults.
    //
    // THE SCREEN'S MAIN AXIS (schema 9.15.0, `alignment.screen`): `justify` lays out only the
    // BODY children; the app bar, the pinned block and the navigation bar stay where they were.
    // Free space is the body area's height minus the length of what scrolls (body padding plus
    // content). If the content is taller there is no free space and it scrolls as before; a layer
    // sized to its content (`shrink`) has none by construction.
    final distributes = !shrink && root.justify != JustifyToken.start && body.isNotEmpty;
    // THE WIDEST CONTENT (schema 9.18.0, `contentMaxWidth`): the body children, the pinned block,
    // the app bar content and the bar items form a column no wider than the number, centered; the
    // background of the root and the zones stays edge to edge. The column comes from a symmetric
    // side margin in the box where the content would stand without padding: the body inside the
    // root's padding, the app bar in its own content box, the bar likewise.
    final contentMax = root.contentMaxWidth;
    final bodyColumn = ContentColumn(
      maxWidth: contentMax,
      child: buildChildColumn(
        bodySource,
        gap: gap,
        align: root.align,
        justify: distributes ? root.justify : JustifyToken.start,
        freeHeight: distributes,
        pullParent: root,
      ),
    );
    // A FLOATING BAR (schema 9.22.0): the zone lies over the body, and the end of the body's content is as tall as the
    // zone. The space belongs to the content, inside the part `Screen.justify` distributes: that free space is
    // counted without it.
    final floats = !shrink && navFloatsIn(navPlace, navBottom?.float ?? false);
    Widget scrollBody(ScrollController controller, ZoneTail? tail) {
      final content = tail == null ? bodyColumn : ZoneTailPadding(tail: tail, child: bodyColumn);
      return distributes
          ? LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                controller: controller,
                padding: bodyPadding,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.hasBoundedHeight
                        ? math.max(0.0, constraints.maxHeight - (bodyPadding?.vertical ?? 0))
                        : 0,
                  ),
                  child: content,
                ),
              ),
            )
          : SingleChildScrollView(controller: controller, padding: bodyPadding, child: content);
    }

    /*
     * The bottom zone consists of TWO layout children: the pinned block and the "low part" (the
     * navigation bar together with the safe area inset). They are separate because of the keyboard
     * (schema 9.13.0, `bottomZone.keyboard`): the pinned block rides ABOVE it while the bar stays
     * BELOW it, so the layout must know their heights separately.
     */
    final hasPinned = pinned != null;
    // A bar placed at the top is not in the bottom zone: there the zone is only the pinned block,
    // and without it there is no zone and the reader adds no safe area inset
    // (`wideScreenZonesOf`).
    final hasLow = pinned != null || navBottom != null;
    // The app bar zone: the app bar with the root's padding or (a bar at the top without an app
    // bar) the bar's own strip edge to edge, without the root's padding; the top padding stays with
    // the body, inside the scroll view.
    // [inset] is the top safe inset: inside the app bar's box above its content, or inside the
    // navigation strip above its items (`safeTop.withAppBar`, `safeTop.wideOwnNavBar`).
    Widget? barZoneFor(double inset, bool scrolled) => bar != null
        ? Padding(
            padding: barPadding,
            child: styledNode(
              bar,
              Slot.free,
              (renderer, _) => renderer.buildAppBar(
                bar,
                contentMax: contentMax,
                nav: navInBar,
                // The bar that changes on scroll (9.21.0): its title waits for the scroll when it asks.
                titleHidden: bar.titleShown == TitleShown.scrolled ? !scrolled : null,
              ),
              extraTop: inset,
              scrolledLayer: scrolled && bar.styleScrolled != null ? theme.applicableStyle(bar.styleScrolled!) : null,
              // The whole box of the app bar takes a press, also where nothing is drawn (from the top edge
              // the body lies UNDER it and must not get it). A recognizer-less opaque detector, not an
              // `AbsorbPointer`: the buttons in the bar must keep working.
              around: (box) => GestureDetector(behavior: HitTestBehavior.opaque, excludeFromSemantics: true, child: box),
            ),
          )
        : (navOnTop == null
              ? null
              : styledNode(
                  navOnTop,
                  Slot.free,
                  (renderer, own) => renderer.buildTopNavBar(navOnTop, own, contentMax: contentMax, topInset: inset),
                ));
    return BodyScrollTracker(
      // The app bar that changes on scroll (9.21.0) is the bar OF THE ZONE: a bar a condition hides, or one that
      // is not first, has no body to follow.
      tracking: bar != null && (bar.styleScrolled != null || bar.titleShown == TitleShown.scrolled),
      bodyAtScreenTop: screenTop,
      overlap: overlap,
      builder: (context, scroll) => Builder(
        builder: (context) {
          final keyboard = MediaQuery.viewInsetsOf(context).bottom;
          // THE TOP SAFE INSET (schema 9.19.0): the reader adds it, from its OWN context (a host that
          // wrapped it in a `SafeArea` gives zero and nothing changes). A layer has none inside. It stands
          // in the app bar's box, in the navigation strip, or, with neither, above the body area.
          final inset = shrink ? 0.0 : topInsetOf(context);
          final barZone = barZoneFor(inset, scroll.scrolled);
          // A sheet that became a window in a wide space: the layer's root takes its bottom corner
          // radius from the top ones, and such a window has no bottom safe area inset
          // (`modalLayer`).
          final sheetWindow = SheetWindowScope.of(context);
          final windowRadius = sheetWindow ? sheetWindowRadius(own?.radius) : own?.radius;
          final boxStyle = identical(windowRadius, own?.radius) ? own : own!.withRadius(windowRadius);
          Widget zonesWith(ZoneTail? tail) => nodeBox(
            boxStyle,
            slot: Slot.fill,
            paddingInside: true,
            // Zones have keys: a bar that moves from the bottom zone to the top when a wider class
            // arrives must not drag a rebuild of the body with it; the key keeps field state, focus
            // and scroll position.
            ScreenZones(
              tail: tail,
              shrink: shrink,
              overlap: overlap,
              keyboard: keyboard,
              bodyAtScreenTop: screenTop,
              // Without an app bar zone the body area starts below the inset (from the top edge it
              // starts at the top and the reader adds nothing to its content).
              topInset: barZone == null && !screenTop && !hasTop ? inset : 0,
              hasBar: barZone != null,
              hasTop: hasTop,
              hasPinned: hasPinned,
              hasLow: hasLow,
              children: [
                if (barZone != null)
                  KeyedSubtree(key: const ValueKey('hl-zone-bar'), child: KeyedSubtree(key: scroll.barKey, child: barZone)),
                if (hasTop)
                  KeyedSubtree(
                    key: const ValueKey('hl-zone-top'),
                    child: Padding(
                      // Under an app bar (or the strip of the navigation bar) the screen gap; at the top of the screen
                      // the safe inset and the root's top padding, outside the boxes of the nodes.
                      padding: EdgeInsetsDirectional.only(
                        top: barZone != null ? gap : inset + padding.top,
                        start: padding.start,
                        end: padding.end,
                      ),
                      child: ContentColumn(
                        maxWidth: contentMax,
                        child: buildChildColumn(topSource, gap: gap, align: root.align, pullParent: root, firstPullRead: false),
                      ),
                    ),
                  ),
                KeyedSubtree(key: const ValueKey('hl-zone-body'), child: scrollBody(scroll.controller, tail)),
                if (pinned != null)
                  KeyedSubtree(
                    key: const ValueKey('hl-zone-pinned'),
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(start: padding.start, end: padding.end, bottom: padding.bottom),
                      child: ContentColumn(
                        maxWidth: contentMax,
                        child: buildChildColumn([pinned], gap: gap, align: root.align),
                      ),
                    ),
                  ),
                if (hasLow)
                  KeyedSubtree(
                    key: const ValueKey('hl-zone-low'),
                    child: buildLowZone(
                      nav: navBottom,
                      // A window in the middle has no safe area inset (`safeArea.modalWindow`).
                      safeInset: !window && !sheetWindow,
                      contentMax: contentMax,
                      floating: floats,
                    ),
                  ),
              ],
            ),
          );
          return floats ? ZoneTailHost(builder: zonesWith) : zonesWith(null);
        },
      ),
    );
  }

  /// The "low part" of the bottom zone: the navigation bar and the safe area inset
  /// (`bottomZone.order`). The pinned block above it is drawn by [_screenBox] as a separate layout
  /// child: it gets the root's side and bottom padding (`padding.pinned`) and stands as a child of
  /// the root column (`pinned.width`), so a `fullWidth` button stretches between the paddings. The
  /// bar has no root padding and runs edge to edge.
  ///
  /// The reader adds the safe area inset ITSELF, under the zone's content: the bar's background
  /// extends under it to the physical bottom; under a block without a bar it is transparent space.
  /// A host that already accounted for the inset (`SafeArea` above) gives `viewPadding.bottom`
  /// zero, so nothing is doubled. While the on-screen keyboard is shown the inset is NOT added
  /// (`bottomZone.keyboard.safeInset`): the bottom is under the keyboard and has no inset above
  /// it.
  ///
  /// A FLOATING bar (schema 9.22.0, `navFloat.safeArea`) takes the inset OUTSIDE its box: under the margin box of the
  /// bar, as transparent room, so the bar hangs above the home indicator and its background does not stretch to the
  /// physical bottom.
  Widget buildLowZone({required NavBarNode? nav, required bool safeInset, int? contentMax, bool floating = false}) => Builder(
    builder: (context) {
      final keyboardShown = MediaQuery.viewInsetsOf(context).bottom > 0;
      final inset = safeInset && !keyboardShown ? MediaQuery.viewPaddingOf(context).bottom : 0.0;
      if (nav != null && floating) {
        final bar = styledNode(
          nav,
          Slot.free,
          (renderer, own) => renderer.buildNavBar(nav, own, safeBottom: 0, zone: true, contentMax: contentMax),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [bar, if (inset > 0) SizedBox(height: inset)],
        );
      }
      if (nav != null) {
        return styledNode(nav, Slot.free, (renderer, own) => renderer.buildNavBar(nav, own, safeBottom: inset, zone: true, contentMax: contentMax));
      }
      return SizedBox(height: inset);
    },
  );
}
