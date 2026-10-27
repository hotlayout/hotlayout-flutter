import 'dart:math' as math;

import 'wide_chrome_rules.dart';

// The bottom safe inset of a modal sheet (schema 9.31.0, `x-style.layout.sheetSafeBottom`).
//
// Mirrors the reference implementation `sheet-safe-bottom.ts`. The case table
// `fixtures/sheet-safe-bottom/sheet-safe-bottom-cases.json` runs these functions and the real widgets
// (`sheet_safe_bottom_cases_test.dart`).
//
// A sheet is pressed to the PHYSICAL bottom of its area, so the home indicator or gesture bar lies over it. The
// reader adds the platform inset INSIDE the sheet box (the root of the modal screen: its background and radius), under
// the content, and only once: with a shown pinned block the inset goes under the content of that zone, as on a page,
// otherwise it is the bottom padding of the box. A window in the middle and a sheet shown as a window have none, and a
// host that accounted for the inset itself gives the reader zero.

/// How much of the inset counts: anything that is not a finite positive number is zero.
double sheetSafeInsetOf(Object? value) =>
    value is num && value.isFinite && value > 0 ? value.toDouble() : 0.0;

/// Where the bottom inset of a layer lies: the bottom padding of the root box, or the room under the zone's content.
final class SheetSafeBottom {
  const SheetSafeBottom({required this.root, required this.zone});

  final double root;
  final double zone;

  @override
  bool operator ==(Object other) =>
      other is SheetSafeBottom && other.root == root && other.zone == zone;

  @override
  int get hashCode => Object.hash(root, zone);

  @override
  String toString() => 'SheetSafeBottom(root: $root, zone: $zone)';
}

const SheetSafeBottom _none = SheetSafeBottom(root: 0, zone: 0);

/// The place of the inset of a screen the reader already knows to be a sheet: under the zone when there is one,
/// otherwise in the root; never both.
SheetSafeBottom sheetInsetPlaceOf(Object? inset, {required bool bottomZone}) {
  final value = sheetSafeInsetOf(inset);
  if (value == 0) return _none;
  return bottomZone
      ? SheetSafeBottom(root: 0, zone: value)
      : SheetSafeBottom(root: value, zone: 0);
}

/// Where the reader adds the bottom safe inset of a screen: a sheet as [sheetInsetPlaceOf]; a window and a sheet shown
/// as a window nowhere; a page as before (`bottomZone.safeArea`): under the zone, and without a zone nowhere.
SheetSafeBottom sheetSafeBottomOf({
  required Object? presentation,
  Object? modalPlacement,
  required double areaWidth,
  Object? safeBottom,
  required bool bottomZone,
}) {
  if (presentation != 'modal') {
    final value = sheetSafeInsetOf(safeBottom);
    return bottomZone && value > 0
        ? SheetSafeBottom(root: 0, zone: value)
        : _none;
  }
  if (modalShapeOf(modalPlacement, areaWidth) != ModalShape.sheet) return _none;
  return sheetInsetPlaceOf(safeBottom, bottomZone: bottomZone);
}

/// The box of a sheet in logical points from the top of the area.
final class SheetBox {
  const SheetBox({
    required this.y,
    required this.height,
    required this.contentBottom,
    required this.scrolls,
  });

  final double y;
  final double height;

  /// The bottom edge of the content, above the inset, from the top of the sheet.
  final double contentBottom;

  /// The content with the inset is taller than the area: the body scrolls above the inset.
  final bool scrolls;
}

/// The box of a sheet with the inset inside: content plus inset, no taller than the area.
SheetBox sheetBoxOf({
  required double areaHeight,
  required double contentHeight,
  Object? safeBottom,
}) {
  final area = math.max(0.0, areaHeight);
  final inset = math.min(sheetSafeInsetOf(safeBottom), area);
  final natural = math.max(0.0, contentHeight) + inset;
  final height = math.min(natural, area);
  return SheetBox(
    y: area - height,
    height: height,
    contentBottom: height - inset,
    scrolls: natural > area,
  );
}
