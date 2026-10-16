import 'dart:math' as math;

import 'visibility.dart';
import 'wide_chrome_rules.dart' show NavBarPlace;

// THE BOTTOM ZONE OF A SCREEN: the navigation bar and the block pinned to the
// bottom (schema 9.12.0).
//
// Mirror of the builder's `bottom-zone-rules.ts`: the same names, the same
// order of steps. The case table
// `contract/fixtures/bottom-zone/bottom-zone-cases.json` runs these functions
// (`bottom_zone_cases_test.dart`), and the widgets draw by them; there is no
// second copy of the formula in `render_document.dart`.
//
// Only rule selection and geometry live here, with no theme: the caller
// supplies the token numbers.

// ───────────────────────────── the `pin` field ─────────────────────────────

/// The only word of the `pin` field (`bottomZone.pinValues`).
const String kPinBottom = 'bottom';

/// How the `pin` field is read (`pinCases`): the word `bottom` and nothing else
/// (`unreadablePin: 'ignore'`). `'top'`, `true`, `null`, a number, an object,
/// `'Bottom'` and an empty string all mean "no field".
String? pinOf(Object? raw) => raw == kPinBottom ? kPinBottom : null;

// ───────────────────────────── which child is in which zone ─────────────────────────────

/// The types of the navigation bar and of its item.
const String kNavBarType = 'NavBar';
const String kNavItemType = 'NavItem';

/// A root child as the zone assignment sees it: its type and whether its `pin` is read.
typedef RootChildInfo = ({String type, bool pin});

/// Indexes of the root's children by zone (`screenChildrenByZone`,
/// `childrenCases`). The body is the rest; its bounds are [bodyFrom] and
/// [bodyTo] (a half-open range).
final class ScreenZoneChildren {
  const ScreenZoneChildren({
    this.appBar,
    this.pinned,
    this.navBar,
    required this.bodyFrom,
    required this.bodyTo,
    this.topFrom = 0,
    this.topTo = 0,
  });

  final int? appBar;
  final int? pinned;
  final int? navBar;

  /// The body is the children with index in `[bodyFrom, bodyTo)`.
  final int bodyFrom;
  final int bodyTo;

  /// The children pinned to the top (`pin: 'top'`, 9.24.0) are those with index in `[topFrom, topTo)`; the range is
  /// empty when there are none.
  final int topFrom;
  final int topTo;

  /// Whether there is a top zone.
  bool get hasTop => topTo > topFrom;
}

/// Which child of the root is in which zone: three rules together, by the
/// DOCUMENT and not by visibility:
///
///  * app bar: the first child, if it is an `AppBar`;
///  * navigation bar: the LAST child, if it is a `NavBar` (`navBarNotLast`: if
///    it is not last it is an ordinary body child);
///  * pinned block: the last child NOT COUNTING the navigation bar, if its
///    `pin` is `bottom` (`pinElsewhere`); an app bar as the first child and the
///    navigation bar itself are never pinned.
///
/// The TOP zone (9.24.0, `topZone`): the run of children right after the app bar zone (or first) whose `pin` is `top`
/// ([topPins], parallel to [children]); the first child without the word, an `AppBar` or a `NavBar` ends it, and the
/// word is not read after it. With `bodyTop: screenTop` ([bodyAtScreenTop]) there is no run: the nodes are body children.
ScreenZoneChildren screenChildrenByZone(
  List<RootChildInfo> children, {
  List<bool>? topPins,
  bool bodyAtScreenTop = false,
}) {
  final count = children.length;
  final appBar = count > 0 && children.first.type == 'AppBar' ? 0 : null;
  final navBar = count > 0 && children.last.type == kNavBarType ? count - 1 : null;
  final index = (navBar == null ? count : count - 1) - 1;
  int? pinned;
  if (index >= 0) {
    final candidate = children[index];
    if (candidate.pin && candidate.type != kNavBarType && !(index == 0 && candidate.type == 'AppBar')) {
      pinned = index;
    }
  }
  final topFrom = appBar == null ? 0 : 1;
  var topTo = topFrom;
  if (topPins != null && !bodyAtScreenTop) {
    while (topTo < count && topPins[topTo] && children[topTo].type != 'AppBar' && children[topTo].type != kNavBarType) {
      topTo += 1;
    }
  }
  final to = count - (navBar == null ? 0 : 1) - (pinned == null ? 0 : 1);
  return ScreenZoneChildren(
    appBar: appBar,
    pinned: pinned,
    navBar: navBar,
    bodyFrom: topTo,
    bodyTo: math.max(topTo, to),
    topFrom: topFrom,
    topTo: topTo,
  );
}

