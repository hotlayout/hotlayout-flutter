import '../report/report_hub.dart';

import '../data/screen_data.dart';

/// Conditional visibility (`visibleIf`).
///
/// `visibleIf` is an optional field of every child node (the root `Screen` deliberately has none:
/// the root is always drawn). It is evaluated against the same data as bindings.
///
/// The main degradation rule is written in the contract itself
/// (`x-compatibility.policy.unknownVisibilityOp: 'visible'`): **an unknown operator does NOT hide
/// content**. The opposite choice would make an older app show an empty screen instead of one
/// extra block.
sealed class VisibilityCondition {
  const VisibilityCondition();

  /// A `null` input means there is no `visibleIf` field, so the node is always visible.
  ///
  /// Never throws: a corrupt condition is the same class of problem as an unknown operator, so it
  /// also degrades to "visible".
  static VisibilityCondition? parse(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map) return _broken('the visibility condition is not an object');

    final path = raw['path'];
    final op = raw['op'];
    if (path is! String || path.isEmpty) return _broken('the visibility condition has no path');
    if (op is! String) return _broken('the visibility condition has no operator');

    final unary = _unaryOps[op];
    if (unary != null) {
      // Schema 9.23.0 (`x-listFilter.emptiness`): the emptiness of a FILTERED list. `item` and `where` come together;
      // `where` alone (no prefix) cannot be judged in a record's scope, so it is read as the plain emptiness.
      final filter = raw['where'];
      final item = raw['item'];
      if ((op == 'isEmpty' || op == 'isNotEmpty') && filter is Map && item is String && item.isNotEmpty) {
        var where = VisibilityCondition.parse(filter) ?? const AlwaysVisibleCondition();
        // A filter does not carry a filter.
        if (where is FilteredEmptinessCondition) where = const AlwaysVisibleCondition();
        return FilteredEmptinessCondition(path, unary, item, where);
      }
      return UnaryCondition(path, unary);
    }

    // Schema 9.23.0 (`x-listFilter.valuePath`): the operand is the value under another path. `value` and `valuePath`
    // together are not a condition.
    final valuePath = raw['valuePath'];
    if (valuePath != null && _comparisonOps.containsKey(op)) {
      if (raw.containsKey('value')) return _broken('a condition with both value and valuePath');
      if (valuePath is! String || valuePath.isEmpty) return _broken('the valuePath is not a path');
      return PathComparisonCondition(path, _comparisonOps[op]!, valuePath);
    }

    final value = raw['value'];
    final equality = _equalityOps[op];
    if (equality != null) {
      if (value is String || value is num || value is bool) {
        return EqualityCondition(path, equality, value!);
      }
      return _broken('operator "$op" has no usable value');
    }

    final order = _orderOps[op];
    if (order != null) {
      if (value is num) return OrderCondition(path, order, value.toDouble());
      return _broken('operator "$op" expects a number');
    }

    // Contract policy: an unknown operator leaves the node visible.
    return _broken('unknown visibility operator "$op"');
  }

  static const Map<String, UnaryVisibilityOp> _unaryOps = {
    'isTrue': UnaryVisibilityOp.isTrue,
    'isFalse': UnaryVisibilityOp.isFalse,
    'isEmpty': UnaryVisibilityOp.isEmpty,
    'isNotEmpty': UnaryVisibilityOp.isNotEmpty,
  };

  static const Map<String, ComparisonVisibilityOp> _comparisonOps = {
    'eq': ComparisonVisibilityOp.eq,
    'neq': ComparisonVisibilityOp.neq,
    'gt': ComparisonVisibilityOp.gt,
    'gte': ComparisonVisibilityOp.gte,
    'lt': ComparisonVisibilityOp.lt,
    'lte': ComparisonVisibilityOp.lte,
  };

  static const Map<String, EqualityVisibilityOp> _equalityOps = {
    'eq': EqualityVisibilityOp.eq,
    'neq': EqualityVisibilityOp.neq,
  };

  static const Map<String, OrderVisibilityOp> _orderOps = {
    'gt': OrderVisibilityOp.gt,
    'gte': OrderVisibilityOp.gte,
    'lt': OrderVisibilityOp.lt,
    'lte': OrderVisibilityOp.lte,
  };

  static VisibilityCondition _broken(String reason) {
    ReportHub.ignored('visibleIf', '$reason: the node stays visible');
    return const AlwaysVisibleCondition();
  }

  bool evaluate(ScreenData data);

  /// Whether a RECORD passes `Repeater.where` (schema 9.23.0): the same judgement as [evaluate], except that a
  /// comparison with no operand lets the record through (a filter nobody gave a value does not filter: "All").
  /// [data] is the scope of THIS record. The two answers differ in one place, so they sit side by side.
  bool passes(ScreenData data) => evaluate(data);
}

