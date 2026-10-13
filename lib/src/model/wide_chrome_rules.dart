import 'dart:math' as math;

import 'bottom_zone_rules.dart';
import 'media_chrome_rules.dart';
import 'style_values.dart';
import 'width_class.dart';

// Wide layouts: the navigation bar at the top and the sheet as a window (schema 9.18.0).
//
// Mirrors the reference implementation `wide-chrome-rules.ts`: same names, same order of steps.
// The case table `contract/fixtures/adaptive/adaptive-cases.json` (groups `chromeCases`,
// `wideNavItemCases`, `wideNavHeightCases`, `wideAppBarCases`, `wideNavBarCases`,
// `wideZoneCases`, `wideModalCases`, `wideModalRadiusCases`) runs these functions
// (`wide_chrome_cases_test.dart`), and the widgets draw from them; there is no second copy of
// the formulas in `render_document.dart`.
//
// THE DOCUMENT DOES NOT CHANGE. The navigation bar is the same node, the last child of the
// screen root; a modal screen is the same entry with `presentation: 'modal'`. The READER picks
// the place by width class: the platform convention for a wide layout beats the phone layout
// (a menu in a site header, the iPadOS tab bar at the top, a centred dialog instead of a sheet).

// ───────────────────────────── clarifications of 9.18.0 ─────────────────────────────

/// The content of a modal screen is always `compact`: the layer box is narrower than 600 in every
/// place (a sheet on a phone is an area narrower than `medium`; on a wide layout the window is at
/// most 560). Mirrors `modalContentAlwaysCompact` of the reference implementation; the reader
/// computes the content class from the layer box anyway (`widthClassOf(box.width)`), so this
/// function exists to be checked against the case table.
bool modalContentAlwaysCompact(Object? presentation) => presentation == 'modal';

/// The width class of a screen's content in an area of class [areaClass]: a page takes the class
/// of the area, a modal layer is always `compact`.
WidthClass screenContentWidthClassIn(Object? presentation, WidthClass areaClass) =>
    modalContentAlwaysCompact(presentation) ? WidthClass.compact : areaClass;

/// Whether a node's `showOn` changes how the PHONE looks in a reader older than 9.18.0
/// (`widthClass.olderReader.showOn`): such a reader does not know the field and shows the node at
/// every width, so a node whose `showOn` lacks `compact` will appear on a phone. A 9.18 reader
/// does nothing about this; it is knowledge for a warning at publish time. The function mirrors
/// the reference implementation and is checked against `olderReaderShowOnCases`.
bool showOnAffectsOlderReaderOnCompact(Object? rawShowOn) {
  final classes = showOnOf(rawShowOn);
  return classes != null && !classes.contains(WidthClass.compact);
}

/// The most noticeable loss: a node in the leading zone of the app bar (`zone: 'leading'`) whose
/// `showOn` lacks `compact` is drawn by an older reader on a phone in place of the back arrow
/// (`widthClass.olderReader.showOnLeadingZone`).
bool showOnReplacesBackArrowForOlderReader({
  required Object? rawShowOn,
  required Object? rawZone,
  required Object? parentType,
}) => parentType == 'AppBar' && barZoneOf(rawZone) == BarZone.leading && showOnAffectsOlderReaderOnCompact(rawShowOn);

// ───────────────────────────── who stands where ─────────────────────────────

/// Whether the class is wide: the navigation bar goes to the top and the sheet becomes a window
/// (`wideNav.classes`, `wideModal.classes`).
bool isWideWidthClass(WidthClass widthClass) => widthClass != WidthClass.compact;

/// Where the navigation bar stands: the bottom zone, the app bar (items inside it) or its own top
/// strip in the app bar zone.
enum NavBarPlace { bottom, appBar, top }

/// The root children by zone in a width class, plus the place of the navigation bar.
final class ScreenChrome {
  const ScreenChrome({required this.zones, required this.navPlace});

  /// Zones as the DOCUMENT defines them (`screenChildrenByZone`): the class does not move
  /// children between zones.
  final ScreenZoneChildren zones;

  /// Where the bar is in this class; `null` means the screen has no navigation bar.
  final NavBarPlace? navPlace;
}

