import 'node.dart';

// A node fading in and out when its `visibleIf` changes (schema 9.33.0, `visibilityTransition: 'fade'`,
// `x-visibilityFade`).
//
// Mirrors the reference implementation `visibility-fade.ts`. The rows of
// `fixtures/visibility-fade/visibility-fade-cases.json` run these functions (`visibility_fade_cases_test.dart`).
//
// Every node follows its own timeline, with no pairing: a leaving node stays in the layout and fades for `out`, then
// leaves it; an appearing node waits `out` out of the layout, then enters it transparent and fades in for `in`. An
// interrupted change goes to the new goal from the current opacity. The clock comes from the caller; the widgets of
// `render/visibility_fade_scope.dart` provide it.

/// The field of the node.
const String kVisibilityTransitionKey = 'visibilityTransition';

/// The only word of the field.
const String kVisibilityTransitionFade = 'fade';

/// Fade out: milliseconds and the cubic Bezier (x1, y1, x2, y2).
const double kVisibilityFadeOutMs = 120;
const List<double> kVisibilityFadeOutCurve = [0.4, 0, 1, 1];

/// Fade in: milliseconds, the cubic Bezier, and the wait out of the layout before it (the length of the fade out).
const double kVisibilityFadeInMs = 160;
const List<double> kVisibilityFadeInCurve = [0, 0, 0.2, 1];
const double kVisibilityFadeInDelayMs = kVisibilityFadeOutMs;

/// The field as the reader reads it: only the word `fade`, anything else is no field.
bool readsVisibilityFade(Object? value) => value == kVisibilityTransitionFade;

/// The phases of a node with the field: `shown` (in the layout, opacity 1), `leaving` (in the layout, fading, no
/// presses, not heard), `hidden` (out), `waiting` (out, waits for the neighbours to fade) and `entering` (in the
/// layout, fading in, a control).
enum VisibilityFadePhase { shown, leaving, hidden, waiting, entering }

/// Whether a node in [phase] stands in the layout.
bool visibilityFadeInLayout(VisibilityFadePhase phase) =>
    phase == VisibilityFadePhase.shown || phase == VisibilityFadePhase.leaving || phase == VisibilityFadePhase.entering;

/// The state of one node: the phase, the moment it began (milliseconds of the caller's clock) and the opacity it
/// began with (`leaving`, `entering`: an interruption starts from the current one).
final class VisibilityFadeState {
  const VisibilityFadeState(this.phase, this.since, this.from);

  final VisibilityFadePhase phase;
  final double since;
  final double from;

  @override
  bool operator ==(Object other) =>
      other is VisibilityFadeState && other.phase == phase && other.since == since && other.from == from;

  @override
  int get hashCode => Object.hash(phase, since, from);

  @override
  String toString() => 'VisibilityFadeState($phase, since: $since, from: $from)';
}

/// What a node draws at a moment.
final class VisibilityFadeFrame {
  const VisibilityFadeFrame({required this.phase, required this.inLayout, required this.opacity, required this.interactive});

  final VisibilityFadePhase phase;
  final bool inLayout;
  final double opacity;

  /// It catches presses and is heard by a screen reader.
  final bool interactive;
}

/// The state of rest: how a node stands at the first show and after any change made "at once".
VisibilityFadeState visibilityFadeRest(bool shown, [double now = 0]) =>
    VisibilityFadeState(shown ? VisibilityFadePhase.shown : VisibilityFadePhase.hidden, now, shown ? 1 : 0);

double _bezierCoord(double t, double a, double b) =>
    3 * a * t * (1 - t) * (1 - t) + 3 * b * t * t * (1 - t) + t * t * t;

/// The cubic Bezier through (0,0) and (1,1): y for x, by bisection on the curve parameter.
double cubicBezierAt(List<double> curve, double x) {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  var lo = 0.0;
  var hi = 1.0;
  var t = x;
  for (var i = 0; i < 40; i += 1) {
    final value = _bezierCoord(t, curve[0], curve[2]) - x;
    if (value.abs() < 1e-9) break;
    if (value > 0) {
      hi = t;
    } else {
      lo = t;
    }
    t = (lo + hi) / 2;
  }
  return _bezierCoord(t, curve[1], curve[3]);
}

double _leavingSpan(VisibilityFadeState state) => kVisibilityFadeOutMs * state.from;
double _enteringSpan(VisibilityFadeState state) => kVisibilityFadeInMs * (1 - state.from);

/// The moment the current phase ends by itself; `null` for a phase of rest.
double? visibilityFadeEndsAt(VisibilityFadeState state) => switch (state.phase) {
  VisibilityFadePhase.leaving => state.since + _leavingSpan(state),
  VisibilityFadePhase.waiting => state.since + kVisibilityFadeInDelayMs,
  VisibilityFadePhase.entering => state.since + _enteringSpan(state),
  _ => null,
};

/// The state at [now]: phases that ended pass on (`leaving → hidden`, `waiting → entering → shown`).
VisibilityFadeState visibilityFadeSettle(VisibilityFadeState state, double now) {
  var current = state;
  for (;;) {
    final end = visibilityFadeEndsAt(current);
    if (end == null || now < end) return current;
    current = switch (current.phase) {
      VisibilityFadePhase.leaving => VisibilityFadeState(VisibilityFadePhase.hidden, end, 0),
      VisibilityFadePhase.waiting => VisibilityFadeState(VisibilityFadePhase.entering, end, 0),
      _ => VisibilityFadeState(VisibilityFadePhase.shown, end, 1),
    };
  }
}

