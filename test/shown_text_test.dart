/// SHOWN TEXT (9.18.0 clarification): mirror of the `x-style.layout.shownText` block
/// against the artifact. The rows themselves (`shownTextCases`, `shownTemplateCases`) are
/// run by `template_cases_test.dart`, and the screens by `eyes_fixes_test.dart`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/shown_text.dart';

void main() {
  final schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as Map<String, Object?>;
  final layout = (schema['x-style']! as Map<String, Object?>)['layout']! as Map<String, Object?>;

  test('the mirror is exactly the artifact block minus the table address', () {
    final block = Map<String, Object?>.of(layout['shownText']! as Map<String, Object?>);
    expect(block.remove('cases'), 'contract/fixtures/template/template-cases.json');
    expect(kShownTextRules, block);
  });

  test('reader whitespace characters are exactly the ones the artifact names', () {
    final collapsible = ((layout['shownText']! as Map)['collapsible']! as List).cast<String>();
    final chars = [for (final tag in collapsible) String.fromCharCode(int.parse(tag.substring(2), radix: 16))];
    for (final c in chars) {
      expect(collapseShownWhitespace('a$c${c}b'), 'a b', reason: 'U+${c.codeUnitAt(0).toRadixString(16)}');
    }
    // Nothing beyond the list: U+202F, U+00A0, U+2003, form feed, zero width stay.
    for (final c in [' ', ' ', ' ', '\f', '​']) {
      expect(collapseShownWhitespace('a${c}b'), 'a${c}b');
      expect(collapseShownWhitespace('${c}b'), '${c}b');
    }
  });

  test('rich text chunks: a line break at the seam is also a single space', () {
    final runs = collapseShownRuns<String>(['a\n', '\r\nb', ' c ', ''], (r) => r, (r, t) => t);
    expect(runs.join(), 'a b c');
  });
}
