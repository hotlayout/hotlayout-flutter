/// The one-time appearance of a node when its screen is shown (schema 9.40.0, `appear`): a paint over the box the node
/// has at rest.
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../model/node_appear.dart';
import 'node_motion.dart' show PaintRotation;

/// The window in which the nodes of a screen that ask to appear are SHOWN.
///
/// A screen is shown when its widgets are first built: the first screen, a page pushed on top, a page revealed again by
/// "back" or a section switch are all new screens. Closing a layer above leaves the screen under it built, so it is not a
/// show. A node that is mounted later, on a screen that is already shown (its condition starts to hold, the width class
/// changes, a record is added to a list), finds the window closed and stands at once. The window closes after the first
/// frame of the screen.
class AppearShow extends StatefulWidget {
  const AppearShow({super.key, required this.child});

  final Widget child;

  /// Whether the screen above [context] is in its show. `false` outside of any screen.
  static bool isOpen(BuildContext context) => context.getInheritedWidgetOfExactType<_AppearWindow>()?.window.open ?? false;

  @override
  State<AppearShow> createState() => _AppearShowState();
}

class _Window {
  bool open = true;
}

class _AppearWindow extends InheritedWidget {
  const _AppearWindow({required this.window, required super.child});

  final _Window window;

  @override
  bool updateShouldNotify(_AppearWindow oldWidget) => false;
}

class _AppearShowState extends State<AppearShow> {
  final _Window _window = _Window();

  @override
  void initState() {
    super.initState();
    // After the first frame of the screen, so that everything built with it is part of the show.
    WidgetsBinding.instance.addPostFrameCallback((_) => _window.open = false);
  }

  @override
  Widget build(BuildContext context) => _AppearWindow(window: _window, child: widget.child);
}

/// Draws [child] where [appear] puts it at the moment the screen was shown: invisible and in its place while the delay
/// runs, then fading in and, for `rise`, rising from below. The layout is untouched: the box stands where it stands at
/// rest and takes touches there from the first frame. The system "reduce motion" leaves the node at rest.
///
/// A node mounted when the screen is already shown ([AppearShow.isOpen] is `false`) is not wrapped at all.
class NodeAppearBox extends StatefulWidget {
  const NodeAppearBox({super.key, required this.appear, required this.child});

  final NodeAppear appear;
  final Widget child;

  @override
  State<NodeAppearBox> createState() => _NodeAppearBoxState();
}

class _NodeAppearBoxState extends State<NodeAppearBox> with SingleTickerProviderStateMixin {
  late final bool _playsAtShow = AppearShow.isOpen(context);
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<double> _elapsedMs = ValueNotifier<double>(0);
  bool _reduced = false;

  void _onTick(Duration elapsed) {
    _elapsedMs.value = elapsed.inMicroseconds / 1000;
    // Over: the node is at rest, nothing more to draw.
    if (_elapsedMs.value >= widget.appear.endsAt) _ticker.stop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!_playsAtShow || _reduced) {
      if (_ticker.isActive) _ticker.stop();
    } else if (!_ticker.isActive && _elapsedMs.value < widget.appear.endsAt) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _elapsedMs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_playsAtShow) return widget.child;
    final turned = PaintRotation.of(context) * math.pi / 180;
    return ValueListenableBuilder<double>(
      valueListenable: _elapsedMs,
      child: widget.child,
      builder: (context, ms, child) {
        final pose = appearPoseAt(widget.appear, ms, reducedMotion: _reduced);
        // The shift goes along the screen vertical: undo the rotation the frame was painted with.
        return Opacity(
          opacity: pose.opacity.clamp(0.0, 1.0),
          // The node is still a node the person can find while it is not yet visible.
          alwaysIncludeSemantics: true,
          child: Transform.translate(
            offset: Offset(pose.y * math.sin(turned), pose.y * math.cos(turned)),
            // The press area stays where the box is at rest.
            transformHitTests: false,
            child: child,
          ),
        );
      },
    );
  }
}
