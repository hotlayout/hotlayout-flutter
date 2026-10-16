/// CLOSING A SHEET BY A DRAG DOWN (schema 9.26.0; rules in `x-sheetDismiss`) and the screen entry's `dismissible`.
///
/// A modal screen shown as a sheet from the bottom follows the finger down. Released past [kSheetDismissShare] of its
/// height, or thrown down at [kSheetFlingVelocity] logical pixels per second or more, it leaves and the stack goes one
/// step back (`navigate.back`); otherwise it returns. A fling up returns it whatever the distance. `dismissible: false`
/// on the entry of a modal screen turns off the drag, the tap on the scrim and Esc. Mirror of the contract's block;
/// `test/sheet_dismiss_cases_test.dart` runs the shared table.
library;

import 'long_press.dart' show kLongPressSlop;

/// The part of the sheet's height that, dragged, closes it.
const double kSheetDismissShare = 0.3;

/// A fling down at this speed (logical pixels per second) closes the sheet at any distance; up, it returns it.
const double kSheetFlingVelocity = 700;

/// The velocity is that of the last this many milliseconds of the movement.
const int kSheetVelocityWindowMs = 100;

/// The return of a sheet that was not dragged far enough, and the exit of one that was.
/// How long a motion of the sheet takes, and the cubic Bézier curve it follows.
typedef SheetMotion = ({int durationMs, List<double> curve});

const SheetMotion kSheetReturn = (durationMs: 250, curve: [0.2, 0, 0, 1]);
const SheetMotion kSheetExit = (durationMs: 200, curve: [0.4, 0, 1, 1]);

/// The key of a modal screen's entry that keeps a person from closing its layer.
const String kDismissibleKey = 'dismissible';

enum SheetDragOutcome { dismiss, returns }

/// What a released sheet comes to. A fling up returns, a fling down dismisses, otherwise the share of the height
/// decides; a sheet of no height is dismissed only by a fling.
SheetDragOutcome sheetDragOutcome({required double sheetHeight, required double dragged, required double velocity}) {
  if (velocity <= -kSheetFlingVelocity) return SheetDragOutcome.returns;
  if (velocity >= kSheetFlingVelocity) return SheetDragOutcome.dismiss;
  if (sheetHeight <= 0) return SheetDragOutcome.returns;
  return dragged >= sheetHeight * kSheetDismissShare ? SheetDragOutcome.dismiss : SheetDragOutcome.returns;
}

/// Whether a move of the finger drags the sheet instead of scrolling its body: only a sheet, only a dismissible one,
/// only a move down past the touch slop that is more down than sideways; off the handle, only when the body is at
/// its top ([scrolled] is how far it is scrolled away from it).
bool sheetDragStarts({
  required bool sheet,
  required bool dismissible,
  required double scrolled,
  required double dy,
  required double dx,
  required bool onHandle,
}) {
  if (!sheet || !dismissible) return false;
  if (dy <= kLongPressSlop || dx.abs() >= dy) return false;
  return onHandle || scrolled <= 0;
}

/// Mirror of the scalar rows of `x-sheetDismiss`; checked against the artifact by a test.
const Map<String, Object> kSheetDismissRules = {
  'layer':
      'a modal screen shown as a sheet from the bottom (x-style.layout.modalLayer, x-style.layout.wideModal); a centred window has no drag',
  'grab': 'the handle drawn by the document or any point of the sheet',
  'starts': 'the finger moves down past the touch slop of «x-longPress» and more down than sideways',
  'follows': 'the sheet follows the finger down; it never goes above its place',
  'dismiss':
      'navigate.back — one step of the stack, the «screen shown» event with reason «back» after the sheet has left',
  'scrim': 'the scrim fades with the share of the sheet that is still visible',
  'reducedMotion': 'the sheet still follows the finger; the return and the exit are instant',
  'keyboard': 'Esc as x-style.layout.modalLayer.dismiss',
};
