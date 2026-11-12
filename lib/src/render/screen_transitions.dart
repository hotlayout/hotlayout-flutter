/// How a screen of the flow replaces another one: the reader's motion between screens, not a
/// field of the document.
library;

import 'package:flutter/material.dart';

import '../model/screen_transition.dart';
import 'motion.dart';

/// Whether the screen flow animates its changes of screen.
///
/// The document says WHICH screen is shown and why (`entry`, `forward`, `back`, a section
/// switch); how one screen replaces another is up to the reader, the way a native app follows
/// its platform. Pass it to `renderDocument` as `transitions`.
enum HotlayoutTransitions {
  /// The default motion of the contract (the `transition` field of a screen refines it per screen):
  ///
  ///  * a page opened forward slides in from the end of the line over the previous one, which drifts
  ///    back by a third of the width; "back" plays it in reverse (300 ms, the same numbers on every
  ///    platform);
  ///  * a modal sheet rises from the bottom while the scrim (and the backdrop blur) thicken with it, and
  ///    goes down when closed; a centred window (and a sheet shown as a window on a wide area) fades in
  ///    from a slight zoom and fades out;
  ///  * a section switch has no motion, unless the screen asks for `fade`; the first screen, a new entry
  ///    and a new document appear without motion;
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

/// Whether the platform has the edge swipe back of a native navigation stack (iOS and macOS). The motion of a page step
/// is the contract's and the same everywhere; only this gesture follows the platform.
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

/// One page of a page transition (`push` or `pop` of the plan).
///
/// [progress] is how far the page on top is IN: it runs from 0 to 1 on a forward step and from 1
/// to 0 on a step back (and follows the finger during an edge swipe), so the same value drives
/// both pages. The share of time it stands for is `progress` forward and `1 - progress` back; the
/// curve and the numbers are the plan's.
class PageMotion extends StatelessWidget {
  const PageMotion({
    super.key,
    required this.role,
    required this.progress,
    required this.forward,
    required this.plan,
    required this.child,
  });

  final PageRole role;
  final Animation<double> progress;

  /// Whether this is a forward step (the page on top comes in). A step back plays the motion in reverse.
  final bool forward;

  /// The motion: `push` forward, `pop` back, at the speed the plan says, or constant (a finger drives it).
  final ScreenTransitionPlan plan;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      child: child,
      builder: (context, child) {
        final share = (forward ? progress.value : 1 - progress.value).clamp(0.0, 1.0);
        final frame = screenTransitionFrame(plan, share * plan.durationMs);
        // The page on top is the incoming one on a step forward and the outgoing one on a step back.
        final look = (role == PageRole.over) == forward ? frame.incoming : frame.outgoing;
        // The shift is toward the END of the line, in either direction of writing.
        final rtl = Directionality.of(context) == TextDirection.rtl;
        return FractionalTranslation(translation: Offset(rtl ? -look.x : look.x, 0), child: child);
      },
    );
  }
}
