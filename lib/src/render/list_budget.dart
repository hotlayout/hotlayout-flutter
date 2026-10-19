/// The list budget of a screen (`x-listBudget`).
///
/// The bound of one list (`limit`, [kMaxRepeaterItems]) multiplies with nesting, and a document the builder did not
/// make may nest deeper. A screen draws at most [kListBudgetPerScreen] instances of list templates, nested ones
/// included, counted in document order, depth first: an instance counts before the lists inside it, then the next
/// instance of the same list, then the next list. The instance that would exceed the budget is not drawn, nor is
/// anything inside it, nor any instance after it on the screen.
///
/// The count follows the TREE of the screen for its width class, not what is shown right now: a list hidden by
/// `visibleIf` or `showOn`, in an inactive tab or in a folded accordion costs the same, so switching a tab never
/// moves the cut in another list. The records are those the list draws (after `where` and `limit`). A group header
/// is not an instance; the lists inside it count right after the instance it stands above.
///
/// The plan is made once per screen, before drawing, because a list cannot know what the lists before it drew: each
/// list asks the plan how many of its records it may draw.
library;

import 'dart:math' as math;

import '../data/screen_data.dart';
import '../model/compatibility.dart';
import '../model/node.dart';
import '../model/repeater_group.dart';

/// How many instances of list templates one screen draws, nested ones included (`x-listBudget.perScreen`).
const int kListBudgetPerScreen = 2550;

/// Counting what was NOT drawn stops here: the report then says "at least".
const int _countCeiling = 1000000;

/// The records a list draws before the budget: the filter first, the bound after (`x-listFilter`).
List<Object?> listRecordsOf(RepeaterNode node, ScreenData data) {
  final where = node.where;
  final all = data.listOf(node.source);
  final passed = where == null
      ? all
      : [
          for (final record in all)
            if (where.passes(data.withItem(node.item, record))) record,
        ];
  final requested = node.limit ?? passed.length;
  final count = requested.clamp(0, math.min(passed.length, kMaxRepeaterItems)).toInt();
  return count == passed.length ? passed : passed.sublist(0, count);
}

/// The plan of one screen: who draws how many, in document order, depth first.
final class ListBudgetPlan {
  ListBudgetPlan._(this._allowed, this.drawnByList, this.total, this.notDrawn);

  /// A plan for a tree without a list: nothing to cut.
  static final ListBudgetPlan empty = ListBudgetPlan._(const {}, const {}, 0, 0);

  final Map<String, int> _allowed;

  /// Instances drawn per list node, summed over the instances of the lists around it.
  final Map<String, int> drawnByList;
  final int total;

  /// Instances the lists would draw without the budget and do not draw (at most the counting ceiling).
  final int notDrawn;

  /// How many of its drawn records the list [nodeId] at the instance path [path] may draw. A list the walk never
  /// reached sits inside an instance that is not drawn, and is never asked.
  int allowed(String nodeId, List<int> path) => _allowed[_keyOf(nodeId, path)] ?? 0;

  /// The plan of [root], with [data] as the scope the screen is drawn in.
  static ListBudgetPlan of(UiNode root, ScreenData data, {int budget = kListBudgetPerScreen}) {
    if (!_hasRepeater(root)) return empty;
    return _Walk(budget).run(root, data);
  }
}

String _keyOf(String nodeId, List<int> path) => '$nodeId@${path.join('.')}';

// A tree without a list needs no plan; the answer is cached per node, since the screen is drawn again on every
// change of the data.
final Expando<bool> _hasRepeaterCache = Expando<bool>('hasRepeater');

bool _hasRepeater(UiNode node) {
  final cached = _hasRepeaterCache[node];
  if (cached != null) return cached;
  final found = node is RepeaterNode || node.children.any(_hasRepeater);
  _hasRepeaterCache[node] = found;
  return found;
}

typedef _Instance = ({ScreenData scope, List<UiNode> parts});

final class _Walk {
  _Walk(this.budget);

  final int budget;
  final Map<String, int> allowed = {};
  final Map<String, int> drawnByList = {};
  int used = 0;
  int notDrawn = 0;

  ListBudgetPlan run(UiNode root, ScreenData data) {
    walk(root, data, const []);
    return ListBudgetPlan._(allowed, drawnByList, used, notDrawn);
  }

  /// The instances of a list in this scope: per record the scope and what is drawn with it.
  List<_Instance> instancesOf(RepeaterNode node, ScreenData outer) {
    final records = listRecordsOf(node, outer);
    final header = node.groupHeader;
    final groupBy = node.groupBy;
    final starts = header == null || groupBy == null
        ? const <int>{}
        : groupStartsOf([for (final record in records) outer.withItem(node.item, record).record?[groupBy]]);
    final template = node.children.isEmpty ? null : node.children.first;
    return [
      for (var index = 0; index < records.length; index += 1)
        (
          scope: outer.withItem(node.item, records[index]),
          // The header of a group comes with the instance it stands above, before its template.
          parts: [if (header != null && starts.contains(index)) header, ?template],
        ),
    ];
  }

  // Counts what a subtree WOULD draw: everything after the cut.
  void countAll(UiNode node, ScreenData outer) {
    if (notDrawn >= _countCeiling) return;
    if (node is! RepeaterNode) {
      for (final child in node.children) {
        countAll(child, outer);
      }
      return;
    }
    for (final instance in instancesOf(node, outer)) {
      notDrawn += 1;
      for (final part in instance.parts) {
        countAll(part, instance.scope);
      }
    }
  }

  void walk(UiNode node, ScreenData outer, List<int> path) {
    if (node is! RepeaterNode) {
      for (final child in node.children) {
        walk(child, outer, path);
      }
      return;
    }
    drawnByList.putIfAbsent(node.id, () => 0);
    final instances = instancesOf(node, outer);
    var index = 0;
    for (; index < instances.length && used < budget; index += 1) {
      used += 1;
      drawnByList[node.id] = drawnByList[node.id]! + 1;
      for (final part in instances[index].parts) {
        walk(part, instances[index].scope, [...path, index]);
      }
    }
    allowed[_keyOf(node.id, path)] = index;
    // What did not fit: these instances and everything inside them.
    for (final instance in instances.skip(index)) {
      if (notDrawn >= _countCeiling) break;
      notDrawn += 1;
      for (final part in instance.parts) {
        countAll(part, instance.scope);
      }
    }
  }
}
