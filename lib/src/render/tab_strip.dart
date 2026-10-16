/// The strip of tab titles whose indicator slides to the open title.
library;

import 'package:flutter/material.dart';

import 'layout/quiet_flex.dart';
import 'motion.dart';
import 'screen_transitions.dart';

/// Key of the indicator while it slides between two titles, for tests.
@visibleForTesting
const Key kTabIndicatorKey = ValueKey<String>('hotlayout-tab-indicator');

/// The titles of a tab group in one row, with an indicator under the open one.
///
/// At rest every title draws its own indicator (transparent when closed), so the strip has the
/// same geometry as without motion. When another tab opens, the titles hide theirs for a moment
/// and ONE indicator slides from the old title to the new one, changing its width on the way:
/// a strip where the underline jumps reads as two separate controls.
class TabStrip extends StatefulWidget {
  const TabStrip({
    super.key,
    required this.open,
    required this.count,
    required this.gap,
    required this.indicatorColor,
    required this.indicatorThickness,
    required this.title,
  });

  final int open;
  final int count;

  /// The gap between two titles.
  final double gap;

  final Color indicatorColor;
  final double indicatorThickness;

  /// One title; [indicator] says whether the title draws its own indicator if it is open.
  final Widget Function(int index, {required bool indicator}) title;

  @override
  State<TabStrip> createState() => _TabStripState();
}

class _TabStripState extends State<TabStrip> with SingleTickerProviderStateMixin {
  final GlobalKey _row = GlobalKey(debugLabel: 'hotlayout-tab-strip');
  late List<GlobalKey> _titles = _keys(widget.count);
  late final AnimationController _slide = AnimationController(vsync: this);
  Rect? _from;
  Rect? _to;

  static List<GlobalKey> _keys(int count) =>
      List.generate(count, (index) => GlobalKey(debugLabel: 'hotlayout-tab-title-$index'));

  @override
  void initState() {
    super.initState();
    _slide.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) setState(() => _from = _to = null);
    });
  }

  @override
  void didUpdateWidget(TabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != widget.count) {
      _titles = _keys(widget.count);
      _stop();
      return;
    }
    if (oldWidget.open == widget.open) return;
    final duration = transitionDurationOf(context, Motion.quick);
    // The titles are laid out already (the last frame), so both ends of the way are known now.
    final from = _slide.isAnimating ? _currentRect : _indicatorOf(oldWidget.open);
    final to = _indicatorOf(widget.open);
    if (duration == Duration.zero || from == null || to == null) {
      _stop();
      return;
    }
    _from = from;
    _to = to;
    _slide
      ..duration = duration
      ..forward(from: 0);
  }

  void _stop() {
    _slide.stop();
    _from = _to = null;
  }

  Rect? get _currentRect {
    final from = _from;
    final to = _to;
    if (from == null || to == null) return null;
    return Rect.lerp(from, to, Motion.standard.transform(_slide.value));
  }

  /// The indicator's rectangle under title [index], in the row's coordinates.
  Rect? _indicatorOf(int index) {
    if (index < 0 || index >= _titles.length) return null;
    final row = _row.currentContext?.findRenderObject();
    final title = _titles[index].currentContext?.findRenderObject();
    if (row is! RenderBox || title is! RenderBox || !row.hasSize || !title.hasSize) return null;
    final box = MatrixUtils.transformRect(title.getTransformTo(row), Offset.zero & title.size);
    return Rect.fromLTRB(box.left, box.bottom - widget.indicatorThickness, box.right, box.bottom);
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _slide,
    builder: (context, _) {
      final moving = _currentRect;
      return Stack(
        key: _row,
        children: [
          QuietRow(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < widget.count; index += 1) ...[
                if (index > 0) SizedBox(width: widget.gap),
                KeyedSubtree(
                  key: _titles[index],
                  child: widget.title(index, indicator: moving == null),
                ),
              ],
            ],
          ),
          if (moving != null)
            Positioned.fromRect(
              rect: moving,
              child: IgnorePointer(
                child: ColoredBox(key: kTabIndicatorKey, color: widget.indicatorColor),
              ),
            ),
        ],
      );
    },
  );
}