// ───────────────────────────── the `widePlacement` field ─────────────────────────────

/// Where the navigation bar sits in a WIDE place (`NavBar.widePlacement`,
/// 9.18.0, `wideNav.values`): `top` is at the top (in the app bar or as a strip
/// of its own), `bottom` is at the bottom, as on a phone.
enum NavWidePlacement { top, bottom }

/// What applies without the field and with an unknown word (`wideNav.default`,
/// `wideNav.unknown`): `top`. A word of the wrong shape is read tolerantly as
/// "no field", since the document may not come from the builder.
NavWidePlacement navWidePlacementOf(Object? raw) => raw == 'bottom' ? NavWidePlacement.bottom : NavWidePlacement.top;

// ───────────────────────────── navigation bar ─────────────────────────────

/// The most items the reader draws (`navBar.items.max`,
/// `navBarExtraItems: 'first-five-visible'`).
const int kNavBarMaxItems = 5;

/// The top line of the bar's built-in look, in logical pixels
/// (`navBar.surface.borderTop`: `{ width: 1, color: 'border' }`).
const double kNavBarLineWidth = 1;

/// The action type that switches a section (`x-actions.section`).
const String kSectionActionType = 'navigate.section';

/// Bar metrics in logical pixels (`navBarHeightOf`, `navHeightCases`).
typedef NavBarMetrics = ({double paddingBlock, double iconBox, double gap, double labelLine, double borderTop});

/// Bar height: border + padding + icon box + gap + label line + padding (61 in
/// the default theme). The safe area inset is not included.
double navBarHeightOf(NavBarMetrics metrics) =>
    metrics.borderTop + metrics.paddingBlock + metrics.iconBox + metrics.gap + metrics.labelLine + metrics.paddingBlock;

/// Which items are drawn (`navDrawnItems`): in document order, the first
/// [kNavBarMaxItems] VISIBLE ones; a hidden item is neither drawn nor given a share.
List<bool> navDrawnItems(List<bool> visible) {
  var drawn = 0;
  return [
    for (final shown in visible)
      if (shown && drawn < kNavBarMaxItems)
        () {
          drawn += 1;
          return true;
        }()
      else
        false,
  ];
}

/// An item's share: [start] is measured from the LEFT edge of the bar.
typedef NavItemShare = ({double start, double width});

/// Item shares (`navItemSharesOf`, `navShareCases`): the drawn items divide the
/// width equally, with no gaps and no rounding; the first item is at the start
/// of the reading direction. `null` means the item is not drawn.
List<NavItemShare?> navItemSharesOf(double barWidth, List<bool> visible, {bool rtl = false}) {
  final drawn = navDrawnItems(visible);
  final count = drawn.where((shown) => shown).length;
  if (count == 0) return [for (final _ in visible) null];
  final width = math.max(0.0, barWidth) / count;
  var position = 0;
  return [
    for (final shown in drawn)
      if (!shown)
        null
      else
        () {
          final index = position;
          position += 1;
          return (start: rtl ? barWidth - width * (index + 1) : width * index, width: width);
        }(),
  ];
}

/// The target screen of a `navigate.section` action (`sectionTargetOf`): the
/// non-empty string `params.screenId`; otherwise it is not a section action.
String? sectionTargetOf(String type, Map<String, String> params) {
  if (type != kSectionActionType) return null;
  final target = params['screenId'];
  return target == null || target.isEmpty ? null : target;
}

/// Whether an item is active (`isActiveNavAction`, `activeCases`): its action is
/// `navigate.section` to the SHOWN screen. There is no separate "which tab is
/// selected" state; a `navigate` to the same screen is not a section.
bool isActiveNavAction(String type, Map<String, String> params, String shownScreenId) =>
    sectionTargetOf(type, params) == shownScreenId;

/// The stack after `navigate.section` (`sectionStackOf`, `sectionCases`): ONE
/// named screen, everything above it closed. `null` means the stack already is
/// that one screen: nothing happens and there is no screen-shown event.
List<String>? sectionStackOf(List<String> stack, String target) {
  if (stack.length == 1 && stack.first == target) return null;
  return [target];
}

// ───────────────────────────── policy ─────────────────────────────

