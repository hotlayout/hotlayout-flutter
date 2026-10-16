/// A value that leads to its new value (schema 9.21.0, `animateChanges`): the hook between the node and
/// [ValueTransition].
library;

import 'package:flutter/widgets.dart';

import '../../model/node.dart';
import '../../model/node_style.dart';
import '../../model/progress_rules.dart';
import '../../model/value_transition.dart';
import '../node_renderer.dart';
import '../render_scope.dart' show Slot;
import '../value_transition.dart';
import 'progress.dart';
import 'text.dart';

extension TransitionWidgets on NodeRenderer {
  /// The body of a node that asks to lead its numbers (`animateChanges: true`), or the plain body when the node
  /// does not (no field, or nothing that comes from data: a literal is changed only by a new document, and a
  /// new document is a first show).
  Widget buildLeading(ChildNode node, NodeStyle? own, Slot slot) {
    final targets = animatesChanges(node) ? transitionTargetsOf(node) : const <TransitionTarget>[];
    if (targets.isEmpty) return _plain(node, this, own, slot);
    final record = recordIdentityOf(data.record);
    return ValueTransition(
      // A list instance is tracked by its record: a state moves with it when the list is reordered.
      key: record == null ? null : ValueKey('lead|${node.id}|$record'),
      targets: targets,
      data: data,
      identity: record ?? instance.join('/'),
      localeKey: '$locale|${strings.locale}',
      builder: (context, shown, active) =>
          _announce(node, active, _plain(node, shown == data ? this : copy(data: shown), own, slot)),
    );
  }

  Widget _plain(ChildNode node, NodeRenderer renderer, NodeStyle? own, Slot slot) => switch (node) {
    TextNode() => renderer.buildText(node, own),
    ProgressBarNode() => renderer.buildProgressBar(node),
    CircularProgressNode() => renderer.buildCircularProgress(node, own, slot),
    _ => const SizedBox.shrink(),
  };

  /// What the screen reader hears: the FINAL value while the shown one is between values, never the numbers in
  /// between (`semantics`). The widgets keep one shape whether a number is between values or not.
  Widget _announce(ChildNode node, bool active, Widget child) {
    final String? spoken = switch (node) {
      TextNode(:final content) => active ? text(content) : null,
      ProgressBarNode(:final value, :final max) || CircularProgressNode(:final value, :final max) =>
        active ? '${(progressRatio(value.resolve(data), max.resolve(data)) * 100).round()}' : null,
      _ => null,
    };
    final isText = node is TextNode;
    return Semantics(
      label: isText ? spoken : null,
      value: isText ? null : spoken,
      child: ExcludeSemantics(excluding: active, child: child),
    );
  }
}

/// Whether the node carries the flag. Only the literal `true` is read.
bool animatesChanges(ChildNode node) => switch (node) {
  TextNode(:final animateChanges) => animateChanges,
  ProgressBarNode(:final animateChanges) => animateChanges,
  CircularProgressNode(:final animateChanges) => animateChanges,
  _ => false,
};

/// The identity of the record a list instance is drawn for: the values under the keys of the form `item.id`.
/// `null` when the record has none (then the instance is told apart by its place in the list).
String? recordIdentityOf(Map<String, Object?>? record) {
  if (record == null) return null;
  final ids = [
    for (final entry in record.entries)
      if (RegExp(r'^[^.]+\.id$').hasMatch(entry.key) && (entry.value is String || entry.value is num)) '${entry.key}=${entry.value}',
  ]..sort();
  return ids.isEmpty ? null : ids.join(';');
}
