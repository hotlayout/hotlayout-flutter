import 'dart:math' as math;

// Image, app bar, modal layer, status bar: the reader's reference formulas (schema 9.9.0).
//
// Mirror of the builder's `media-chrome-rules.ts`: same names, same order of steps. The case table
// `contract/fixtures/media-chrome/media-chrome-cases.json` runs these functions
// (`media_chrome_cases_test.dart`), and the widgets draw by them; there is no second copy of the
// formulas in `render_document.dart`.
//
// Only geometry and rule selection live here, with no theme: the caller supplies the token numbers.

// -- Image --

/// Ratios of the list, as "width to height" (`x-style.layout.image.ratios`).
const Map<String, (int, int)> kImageRatioTokens = {'1:1': (1, 1), '16:9': (16, 9), '4:3': (4, 3)};

/// The word used when the ratio is unreadable (`unreadableImageRatio: field-default`).
const String kImageRatioFallback = '16:9';

/// Bounds of the "width / height" ratio (`ratioRange`): from 1:8 to 8:1.
const double kImageRatioMin = 0.125;
const double kImageRatioMax = 8;

/// The ratio of an image as the reader reads it: a word of the list, or a pair.
///
/// A pair of two positive finite numbers is their ratio, clamped to the bounds
/// (`imageRatioOutOfRange: clamp-to-range`); the reader also accepts fractional sides, which the
/// schema rejects: it draws what it received. Everything else (a word from a newer minor, a string
/// instead of a pair, zero, `null`, a number, a missing field) gives `16:9`.
final class ImageRatio {
  const ImageRatio._(this.ratio, this.wire);

  /// Width divided by height.
  final double ratio;

  /// The word of the list the ratio was written with; for a pair, `width:height`.
  final String wire;

  static const ImageRatio wide = ImageRatio._(16 / 9, '16:9');

  static ImageRatio parse(Object? raw) {
    if (raw is String) {
      final token = kImageRatioTokens[raw];
      if (token == null) return wide;
      return ImageRatio._(token.$1 / token.$2, raw);
    }
    if (raw is Map) {
      final width = raw['width'];
      final height = raw['height'];
      if (width is num && height is num) {
        final w = width.toDouble();
        final h = height.toDouble();
        if (w.isFinite && h.isFinite && w > 0 && h > 0) {
          final ratio = (w / h).clamp(kImageRatioMin, kImageRatioMax).toDouble();
          return ImageRatio._(ratio, '${_trim(w)}:${_trim(h)}');
        }
      }
    }
    return wide;
  }

  static String _trim(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

  @override
  String toString() => 'ImageRatio($wire)';
}

/// Height of an image box (`imageBoxOf`): a named `style.height` beats the ratio; the ratio computes
/// only a height from the width; `minHeight` / `maxHeight` clamp both a named and a computed height,
/// and the minimum wins.
({double width, double height, bool byRatio}) imageBoxOf({
  required double ratio,
  required double width,
  double? height,
  double? minHeight,
  double? maxHeight,
}) {
  final byRatio = height == null;
  final raw = height ?? width / ratio;
  final capped = maxHeight == null ? raw : math.min(raw, maxHeight);
  final result = minHeight == null ? capped : math.max(capped, minHeight);
  return (width: width, height: result, byRatio: byRatio);
}

/// Where the image with the natural ratio [natural] lies in the box, for `cover` and `contain`,
/// centered (`imagePaintRect`). An unknown `fit` and a missing field mean `cover`.
({double x, double y, double width, double height}) imagePaintRect({
  required double boxWidth,
  required double boxHeight,
  required double natural,
  Object? fit,
}) {
  final boxRatio = boxWidth / boxHeight;
  final contain = fit == 'contain';
  final widthBound = contain ? natural >= boxRatio : natural <= boxRatio;
  final width = widthBound ? boxWidth : boxHeight * natural;
  final height = widthBound ? boxWidth / natural : boxHeight;
  return (x: (boxWidth - width) / 2, y: (boxHeight - height) / 2, width: width, height: height);
}

/// Effective corner radius of a box: the named one, clamped to half of the shorter side
/// (`effectiveCornerRadius`).
double effectiveCornerRadius({required double width, required double height, required double radius}) =>
    math.max(0, math.min(radius, math.min(width / 2, height / 2)));

/// A circle is a square whose effective radius equals half the side (`isCircleBox`).
bool isCircleBox({required double width, required double height, required double radius}) =>
    width == height && effectiveCornerRadius(width: width, height: height, radius: radius) == width / 2;

// -- App bar --

/// Zones of the app bar in READING order (`appBarZones`): coordinates are measured from the start of
/// the line; in right-to-left writing the caller measures them from the right edge.
final class AppBarZones {
  const AppBarZones({
    required this.leading,
    required this.trailing,
    required this.titleRoom,
    required this.titleWidth,
    required this.titleStart,
    required this.centered,
    required this.truncated,
    required this.actionStarts,
    this.leadingShown = AppBarLeadingShown.none,
    this.leadingWidth = 0,
  });