/// WHO STANDS WHERE IN A WIDTH CLASS, IN ONE PLACE (`screenChromeIn`).
///
/// Which node is the app bar, body, pinned block and navigation bar is still decided by the
/// document; the one new thing here is the PLACE OF THE BAR:
///
///  1. on `compact` it is at the bottom, whatever the field says;
///  2. `widePlacement: 'bottom'` puts it at the bottom at every width;
///  3. otherwise the bar goes to the TOP: into the app bar if an app bar zone exists and is SHOWN
///     ([appBarShown]: width class and data condition), and without one as its own strip in the
///     app bar zone.
///
/// The bar does NOT wait for an app bar hidden by a condition or a class: that zone does not
/// exist, and the items inside it would vanish with it. [navPlacement] is the node's already
/// parsed `widePlacement` field.
ScreenChrome screenChromeIn(
  List<RootChildInfo> children,
  WidthClass widthClass, {
  NavWidePlacement navPlacement = NavWidePlacement.top,
  bool appBarShown = true,
}) {
  final zones = screenChildrenByZone(children);
  if (zones.navBar == null) return ScreenChrome(zones: zones, navPlace: null);
  if (!isWideWidthClass(widthClass) || navPlacement == NavWidePlacement.bottom) {
    return ScreenChrome(zones: zones, navPlace: NavBarPlace.bottom);
  }
  return ScreenChrome(
    zones: zones,
    navPlace: zones.appBar != null && appBarShown ? NavBarPlace.appBar : NavBarPlace.top,
  );
}

// ───────────────────────────── navigation items at the top ─────────────────────────────

/// How much room the app bar title keeps while the item labels are still shown
/// (`wideNav.overflow.titleKeeps`).
const double kWideNavTitleKeeps = 120;

/// The largest width of an item label at the top; a longer one gets an ellipsis
/// (`wideNav.item.labelMaxWidth`).
const double kWideNavLabelMax = 160;

/// The look of the items at the top: with labels, or icons only.
enum WideNavMode { labels, icons }

/// Numbers of a navigation item at the top, in theme points.
final class WideNavMetrics {
  const WideNavMetrics({
    required this.paddingInline,
    required this.iconWidth,
    required this.gap,
    required this.between,
  });

  /// The item's inline padding (`item.paddingInline`).
  final double paddingInline;

  /// Width of the icon box: the font size of the typography style for the `item.iconSize` step.
  final double iconWidth;

  /// Gap between the icon and the label (`item.gap`).
  final double gap;

  /// Gap between items (`item.between`).
  final double between;

  @override
  bool operator ==(Object other) =>
      other is WideNavMetrics &&
      other.paddingInline == paddingInline &&
      other.iconWidth == iconWidth &&
      other.gap == gap &&
      other.between == between;

  @override
  int get hashCode => Object.hash(paddingInline, iconWidth, gap, between);
}

/// Reference implementation: the width of one item at the top (`wideNavItemWidth`). [labelWidth]
/// is the natural width of the label on one line; it is capped at [kWideNavLabelMax].
double wideNavItemWidth(double labelWidth, WideNavMetrics metrics, WideNavMode mode) {
  final box = metrics.paddingInline + metrics.iconWidth + metrics.paddingInline;
  if (mode == WideNavMode.icons) return box;
  return box + metrics.gap + math.min(math.max(0.0, labelWidth), kWideNavLabelMax);
}

/// Reference implementation: the width of a group of items with gaps; zero without items.
double wideNavGroupWidth(List<double> labelWidths, WideNavMetrics metrics, WideNavMode mode) {
  if (labelWidths.isEmpty) return 0;
  var sum = 0.0;
  for (final width in labelWidths) {
    sum += wideNavItemWidth(width, metrics, mode);
  }
  return sum + (labelWidths.length - 1) * metrics.between;
}

/// Reference implementation: the height of an item at the top (`item.height`).
double wideNavItemHeight({required double paddingBlock, required double iconBox, required double labelLine}) =>
    paddingBlock + math.max(iconBox, labelLine) + paddingBlock;

