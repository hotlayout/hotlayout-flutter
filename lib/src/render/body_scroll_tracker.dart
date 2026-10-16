import 'package:flutter/widgets.dart';

import '../model/scrolled_bar.dart';

/// What the body of a screen tells the app bar zone: the controller of its scroll view, the key of the bar
/// zone (to measure its bottom edge) and whether the bar counts as scrolled now.
typedef BodyScroll = ({ScrollController controller, GlobalKey barKey, bool scrolled});

/// Follows the scroll of ONE screen's body for the app bar that changes on scroll (schema 9.21.0,
/// `appBarScrolled`).
///
/// It listens to the `ScrollController` of the body's own scroll view, not to a `NotificationListener` above
/// it: that one would also hear the scrolling rows nested in the body. The threshold is
/// `scrollTop > max(0, barBottom - bodyTop)` ([isBarScrolled]); the bar's bottom edge is measured from its
/// zone, so the number is the one the user sees whatever the safe inset and the bar's padding are.
///
/// The widget is always in the tree of a screen, tracking or not: a bar that a condition shows and hides
/// must not rebuild the scroll view (its position, its fields) with it.
class BodyScrollTracker extends StatefulWidget {
  const BodyScrollTracker({
    super.key,
    required this.tracking,
    required this.bodyAtScreenTop,
    required this.overlap,
    required this.builder,
  });

  /// Whether the app bar zone has anything to change on scroll.
  final bool tracking;

  /// The body area starts at the top edge of the screen (`bodyTop: 'screenTop'`), so `bodyTop` is zero.
  final bool bodyAtScreenTop;

  /// How far a pulled first child raises the body area over the bar.
  final double overlap;

  final Widget Function(BuildContext context, BodyScroll scroll) builder;

  @override
  State<BodyScrollTracker> createState() => _BodyScrollTrackerState();
}

class _BodyScrollTrackerState extends State<BodyScrollTracker> {
  final ScrollController _controller = ScrollController();
  final GlobalKey _barKey = GlobalKey(debugLabel: 'hl-bar-zone');
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_update);
  }

  @override
  void didUpdateWidget(BodyScrollTracker old) {
    super.didUpdateWidget(old);
    if (!widget.tracking) {
      _scrolled = false;
    } else if (!old.tracking || old.bodyAtScreenTop != widget.bodyAtScreenTop || old.overlap != widget.overlap) {
      // A bar that just appeared (or a threshold that moved) is judged by the scroll the body already has, once
      // the new layout has measured it.
      WidgetsBinding.instance.addPostFrameCallback((_) => _update());
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_update)
      ..dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted || !widget.tracking || !_controller.hasClients) return;
    final barBottom = (_barKey.currentContext?.findRenderObject() as RenderBox?)?.size.height;
    if (barBottom == null) return;
    // The scroll view is the body's; its `offset` is how far it is scrolled in logical pixels.
    final scrolled = isBarScrolled(
      _controller.offset,
      barBottom: barBottom,
      bodyTop: widget.bodyAtScreenTop ? 0 : barBottom - widget.overlap,
    );
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, (controller: _controller, barKey: _barKey, scrolled: widget.tracking && _scrolled));
}