  /// The leading zone together with the gap to the title; zero means there is no zone.
  final double leading;

  /// The trailing zone together with the gap; zero means there are no actions.
  final double trailing;

  /// Room the title may occupy.
  final double titleRoom;

  /// Width of the title block.
  final double titleWidth;

  /// Offset of the block from the start of the line.
  final double titleStart;

  /// The block stands exactly at the center of the app bar.
  final bool centered;

  /// The title did not fit and is cut with an ellipsis.
  final bool truncated;

  /// Offsets of the actions from the start of the line, in document order.
  final List<double> actionStarts;

  /// What stands in the leading zone (9.16.0).
  final AppBarLeadingShown leadingShown;

  /// Width of what stands in the leading zone WITHOUT the gap: the node (already clamped), the back
  /// arrow's square, or zero.
  final double leadingWidth;
}

/// Zones of the app bar (`x-style.layout.appBar`, and since 9.16.0 `appBarLeading`): the leading
/// zone is the node ([leadingNatural], clamped to [kAppBarLeadingMaxShare] of the app bar width),
/// otherwise the `backSide` arrow, otherwise nothing; plus `gap` if anything is there. The trailing
/// zone is the sum of the sides of the visible actions plus `actionGap` between them plus `gap` if there
/// are actions. The title is centered in the app bar while it fits, otherwise shifted just enough not to
/// overlap a zone; with `titleAlign: start` it comes right after the leading zone. There is no
/// counterweight opposite the arrow.
///
/// [leadingNatural] is the natural outer width of the VISIBLE leading-zone node (or its named
/// `style.width`); `null` means there is no node or a condition hides it, and [showBack] applies.
/// [titleAlign] is as in the document: an unknown word gives `center`.
AppBarZones appBarZones({
  required double width,
  required bool showBack,
  required double backSide,
  required List<double> actionSides,
  required double gap,
  required double actionGap,
  required double titleNatural,
  double? leadingNatural,
  Object? titleAlign,
}) {
  final actions =
      actionSides.fold<double>(0, (sum, side) => sum + side) +
      math.max(0, actionSides.length - 1) * actionGap;
  final shown = appBarLeadingShown(leadingNatural == null ? null : true, showBack);
  final leadingWidth = switch (shown) {
    AppBarLeadingShown.node => appBarLeadingWidth(leadingNatural ?? 0, width),
    AppBarLeadingShown.back => backSide,
    AppBarLeadingShown.none => 0.0,
  };
  final leading = shown == AppBarLeadingShown.none ? 0.0 : leadingWidth + gap;
  final trailing = actionSides.isNotEmpty ? actions + gap : 0.0;
  final titleRoom = math.max(0.0, width - leading - trailing);
  final titleWidth = math.min(math.max(0.0, titleNatural), titleRoom);
  final ideal = (width - titleWidth) / 2;
  // The leading zone wins when there is no room at all. For `start` the block comes right after the
  // leading zone, which is the same lower bound of the clamp.
  final titleStart = titleAlignOf(titleAlign) == AppBarTitleAlign.start
      ? leading
      : math.max(leading, math.min(ideal, width - trailing - titleWidth));
  var cursor = width - actions;
  final starts = <double>[];
  for (final side in actionSides) {
    starts.add(cursor);
    cursor += side + actionGap;
  }
  return AppBarZones(
    leading: leading,
    trailing: trailing,
    titleRoom: titleRoom,
    titleWidth: titleWidth,
    titleStart: titleStart,
    centered: titleStart == ideal,
    truncated: titleNatural > titleRoom,
    actionStarts: starts,
    leadingShown: shown,
    leadingWidth: leadingWidth,
  );
}

// -- App bar 9.16.0: a node in the leading zone, title from the start --

/// The app bar zone a child stands in (`$defs.NodeZone`). There is one word: the trailing zone is "a
/// child without the field" (the actions of 9.9.0). A newer word reads as "no field".
enum BarZone { leading }

/// The effective value of `zone`: a word of the list, or `null` (`appBarLeading.unknown`).
BarZone? barZoneOf(Object? raw) => raw == 'leading' ? BarZone.leading : null;

/// What stands in the leading zone of the app bar.
enum AppBarLeadingShown { node, back, none }

/// Largest share of the app bar width that the leading-zone node occupies
/// (`x-style.layout.appBarLeading.maxShare`).
const double kAppBarLeadingMaxShare = 0.5;

/// Types allowed in the leading zone: a button with a label and an icon button.
const List<String> kAppBarLeadingTypes = ['Button', 'IconButton'];

/// Type of an app bar action (trailing zone).
const String kAppBarActionType = 'IconButton';

/// Index of the leading-zone node among the children of the app bar: the FIRST child by the document
/// with `zone: leading` and a type from [kAppBarLeadingTypes] (`appBarLeadingOf`). Visibility is not
/// counted; whoever knows the data knows it. A second such child is neither the zone node nor an
/// action: the reader does not draw it (`extra`).
int? appBarLeadingIndex(List<({String type, BarZone? zone})> children) {
  for (var i = 0; i < children.length; i++) {
    if (children[i].zone == BarZone.leading && kAppBarLeadingTypes.contains(children[i].type)) return i;
  }
  return null;
}

/// Indexes of the app bar ACTIONS: icon buttons WITHOUT the zone field, in document order
/// (`appBarActionsOf`). The zone node is not included and does not count towards the limit of two
/// actions.
List<int> appBarActionIndexes(List<({String type, BarZone? zone})> children) => [
  for (var i = 0; i < children.length; i++)
    if (children[i].type == kAppBarActionType && children[i].zone == null) i,
];

/// What is drawn in the leading zone: a VISIBLE node replaces the arrow whatever `showBack` says; with
/// no node (`null`) or a hidden one, `showBack` applies.
AppBarLeadingShown appBarLeadingShown(bool? nodeVisible, bool showBack) {
  if (nodeVisible == true) return AppBarLeadingShown.node;
  return showBack ? AppBarLeadingShown.back : AppBarLeadingShown.none;
}

/// Width of the leading-zone node: its natural width, but not more than half the app bar content width
/// (the number is not rounded: 369 gives 184.5).
double appBarLeadingWidth(double natural, double barWidth) =>
    math.max(0.0, math.min(natural, barWidth * kAppBarLeadingMaxShare));

/// Where a child placed into the app bar goes (a reader's reference; the builder and validator decide):
/// `leading`, `action`, `leading-taken`, `actions-full`, `type`.
String appBarPlaceOf(List<({String type, BarZone? zone})> siblings, ({String type, BarZone? zone}) child) {
  final isAction = child.type == kAppBarActionType;
  if (!isAction && !kAppBarLeadingTypes.contains(child.type)) return 'type';
  final leadingFree = appBarLeadingIndex(siblings) == null;
  final actionFree = appBarActionIndexes(siblings).length < kAppBarMaxDrawnActions;
  if (child.zone == BarZone.leading && leadingFree) return 'leading';
  if (isAction) return actionFree ? 'action' : 'actions-full';
  return leadingFree ? 'leading' : 'leading-taken';
}

/// Where the title block stands (`AppBar.titleAlign`).
enum AppBarTitleAlign { start, center }

/// The alignment the READER draws with: an unknown word and a missing field give `center`.
AppBarTitleAlign titleAlignOf(Object? raw) => raw == 'start' ? AppBarTitleAlign.start : AppBarTitleAlign.center;

// -- Screen zones --

/// Index of the child of the root that is the APP BAR ZONE (`screenAppBarOf`), or `null`. The DOCUMENT
/// is counted, not visibility: the first child is the app bar if it is an `AppBar`; hidden by a
/// condition it remains a zone (empty for now), and the next node does not become the app bar.
int? screenAppBarIndex(List<String> childTypes) =>
    childTypes.isNotEmpty && childTypes.first == 'AppBar' ? 0 : null;

/// The bottom zone in screen coordinates (`bottomZoneOf`, `zoneCases`, 9.12.0): top to bottom, the
/// pinned block, the root's bottom padding under it, the navigation bar, the safe area inset. The
/// bar's background stretches under the inset to the physical bottom, so [navHeight] includes it and
/// [navContentHeight] does not.
final class BottomZoneBoxes {
  const BottomZoneBoxes({
    required this.top,
    required this.height,
    required this.pinnedTop,
    required this.pinnedHeight,
    required this.navTop,
    required this.navHeight,
    required this.navContentHeight,
    required this.safeBottom,
  });

