/// The parts of a date (schema 9.19.0, `x-dateParts`): the word beside `format: 'date'`.
///
/// The rows of `datePartsCases` run in `template_cases_test.dart`; here are the mirror of the artifact and what the
/// reader does with a field it does not read.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/bindable.dart';
import 'package:hotlayout_flutter/src/model/date_parts.dart';

typedef _Json = Map<String, Object?>;

final _Json _block = (jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Json)['x-dateParts']! as _Json;

void main() {
  test('x-dateParts: the words and their skeletons are the artifact\'s', () {
    final words = _block['words']! as _Json;
    expect(_block['prop'], 'dateParts');
    expect(_block['format'], 'date');
    expect(words.keys, DateParts.values.map((word) => word.wire));
    for (final word in DateParts.values) {
      expect((words[word.wire]! as _Json)['cldrSkeleton'], word.skeleton, reason: word.wire);
    }
    expect((_block['withoutField']! as _Json)['cldrSkeleton'], 'yMMMd');
    expect(_block['unknownWord'], 'field-is-absent');
    expect(_block['fieldOnAnotherFormat'], 'ignored');
    expect(_block['calendar'], 'gregory');
  });

  test('a word is read only beside the date format', () {
    expect(DateParts.readFor(null, 'dayMonth'), isNull);
    for (final other in ['dateTime', 'time', 'number', 'currency', 'daysUntil']) {
      final binding = {'kind': 'binding', 'path': 'x', 'format': other, 'dateParts': 'dayMonth'};
      expect((BindableString.parse(binding) as BoundString).dateParts, isNull, reason: other);
    }
    final date = {'kind': 'binding', 'path': 'x', 'format': 'date', 'dateParts': 'dayMonth'};
    expect((BindableString.parse(date) as BoundString).dateParts, DateParts.dayMonth);
  });

  test('an unknown word, a word of a later minor and a value that is not a string are no field', () {
    for (final raw in <Object?>['relative', 'DayMonth', 7, true, null, {'a': 1}, ['dayMonth'], '']) {
      expect(DateParts.parse(raw), isNull, reason: '$raw');
    }
  });
}
