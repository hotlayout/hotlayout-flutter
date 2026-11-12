import 'package:flutter/foundation.dart';

import 'visibility_fade.dart' show cubicBezierAt;
import 'wide_chrome_rules.dart' show ModalShape, modalShapeOf;

// Default transitions between screens (schema 9.38.0, `x-screenTransition`).
//
// Mirrors the reference implementation `screen-transition.ts`. A step of the stack is described by what happened to
// it (start, push, pop, switch), the top screen before and after it, the width of the area the host gave the stack
// and the reduced-motion setting; [screenTransitionPlan] says which motion the reader plays and with what numbers,
// [screenTransitionFrame] where both screens stand at a moment of it. The rows of
// `fixtures/screen-transition/screen-transition-cases.json` run these functions (`screen_transition_cases_test.dart`);
// the widgets and the clock belong to `render/screen_flow*.dart` and `render/modal_layer.dart`.

/// The field of a screen entry.
const String kScreenTransitionKey = 'transition';

/// What happened to the stack.
enum StackStep {
  /// The first show, a new entry, a stack the host built anew: always at once.
  start('start'),

  /// The stack grew by one (`navigate`).
  push('push'),

  /// The stack became shorter by one (`navigate.back`, the scrim, Esc, the system "back").
  pop('pop'),

  /// A section was switched (`navigate.section`, a navigation item).
  switchSection('switch');

  const StackStep(this.wire);

  final String wire;

  static StackStep? tryParse(Object? raw) {
    for (final step in values) {
      if (step.wire == raw) return step;
    }
    return null;
  }
}

/// How a screen asks to come and go: only a word of the list counts, anything else is no field.
enum ScreenTransitionWord {
  /// A cross-dissolve: a page fades out over the new one, a layer changes its opacity only.
  fade,

  /// At once.
  none;

  /// The word `raw` names, or `null` (no field, an unknown word, not a string).
  static ScreenTransitionWord? of(Object? raw) {
    for (final word in values) {
      if (word.name == raw) return word;
    }
    return null;
  }
}

/// A screen as the transition sees it: three fields of its record.
@immutable
final class TransitionScreen {
  const TransitionScreen({this.modal = false, this.placement, this.transition});

  /// The screen is laid over another one (the EFFECTIVE presentation: the first screen of a stack is a page).
  final bool modal;

  /// The `modalPlacement` word (any value; [modalShapeOf] knows what it means).
  final Object? placement;

  /// The `transition` field, read ([ScreenTransitionWord.of]).
  final ScreenTransitionWord? transition;
}

/// What the reader plays.
enum TransitionMotion {
  none('none'),
  push('push'),
  pop('pop'),
  crossfade('crossfade'),
  sheetIn('sheet-in'),
  sheetOut('sheet-out'),
  windowIn('window-in'),
  windowOut('window-out'),
  layerFadeIn('layer-fade-in'),
  layerFadeOut('layer-fade-out');

  const TransitionMotion(this.wire);

  final String wire;

  /// A layer (sheet, window, or only its opacity) comes in or goes out.
  bool get isLayer => switch (this) {
    sheetIn || sheetOut || windowIn || windowOut || layerFadeIn || layerFadeOut => true,
    _ => false,
  };

  /// The layer comes in.
  bool get isLayerIn => this == sheetIn || this == windowIn || this == layerFadeIn;
}

/// Why nothing moves.
enum StillReason {
  start('start'),
  reducedMotion('reduced-motion'),
  covered('covered'),
  dragged('dragged'),
  section('section'),
  fieldNone('field-none');

  const StillReason(this.wire);

  final String wire;
}

/// What happens to the scrim (and the backdrop blur) under a layer.
enum ScrimMotion {
  /// It comes and goes with the layer: a page is on the other side.
  fade,

  /// It stays: a layer is on the other side.
  still,
}

/// The durations and curves of the motions (`x-screenTransition`).
const List<double> kDecelerateCurve = [0.2, 0, 0, 1];
const List<double> kAccelerateCurve = [0.4, 0, 1, 1];
const List<double> kStandardFadeCurve = [0.4, 0, 0.2, 1];

const int kPageMotionMs = 300;
const double kPageParallax = 0.3;
const int kSheetOpenMs = 280;
const int kSheetCloseMs = 220;
const int kWindowOpenMs = 200;
const int kWindowCloseMs = 150;
const double kWindowScaleFrom = 0.96;
const int kScreenFadeMs = 200;

/// A planned motion of a step: the motion and its numbers, or nothing and the reason.
@immutable
final class ScreenTransitionPlan {
  const ScreenTransitionPlan.still(StillReason this.reason)
    : motion = TransitionMotion.none,
      durationMs = 0,
      curve = const [0, 0, 1, 1],
      parallax = null,
      scaleFrom = null,
      scrim = null;