/// Reference implementation: the height of the own top strip (`ownBar.height`); [borderBottom] is
/// zero when the node names its own border.
double wideNavBarHeight({
  required double paddingBlock,
  required double iconBox,
  required double labelLine,
  required double borderBottom,
}) => wideNavItemHeight(paddingBlock: paddingBlock, iconBox: iconBox, labelLine: labelLine) + borderBottom;

/// Offsets and widths of items from the start of the row (in reading order).
({List<double> starts, List<double> widths}) wideNavItemStarts(
  double from,
  List<double> labelWidths,
  WideNavMetrics metrics,
  WideNavMode mode,
) {
  var cursor = from;
  final widths = [for (final width in labelWidths) wideNavItemWidth(width, metrics, mode)];
  final starts = <double>[];
  for (final width in widths) {
    starts.add(cursor);
    cursor += width + metrics.between;
  }
  return (starts: starts, widths: widths);
}

/// App bar zones with navigation items (`wideAppBarZones`): the same zones as 9.9-9.16 plus the
/// look of the items and their positions.
final class WideAppBarZones {
  const WideAppBarZones({
    required this.zones,
    required this.actionStarts,
    required this.navMode,
    required this.navStart,
    required this.navWidth,
    required this.navItemStarts,
    required this.navItemWidths,
    required this.clipped,
  });

  /// The leading zone, the title and the trailing zone (items and actions together form one
  /// block).
  final AppBarZones zones;

  /// Offsets of the actions from the start of the row, in document order.
  final List<double> actionStarts;

  final WideNavMode navMode;

  /// Offset of the item group from the START of the row (in reading order), and its width.
  final double navStart;
  final double navWidth;

  /// Offsets and widths of the items, in document order.
  final List<double> navItemStarts;
  final List<double> navItemWidths;

  /// Even with icons only the row is wider than the app bar: the overflow is clipped at its edge.
  final bool clipped;
}

/// Reference implementation: app bar zones with navigation items (`wideNav.inAppBar`,
/// `overflow`).
///
/// Items and actions form ONE block of the trailing zone: "items, app bar gap, actions". The
/// same [appBarZones] as before 9.18.0 does the rest: the title, the leading zone and the
/// centring rule remain its business; this function only decides the look of the items and their
/// positions inside the block.
///
/// LABELS ARE SHOWN when everything fits together: the leading zone, a title no narrower than
/// [kWideNavTitleKeeps] (or than itself, if shorter) and the trailing zone with labels. The
/// condition reads only NATURAL widths, which do not depend on the chosen look: a measurement
/// must not change what it measures.
WideAppBarZones wideAppBarZones({
  required double width,
  required bool showBack,
  required double backSide,
  required List<double> actionSides,
  required double gap,
  required double actionGap,
  required double titleNatural,
  double? leadingNatural,
  Object? titleAlign,
  required List<double> navLabels,
  required WideNavMetrics nav,
}) {
  var actions = math.max(0, actionSides.length - 1) * actionGap;
  for (final side in actionSides) {
    actions += side;
  }
  double blockOf(WideNavMode mode) {
    final group = wideNavGroupWidth(navLabels, nav, mode);
    return group + (group > 0 && actions > 0 ? gap : 0) + actions;
  }

  // The leading zone is computed as the app bar does: the node is at most half the width, the
  // arrow is a square, plus the gap.
  final plain = appBarZones(
    width: width,
    showBack: showBack,
    backSide: backSide,
    actionSides: const [],
    gap: gap,
    actionGap: actionGap,
    titleNatural: 0,
    leadingNatural: leadingNatural,
    titleAlign: titleAlign,
  );
  final need = math.min(math.max(0.0, titleNatural), kWideNavTitleKeeps);
  double trailingOf(double block) => block > 0 ? block + gap : 0.0;
  final mode = plain.leading + need + trailingOf(blockOf(WideNavMode.labels)) <= width
      ? WideNavMode.labels
      : WideNavMode.icons;
  final block = blockOf(mode);
  final trailing = trailingOf(block);
  // The leading-zone node shrinks LAST of the things that shrink: when the title has nothing left
  // to give, the zone gets what the items and actions left. While there is room, this number is
  // larger than half the app bar and changes nothing.
  final leadingRoom = math.max(0.0, width - trailing - gap);
  final leadingClamped = leadingNatural == null ? null : math.min(leadingNatural, leadingRoom);
  final zones = appBarZones(
    width: width,
    showBack: showBack,
    backSide: backSide,
    actionSides: block > 0 ? [block] : const [],
    gap: gap,
    actionGap: actionGap,
    titleNatural: titleNatural,
    leadingNatural: leadingClamped,
    titleAlign: titleAlign,
  );
  final navWidth = wideNavGroupWidth(navLabels, nav, mode);
  // The block is pushed to the END of the row; if it does not fit, it starts right after the
  // leading zone and the overflow is clipped at the end edge of the app bar
  // (`overflow.clipped`): the start of the row stays in place.
  final navStart = math.max(width - block, zones.leading);
  final items = wideNavItemStarts(navStart, navLabels, nav, mode);
  var cursor = navStart + block - actions;
  final actionStarts = <double>[];
  for (final side in actionSides) {
    actionStarts.add(cursor);
    cursor += side + actionGap;
  }
  return WideAppBarZones(
    zones: zones,
    actionStarts: actionStarts,
    navMode: mode,
    navStart: navStart,
    navWidth: navWidth,
    navItemStarts: items.starts,
    navItemWidths: items.widths,
    clipped: zones.leading + trailing > width,
  );
}

