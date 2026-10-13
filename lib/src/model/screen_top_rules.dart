import 'dart:math' as math;

import 'bottom_zone_rules.dart';
import 'media_chrome_rules.dart';
import 'wide_chrome_rules.dart';
import 'width_class.dart';

/// THE TOP OF THE SCREEN (schema 9.19.0): where the body area starts and the top safe inset the reader
/// adds. Mirror of the reference `screen-top-rules.ts`; the blocks are `x-style.layout.bodyTop` and
/// `x-style.layout.safeTop`, the shared case groups are in `media-chrome-cases.json`
/// (`bodyTopCases`, `topZoneCases`, `screenTopZoneCases`, `screenTopPressCases`, `safeTopValueCases`).
///
/// The frame stays: the app bar and the bottom zone STAND, only the body scrolls. `Screen.props.bodyTop`
/// changes one thing, where the body AREA begins; the app bar lies over it where it always stood.
/// Only geometry and the choice of rules are here, with no theme and no widgets: the numbers come from
/// whoever asks.

/// Where the body area of the screen starts (`Screen.props.bodyTop`). There is one word; "as without the
/// field" is the absence of the field and has no word of its own.
enum BodyTop {
  /// At the top edge of the screen: the body lies under the app bar and under the status bar.
  screenTop('screenTop');

  const BodyTop(this.wire);

  final String wire;
}

/// The word of the field as the reader reads it. An unknown word (including `belowBar`, which does not
/// exist), another case, `true`, `null` and a missing field are all `null`: the screen as before 9.19.0.
BodyTop? bodyTopOf(Object? raw) => raw is String && raw == BodyTop.screenTop.wire ? BodyTop.screenTop : null;

/// Who stands in the app bar zone.
enum TopZoneOwner { appBar, navBar, none }

/// Whether the body starts at the top edge of the screen. The word acts always EXCEPT on a screen where
/// the zone is taken by the navigation bar's own strip: that strip has a built-in background and the
/// content never goes under it. The items of a navigation bar inside the app bar are the app bar.
bool bodyStartsAtScreenTop(BodyTop? bodyTop, TopZoneOwner owner) =>
    bodyTop == BodyTop.screenTop && owner != TopZoneOwner.navBar;

/// Who owns the app bar zone, from the TYPES of the root's children in document order (`AppBar`,
/// `NavBar`, anything else), the width class, the bar's `widePlacement` and which children a condition
/// hides now ([hidden], the indexes). The place of the navigation bar is [screenChromeIn]'s answer.
TopZoneOwner topZoneOwnerIn(
  List<RootChildInfo> children,
  WidthClass widthClass, {
  NavWidePlacement navPlacement = NavWidePlacement.top,
  Set<int> hidden = const {},
}) {
  final zones = screenChildrenByZone(children);
  final barIndex = zones.appBar;
  final barShown = barIndex != null && !hidden.contains(barIndex);
  final chrome = screenChromeIn(children, widthClass, navPlacement: navPlacement, appBarShown: barShown);
  if (chrome.navPlace == NavBarPlace.top) return TopZoneOwner.navBar;
  return barShown ? TopZoneOwner.appBar : TopZoneOwner.none;
}

/// How much of the top safe inset is taken into account (`safeTop.value`). The inset comes from the
/// host, so the answer to "not a number" is one for every reader: a non-number, `NaN`, infinity and a
/// negative are zero; more than the screen height is clamped to it, so the zones never leave the screen.
double safeTopOf(Object? value, double screenHeight) {
  if (value is! num || !value.isFinite || value <= 0) return 0;
  return math.min(value.toDouble(), math.max(0.0, screenHeight));
}

/// The box of the app bar WITH the inset inside it; [contentTop] is where its content starts.
final class AppBarBox {
  const AppBarBox({required this.top, required this.height, required this.contentTop});

  final double top;
  final double height;
  final double contentTop;
}

/// The screen zones from the PHYSICAL top (`screenTopZonesOf`): [zones] as `screenZoneBoxes` gives
/// them, with the app bar box replaced by [appBar] (the inset is inside it).
final class ScreenTopBoxes {
  const ScreenTopBoxes({
    required this.zones,
    required this.appBar,
    required this.bodyAtScreenTop,
    required this.safeTop,
  });

  final ScreenZoneBoxes zones;

  /// `null` when there is no app bar zone.
  final AppBarBox? appBar;

  /// The body starts at the top edge of the screen and the app bar lies over it.
  final bool bodyAtScreenTop;

  /// How much of the top inset is taken into account.
  final double safeTop;
}