  final double top;
  final double height;

  /// The pinned block; `null` if there is none (or it is hidden).
  final double? pinnedTop;
  final double? pinnedHeight;

  /// The navigation bar; `null` if there is none (or it is hidden or not drawn).
  final double? navTop;
  final double? navHeight;
  final double? navContentHeight;

  /// The safe area inset actually added (0 when there is no zone).
  final double safeBottom;
}

/// Screen zones in the coordinates of the screen itself, measured from the top edge
/// (`screenZonesOf`, `zoneCases`). Only the reader's formula: `ScreenZones` draws these zones, and the
/// table checks both.
final class ScreenZoneBoxes {
  const ScreenZoneBoxes({
    required this.height,
    required this.appBarTop,
    required this.appBarHeight,
    required this.bodyTop,
    required this.bodyHeight,
    required this.contentTop,
    required this.contentHeight,
    required this.maxScroll,
    required this.scrollTop,
    this.bottom,
    this.float = false,
  });

  /// The bottom zone lies OVER the body (schema 9.22.0, `NavBar.float`).
  final bool float;

  /// Screen height (for a modal layer, the layer height).
  final double height;

  /// Box of the app bar; `null` when there is no zone.
  final double? appBarTop;
  final double? appBarHeight;

  /// Body area: from the bottom edge of the app bar (minus the overlap of a pulled first child, not
  /// above the top of the screen) to the TOP EDGE of the bottom zone (9.12.0), or to the bottom without
  /// one.
  final double bodyTop;
  final double bodyHeight;