/// Items in the OWN top strip (`wideNavBarOf`).
final class WideNavBarBox {
  const WideNavBarBox({
    required this.navMode,
    required this.navWidth,
    required this.navItemStarts,
    required this.navItemWidths,
    required this.clipped,
  });

  final WideNavMode navMode;
  final double navWidth;

  /// Offsets of the items from the START of the row (in reading order), and their widths.
  final List<double> navItemStarts;
  final List<double> navItemWidths;
  final bool clipped;
}

/// Reference implementation: items in the OWN top strip (`wideNav.ownBar`). [width] is the
/// content width of the strip (the screen's content column, if one is named). Items start at
/// the inline start; if they do not fit with labels they show icons only; if they still do not
/// fit, the edge clips them.
WideNavBarBox wideNavBarOf({required double width, required List<double> navLabels, required WideNavMetrics nav}) {
  final mode = wideNavGroupWidth(navLabels, nav, WideNavMode.labels) <= width ? WideNavMode.labels : WideNavMode.icons;
  final navWidth = wideNavGroupWidth(navLabels, nav, mode);
  final items = wideNavItemStarts(0, navLabels, nav, mode);
  return WideNavBarBox(
    navMode: mode,
    navWidth: navWidth,
    navItemStarts: items.starts,
    navItemWidths: items.widths,
    clipped: navWidth > width,
  );
}

// ───────────────────────────── screen zones with the bar at the top ─────────────────────────────

/// Screen zones in a width class: the same [ScreenZoneBoxes] plus the own top strip.
final class WideScreenZoneBoxes {
  const WideScreenZoneBoxes({required this.zones, this.topNavTop, this.topNavHeight});

  final ScreenZoneBoxes zones;

  /// The navigation bar's own top strip; `null` when there is none (the bar is at the bottom,
  /// inside the app bar, or absent).
  final double? topNavTop;
  final double? topNavHeight;
}

