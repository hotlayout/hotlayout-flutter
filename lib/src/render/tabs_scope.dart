// Holds which tab of a tab group is open.
library;

import 'package:flutter/material.dart';

import 'choice_scope.dart';

/// Which tab of a group is open. State lives in the same node that owns it.
///
/// The same reason as for [ChoiceGroupScope]: if the tab were addressed by the node `id` in some
/// shared store, two bars with the same `id` on different screens would silently share one
/// switch.
///
/// The document does not change and nothing goes to the store: `initialTab` is the INITIAL
/// state, not a mirror of the current one.
class TabsScope extends StatefulWidget {
  const TabsScope({
    required this.initialTab,
    required this.tabCount,
    required this.builder,
    super.key,
  });

  final int initialTab;

  /// How many VISIBLE panels the bar has right now. Needed so that an index from the document
  /// does not outlive a tab that disappeared through its visibility condition.
  final int tabCount;

  final Widget Function(int open, ValueChanged<int> select) builder;

  @override
  State<TabsScope> createState() => _TabsScopeState();
}

class _TabsScopeState extends State<TabsScope> {
  late int _open = widget.initialTab;

  @override
  void didUpdateWidget(covariant TabsScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The document wins over the finger: a different `initialTab` means a new document or other
    // data, and the earlier choice is no longer about it.
    if (oldWidget.initialTab != widget.initialTab) _open = widget.initialTab;
    // The tab may have disappeared through its visibility condition while it was open. The index
    // would then point into nothing, so the bar must show something that exists.
    if (_open >= widget.tabCount) _open = 0;
  }

  @override
  Widget build(BuildContext context) => widget.builder(_open, _select);

  void _select(int index) => setState(() => _open = index);
}