  const ScreenTransitionPlan._(
    this.motion, {
    required this.durationMs,
    required this.curve,
    this.parallax,
    this.scaleFrom,
    this.scrim,
  }) : reason = null;

  final TransitionMotion motion;

  /// Why nothing moves; `null` when something does.
  final StillReason? reason;

  final int durationMs;

  /// The control points of the cubic Bezier through (0,0) and (1,1).
  final List<double> curve;

  /// `push` and `pop`: the share of the width the page beneath moves.
  final double? parallax;

  /// `window-in`: the scale the window grows from.
  final double? scaleFrom;

  /// A layer's motion: what the scrim does.
  final ScrimMotion? scrim;

  bool get moves => motion != TransitionMotion.none;

  /// The same motion at a constant speed: a transition that follows a finger stays under it.
  ScreenTransitionPlan get linear => ScreenTransitionPlan._(
    motion,
    durationMs: durationMs,
    curve: const [0, 0, 1, 1],
    parallax: parallax,
    scaleFrom: scaleFrom,
    scrim: scrim,
  );

  Duration get duration => Duration(milliseconds: durationMs);
}

ScreenTransitionPlan _layerIn(TransitionScreen from, TransitionScreen to, ScreenTransitionWord? word, double areaWidth) {
  final scrim = from.modal ? ScrimMotion.still : ScrimMotion.fade;
  if (word == ScreenTransitionWord.fade) {
    return ScreenTransitionPlan._(
      TransitionMotion.layerFadeIn,
      durationMs: kScreenFadeMs,
      curve: kStandardFadeCurve,
      scrim: scrim,
    );
  }
  if (modalShapeOf(to.placement, areaWidth) == ModalShape.sheet) {
    return ScreenTransitionPlan._(
      TransitionMotion.sheetIn,
      durationMs: kSheetOpenMs,
      curve: kDecelerateCurve,
      scrim: scrim,
    );
  }
  return ScreenTransitionPlan._(
    TransitionMotion.windowIn,
    durationMs: kWindowOpenMs,
    curve: kDecelerateCurve,
    scaleFrom: kWindowScaleFrom,
    scrim: scrim,
  );
}

ScreenTransitionPlan _layerOut(
  TransitionScreen leaving,
  TransitionScreen to,
  ScreenTransitionWord? word,
  double areaWidth,
  bool dragged,
) {
  final scrim = to.modal ? ScrimMotion.still : ScrimMotion.fade;
  if (word == ScreenTransitionWord.fade) {
    return ScreenTransitionPlan._(
      TransitionMotion.layerFadeOut,
      durationMs: kScreenFadeMs,
      curve: kStandardFadeCurve,
      scrim: scrim,
    );
  }
  if (modalShapeOf(leaving.placement, areaWidth) == ModalShape.sheet) {
    if (dragged) return const ScreenTransitionPlan.still(StillReason.dragged);
    return ScreenTransitionPlan._(
      TransitionMotion.sheetOut,
      durationMs: kSheetCloseMs,
      curve: kAccelerateCurve,
      scrim: scrim,
    );
  }
  return ScreenTransitionPlan._(
    TransitionMotion.windowOut,
    durationMs: kWindowCloseMs,
    curve: kAccelerateCurve,
    scrim: scrim,
  );
}

ScreenTransitionPlan _page(TransitionMotion motion) => ScreenTransitionPlan._(
  motion,
  durationMs: kPageMotionMs,
  curve: kDecelerateCurve,
  parallax: kPageParallax,
);

const ScreenTransitionPlan _crossfade = ScreenTransitionPlan._(
  TransitionMotion.crossfade,
  durationMs: kScreenFadeMs,
  curve: kStandardFadeCurve,
);

/// HOW THE READER SHOWS A STEP OF THE STACK. The order of the checks is part of the rule: `start`, reduced motion, the
/// fill of a swipe button, whose word decides, the word `none`, then the shape of the screen.
///
/// [from] is the top screen before the step (`null` at [StackStep.start]), [to] after it. [areaWidth] is the width of
/// the area the host gave the stack: the shape of a layer (`modalShapeOf`) follows it.
ScreenTransitionPlan screenTransitionPlan({
  required StackStep step,
  TransitionScreen? from,
  required TransitionScreen to,
  required double areaWidth,
  bool reducedMotion = false,
  bool covered = false,
  bool dragged = false,
}) {
  if (step == StackStep.start || from == null) return const ScreenTransitionPlan.still(StillReason.start);
  if (reducedMotion) return const ScreenTransitionPlan.still(StillReason.reducedMotion);
  if (covered) return const ScreenTransitionPlan.still(StillReason.covered);
  if (step == StackStep.pop) {
    final word = from.transition;
    if (word == ScreenTransitionWord.none) return const ScreenTransitionPlan.still(StillReason.fieldNone);
    if (from.modal) return _layerOut(from, to, word, areaWidth, dragged);
    return word == ScreenTransitionWord.fade ? _crossfade : _page(TransitionMotion.pop);
  }
  final word = to.transition;
  if (word == ScreenTransitionWord.none) return const ScreenTransitionPlan.still(StillReason.fieldNone);
  if (step == StackStep.switchSection) {
    if (word != ScreenTransitionWord.fade) return const ScreenTransitionPlan.still(StillReason.section);
    return to.modal ? _layerIn(from, to, word, areaWidth) : _crossfade;
  }
  if (to.modal) return _layerIn(from, to, word, areaWidth);
  return word == ScreenTransitionWord.fade ? _crossfade : _page(TransitionMotion.push);
}