/// Reference implementation: screen zones in a width class. It is the same [screenZoneBoxes],
/// told where the navigation bar is (`wideScreenZonesOf`).
///
///  * `bottom`: the bar is in the bottom zone, numbers as before 9.18.0;
///  * `appBar`: there is NO bar in the bottom zone; the zone is just the pinned block, and
///    without it there is no zone and the reader adds no safe area inset;
///  * `top`: the own strip occupies the top of the screen at its height, and everything else is
///    computed in what remains beneath it; the root's top padding stays with the body, inside
///    the scroll (there is no app bar zone by definition of this place).
///
/// [navBarHeight] is the height of the bar WHERE IT STANDS: at the bottom, without the safe area
/// inset; as an own strip at the top, [wideNavBarHeight]; inside the app bar no number is needed.
WideScreenZoneBoxes wideScreenZoneBoxes({
  required NavBarPlace? navPlace,
  double? navBarHeight,
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
  double safeBottom = 0,
}) {
  if (navPlace != NavBarPlace.top) {
    return WideScreenZoneBoxes(
      zones: screenZoneBoxes(
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
        navBarHeight: navPlace == NavBarPlace.bottom ? navBarHeight : null,
        safeBottom: safeBottom,
      ),
    );
  }
  final bar = math.max(0.0, navBarHeight ?? 0);
  final under = screenZoneBoxes(
    height: math.max(0.0, height - bar),
    paddingTop: paddingTop,
    paddingBottom: paddingBottom,
    gap: gap,
    bodyContentHeight: bodyContentHeight,
    firstPull: firstPull,
    scrollTop: scrollTop,
    shrink: shrink,
    pinnedHeight: pinnedHeight,
    safeBottom: safeBottom,
  );
  final below = under.bottom;
  return WideScreenZoneBoxes(
    zones: ScreenZoneBoxes(
      height: under.height + bar,
      appBarTop: null,
      appBarHeight: null,
      bodyTop: under.bodyTop + bar,
      bodyHeight: under.bodyHeight,
      contentTop: under.contentTop + bar,
      contentHeight: under.contentHeight,
      maxScroll: under.maxScroll,
      scrollTop: under.scrollTop,
      bottom: below == null
          ? null
          : BottomZoneBoxes(
              top: below.top + bar,
              height: below.height,
              pinnedTop: below.pinnedTop == null ? null : below.pinnedTop! + bar,
              pinnedHeight: below.pinnedHeight,
              navTop: null,
              navHeight: null,
              navContentHeight: null,
              safeBottom: below.safeBottom,
            ),
    ),
    topNavTop: 0,
    topNavHeight: bar,
  );
}

// ───────────────────────────── modal layer in a wide layout ─────────────────────────────

/// The largest width of the window a sheet becomes in a wide layout (`wideModal.window.maxWidth`).
const double kWideModalMaxWidth = 560;

/// The largest share of the area height such a window takes (`wideModal.window.maxHeightShare`).
const double kWideModalMaxHeightShare = 0.85;

/// How a modal layer is shown: as a bottom sheet, as a `center` window, or as a sheet that became
/// a window in a wide layout.
enum ModalShape { sheet, window, sheetWindow }

/// HOW THE LAYER IS SHOWN (`modalShapeOf`): `center` is a window at every width; otherwise (no
/// field, `bottom`, an unknown word) it is a sheet on `compact` and a window in a wider layout.
/// [areaWidth] is the width of the area the host gave the screen (where the stack is shown), not
/// of the layer.
ModalShape modalShapeOf(Object? placement, double areaWidth) {
  if (ModalPlacement.of(placement) == ModalPlacement.center) return ModalShape.window;
  return isWideWidthClass(widthClassOf(areaWidth)) ? ModalShape.sheetWindow : ModalShape.sheet;
}

/// Reference implementation: the layer width. It must be known BEFORE the content is measured,
/// and the content's width class is computed from it (`modalLayerWidthOf`).
double modalLayerWidthOf(Object? placement, double areaWidth, double margin) {
  if (modalShapeOf(placement, areaWidth) != ModalShape.sheetWindow) {
    return modalWidthOf(placement, areaWidth, margin);
  }
  return math.max(0.0, math.min(areaWidth - 2 * margin, kWideModalMaxWidth));
}

/// The rectangle of a modal layer and the width class of its CONTENT (from its own box).
typedef ModalLayerBox = ({
  ModalShape shape,
  double x,
  double y,
  double width,
  double height,
  bool scrolls,
  WidthClass contentWidthClass,
});

/// Reference implementation: the rectangle of a modal layer in an area, chosen by the width class
/// of the AREA (`modalLayerBoxOf`).
///
/// For a sheet that became a window: the width is the area minus the margin on each side, at most
/// [kWideModalMaxWidth]; the height follows the content, at most the lesser of two limits: the
/// share [kWideModalMaxHeightShare] of the area height, or the area minus margins; centred on
/// both axes.
ModalLayerBox modalLayerBoxOf({
  required Object? placement,
  required double viewportWidth,
  required double viewportHeight,
  required double contentHeight,
  required double margin,
}) {
  final shape = modalShapeOf(placement, viewportWidth);
  if (shape != ModalShape.sheetWindow) {
    final box = modalBoxOf(
      placement: placement,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      contentHeight: contentHeight,
      margin: margin,
    );
    return (
      shape: shape,
      x: box.x,
      y: box.y,
      width: box.width,
      height: box.height,
      scrolls: box.scrolls,
      contentWidthClass: widthClassOf(box.width),
    );
  }
  final width = modalLayerWidthOf(placement, viewportWidth, margin);
  final available = math.max(0.0, math.min(viewportHeight * kWideModalMaxHeightShare, viewportHeight - 2 * margin));
  final height = math.min(math.max(0.0, contentHeight), available);
  return (
    shape: shape,
    x: (viewportWidth - width) / 2,
    y: (viewportHeight - height) / 2,
    width: width,
    height: height,
    scrolls: contentHeight > available,
    contentWidthClass: widthClassOf(width),
  );
}

