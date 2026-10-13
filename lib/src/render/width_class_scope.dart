// Measures the screen box and gives the subtree its width class; the content
// column of a screen.
library;

import 'package:flutter/material.dart';

import '../model/width_class.dart';

/// Measures the width class of the screen box (schema 9.18.0).
///
/// Uses `LayoutBuilder`, not `MediaQuery.sizeOf`: it measures the box this screen is painted
/// in, not the window, because the widget may occupy only part of a tablet screen. An unbounded
/// width (scrolling, `Row`) means "unknown" and gives `compact`. The built subtree is kept
/// until the class or the widget itself changes, so a change of box height alone (keyboard
/// animation) does not rebuild the screen.
class WidthClassScope extends StatefulWidget {
  const WidthClassScope({super.key, required this.builder});

  final Widget Function(BuildContext context, WidthClass widthClass) builder;

  @override
  State<WidthClassScope> createState() => _WidthClassScopeState();
}

class _WidthClassScopeState extends State<WidthClassScope> {
  WidthClass? _class;
  Widget? _built;

  @override
  void didUpdateWidget(WidthClassScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _built = null;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final widthClass = widthClassOf(constraints.maxWidth);
      if (_built == null || _class != widthClass) {
        _class = widthClass;
        _built = widget.builder(context, widthClass);
      }
      return _built!;
    },
  );
}

/// Content column no wider than `contentMaxWidth`, centred (schema 9.18.0).
///
/// Adds a symmetric side inset of half the remainder (`screenContentBox`, not rounded), the
/// same in both writing directions. With no limit, in an unbounded box, or in a box narrower
/// than the limit, the widget changes nothing.
class ContentColumn extends StatelessWidget {
  const ContentColumn({super.key, required this.maxWidth, required this.child});

  final int? maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final max = maxWidth;
    if (max == null) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth) return child;
        final inset = screenContentBox(constraints.maxWidth, max).start;
        return inset == 0 ? child : Padding(padding: EdgeInsetsDirectional.symmetric(horizontal: inset), child: child);
      },
    );
  }
}