/// How one layer stands at a moment of a motion: a shift as a share of the screen width (`x`) or of the layer's own
/// height (`y`), the opacity and the scale.
@immutable
final class TransitionLayerFrame {
  const TransitionLayerFrame({this.x = 0, this.y = 0, this.opacity = 1, this.scale = 1});

  final double x;
  final double y;
  final double opacity;
  final double scale;
}

/// Both screens and the scrim at a moment of a motion.
@immutable
final class ScreenTransitionFrame {
  const ScreenTransitionFrame({required this.incoming, required this.outgoing, required this.scrim});

  /// The screen that comes (the new top of the stack).
  final TransitionLayerFrame incoming;

  /// The screen that goes (the old top).
  final TransitionLayerFrame outgoing;

  /// The share of the resting opacity of the scrim under a layer: 1 at rest, 0 not seen.
  final double scrim;
}

const TransitionLayerFrame _rest = TransitionLayerFrame();

/// WHERE BOTH SCREENS STAND [elapsedMs] after the motion began. `x` is positive towards the end edge (the reader mirrors
/// the sign in a right-to-left language). Past the duration it is the final state: what went is no longer seen.
ScreenTransitionFrame screenTransitionFrame(ScreenTransitionPlan plan, double elapsedMs) {
  if (!plan.moves) {
    return const ScreenTransitionFrame(incoming: _rest, outgoing: TransitionLayerFrame(opacity: 0), scrim: 1);
  }
  final share = plan.durationMs <= 0 ? 1.0 : elapsedMs / plan.durationMs;
  final e = cubicBezierAt(plan.curve, share);
  final scrimIn = plan.scrim == ScrimMotion.fade ? e : 1.0;
  final scrimOut = plan.scrim == ScrimMotion.fade ? 1 - e : 1.0;
  final parallax = plan.parallax ?? 0;
  switch (plan.motion) {
    case TransitionMotion.none:
      return const ScreenTransitionFrame(incoming: _rest, outgoing: _rest, scrim: 1);
    case TransitionMotion.push:
      return ScreenTransitionFrame(
        incoming: TransitionLayerFrame(x: 1 - e),
        outgoing: TransitionLayerFrame(x: -parallax * e),
        scrim: 1,
      );
    case TransitionMotion.pop:
      return ScreenTransitionFrame(
        incoming: TransitionLayerFrame(x: -parallax * (1 - e)),
        outgoing: TransitionLayerFrame(x: e),
        scrim: 1,
      );
    case TransitionMotion.crossfade:
      return ScreenTransitionFrame(incoming: _rest, outgoing: TransitionLayerFrame(opacity: 1 - e), scrim: 1);
    case TransitionMotion.sheetIn:
      return ScreenTransitionFrame(incoming: TransitionLayerFrame(y: 1 - e), outgoing: _rest, scrim: scrimIn);
    case TransitionMotion.sheetOut:
      return ScreenTransitionFrame(incoming: _rest, outgoing: TransitionLayerFrame(y: e), scrim: scrimOut);
    case TransitionMotion.windowIn:
      final from = plan.scaleFrom ?? 1;
      return ScreenTransitionFrame(
        incoming: TransitionLayerFrame(opacity: e, scale: from + (1 - from) * e),
        outgoing: _rest,
        scrim: scrimIn,
      );
    case TransitionMotion.layerFadeIn:
      return ScreenTransitionFrame(incoming: TransitionLayerFrame(opacity: e), outgoing: _rest, scrim: scrimIn);
    case TransitionMotion.windowOut || TransitionMotion.layerFadeOut:
      return ScreenTransitionFrame(incoming: _rest, outgoing: TransitionLayerFrame(opacity: 1 - e), scrim: scrimOut);
  }
}

String _bezier(List<double> curve) => 'cubic-bezier(${curve.map(_num).join(', ')})';

String _num(double value) => value == value.roundToDouble() ? value.toInt().toString() : value.toString();