/// The sixteen policy rows of 9.12.0 (`x-compatibility.policy`, starting at
/// `navBarNotLast`). A mirror for comparison with the artifact.
const Map<String, String> kBottomZonePolicy = {
  'navBarNotLast': 'ordinary-child',
  'navBarInModalLayer': 'not-drawn',
  'navBarExtraItems': 'first-five-visible',
  'navBarNoActiveItem': 'none-active',
  'pinElsewhere': 'ignore',
  'unreadablePin': 'ignore',
  'pinWithPull': 'pull-not-read',
  'sectionSwitch': 'stack-reset-to-the-section',
  'sectionSwitchSameScreen': 'nothing',
  'sectionSwitchRecord': 'not-carried',
  'sectionSwitchScroll': 'from-the-top',
  'sectionTargetModal': 'shown-as-page',
  'unknownSectionTarget': 'host',
  'backOnSection': 'host-as-on-the-first-screen',
  'bottomSafeInset': 'reader-adds-under-the-bottom-zone',
  'bottomZoneKeyboard': 'pinned-above-nav-bar-covered',
};

// ───────────────────────────── the floating bar and the dot (9.22.0) ─────────────────────────────

/// `NavBar.float` as the reader reads it (`x-style.layout.navFloat.value`): only the literal `true`. `false`, the
/// string `"true"` and any other value are "no field".
bool navFloatOf(Object? raw) => raw == true;

/// Whether the bar FLOATS: only where it stands in the bottom zone (`navFloat.applies`); at the top, in an app bar
/// or in a strip of its own, there is nothing to float over.
bool navFloatsIn(NavBarPlace? place, bool float) => place == NavBarPlace.bottom && float;

/// The dot on an item (`x-style.layout.navBadge`): the diameter, in logical pixels.
const double kNavBadgeDiameter = 8;

/// The condition of the dot: the form of `visibleIf`, the same judgement over missing data
/// (`navBadge.condition`). A condition this reader cannot read -- no object, no operator, a newer operator --
/// gives `null`, and `null` means NO dot (`navBadge.unknownCondition`): the opposite of `visibleIf`, where the node
/// stays visible, because a dot nobody asked for is the worse mistake.
VisibilityCondition? navBadgeConditionOf(Object? raw) {
  if (raw is! Map) return null;
  final condition = VisibilityCondition.parse(raw);
  return condition is AlwaysVisibleCondition ? null : condition;
}

/// The box of the dot in the coordinates of the item, from its LEFT edge: its centre is on the top corner of the
/// glyph on the side of the end of the line (the top right corner; right to left, the top left one). The glyph is a
/// square in the size of the font, in the middle of the box of the row, so its top is below the top of the box.
({double left, double top, double size}) navBadgeBoxOf({
  required double glyphLeft,
  required double glyphTop,
  required double glyphSize,
  required bool rtl,
}) {
  final cornerX = rtl ? glyphLeft : glyphLeft + glyphSize;
  return (left: cornerX - kNavBadgeDiameter / 2, top: glyphTop - kNavBadgeDiameter / 2, size: kNavBadgeDiameter);
}

// ───────────────────────────── the motion of the dot (9.24.0) ─────────────────────────────

/// The appearance of the dot lasts 320 ms and its fading 200 ms (`x-style.layout.navBadgeMotion`).
const int kNavBadgeAppearMs = 320;
const int kNavBadgeDisappearMs = 200;

/// The peak of the flash and where it falls in the appearance.
const double kNavBadgePeakScale = 1.25;
const double kNavBadgePeakAt = 0.6;

/// What the dot does when its condition is judged again (`navBadgeChangeOf`).
enum NavBadgeChange { none, appear, disappear }

/// Motion only on a CHANGE of the answer on a screen that is already shown: the first show, a screen shown again and
/// "reduce motion" give none.
NavBadgeChange navBadgeChangeOf({
  required bool shownBefore,
  required bool before,
  required bool after,
  bool reducedMotion = false,
}) {
  if (!shownBefore || reducedMotion || before == after) return NavBadgeChange.none;
  return after ? NavBadgeChange.appear : NavBadgeChange.disappear;
}

double _lerp(double from, double to, double share) => from + (to - from) * share;

double _share(num t, int duration) => math.min(1.0, math.max(0.0, t / duration));

/// The scale of the dot [t] ms into the appearance: 0 to 1.25 at 0.6 of the time, then to 1, linear between.
double navBadgeAppearScaleAt(num t) {
  final p = _share(t, kNavBadgeAppearMs);
  if (p <= kNavBadgePeakAt) return _lerp(0, kNavBadgePeakScale, p / kNavBadgePeakAt);
  return _lerp(kNavBadgePeakScale, 1, (p - kNavBadgePeakAt) / (1 - kNavBadgePeakAt));
}

/// The opacity of the dot [t] ms into its fading: 1 to 0, linear.
double navBadgeDisappearOpacityAt(num t) => 1 - _share(t, kNavBadgeDisappearMs);
