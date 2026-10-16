/// How a screen of the flow replaces another one: the reader's motion between screens, not a
/// field of the document.
library;

import 'package:flutter/cupertino.dart' show CupertinoPageTransition;
import 'package:flutter/material.dart';

import 'motion.dart';

/// Whether the screen flow animates its changes of screen.
///
/// The document says WHICH screen is shown and why (`entry`, `forward`, `back`, a section
/// switch); how one screen replaces another is up to the reader, the way a native app follows
/// its platform. Pass it to `renderDocument` as `transitions`.
enum HotlayoutTransitions {
  /// The motion of the platform the app runs on (`Theme.of(context).platform`):
  ///
  ///  * a page opened forward slides in from the end of the line over the previous one; on iOS
  ///    and macOS as a native navigation push (the previous page drifts a third of the way
  ///    back), elsewhere as the Material "fade forwards" transition; "back" plays it in reverse;
  ///  * a modal sheet rises from the bottom while the scrim (and the backdrop blur) thicken with
  ///    it, and sinks back when closed; a centred window grows from 96 % while it fades in;
  ///  * a section switch of the navigation bar is a short cross-fade; parts that are the same on
  ///    both screens (the app bar, the navigation bar) do not move;
  ///  * the first screen, a new entry and a new document appear without motion;
  ///  * the panel of a tab group cross-fades and its indicator slides to the open title.
  ///
  /// On iOS and macOS a swipe from the leading edge of the screen goes back one page, following
  /// the finger, like a native navigation stack.
  ///
  /// The system "reduce motion" setting (`MediaQuery.disableAnimations`) always wins: every change
  /// is then instant and the edge swipe is off.
  platform,

  /// No motion at all: every change of screen, modal layer and tab is instant, and there is no
  /// edge swipe. For a host that runs its own transitions around the flow, or for tests that
  /// do not want to wait.
  none,
}

/// The transitions the flow below runs with, for the widgets that animate on their own (tabs).
class TransitionsScope extends InheritedWidget {
  const TransitionsScope({super.key, required this.transitions, required super.child});

  final HotlayoutTransitions transitions;

  /// The transitions of the closest flow; [HotlayoutTransitions.platform] outside of any.
  static HotlayoutTransitions of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TransitionsScope>()?.transitions ??
      HotlayoutTransitions.platform;

  @override
  bool updateShouldNotify(TransitionsScope oldWidget) => oldWidget.transitions != transitions;
}

/// A duration for a transition of the flow: zero when the host turned transitions off or the
/// system asks for no motion.
Duration transitionDurationOf(BuildContext context, Duration duration) =>
    TransitionsScope.of(context) == HotlayoutTransitions.none ? Duration.zero : motionOf(context, duration);

/// Whether pages move the way iOS moves them (a horizontal push with parallax and an edge swipe
/// back) rather than the Material way.
bool cupertinoPagesOf(BuildContext context) => switch (Theme.of(context).platform) {
  TargetPlatform.iOS || TargetPlatform.macOS => true,
  _ => false,
};

/// The role of a page in a page transition.
enum PageRole {
  /// The page on top: the one that comes in on a forward step, or leaves on a step back.
  over,

  /// The page beneath: the one that is covered on a forward step, or revealed on a step back.
  under,
}

/// One page of a page transition.
///
/// [progress] is how far the page on top is IN: it runs from 0 to 1 on a forward step and from 1
/// to 0 on a step back (and follows the finger during an edge swipe), so the same value drives
/// both pages, the way a route's animation and its secondary animation do.
class PageMotion extends StatelessWidget {
  const PageMotion({
    super.key,
    required this.role,
    required this.progress,
    required this.forward,
    required this.cupertino,
    required this.linear,
    required this.child,
  });

  final PageRole role;
  final Animation<double> progress;

  /// Whether this is a forward step (the page on top comes in). A step back plays the motion in
  /// reverse, with the curves of a step back.
  final bool forward;

  /// iOS motion rather than Material.
  final bool cupertino;

  /// A transition driven by the finger: linear, so the page stays under it.
  final bool linear;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (cupertino) {
      return CupertinoPageTransition(
        primaryRouteAnimation: role == PageRole.over ? progress : kAlwaysCompleteAnimation,
        secondaryRouteAnimation: role == PageRole.under ? progress : kAlwaysDismissedAnimation,
        linearTransition: linear,
        child: child,
      );
    }
    return AnimatedBuilder(
      animation: progress,
      child: child,
      builder: (context, child) {
        final look = materialPageLook(role: role, progress: progress.value, forward: forward);
        return FadeTransition(
          opacity: AlwaysStoppedAnimation(look.opacity),
          child: FractionalTranslation(
            // The shift is along the line: from the end of the line in either direction of writing.
            translation: Offset(Directionality.of(context) == TextDirection.rtl ? -look.shift : look.shift, 0),
            child: child,
          ),
        );
      },
    );
  }
}

/// The Material "fade forwards" page transition (the Android default of Flutter's own routes), by
/// role: the page on top comes in from a quarter of its width toward the end of the line while
/// fading in over the first three quarters; the page beneath drifts a quarter of its width back
/// while fading out over the first quarter. A step back is the same in reverse.
///
/// [shift] is a fraction of the page width toward the END of the line (negative: toward the start).
({double opacity, double shift}) materialPageLook({
  required PageRole role,
  required double progress,
  required bool forward,
}) {
  const curve = Curves.easeInOutCubicEmphasized;
  const fadeIn = Interval(0, 0.75);
  const fadeOut = Interval(0, 0.25);
  final p = progress.clamp(0.0, 1.0);
  // How far the transition has run, whichever way it runs.
  final run = forward ? p : 1 - p;
  return switch ((role, forward)) {
    (PageRole.over, true) => (opacity: fadeIn.transform(run), shift: 0.25 * (1 - curve.transform(run))),
    (PageRole.over, false) => (opacity: 1 - fadeOut.transform(run), shift: 0.25 * curve.transform(run)),
    (PageRole.under, true) => (opacity: 1 - fadeOut.transform(run), shift: -0.25 * curve.transform(run)),
    (PageRole.under, false) => (opacity: fadeIn.transform(run), shift: -0.25 * (1 - curve.transform(run))),
  };
}

/// The opacities of a section switch at [progress]: the new screen fades in over the first 60 %
/// while the old one stays whole beneath it, and only then the old one fades out.
///
/// Why not a plain cross-fade: two half-transparent copies of the same opaque app bar over each
/// other are lighter than one, so the bar would flash although both screens draw it the same.
/// With the old screen whole beneath, every part that is the same on both screens stays exactly
/// as it was; only what differs cross-fades. The old screen fading out at the end matters only
/// where the new one is transparent.
({double incoming, double outgoing}) sectionSwitchLook(double progress) {
  final p = progress.clamp(0.0, 1.0);
  return (
    incoming: Curves.easeOut.transform((p / 0.6).clamp(0.0, 1.0)),
    outgoing: 1 - Curves.easeIn.transform(((p - 0.6) / 0.4).clamp(0.0, 1.0)),
  );
}