  /// Top of the first body child at this scroll position.
  final double contentTop;

  /// Length of what scrolls, from the top of the body area.
  final double contentHeight;

  final double maxScroll;
  final double scrollTop;

  /// The bottom zone; `null` when there is none (no block and no bar, or they are hidden).
  final BottomZoneBoxes? bottom;

  bool get scrolls => maxScroll > 0.0001;
}

/// Zone layout (`x-style.layout.screen`, and the bottom zone since 9.12.0). [appBarHeight] is the box
/// of the app bar with its own padding (without the screen's top padding); `null` means there is no
/// zone. [bodyContentHeight] is the flow of the visible body children WITHOUT the pull of the first
/// one; `null` means there are none visible. [shrink] is a modal layer: [height] is the AVAILABLE
/// height, and the layer is no taller than the content PLUS the bottom zone.
///
/// Bottom zone: [pinnedHeight] is the height of the pinned block (`null` if there is no block, or it
/// is hidden by a condition), [navBarHeight] is the height of the bar without the inset, [safeBottom] is
/// the platform's bottom safe area inset, which the reader adds only when the zone exists. With a
/// pinned block the body ends with the screen gap instead of the bottom padding, and the padding itself
/// lies under the block.
ScreenZoneBoxes screenZoneBoxes({
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
  bool navFloat = false,
}) {
  final hasBar = appBarHeight != null;
  final hasBody = bodyContentHeight != null;
  final hasPinned = pinnedHeight != null;
  final hasNav = navBarHeight != null;
  final hasZone = hasPinned || hasNav;
  final barBottom = hasBar ? paddingTop + appBarHeight : 0.0;
  // The overlap lies only under the app bar; without one a pulled child goes into the top padding.
  final overlap = hasBar && hasBody ? math.max(0.0, firstPull - gap) : 0.0;
  final areaTop = hasBar ? math.max(0.0, barBottom - overlap) : 0.0;
  final raise = barBottom - areaTop;
  final padTop = hasBar ? (hasBody ? gap + raise : 0.0) : paddingTop;
  final pull = hasBody ? firstPull : 0.0;
  // Bottom padding of the body: with a pinned block, the screen gap (a body with no visible children
  // has none); without a block, the root's padding.
  final bodyBottom = hasPinned ? (hasBody ? gap : 0.0) : paddingBottom;
  final contentHeight = padTop + (bodyContentHeight ?? 0) - pull + bodyBottom;
  // The safe area inset is added only when a zone exists (`bottomSafeInset`).
  final safe = hasZone ? math.max(0.0, safeBottom) : 0.0;
  final pinnedBand = hasPinned ? math.max(0.0, pinnedHeight) + math.max(0.0, paddingBottom) : 0.0;
  final navContent = hasNav ? math.max(0.0, navBarHeight) : 0.0;
  final zoneHeight = hasZone ? pinnedBand + navContent + safe : 0.0;
  final room = math.max(0.0, height - zoneHeight - areaTop);
  final bodyHeight = shrink ? math.min(contentHeight, room) : room;
  final maxScroll = math.max(0.0, contentHeight - bodyHeight);
  final scrolled = math.min(math.max(0.0, scrollTop), maxScroll);
  final zoneTop = areaTop + bodyHeight;
  // A FLOATING BAR (schema 9.22.0, `floatScreenZonesOf`): the whole bottom zone lies over the body, which reaches
  // the bottom of the screen; the content gets the height of the zone at its end, so the scroll limit stays the
  // one it was; the safe inset is under the box of the bar, not in it. Not read without a bar in the zone and in a layer.
  if (navFloat && hasNav && !shrink) {
    final floatBody = math.max(0.0, height - areaTop);
    final floatContent = contentHeight + zoneHeight;
    final floatMax = math.max(0.0, floatContent - floatBody);
    final floatScrolled = math.min(math.max(0.0, scrollTop), floatMax);
    return ScreenZoneBoxes(
      height: height,
      appBarTop: hasBar ? paddingTop : null,
      appBarHeight: appBarHeight,
      bodyTop: areaTop,
      bodyHeight: floatBody,
      contentTop: areaTop + padTop - pull - floatScrolled,
      contentHeight: floatContent,
      maxScroll: floatMax,
      scrollTop: floatScrolled,
      float: true,
      bottom: BottomZoneBoxes(
        top: zoneTop,
        height: zoneHeight,
        pinnedTop: hasPinned ? zoneTop : null,
        pinnedHeight: hasPinned ? math.max(0.0, pinnedHeight) : null,
        navTop: zoneTop + pinnedBand,
        navHeight: navContent,
        navContentHeight: navContent,
        safeBottom: safe,
      ),
    );
  }
  return ScreenZoneBoxes(
    height: shrink ? zoneTop + zoneHeight : height,
    appBarTop: hasBar ? paddingTop : null,
    appBarHeight: appBarHeight,
    bodyTop: areaTop,
    bodyHeight: bodyHeight,
    contentTop: areaTop + padTop - pull - scrolled,
    contentHeight: contentHeight,
    maxScroll: maxScroll,
    scrollTop: scrolled,
    bottom: hasZone
        ? BottomZoneBoxes(
            top: zoneTop,
            height: zoneHeight,
            pinnedTop: hasPinned ? zoneTop : null,
            pinnedHeight: hasPinned ? math.max(0.0, pinnedHeight) : null,
            navTop: hasNav ? zoneTop + pinnedBand : null,
            navHeight: hasNav ? navContent + safe : null,
            navContentHeight: hasNav ? navContent : null,
            safeBottom: safe,
          )
        : null,
  );
}

// -- Modal layer --

/// Where a modal layer lies (`ScreenEntry.modalPlacement`, 9.9.0).
enum ModalPlacement {
  /// A sheet from the bottom, which is what it was before 9.9.0.
  bottom,