/// Reference implementation: the radius of the root of a sheet shown as a WINDOW
/// (`sheetWindowRadius`). A single value for all corners, and a missing radius, stay as they are;
/// in a per-corner radius an UNNAMED bottom corner takes the top corner of the same side. A named
/// corner, zero included, stays. If nothing changes, the same value is returned.
BoxRadius? sheetWindowRadius(BoxRadius? radius) {
  if (radius == null || radius.isSingleValue) return radius;
  final bottomStart = radius.bottomStart ?? radius.topStart;
  final bottomEnd = radius.bottomEnd ?? radius.topEnd;
  if (bottomStart == radius.bottomStart && bottomEnd == radius.bottomEnd) return radius;
  return BoxRadius.corners(
    topStart: radius.topStart,
    topEnd: radius.topEnd,
    bottomEnd: bottomEnd,
    bottomStart: bottomStart,
  );
}

// ───────────────────────────── mirror of the artifact blocks ─────────────────────────────

/// Mirror of `x-style.layout.wideNav` (without the `cases` table address); checked against the
/// artifact in `test/wide_chrome_cases_test.dart`.
const Map<String, Object> kWideNavLayout = {
  'field': 'widePlacement',
  'on': 'NavBar',
  'values': ['top', 'bottom'],
  'default': 'top',
  'unknown': 'default',
  'classes': ['medium', 'expanded'],
  'measured': 'the-width-class-of-the-screen-box',
  'compact': 'bottom-whatever-the-field-says',
  'document': 'unchanged-the-nav-bar-stays-the-last-child-of-the-screen-root',
  'place': {
    'bottom': 'bottom-zone-on-every-width-as-on-compact',
    'topWithAppBar': 'items-inside-the-app-bar',
    'topWithoutAppBar': 'own-bar-in-the-app-bar-zone',
    'appBarCounts': 'the-app-bar-zone-that-is-shown-in-this-class-and-by-its-condition',
    'hiddenNavBar': 'drawn-nowhere',
    'inModalLayer': 'not-drawn',
    'notLast': 'ordinary-child-of-the-body',
  },
  'item': {
    'direction': 'icon-before-label',
    'align': 'centered-on-the-cross-axis',
    'paddingBlock': 'sm',
    'paddingInline': 'md',
    'gap': 'xs',
    'iconSize': 'md',
    'labelTypography': 'bodyM',
    'labelLines': 1,
    'labelMaxWidth': 160,
    'labelOverflow': 'ellipsis',
    'width': 'natural-padding-icon-gap-label-padding',
    'iconOnlyWidth': 'padding-icon-padding',
    'height': 'padding-plus-the-taller-of-icon-box-and-label-line-plus-padding',
    'shares': 'none',
    'between': 'xs',
    'order': 'reading-direction-first-item-at-the-inline-start',
    'drawn': 'navBar.items-first-five-visible',
    'touchArea': 'the-item-box',
    'unknownIcon': 'empty-box-of-the-same-size',
  },
  'color': 'x-style.layout.navBar.color',
  'active': 'x-style.layout.navBar.active',
  'press': 'x-style.layout.navBar.press',
  'semantics': 'x-style.layout.navBar.semantics',
  'inAppBar': {
    'order': ['leading', 'title', 'navItems', 'actions'],
    'zone': 'trailing-before-the-actions',
    'gapToActions': 'appBar.gap',
    'gapToTitle': 'appBar.gap',
    'title': 'appBar.titlePlacement-the-nav-items-count-as-the-trailing-zone',
    'titleAlign': 'appBarTitle-as-is',
    'leading': 'appBarLeading-as-is',
    'navBarBox': 'not-drawn-background-border-padding-shadow-radius-size-of-the-nav-bar-are-not-read',
    'inherits': 'color-and-typography-named-on-the-nav-bar',
    'height': 'appBar.height-the-nav-items-are-a-zone',
    'crossAlign': 'appBar.crossAlign',
    'contentMaxWidth': 'inside-the-app-bar-content-column',
  },
  'ownBar': {
    'zone': 'appBar',
    'position': 'top-of-the-screen-fixed',
    'width': 'edge-to-edge-root-padding-does-not-apply',
    'surface': {
      'background': 'surface',
      'borderBottom': {'width': 1, 'color': 'border'},
      'named': 'style-background-replaces-the-background-style-border-replaces-the-bottom-line',
    },
    'items': 'from-the-inline-start',
    'height': 'bottom-border-plus-item-height',
    'contentMaxWidth': 'items-inside-the-content-column-the-box-stays-edge-to-edge',
    'rootPaddingTop': 'stays-with-the-body-inside-scroll',
    'bodyArea': 'from-the-bottom-edge-of-the-bar',
    'pulledFirstChild': 'as-without-an-app-bar',
    'safeAreaTop': 'reader-adds-nothing',
  },
  'overflow': {
    'order': ['title-down-to-titleKeeps', 'labels-hidden', 'title-down-to-zero', 'leading-node', 'clipped'],
    'titleKeeps': 120,
    'titleShorter': 'keeps-its-own-width',
    'labelsHidden': 'all-at-once-icons-only',
    'hiddenLabel': 'stays-the-accessible-name',
    'perItem': 'no',
    'neverShrink': ['nav-item-icons', 'actions'],
    'clipped': 'at-the-end-edge-of-the-bar',
    'ownBar': 'labels-hidden-when-the-items-do-not-fit-then-clipped',
    'rounding': 'none',
  },
  'bottomZone': 'pinned-block-only-no-zone-without-it',
  'safeAreaBottom': 'bottomZone.safeArea-only-when-the-zone-exists',
  'sections': 'every-section-carries-the-same-widePlacement',
  'olderReader': 'nav-bar-at-the-bottom-on-every-width',
};

