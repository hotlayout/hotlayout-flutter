import 'binding_format.dart' show BindingFormat;

/// A COUNTDOWN THAT TICKS (schema 9.21.0, `x-countdown`): the `countdownPart` format and its two
/// neighbouring fields, `unit` and `pad`.
///
/// The format gives ONE NUMBER, a part of the time left. The sentence ("2 d 14 h 05 min") is composed by
/// the template with its own words, so the order of the parts, the words and the plural agreement belong
/// to the translation.
///
/// The arithmetic is the same for every part:
///
///     S = floor(max(0, moment - now) / 1000)
///     days = floor(S / 86400)   hours = floor(S / 3600) mod 24
///     minutes = floor(S / 60) mod 60   seconds = S mod 60
///
/// The parts round DOWN, so they always add up to the same duration ("1 h 60 min" does not exist). A past
/// moment gives zeros, never a minus. There is no time zone in the rule.
enum CountdownUnit {
  days('days', 86400, null),
  hours('hours', 3600, 24),
  minutes('minutes', 60, 60),
  seconds('seconds', 1, 60);

  const CountdownUnit(this.wire, this.secondsIn, this.wrap);

  /// The word the document uses.
  final String wire;

  /// How many seconds one step of this part is.
  final int secondsIn;

  /// The part returns to zero at this value; `null` for days, which have no upper bound.
  final int? wrap;

  /// The word of the document, or `null` when it is absent, unknown or not a string.
  static CountdownUnit? parse(Object? raw) {
    for (final unit in values) {
      if (unit.wire == raw) return unit;
    }
    return null;
  }
}

/// The only value of `pad`: at least two integer digits.
const int kCountdownPad = 2;

/// The two fields of a `countdownPart` binding, read only beside that format.
final class Countdown {
  const Countdown(this.unit, {this.pad});

  final CountdownUnit unit;

  /// The smallest number of integer digits (zeros in front); `null` writes as many digits as the number has.
  final int? pad;

  /// The fields of a binding. `null` when the format is not `countdownPart` or `unit` is missing or unknown:
  /// then the format does not apply and the value is shown as it is (`withoutUnit`). A `pad` other than 2 is
  /// no field.
  static Countdown? readFor(BindingFormat? format, Map<Object?, Object?> raw) {
    if (format != BindingFormat.countdownPart) return null;
    final unit = CountdownUnit.parse(raw['unit']);
    if (unit == null) return null;
    final pad = raw['pad'];
    return Countdown(unit, pad: pad is num && pad == kCountdownPad ? kCountdownPad : null);
  }
}

/// The part of the time left from [now] to [moment], in whole units. The reference function of the rule.
int countdownPartOf(DateTime moment, DateTime now, CountdownUnit unit) {
  final left = moment.millisecondsSinceEpoch - now.millisecondsSinceEpoch;
  final seconds = (left <= 0 ? 0 : left) ~/ 1000;
  final whole = seconds ~/ unit.secondsIn;
  final wrap = unit.wrap;
  return wrap == null ? whole : whole % wrap;
}

/// How often a node that shows these parts is redrawn: every second when one of them is seconds, otherwise
/// every minute. `null` when there is no countdown part at all.
Duration? countdownTickOf(Iterable<CountdownUnit> units) {
  var any = false;
  for (final unit in units) {
    if (unit == CountdownUnit.seconds) return const Duration(seconds: 1);
    any = true;
  }
  return any ? const Duration(minutes: 1) : null;
}

/// Mirror of `x-countdown` (scalar rows); checked against the artifact by a test.
const Map<String, Object> kCountdownRules = {
  'format': 'countdownPart',
  'pathType': 'date',
  'withoutUnit': 'the format does not apply, the value as it is',
  'fallback': 'never formatted',
};

/// The countdown parts a document names, anywhere in a raw tree (a node's props, a template value, a width
/// layer): every map `{kind: 'binding', format: 'countdownPart', unit}` with a readable unit. Iterative, so a tree
/// of any depth is walked without a deep stack, and bounded by [limit] visited values.
Set<CountdownUnit> countdownUnitsIn(Object? raw, {int limit = 200000}) {
  final found = <CountdownUnit>{};
  final pending = <Object?>[raw];
  var visited = 0;
  while (pending.isNotEmpty && visited < limit && found.length < CountdownUnit.values.length) {
    final value = pending.removeLast();
    visited += 1;
    if (value is Map) {
      if (value['kind'] == 'binding' && value['format'] == 'countdownPart') {
        final unit = CountdownUnit.parse(value['unit']);
        if (unit != null) found.add(unit);
      }
      pending.addAll(value.values);
    } else if (value is List) {
      pending.addAll(value);
    }
  }
  return found;
}