/// Mirror of the `x-screenTransition` block. Checked against the artifact by `screen_transition_cases_test.dart`.
final Map<String, Object?> kScreenTransitionRules = {
  'field': kScreenTransitionKey,
  'on': 'ScreenEntry',
  'words': ['fade', 'none'],
  'value':
      'how this screen comes and goes: «fade» — a cross-dissolve (a page: the old one fades out over the new one; a layer: opacity only, no slide and no zoom), «none» — at once; no field — the platform default below',
  'decides':
      'the screen that comes decides when the stack grows or a section is switched; the screen that leaves decides when the stack shrinks',
  'unknownWord': 'as no field — the platform default',
  'page': {
    'push': {
      'durationMs': kPageMotionMs,
      'curve': kDecelerateCurve,
      'parallax': kPageParallax,
      'curveCss': _bezier(kDecelerateCurve),
      'incoming': 'slides in from the end edge over the whole width (x from 1 to 0)',
      'outgoing':
          'slides back by «parallax» of the width (x from 0 to −parallax) and stays under the incoming page',
    },
    'pop': {
      'durationMs': kPageMotionMs,
      'curve': kDecelerateCurve,
      'parallax': kPageParallax,
      'curveCss': _bezier(kDecelerateCurve),
      'outgoing': 'slides out to the end edge (x from 0 to 1) above the incoming page',
      'incoming': 'comes back from −parallax to 0 under it',
    },
    'direction':
        'x is a share of the screen width towards the end edge: right in a left-to-right language, left in a right-to-left one',
    'background': 'each page slides with its own screen background; no shadow and no dimming under the incoming page',
  },
  'sheet': {
    'open': {
      'durationMs': kSheetOpenMs,
      'curve': kDecelerateCurve,
      'curveCss': _bezier(kDecelerateCurve),
      'layer': 'rises from below by its own height (y from 1 to 0)',
    },
    'close': {
      'durationMs': kSheetCloseMs,
      'curve': kAccelerateCurve,
      'curveCss': _bezier(kAccelerateCurve),
      'layer': 'goes down by its own height (y from 0 to 1)',
    },
    'shape': 'a modal screen shown as a sheet at the bottom («modalShapeOf» is «sheet»)',
    'dragged':
        'a sheet dismissed by the drag gesture («x-sheetDismiss») has already reached the bottom: the pop plays nothing more',
  },
  'window': {
    'open': {
      'durationMs': kWindowOpenMs,
      'curve': kDecelerateCurve,
      'scaleFrom': kWindowScaleFrom,
      'curveCss': _bezier(kDecelerateCurve),
      'layer': 'opacity from 0 to 1, scale from «scaleFrom» to 1 around the centre of the window',
    },
    'close': {
      'durationMs': kWindowCloseMs,
      'curve': kAccelerateCurve,
      'curveCss': _bezier(kAccelerateCurve),
      'layer': 'opacity from 1 to 0, no scale',
    },
    'shape':
        'a window in the centre and a sheet shown as a window on a wide area («modalShapeOf» is «window» or «sheetWindow»)',
  },
  'fade': {
    'durationMs': kScreenFadeMs,
    'curve': kStandardFadeCurve,
    'curveCss': _bezier(kStandardFadeCurve),
    'page': 'the outgoing page fades out (opacity from 1 to 0) above the incoming page, which stands still',
    'layer': 'the layer only changes its opacity: from 0 to 1 when it opens, from 1 to 0 when it closes',
  },
  'scrim':
      'the scrim and the backdrop blur under a layer fade together with the layer on the same curve, from 0 to their resting opacity and back, when a page is on the other side; between two layers they stay',
  'section':
      'switching a section («navigate.section», a NavBar item) — no motion; «fade» on the target screen cross-dissolves, «none» keeps it at once',
  'notTransition': [
    'the first show of the document, a new entry, a stack rebuilt by the host',
    'reduced motion',
    'the editor canvas and thumbnails',
    'a step made under the swipe-button ripple that covers the screen («x-swipeConfirmMotion.ripple») — the ripple is the transition',
    'a sheet dismissed by the drag gesture',
  ],
  'interaction':
      'the outgoing screen catches no touch and leaves the accessibility tree from the first frame; the incoming screen is a control from the first frame; focus is handled as after any step',
  'interrupted':
      'a new step during a transition finishes the current one at once; the new transition starts from the final state — layers never pile up',
  'layers': 'the outgoing page lies under the incoming one on push and above it on pop and on a cross-dissolve',
  'visibilityFade':
      'a node with «visibilityTransition» stands in its rest state when its screen is shown («x-visibilityFade.notTransition»)',
  'olderReader': 'at once',
  'cases': 'contract/fixtures/screen-transition/screen-transition-cases.json',
};