/// The frame at [now]: the phase, whether the node is in the layout, its opacity and whether it is a control.
VisibilityFadeFrame visibilityFadeAt(VisibilityFadeState state, double now) {
  final settled = visibilityFadeSettle(state, now);
  switch (settled.phase) {
    case VisibilityFadePhase.shown:
      return const VisibilityFadeFrame(phase: VisibilityFadePhase.shown, inLayout: true, opacity: 1, interactive: true);
    case VisibilityFadePhase.hidden:
      return const VisibilityFadeFrame(phase: VisibilityFadePhase.hidden, inLayout: false, opacity: 0, interactive: false);
    case VisibilityFadePhase.waiting:
      return const VisibilityFadeFrame(phase: VisibilityFadePhase.waiting, inLayout: false, opacity: 0, interactive: false);
    case VisibilityFadePhase.leaving:
      final span = _leavingSpan(settled);
      final p = span <= 0 ? 1.0 : (now - settled.since) / span;
      return VisibilityFadeFrame(
        phase: VisibilityFadePhase.leaving,
        inLayout: true,
        opacity: settled.from * (1 - cubicBezierAt(kVisibilityFadeOutCurve, p)),
        interactive: false,
      );
    case VisibilityFadePhase.entering:
      final span = _enteringSpan(settled);
      final p = span <= 0 ? 1.0 : (now - settled.since) / span;
      return VisibilityFadeFrame(
        phase: VisibilityFadePhase.entering,
        inLayout: true,
        opacity: settled.from + (1 - settled.from) * cubicBezierAt(kVisibilityFadeInCurve, p),
        interactive: true,
      );
  }
}

/// The condition of the node became [shown] at [now]. `animate: false` — the change is "at once": the state of rest of
/// the new goal.
VisibilityFadeState visibilityFadeChange(VisibilityFadeState state, bool shown, double now, {required bool animate}) {
  if (!animate) return visibilityFadeRest(shown, now);
  final settled = visibilityFadeSettle(state, now);
  final opacity = visibilityFadeAt(settled, now).opacity;
  if (shown) {
    if (settled.phase == VisibilityFadePhase.hidden) return VisibilityFadeState(VisibilityFadePhase.waiting, now, 0);
    if (settled.phase == VisibilityFadePhase.leaving) return VisibilityFadeState(VisibilityFadePhase.entering, now, opacity);
    return settled;
  }
  if (settled.phase == VisibilityFadePhase.shown || settled.phase == VisibilityFadePhase.entering) {
    return VisibilityFadeState(VisibilityFadePhase.leaving, now, opacity);
  }
  if (settled.phase == VisibilityFadePhase.waiting) return visibilityFadeRest(false, now);
  return settled;
}

/// The zones of the screen read no fade: they follow their condition at once. A zone is a navigation bar or its item,
/// a node with the `pin` field of ANY value (`bottom` and `top` alike), and an `AppBar` that is the FIRST child of the
/// screen root. An `AppBar` that is not first is no zone: it fades.
bool isScreenZoneNode(String type, {required bool pinned, required bool firstOfScreenRoot}) =>
    type == 'NavBar' || type == 'NavItem' || pinned || (type == 'AppBar' && firstOfScreenRoot);

/// The nodes that carry the field and are read: a `visibleIf` stands on them and they are no zone.
final Expando<bool> _fading = Expando<bool>('visibilityFade');

/// Marks [node] as one that fades (the parser calls it when the word, a condition and no zone are all there).
void markVisibilityFade(ChildNode node) => _fading[node] = true;

/// Takes the mark off: the node turned out to be the app bar zone of a screen root.
void unmarkVisibilityFade(ChildNode node) => _fading[node] = null;

/// Whether [node] fades when its condition changes.
bool fadesOnChange(ChildNode node) => _fading[node] == true;

/// Mirror of the `x-visibilityFade` block. Values are checked against the artifact by `visibility_fade_cases_test.dart`.
const Map<String, Object?> kVisibilityFadeRules = {
  'field': kVisibilityTransitionKey,
  'words': [kVisibilityTransitionFade],
  'value':
      '«fade» — the node fades when its «visibleIf» changes on the shown screen; no field — it appears and disappears at once',
  'out': {
    'durationMs': kVisibilityFadeOutMs,
    'curve': kVisibilityFadeOutCurve,
    'when': 'the condition of a shown node stops holding',
    'layout': 'the node keeps its place while it fades and leaves the layout when it ends',
  },
  'in': {
    'durationMs': kVisibilityFadeInMs,
    'curve': kVisibilityFadeInCurve,
    'delayMs': kVisibilityFadeInDelayMs,
    'when': 'the condition of a hidden node starts to hold',
    'layout': 'the node waits «delayMs» out of the layout, then enters it with opacity 0 and fades in',
  },
  'pair':
      'no pairing: every node follows its own timeline; two neighbours with mutually exclusive conditions are both invisible at «delayMs» and the layout changes once, at that moment',
  'interrupted':
      'a change during a transition goes to the new goal from the current opacity, the duration scaled by the distance (out × opacity, in × (1 − opacity)); a node still waiting out of the layout stays hidden',
  'interaction':
      'a leaving node catches no press and leaves the accessibility tree at once; an entering node is a control from the moment it enters the layout',
  'notTransition': [
    'the first show of the screen',
    'going back to a screen',
    'a change of the language or of the width class («showOn»)',
    'reduced motion',
    'the editor canvas',
  ],
  'scope':
      'the box of the node with its subtree; the zones of the screen (app bar, pinned block, navigation bar) and the drawn navigation items follow the condition at once',
  'notRead':
      'a node without «visibleIf», the first child of the screen root that is an AppBar, a pinned node, a NavBar and a NavItem',
  'olderReader': 'at once',
  'cases': 'contract/fixtures/visibility-fade/visibility-fade-cases.json',
};
