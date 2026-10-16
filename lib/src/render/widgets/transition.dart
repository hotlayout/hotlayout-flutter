/// A value that leads to its new value (schema 9.21.0, `animateChanges`) or grows from zero when shown (9.24.0,
/// `animateIn`): the hook between the node and [ValueTransition].
library;

import 'package:flutter/widgets.dart';

import '../../model/bindable.dart';
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
    final changes = animatesChanges(node) ? transitionTargetsOf(node) : const <TransitionTarget>[];
    final appearing = animatesIn(node) ? appearTargetsOf(node) : const <TransitionTarget>[];
    if (changes.isEmpty && appearing.isEmpty) return _plain(node, this, own, slot);
    // The literal value of a scale that appears is read through a data path of its own, so the shown value can
    // lie over it; without a shown value the path is empty and the literal itself is the fallback.
    final literalScale = appearing.any((target) => target.path == kScaleLiteralKey);
    final literal = switch (node) {
      ProgressBarNode(:final value) when literalScale => value.resolve(data),
      CircularProgressNode(:final value) when literalScale => value.resolve(data),
      _ => null,
    };
    final drawn = literal == null
        ? node
        : switch (node) {
            ProgressBarNode(:final value) => node.withValue(_literalPath(value, literal)),
            CircularProgressNode(:final value) => node.withValue(_literalPath(value, literal)),
            _ => node,
          };
    final targets = [
      ...appearing,
      for (final target in changes)
        if (!appearing.any((other) => other.path == target.path)) target,
    ];
    final record = recordIdentityOf(data.record);
    return ValueTransition(
      // A list instance is tracked by its record: a state moves with it when the list is reordered.
      key: record == null ? null : ValueKey('lead|${node.id}|$record'),
      targets: targets,
      appears: {for (final target in appearing) target.path},
      literals: {kScaleLiteralKey: ?literal},
      animatesChanges: changes.isNotEmpty,
      data: data,
      identity: record ?? instance.join('/'),
      localeKey: '$locale|${strings.locale}',
      builder: (context, shown, active, leads) =>
          _announce(drawn, active, _plain(drawn, shown == data ? this : copy(data: shown), own, slot, leads)),
    );
  }

  BindableNumber _literalPath(BindableNumber value, double literal) =>
      value is BoundNumber ? value : BoundNumber(kScaleLiteralKey, literal);

  Widget _plain(ChildNode node, NodeRenderer renderer, NodeStyle? own, Slot slot, [TransitionLeads leads = const {}]) =>
      switch (node) {
    TextNode() => renderer.buildText(node, own),
    ProgressBarNode() => renderer.buildProgressBar(node, leads: leads),
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
bool animatesIn(ChildNode node) => switch (node) {
  TextNode(:final animateIn) => animateIn,
  ProgressBarNode(:final animateIn) => animateIn,
  CircularProgressNode(:final animateIn) => animateIn,
  _ => false,
};

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