/// The zones of a screen with a top safe inset and the `bodyTop` field. Without an inset and without
/// the field it is exactly [screenZoneBoxes]. The geometry is not computed a second time: each case
/// reduces to that one formula with other numbers:
///
///  * an app bar with an inset is an app bar taller by the inset (the root's top padding stays above it);
///  * a screen without an app bar and with an inset is the same screen, lower by the inset and shorter;
///  * the body from the top edge is a screen WITHOUT the app bar zone (and, with an app bar, without the
///    top padding above the first child), while the app bar box is counted separately and lies over it.
///
/// A screen with the navigation bar's own strip does not come here: the field is not read there and its
/// zones are [wideScreenZonesOf]'s.
ScreenTopBoxes screenTopBoxesOf({
  required double height,
  double? appBarHeight,
  required double paddingTop,
  required double paddingBottom,
  required double gap,
  double? bodyContentHeight,
  double firstPull = 0,
  double scrollTop = 0,
  bool shrink = false,
  double? pinnedHeight,
  double? navBarHeight,
  double safeBottom = 0,
  BodyTop? bodyTop,
  Object? safeTop,
}) {
  final inset = safeTopOf(safeTop, height);
  final hasBar = appBarHeight != null;
  final box = hasBar
      ? AppBarBox(top: paddingTop, height: inset + math.max(0.0, appBarHeight), contentTop: paddingTop + inset)
      : null;

  ScreenZoneBoxes zonesOf({
    required double height,
    double? appBarHeight,
    required double paddingTop,
    bool shrink = false,
  }) => screenZoneBoxes(
    height: height,
    appBarHeight: appBarHeight,
    paddingTop: paddingTop,
    paddingBottom: paddingBottom,
    gap: gap,
    bodyContentHeight: bodyContentHeight,
    firstPull: firstPull,
    scrollTop: scrollTop,
    shrink: shrink,
    pinnedHeight: pinnedHeight,
    navBarHeight: navBarHeight,
    safeBottom: safeBottom,
  );

  if (bodyStartsAtScreenTop(bodyTop, hasBar ? TopZoneOwner.appBar : TopZoneOwner.none)) {
    final natural = zonesOf(height: height, paddingTop: hasBar ? 0.0 : paddingTop, shrink: shrink);
    // A layer as tall as its content is not lower than the app bar that lies on it (and not taller than
    // what is available).
    final floor = box == null ? 0.0 : math.min(box.top + box.height, math.max(0.0, height));
    final body = shrink && natural.height < floor
        ? zonesOf(height: floor, paddingTop: hasBar ? 0.0 : paddingTop)
        : natural;
    return ScreenTopBoxes(zones: body, appBar: box, bodyAtScreenTop: true, safeTop: inset);
  }
  if (box != null) {
    return ScreenTopBoxes(
      zones: zonesOf(height: height, appBarHeight: box.height, paddingTop: paddingTop, shrink: shrink),
      appBar: box,
      bodyAtScreenTop: false,
      safeTop: inset,
    );
  }
  final below = zonesOf(height: math.max(0.0, height - inset), paddingTop: paddingTop, shrink: shrink);
  return ScreenTopBoxes(zones: _lowered(below, inset), appBar: null, bodyAtScreenTop: false, safeTop: inset);
}

/// All the offsets of [zones] moved down by [by] (a screen without an app bar, under the inset).
ScreenZoneBoxes _lowered(ScreenZoneBoxes zones, double by) {
  if (by == 0) return zones;
  final bottom = zones.bottom;
  return ScreenZoneBoxes(
    height: zones.height + by,
    appBarTop: zones.appBarTop,
    appBarHeight: zones.appBarHeight,
    bodyTop: zones.bodyTop + by,
    bodyHeight: zones.bodyHeight,
    contentTop: zones.contentTop + by,
    contentHeight: zones.contentHeight,
    maxScroll: zones.maxScroll,
    scrollTop: zones.scrollTop,
    bottom: bottom == null
        ? null
        : BottomZoneBoxes(
            top: bottom.top + by,
            height: bottom.height,
            pinnedTop: bottom.pinnedTop == null ? null : bottom.pinnedTop! + by,
            pinnedHeight: bottom.pinnedHeight,
            navTop: bottom.navTop == null ? null : bottom.navTop! + by,
            navHeight: bottom.navHeight,
            navContentHeight: bottom.navContentHeight,
            safeBottom: bottom.safeBottom,
          ),
  );
}

/// What takes a press at a point of the screen: a zone, not a node.
enum ScreenPressZone { appBar, body, bottom, none }

/// Which zone takes a press at ([x], [y]) (`bodyTop.screenTop.press`). [y] is from the top of the
/// screen; [barLeft] and [barWidth] are the box of the app bar inside the root's side padding, which
/// tells it from the padding beside it (there the body, which lies under the app bar, takes the press).
/// Without them the whole width is the box. On a screen WITHOUT `screenTop` the app bar and the body do
/// not overlap, except the strip of a pulled first child, where the body is on top.
ScreenPressZone screenPressZoneAt(
  ScreenTopBoxes boxes, {
  required double y,
  double? x,
  double? barLeft,
  double? barWidth,
}) {
  final zones = boxes.zones;
  if (y < 0 || y >= zones.height) return ScreenPressZone.none;
  final bottom = zones.bottom;
  if (bottom != null && y >= bottom.top) return ScreenPressZone.bottom;
  final bar = boxes.appBar;
  final inInline = x == null || barLeft == null || barWidth == null || (x >= barLeft && x < barLeft + barWidth);
  final inBar = bar != null && y >= bar.top && y < bar.top + bar.height && inInline;
  final inBody = y >= zones.bodyTop && y < zones.bodyTop + zones.bodyHeight;
  if (boxes.bodyAtScreenTop) {
    return inBar
        ? ScreenPressZone.appBar
        : inBody
        ? ScreenPressZone.body
        : ScreenPressZone.none;
  }
  // The body raised onto the app bar by a pulled first child lies over it (`screen.body.paintOrder`).
  if (inBody) return ScreenPressZone.body;
  return inBar ? ScreenPressZone.appBar : ScreenPressZone.none;
}