  /// A window in the middle.
  center;

  String get wire => name;

  /// The placement the reader draws with: an unknown word and a missing field give a sheet
  /// (`unknownModalPlacement: bottom`).
  static ModalPlacement of(Object? raw) => raw == 'center' ? center : bottom;

  /// The document's word if it is known; otherwise `null`, so the show event needs no extra key.
  static ModalPlacement? tryParse(Object? raw) => switch (raw) {
    'center' => center,
    'bottom' => bottom,
    _ => null,
  };
}

/// Largest width of a window in the middle, dp (`modalLayer.center.maxWidth`).
const double kModalWindowMaxWidth = 400;

/// Opacity of the black scrim (`modalLayer.scrim.opacity`).
const double kModalScrimOpacity = 0.45;

/// Layer width: it has to be known BEFORE the content is measured (`modalWidthOf`).
double modalWidthOf(Object? placement, double viewportWidth, double margin) {
  if (ModalPlacement.of(placement) == ModalPlacement.bottom) return viewportWidth;
  return math.max(0.0, math.min(viewportWidth - 2 * margin, kModalWindowMaxWidth));
}

/// Rectangle of the modal layer in the screen area (`modalBoxOf`).
({double x, double y, double width, double height, bool scrolls}) modalBoxOf({
  required Object? placement,
  required double viewportWidth,
  required double viewportHeight,
  required double contentHeight,
  required double margin,
}) {
  final place = ModalPlacement.of(placement);
  final width = modalWidthOf(place.wire, viewportWidth, margin);
  final available = place == ModalPlacement.bottom
      ? viewportHeight
      : math.max(0.0, viewportHeight - 2 * margin);
  final height = math.min(math.max(0.0, contentHeight), available);
  final scrolls = contentHeight > available;
  if (place == ModalPlacement.bottom) {
    return (x: 0, y: viewportHeight - height, width: width, height: height, scrolls: scrolls);
  }
  return (
    x: (viewportWidth - width) / 2,
    y: (viewportHeight - height) / 2,
    width: width,
    height: height,
    scrolls: scrolls,
  );
}

// -- Status bar --

/// A screen's request for the icons of the system status bar (`ScreenEntry.statusBarIcons`). The word
/// names the COLOR OF THE ICONS: `light` is light icons (on a dark background).
enum StatusBarIcons {
  light,
  dark;