/// Mirror of `x-style.layout.wideModal` (without the `cases` table address); checked against the
/// artifact.
const Map<String, Object> kWideModalRules = {
  'appliesTo': 'modal-screen-with-no-modalPlacement-or-with-bottom',
  'decidedBy': 'the-width-class-of-the-area-the-host-gave-the-screen',
  'classes': ['medium', 'expanded'],
  'compact': 'sheet-at-the-bottom-modalLayer.bottom',
  'wide': 'window-in-the-centre',
  'window': {
    'width': 'fill-minus-margins-up-to-max',
    'maxWidth': 560,
    'margin': 'xl',
    'height': 'content',
    'maxHeightShare': 0.85,
    'maxHeight': 'the-lesser-of-the-share-of-the-area-height-and-the-area-minus-margins',
    'align': 'center',
    'rounding': 'none',
  },
  'centerPlacement': 'modalLayer.center-unchanged-on-every-width',
  'contentWidthClass': 'from-the-box-of-the-layer-always-compact-under-600',
  'radius': {
    'unnamedBottomCorner': 'takes-the-radius-of-the-top-corner-of-the-same-side',
    'namedCorner': 'as-is-zero-too',
    'singleValue': 'as-is',
    'appliesTo': 'sheet-shown-as-a-window-only',
  },
  'look': 'modalLayer.look',
  'scrim': 'modalLayer.scrim',
  'dismiss': 'modalLayer.dismiss',
  'overflow': 'modalLayer.overflow',
  'zones': 'modalLayer.zones',
  'record': 'modalLayer.record',
  'pinned': 'at-the-bottom-of-the-window',
  'navBar': 'not-drawn',
  'safeAreaBottom': 'none-as-a-window',
  'event': 'screen-shown-as-is-no-new-field',
  'olderReader': 'sheet-at-the-bottom-on-every-width',
};
