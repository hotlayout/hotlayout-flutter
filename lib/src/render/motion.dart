import 'package:flutter/widgets.dart';

/// The renderer's motion: durations and curves in one place.
///
/// Why this is not in the contract: the contract says WHAT to show; how it appears is up to
/// the reader. A web reader of the same document may animate nothing, and the document does
/// not become different. So there is no version or artifact here: this is implementation
/// quality, not an agreement between platforms.
///
/// Why one file rather than numbers in place: motion is a language too. A modal sliding in over
/// 220 ms and a block expanding over 400 read as two different apps. Numbers scattered across
/// call sites drift apart first: that is what happened with `AnimatedRotation` in the
/// accordion block, where the arrow turned smoothly while the content below it appeared with a
/// jump.
///
/// Why these durations: one for small things (arrow, tab underline, panel cross-fade), one for
/// large ones (a half-screen modal sheet, a section cross-fade), and one for a whole page crossing
/// the screen, close to what both platforms use for their own navigation. A large object moving
/// in the same time as a small one reads as a jerk: the eye follows distance, not time.
abstract final class Motion {
  /// Small motion: rotation, underline, panel cross-fade.
  static const Duration quick = Duration(milliseconds: 150);

  /// Large motion: a modal sheet appearing.
  static const Duration sheet = Duration(milliseconds: 220);

  /// A whole page crossing the screen: a step forward or back in the flow.
  static const Duration page = Duration(milliseconds: 300);

  /// Entry: fast start, soft braking, so the object "arrives" and stops.
  static const Curve enter = Curves.easeOutCubic;

  /// Leaving: a soft start that gathers speed, so the object "goes away" rather than stops.
  static const Curve exit = Curves.easeInCubic;

  /// Change in place (size, opacity): no jerk at either end.
  static const Curve standard = Curves.easeInOut;
}

/// A duration adjusted for the system "reduce motion" setting.
///
/// This is an accessibility matter, not a nicety: people who turn that switch on do so because
/// motion physically bothers them (vestibular disorders), and an app that ignores it is
/// unusable for them.
///
/// Zero rather than "do not animate at all": every animation widget stays in place and behaves
/// as usual, so no render branch forks and exactly one number changes.
Duration motionOf(BuildContext context, Duration duration) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false
    ? Duration.zero
    : duration;