enum UnaryVisibilityOp { isTrue, isFalse, isEmpty, isNotEmpty }

enum EqualityVisibilityOp { eq, neq }

enum OrderVisibilityOp { gt, gte, lt, lte }

enum ComparisonVisibilityOp { eq, neq, gt, gte, lt, lte }

/// A condition the reader could not understand. Always `true`; see the policy above.
final class AlwaysVisibleCondition extends VisibilityCondition {
  const AlwaysVisibleCondition();

  @override
  bool evaluate(ScreenData data) => true;
}

/// `{path, op}` with `isTrue | isFalse | isEmpty | isNotEmpty`.
final class UnaryCondition extends VisibilityCondition {
  const UnaryCondition(this.path, this.op);

  final String path;
  final UnaryVisibilityOp op;

  @override
  bool evaluate(ScreenData data) {
    final value = data.lookup(path);
    // "Empty" is a question about the VALUE under the path, whatever the type of the path (`x-conditions.emptiness`):
    // see [isEmptyConditionValue]. A missing value is empty (`x-compatibility.policy.missingConditionValue`).
    //
    // That is the only question absence answers. One rule for every operator ("condition not met") would treat an
    // operator AND ITS NEGATION alike, so on empty data BOTH halves of a branch vanish: `isEmpty` and `isNotEmpty`
    // would both be false, and "either the list or a 'nothing yet' label" would show neither. A missing flag has
    // neither truth nor falsehood, so `isTrue` and `isFalse` are both silent.
    return switch (op) {
      UnaryVisibilityOp.isEmpty => isEmptyConditionValue(value),
      UnaryVisibilityOp.isNotEmpty => !isEmptyConditionValue(value),
      // Flag operators make no sense over a list: the contract does not allow them, but a document from the
      // network may contain anything.
      UnaryVisibilityOp.isTrue => value is! List && _asBool(value) == true,
      UnaryVisibilityOp.isFalse => value is! List && _asBool(value) == false,
    };
  }
}

/// WHETHER A VALUE IS EMPTY (`x-conditions.emptiness`, `isEmptyConditionValue`): absent, `null`, the empty string
/// and a list without records. Any number is NOT empty (zero too), any flag is NOT empty (`false` too), and a
/// string is not trimmed: spaces are a value. A cleared number field writes the empty string, so it is empty.
bool isEmptyConditionValue(Object? value) {
  if (value == null) return true;
  if (value is String) return value.isEmpty;
  return value is List && value.isEmpty;
}

/// `{path, op, value}` with `eq | neq`; the value is a string, a number or a boolean.
final class EqualityCondition extends VisibilityCondition {
  const EqualityCondition(this.path, this.op, this.value);

  final String path;
  final EqualityVisibilityOp op;
  final Object value;

  @override
  bool evaluate(ScreenData data) {
    final actual = data.lookup(path);
    if (actual == null) return false;
    final equal = _equals(actual, value);
    return op == EqualityVisibilityOp.eq ? equal : !equal;
  }

  /// The operand type selects the comparison. The builder already rejects a document whose value
  /// type differs from the path type, so only tolerance remains here for a backend that sends
  /// numbers and flags as strings.
  static bool _equals(Object actual, Object expected) => switch (expected) {
    final num e => _asNumber(actual) == e,
    final bool e => _asBool(actual) == e,
    _ => actual is String && actual == expected,
  };
}

/// `{path, op, value}` with `gt | gte | lt | lte`; the value is always a number.
final class OrderCondition extends VisibilityCondition {
  const OrderCondition(this.path, this.op, this.value);

  final String path;
  final OrderVisibilityOp op;
  final double value;

