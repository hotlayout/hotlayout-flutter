/// Hostile-input tests for the icon body parser (9.3.0).
///
/// NOT REACHABLE TODAY: a drawing is taken only from the bundled `kIconBodies`
/// (`iconDrawingOf` -> `IconToken.parse` looks the name up among the set keys), and
/// a string from a document or theme never reaches the parser. But `parseIconBody` is
/// a public function, and its promise ("throws [FormatException] on everything the
/// format does not name") is all `iconDrawingOf` stands on: it catches
/// EXACTLY `FormatException`. Once the set comes from the network (custom icons),
/// an exception of another type would escape `build` and take down the host screen.
///
/// Checked and NOT broken: negative width and height of a rectangle; a megabyte of numbers, unclosed elements, attributes,
/// whitespace and `<` characters (all linear, up to 35 ms); NaN, Infinity, 1e999;
/// coordinates 1e308; an odd number of coordinates; a number after `z`; the Kelvin sign
/// in place of a command.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/render/icon_glyph.dart';

void main() {
  // The reference (`iconBodyProblems`) checks geometry with the number expression and does not reject
  // a negative width, so such a body passes the set gate too.
  const bodies = {
    'negative corner radius': "<rect width='5' height='5' rx='-9'/>",
  };

  for (final entry in bodies.entries) {
    test('${entry.key}: FormatException or a drawing - but no exception of another type', () {
      Object? thrown;
      try {
        parseIconBody(entry.value);
      } catch (error) {
        thrown = error;
      }
      expect(thrown, anyOf(isNull, isA<FormatException>()), reason: 'type: ${thrown.runtimeType}');
    });
  }
}
