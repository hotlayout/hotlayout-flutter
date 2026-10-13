import 'package:intl/intl.dart';

import 'binding_format.dart' show BindingFormat;

/// WHICH PARTS OF A DATE TO SHOW (schema 9.19.0, `x-dateParts`): the word beside `format: 'date'`. The order of the
/// parts, the separators and the case of the month are the language's (CLDR), as for `date` itself; the calendar is
/// always Gregorian and the day is the one in the time zone of the device.
enum DateParts {
  /// Day and month in full, no year: `MMMMd`.
  dayMonth('dayMonth', 'MMMMd'),

  /// The day of the week, the day and the month in full: `MMMMEEEEd`.
  weekdayDayMonth('weekdayDayMonth', 'MMMMEEEEd'),

  /// Day, month in full and year: `yMMMMd`.
  dayMonthYear('dayMonthYear', 'yMMMMd');

  const DateParts(this.wire, this.skeleton);

  /// The word the document uses.
  final String wire;

  /// The CLDR skeleton (`x-dateParts.words.*.cldrSkeleton`).
  final String skeleton;

  /// The word of the document, or `null` for "no field": an absent field, a word of a later minor and a value that
  /// is not a string all mean the date is written as before 9.19.0.
  static DateParts? parse(Object? raw) {
    for (final word in values) {
      if (word.wire == raw) return word;
    }
    return null;
  }

  /// The word, read only when the format reads it: the field means nothing on `dateTime`, `time`, `daysUntil`, a
  /// number or a binding without a format.
  static DateParts? readFor(BindingFormat? format, Object? raw) => format == BindingFormat.date ? parse(raw) : null;

  /// The formatter of this word for a locale tag known to `intl`; the parts are named by the skeleton, not by a
  /// `dateStyle`.
  DateFormat formatter(String? tag) => DateFormat(skeleton, tag);
}
