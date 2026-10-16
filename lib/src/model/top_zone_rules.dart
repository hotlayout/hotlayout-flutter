import 'dart:math' as math;

/// THE TOP ZONE OF A SCREEN (schema 9.24.0, `pin: 'top'`): children of the root that stand in a run at the start and do
/// not scroll. Mirror of the reference `top-zone-rules.ts`; the data is `x-style.layout.topZone` and the shared table is
/// `contract/fixtures/top-zone/top-zone-cases.json`. Which child is in the zone is `screenChildrenByZone`; this file has
/// the word, the reasons a word is not read and the geometry of the zone.

/// The word of the field for the top zone.
const String kPinTop = 'top';

/// Whether a raw `pin` is the word `top` (`pinCases`): that word exactly, nothing else.
bool pinTopOf(Object? raw) => raw == kPinTop;

/// Why a node's `pin: 'top'` is not read (`documentCases`); the first reason in this order.
enum TopPinIssue { onZone, outsideScreen, withBodyAtScreenTop, notInRun }

/// Why the word `top` on a node is not read (`topPinIssueOf`, `documentCases`), or `null` when it is: the first reason
/// in the order `onZone` (an app bar or a navigation bar is a zone already), `outsideScreen` (the node is not a child
/// of the screen root), `withBodyAtScreenTop`, `notInRun` (a child without the word stands before it).
TopPinIssue? topPinIssueOf({
  required bool pinTop,
  required String type,
  required String? parentType,
  required bool bodyAtScreenTop,
  required bool inRun,
}) {
  if (!pinTop) return null;
  if (type == 'AppBar' || type == 'NavBar') return TopPinIssue.onZone;
  if (parentType != 'Screen') return TopPinIssue.outsideScreen;
  if (bodyAtScreenTop) return TopPinIssue.withBodyAtScreenTop;
  return inRun ? null : TopPinIssue.notInRun;
}

/// One shown node of the zone: its height and its `pull` (the first node's pull is not read).
typedef TopZoneNode = ({double height, double pull});

/// A box in the coordinates of the screen from its physical top.
typedef TopZoneSpan = ({double top, double height});

/// The box of the zone (`topZoneOf`, `geometryCases`).
typedef TopZoneBox = ({double height, TopZoneSpan? appBar, List<TopZoneSpan> pinned, double bodyTop});

/// The geometry of the zone: the root's top padding and the app bar (which carries the safe inset), or, without an app
/// bar, the safe inset and then the padding above the first node; the screen gap between nodes less the `pull` of the
/// later ones. The body area starts at the bottom edge of the last node.
TopZoneBox topZoneOf({
  double? appBarHeight,
  required List<TopZoneNode> pinned,
  required double rootPaddingTop,
  required double gap,
  double safeTop = 0,
}) {
  final gapSize = math.max(0.0, gap);
  final padding = math.max(0.0, rootPaddingTop);
  final hasBar = appBarHeight != null;
  final barHeight = math.max(0.0, appBarHeight ?? 0);
  final safe = hasBar ? 0.0 : math.max(0.0, safeTop);
  var cursor = hasBar ? padding + barHeight : safe;
  final boxes = <TopZoneSpan>[];
  for (var i = 0; i < pinned.length; i++) {
    final lead = i == 0 ? (hasBar ? gapSize : padding) : gapSize - math.max(0.0, pinned[i].pull);
    final top = cursor + lead;
    final height = math.max(0.0, pinned[i].height);
    cursor = top + height;
    boxes.add((top: top, height: height));
  }
  return (height: cursor, appBar: hasBar ? (top: padding, height: barHeight) : null, pinned: boxes, bodyTop: cursor);
}

/// Mirror of `x-style.layout.topZone` (scalar rows); compared with the artifact by a test.
const Map<String, Object> kTopZoneRules = {
  'field': 'pin',
  'word': kPinTop,
  'counts': 'document-order-not-visibility',
  'scrolls': 'never',
  'olderReader': 'reads-the-word-as-no-field-the-nodes-scroll-with-the-body',
};
