/// GROUPING OF A LIST FROM DATA (schema 9.26.0, `Repeater.groupBy`; rules in `x-repeaterGroup`).
///
/// Records that follow one another with the same value under the `groupBy` path form a group, and the SECOND child
/// of the `Repeater` (the header) is drawn before each group, in the scope of the FIRST record of the group. Groups
/// are made of the records the list DRAWS: after `where` and `limit`, in the order of the data. A list in a column
/// only. Mirror of the contract's block; `test/repeater_group_cases_test.dart` runs the shared table.
library;

/// One group of the drawn records: the number of its first record among the drawn ones, and how many follow.
typedef RecordGroup = ({int start, int size});

/// The prop that turns grouping on, and the number of the child that is the header.
const String kGroupByKey = 'groupBy';
const int kGroupHeaderIndex = 1;

bool _isMissing(Object? value) => value == null || value == '';

/// Whether two values under the path are one group. "Absent" (missing, `null`, the empty string) is one value;
/// otherwise the same type and equal, with no conversion (`1` and `"1"` are two groups). An object or a list is a
/// group of its own.
bool sameGroupValue(Object? left, Object? right) {
  if (_isMissing(left) || _isMissing(right)) return _isMissing(left) && _isMissing(right);
  if (left is Map || left is List || right is Map || right is List) return false;
  return left.runtimeType == right.runtimeType && left == right;
}

/// The groups of the drawn records. [values] are the values under the `groupBy` path, in drawing order.
List<RecordGroup> recordGroupsOf(List<Object?> values) {
  final groups = <({int start, int size})>[];
  for (var index = 0; index < values.length; index += 1) {
    if (groups.isNotEmpty && sameGroupValue(values[groups.last.start], values[index])) {
      groups[groups.length - 1] = (start: groups.last.start, size: groups.last.size + 1);
    } else {
      groups.add((start: index, size: 1));
    }
  }
  return groups;
}

/// The numbers of the drawn records that a header stands before.
Set<int> groupStartsOf(List<Object?> values) => {for (final group in recordGroupsOf(values)) group.start};

/// The `groupBy` path of a node's props, or `null`: a value that is not a non-empty string is no field.
String? readGroupBy(Object? raw) => raw is String && raw.isNotEmpty ? raw : null;

/// Mirror of the scalar rows of `x-repeaterGroup`; checked against the artifact by a test.
const Map<String, Object> kRepeaterGroupRules = {
  'widget': 'Repeater',
  'prop': kGroupByKey,
  'path': 'a path of the record of the collection (the «item» prefix); string, number, boolean or date',
  'group': 'records that follow one another with the same value under the path',
  'order': 'the order of the data — the backend sorts; the same value after another one starts a new group',
  'empty': 'no records — no groups and no headers',
  'gap': 'the «gap» of the Repeater between every two drawn nodes, headers and records alike',
  'layout': 'a list in a column only: with «columns» (any width class) or «direction: row» the field is not published',
};