  @override
  bool evaluate(ScreenData data) {
    final actual = _asNumber(data.lookup(path));
    if (actual == null) return false;
    return switch (op) {
      OrderVisibilityOp.gt => actual > value,
      OrderVisibilityOp.gte => actual >= value,
      OrderVisibilityOp.lt => actual < value,
      OrderVisibilityOp.lte => actual <= value,
    };
  }
}

/// A flag from data. The strings `'true'`/`'false'` are accepted for the same reason as numeric
/// strings in `BindableNumber`: half of real backends send them that way.
bool? _asBool(Object? value) => switch (value) {
  final bool b => b,
  'true' => true,
  'false' => false,
  _ => null,
};

double? _asNumber(Object? value) => switch (value) {
  final num n => n.toDouble(),
  final String s => double.tryParse(s),
  _ => null,
};

/// `{path, op, valuePath}` with `eq | neq | gt | gte | lt | lte` (schema 9.23.0): the operand is read from ANOTHER path
/// in the same scope as [path]. Types are not coerced: equal kinds compare as they are, different kinds compare as
/// text (a date is an ISO string, so text with text is legitimate); an order exists only between numbers, and the
/// empty string is not a number.
final class PathComparisonCondition extends VisibilityCondition {
  const PathComparisonCondition(this.path, this.op, this.valuePath);

  final String path;
  final ComparisonVisibilityOp op;
  final String valuePath;

  /// No operand: nothing under the path, `null` or the empty string. Spaces are a value.
  static bool isOperandMissing(Object? value) => value == null || (value is String && value.isEmpty);

  @override
  bool evaluate(ScreenData data) {
    final actual = data.lookup(path);
    // Nothing under the path itself: the rule of 8.18.0, no answer.
    if (actual == null) return false;
    final operand = data.lookup(valuePath);
    // No operand: the condition does not hold, for `eq` and `neq` alike (otherwise one of the two branches would
    // appear on empty data).
    if (isOperandMissing(operand)) return false;
    return switch (op) {
      ComparisonVisibilityOp.eq => _sameValue(actual, operand!),
      ComparisonVisibilityOp.neq => !_sameValue(actual, operand!),
      _ => _ordered(actual, operand!, op),
    };
  }

  @override
  bool passes(ScreenData data) => isOperandMissing(data.lookup(valuePath)) || evaluate(data);

  static bool _sameValue(Object left, Object right) {
    if (left is num && right is num) return left == right;
    if (left is String && right is String) return left == right;
    if (left is bool && right is bool) return left == right;
    return _textOf(left) == _textOf(right);
  }

  /// The text of a value as the reference writes it: a whole number without `.0`.
  static String _textOf(Object value) => switch (value) {
    final String text => text,
    final double number when number.isFinite && number == number.truncateToDouble() => number.toInt().toString(),
    final num number => number.toString(),
    final bool flag => flag.toString(),
    _ => '[object]',
  };

  static double? _comparable(Object value) => switch (value) {
    final num number => number.toDouble(),
    final String text when text.trim().isEmpty => null,
    final String text => double.tryParse(text.trim()),
    _ => null,
  };

  static bool _ordered(Object left, Object right, ComparisonVisibilityOp op) {
    final a = _comparable(left);
    final b = _comparable(right);
    if (a == null || b == null || a.isNaN || b.isNaN) return false;
    return switch (op) {
      ComparisonVisibilityOp.gt => a > b,
      ComparisonVisibilityOp.gte => a >= b,
      ComparisonVisibilityOp.lt => a < b,
      _ => a <= b,
    };
  }
}

/// `{path, op: isEmpty | isNotEmpty, item, where}` (schema 9.23.0): the emptiness of a list AFTER the filter. The
/// records that pass the same predicate as `Repeater.where` are counted; `limit` is not applied. No list under the path
/// means no records.
final class FilteredEmptinessCondition extends VisibilityCondition {
  const FilteredEmptinessCondition(this.path, this.op, this.item, this.where);

  final String path;
  final UnaryVisibilityOp op;
  final String item;
  final VisibilityCondition where;

  @override
  bool evaluate(ScreenData data) {
    final records = data.listOf(path);
    final any = records.any((record) => where.passes(data.withItem(item, record)));
    return op == UnaryVisibilityOp.isEmpty ? !any : any;
  }
}