  String get wire => name;

  /// The request as the reader reads it; an unknown word means no request.
  static StatusBarIcons? of(Object? raw) => switch (raw) {
    'light' => light,
    'dark' => dark,
    _ => null,
  };
}

/// How many app bar actions the reader draws (`x-style.layout.appBar.maxDrawnActions`, policy row
/// `appBarExtraActions: 'draw-first-two'`). The limit of two is guarded by the validator; a reader
/// that receives a document with more does not shrink the title to zero width: actions beyond the second
/// are NOT drawn.
const int kAppBarMaxDrawnActions = 2;

/// Which of the action children of the app bar are drawn (`appBarDrawnCases`): by document order, the
/// first [kAppBarMaxDrawnActions] VISIBLE ones; those hidden by a condition are not counted and take
/// no room. [visible] has one flag per child (visible or not).
List<bool> appBarDrawnActions(List<bool> visible) {
  var drawn = 0;
  return [
    for (final shown in visible)
      if (shown && drawn < kAppBarMaxDrawnActions)
        () {
          drawn += 1;
          return true;
        }()
      else
        false,
  ];
}

/// The fourteen policy rows of 9.9.0 (`x-compatibility.policy`, from `imageNamedHeight`; the
/// fourteenth, `appBarExtraActions`, is a clarification made before release). A mirror for checking
/// against the artifact.
const Map<String, String> kMediaChromePolicy = {
  'imageNamedHeight': 'box-is-named-ratio-not-read',
  'unreadableImageRatio': 'field-default',
  'imageRatioOutOfRange': 'clamp-to-range',
  'appBarScroll': 'fixed-only-the-body-scrolls',
  'appBarChildren': 'icon-buttons-in-order-others-not-drawn',
  'appBarExtraActions': 'draw-first-two',
  'appBarActionColor': 'own-role-not-bar-color',
  'unknownModalPlacement': 'bottom',
  'modalPlacementOnPage': 'ignore',
  'modalLayerLook': 'screen-root-style-nothing-built-in',
  'modalDismiss': 'navigate-back',
  'modalOverflow': 'body-of-the-layer-scrolls',
  'statusBarIcons': 'handed-to-host-reader-touches-nothing',
  'unknownStatusBarIcons': 'no-request',
};
